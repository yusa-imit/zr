const std = @import("std");
const Repository = @import("../../repository.zig").Repository;
const Task = @import("../../repository.zig").Task;
const TaskGroup = @import("../../repository.zig").TaskGroup;
const Config = @import("../../config.zig").Config;
const ArrayList = std.ArrayList;
const ChildProcess = std.process.Child;
const Allocator = std.mem.Allocator;
const os = std.os;
const builtin = @import("builtin");
const File = std.fs.File;
const Thread = std.Thread;
const Arguments = @import("../args.zig").Arguments;

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
    TaskNotFound,
} || File.WriteError || File.ReadError || ChildProcess.SpawnError;

pub const RunOptions = struct {
    buffer_size: usize = DEFAULT_BUFFER_SIZE,
    capture_output: bool = true,
    inherit_env: bool = true,
    show_command: bool = true,
};

pub fn execute(config: *Config, args: *Arguments, allocator: Allocator) RunError!void {
    const repo_name = args.next() orelse {
        std.debug.print("Error: Repository name required\n", .{});
        std.debug.print("Usage: zr run <repo> <task>\n", .{});
        return;
    };

    const task_name = args.next() orelse {
        std.debug.print("Error: Task name required\n", .{});
        std.debug.print("Usage: zr run <repo> <task>\n", .{});
        return;
    };

    const repo = config.findRepository(repo_name) orelse {
        std.debug.print("Error: Repository not found: {s}\n", .{repo_name});
        return;
    };

    const task = repo.findTask(task_name) orelse {
        std.debug.print("Error: Task not found: {s}\n", .{task_name});
        return error.TaskNotFound;
    };

    const options = RunOptions{};
    try executeTask(task, repo, allocator, options);
}

fn executeTask(task: *Task, repo: *Repository, allocator: Allocator, options: RunOptions) !void {
    // 각 TaskGroup을 순차적으로 실행
    for (task.groups.items) |group| {
        try executeTaskGroup(group, repo, allocator, options);
    }
}

fn executeTaskGroup(group: *TaskGroup, repo: *Repository, allocator: Allocator, options: RunOptions) !void {
    if (group.commands.items.len == 1) {
        // 단일 명령어 실행
        var cmd_args = try parseCommandString(allocator, group.commands.items[0].command);
        defer cmd_args.deinit();
        try executeChildProcess(repo, &cmd_args, allocator, options);
    } else {
        // 병렬 실행을 위한 컨텍스트 생성
        var threads = ArrayList(Thread).init(allocator);
        defer threads.deinit();

        // 각 명령어를 별도 스레드에서 실행
        for (group.commands.items) |cmd| {
            const command_dup = try allocator.dupe(u8, cmd.command);
            const thread = try Thread.spawn(.{}, struct {
                fn run(repo_arg: *Repository, command: []const u8, alloc: Allocator, opts: RunOptions) !void {
                    defer alloc.free(command);
                    var args = try parseCommandString(alloc, command);
                    defer args.deinit();
                    try executeChildProcess(repo_arg, &args, alloc, opts);
                }
            }.run, .{ repo, command_dup, allocator, options });
            try threads.append(thread);
        }

        // 모든 스레드 완료 대기
        for (threads.items) |thread| {
            thread.join();
        }
    }
}

fn parseCommandString(allocator: Allocator, command: []const u8) !ArrayList([]const u8) {
    var args = ArrayList([]const u8).init(allocator);
    errdefer args.deinit();

    var iter = std.mem.split(u8, command, " ");
    while (iter.next()) |arg| {
        try args.append(arg);
    }

    return args;
}

const ProcessContext = struct {
    child: *ChildProcess,
    original_termios: ?TermiosData = null,
    output_threads: ?struct {
        stdout: Thread,
        stderr: Thread,
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

fn executeChildProcess(repo: *Repository, cmd_args: *ArrayList([]const u8), allocator: Allocator, options: RunOptions) RunError!void {
    if (options.buffer_size < MIN_BUFFER_SIZE or options.buffer_size > MAX_BUFFER_SIZE) {
        return error.InvalidBufferSize;
    }

    if (options.show_command) {
        const cmd_str = try std.mem.join(allocator, " ", cmd_args.items);
        defer allocator.free(cmd_str);
        std.debug.print("Running '{s}' in {s}...\n", .{ cmd_str, repo.name });
    }

    var child = ChildProcess.init(cmd_args.items, allocator);
    child.cwd = repo.path;

    // 터미널 설정
    if (builtin.os.tag == .windows) {
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
    } else {
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
