const std = @import("std");
const Repository = @import("../../repository.zig").Repository;
const Config = @import("../../config.zig").Config;
const ArrayList = std.ArrayList;
const ChildProcess = std.process.Child;
const Allocator = std.mem.Allocator;
const os = std.os;
const builtin = @import("builtin");
const File = std.fs.File;
const Thread = std.Thread;

// Constants for configuration
const DEFAULT_BUFFER_SIZE: usize = 4096;
const MAX_BUFFER_SIZE: usize = 1024 * 1024; // 1MB
const MIN_BUFFER_SIZE: usize = 1024; // 1KB

pub const RunError = error{
    InvalidBufferSize,
    ProcessSpawnFailed,
    OutputThreadFailed,
    SignalHandlerFailed,
    TerminalStateFailed,
    ProcessTerminated,
    IoError,
    OutOfMemory,
    ThreadQuotaExceeded,
    LockedMemoryLimitExceeded,
} || File.WriteError || File.ReadError || ChildProcess.SpawnError;

pub const RunOptions = struct {
    buffer_size: usize = DEFAULT_BUFFER_SIZE,
    capture_output: bool = true,
    inherit_env: bool = true,
    show_command: bool = true,
};

pub fn execute(config: *Config, args: *std.process.ArgIterator, allocator: Allocator) RunError!void {
    const repo_name = args.next() orelse {
        std.debug.print("Error: Repository name required\n", .{});
        std.debug.print("Usage: zr run <repo> <command>\n", .{});
        return;
    };

    const repo = findRepository(config, repo_name) orelse {
        std.debug.print("Error: Repository not found: {s}\n", .{repo_name});
        return;
    };

    // Default options
    const options = RunOptions{};
    try runCommand(repo, args, allocator, options);
}

fn findRepository(config: *Config, name: []const u8) ?Repository {
    for (config.repos.items) |repo| {
        if (std.mem.eql(u8, repo.name, name)) {
            return repo;
        }
    }
    return null;
}

fn runCommand(repo: Repository, args: *std.process.ArgIterator, allocator: Allocator, options: RunOptions) RunError!void {
    // Validate buffer size
    if (options.buffer_size < MIN_BUFFER_SIZE or options.buffer_size > MAX_BUFFER_SIZE) {
        return error.InvalidBufferSize;
    }

    var cmd_args = ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    while (args.next()) |arg| {
        try cmd_args.append(arg);
    }

    if (cmd_args.items.len == 0) {
        std.debug.print("Error: Command required\n", .{});
        std.debug.print("Usage: zr run <repo> <command>\n", .{});
        return;
    }

    if (options.show_command) {
        const cmd_str = try std.mem.join(allocator, " ", cmd_args.items);
        defer allocator.free(cmd_str);
        std.debug.print("Running '{s}' in {s}...\n", .{ cmd_str, repo.name });
    }

    try executeChildProcess(repo, &cmd_args, allocator, options);
}

const ProcessContext = struct {
    child: *ChildProcess,
    original_termios: ?TermiosData = null,
    output_threads: ?struct {
        stdout: std.Thread,
        stderr: std.Thread,
    } = null,
    allocator: Allocator,
    options: RunOptions,
    env_map: ?*std.process.EnvMap = null,

    pub fn init(child: *ChildProcess, allocator: Allocator, options: RunOptions) ProcessContext {
        return .{
            .child = child,
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *ProcessContext) void {
        if (self.env_map) |env_map| {
            env_map.deinit();
            self.allocator.destroy(env_map);
        }
        if (builtin.os.tag != .windows) {
            if (self.original_termios) |termios| {
                restoreTerminalState(termios) catch {};
            }
        }
    }
};

fn executeChildProcess(repo: Repository, cmd_args: *ArrayList([]const u8), allocator: Allocator, options: RunOptions) RunError!void {
    if (options.show_command) {
        const cmd_str = try std.mem.join(allocator, " ", cmd_args.items);
        defer allocator.free(cmd_str);
        std.debug.print("Running '{s}' in {s}...\n", .{ cmd_str, repo.name });
    }

    var child = ChildProcess.init(cmd_args.items, allocator);
    child.cwd = repo.path;

    // 터미널 설정
    if (builtin.os.tag == .windows) {
        // Windows에서는 stdio 직접 상속
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
    } else {
        // Unix에서는 현재 프로세스의 터미널 설정을 유지
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.term = .{ .Pid = std.os.getpid() };
    }

    var ctx = ProcessContext.init(&child, allocator, options);
    defer ctx.deinit();

    if (options.inherit_env) {
        var env_map_ptr = try allocator.create(std.process.EnvMap);
        errdefer allocator.destroy(env_map_ptr);

        env_map_ptr.* = try std.process.getEnvMap(allocator);
        errdefer env_map_ptr.deinit();

        ctx.env_map = env_map_ptr;
        child.env_map = env_map_ptr;
    }

    try child.spawn();

    // Setup signal handling
    if (builtin.os.tag != .windows) {
        try setupUnixSignalHandler(&ctx);
    } else {
        try setupWindowsSignalHandler(&ctx);
    }

    // Wait for process completion
    const term = try child.wait();

    // Handle process termination
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("\nCommand exited with code: {d}\n", .{code});
                return error.ProcessTerminated;
            }
        },
        .Signal => |sig| {
            std.debug.print("\nCommand terminated by signal: {d}\n", .{sig});
            return error.ProcessTerminated;
        },
        .Stopped => |sig| {
            std.debug.print("\nCommand stopped by signal: {d}\n", .{sig});
            return error.ProcessTerminated;
        },
        .Unknown => |code| {
            std.debug.print("\nCommand terminated with unknown status: {d}\n", .{code});
            return error.ProcessTerminated;
        },
    }
}

fn handleOutputThread(pipe: File, output: File, buffer_size: usize) void {
    var buffer = std.heap.page_allocator.alloc(u8, buffer_size) catch return;
    defer std.heap.page_allocator.free(buffer);

    const writer = output.writer();

    if (builtin.os.tag == .windows) {
        // Windows에서는 더 작은 버퍼로 더 자주 읽고 쓰기
        const windows_buffer_size = 1024;
        const read_size = @min(buffer.len, windows_buffer_size);

        while (true) {
            const bytes_read = pipe.read(buffer[0..read_size]) catch break;
            if (bytes_read == 0) break;
            writer.writeAll(buffer[0..bytes_read]) catch break;
        }
    } else {
        // Unix 시스템에서는 기존 방식 유지
        while (true) {
            const bytes_read = pipe.read(buffer) catch break;
            if (bytes_read == 0) break;
            writer.writeAll(buffer[0..bytes_read]) catch break;
            output.sync() catch {};
        }
    }
}

const TermiosData = if (builtin.os.tag == .windows) void else os.termios;

fn saveTerminalState() !TermiosData {
    if (builtin.os.tag == .windows) {
        return;
    }
    const stdin_fd = std.io.getStdIn().handle;
    return os.tcgetattr(stdin_fd) catch |err| {
        std.debug.print("Failed to save terminal state: {s}\n", .{@errorName(err)});
        return error.TerminalStateFailed;
    };
}

fn restoreTerminalState(original: TermiosData) !void {
    if (builtin.os.tag == .windows) {
        return;
    }
    const stdin_fd = std.io.getStdIn().handle;
    try os.tcsetattr(stdin_fd, .FLUSH, original);
}

fn setupWindowsSignalHandler(ctx: *ProcessContext) !void {
    if (builtin.os.tag == .windows) {
        const kernel32 = std.os.windows.kernel32;
        const CTRL_C_EVENT = 0;

        const HandlerContext = struct {
            ctx: *ProcessContext,

            fn handler(self: *const @This(), dwCtrlType: u32) callconv(.C) c_int {
                if (dwCtrlType == CTRL_C_EVENT) {
                    if (self.ctx.child.kill()) |_| {
                        return 1;
                    } else |_| {
                        return 0;
                    }
                }
                return 0;
            }
        };

        const handler_ctx = try ctx.allocator.create(HandlerContext);
        handler_ctx.* = .{ .ctx = ctx };

        if (kernel32.SetConsoleCtrlHandler(
            @ptrCast(&HandlerContext.handler),
            @intFromBool(true),
        ) == 0) {
            std.debug.print("Failed to set up Windows signal handler\n", .{});
            return error.SignalHandlerFailed;
        }
    }
}

fn setupUnixSignalHandler(ctx: *ProcessContext) !void {
    const Handler = struct {
        ctx: *ProcessContext,
        fn handle(self: @This(), sig: c_int) void {
            _ = sig;
            if (self.ctx.child.kill()) |_| {} else |_| {}
        }
    };

    const handler = Handler{ .ctx = ctx };
    try os.sigaction(
        os.SIG.INT,
        &os.Sigaction{
            .handler = .{ .handler = struct {
                fn handleSignal(sig: c_int) callconv(.C) void {
                    @as(*const Handler, @ptrCast(&handler)).handle(sig);
                }
            }.handleSignal },
            .mask = os.empty_sigset,
            .flags = 0,
        },
        null,
    );
}
