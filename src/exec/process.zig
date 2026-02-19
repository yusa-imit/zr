const std = @import("std");
const platform = @import("../util/platform.zig");

pub const ProcessError = error{
    SpawnFailed,
    WaitFailed,
    InvalidCommand,
    EnvSetupFailed,
} || std.mem.Allocator.Error;

pub const ProcessResult = struct {
    exit_code: u8,
    duration_ms: u64,
    success: bool,
};

pub const ProcessConfig = struct {
    cmd: []const u8,
    cwd: ?[]const u8,
    /// Optional env var overrides. Each entry is [key, value].
    /// These are merged with the current process environment.
    env: ?[]const [2][]const u8,
    /// Whether to inherit parent stdio (default true for interactive use).
    /// Set to false in tests or when output capture is needed.
    inherit_stdio: bool = true,
    /// Optional timeout in milliseconds. If the child does not exit within
    /// this time, it is killed (SIGKILL) and the run returns exit_code=1.
    timeout_ms: ?u64 = null,
};

/// Context shared between the main thread and the timeout watcher thread.
const TimeoutCtx = struct {
    pid: std.process.Child.Id,
    timeout_ms: u64,
    /// Written to true by the watcher if it kills the process.
    timed_out: *std.atomic.Value(bool),
    /// Written to true by the main thread when the child exits normally.
    done: *std.atomic.Value(bool),
};

fn timeoutWatcher(ctx: TimeoutCtx) void {
    // Sleep in small increments so we can detect normal exit early
    const slice_ms: u64 = 50;
    var elapsed_ms: u64 = 0;
    while (elapsed_ms < ctx.timeout_ms) {
        if (ctx.done.load(.acquire)) return; // child already exited normally
        std.Thread.sleep(slice_ms * std.time.ns_per_ms);
        elapsed_ms += slice_ms;
    }
    if (ctx.done.load(.acquire)) return; // child exited just before we fired
    // Kill the child process
    platform.killProcess(ctx.pid);
    ctx.timed_out.store(true, .release);
}

/// Run a shell command and wait for it to complete.
/// Inherits stdin/stdout/stderr from parent (user sees output in real-time).
/// Uses `sh -c <cmd>` to support pipes, redirects, and shell builtins.
pub fn run(allocator: std.mem.Allocator, config: ProcessConfig) ProcessError!ProcessResult {
    if (config.cmd.len == 0) return error.InvalidCommand;

    const start_ms = std.time.milliTimestamp();

    const argv = [_][]const u8{ "sh", "-c", config.cmd };
    var child = std.process.Child.init(&argv, allocator);

    if (config.inherit_stdio) {
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
    } else {
        child.stdin_behavior = .Close;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
    }
    child.cwd = config.cwd;

    // When env overrides are provided, build a merged EnvMap.
    // We use an ArenaAllocator so all temporary strings are freed together.
    var maybe_arena: ?std.heap.ArenaAllocator = null;
    var maybe_env_map: ?std.process.EnvMap = null;
    defer {
        if (maybe_env_map) |*m| m.deinit();
        if (maybe_arena) |*a| a.deinit();
    }

    if (config.env) |env_pairs| {
        // Build merged env: current environment + overrides
        maybe_env_map = std.process.getEnvMap(allocator) catch return error.EnvSetupFailed;

        for (env_pairs) |pair| {
            maybe_env_map.?.put(pair[0], pair[1]) catch return error.EnvSetupFailed;
        }

        child.env_map = &maybe_env_map.?;
    }

    child.spawn() catch return error.SpawnFailed;

    // Optionally start a timeout watcher thread
    var timed_out = std.atomic.Value(bool).init(false);
    var child_done = std.atomic.Value(bool).init(false);
    var maybe_timeout_thread: ?std.Thread = null;

    if (config.timeout_ms) |timeout_ms| {
        const ctx = TimeoutCtx{
            .pid = child.id,
            .timeout_ms = timeout_ms,
            .timed_out = &timed_out,
            .done = &child_done,
        };
        maybe_timeout_thread = std.Thread.spawn(.{}, timeoutWatcher, .{ctx}) catch null;
    }

    const term = child.wait() catch return error.WaitFailed;

    // Signal timeout watcher that child is done
    child_done.store(true, .release);
    if (maybe_timeout_thread) |t| t.join();

    const end_ms = std.time.milliTimestamp();
    const duration_ms: u64 = @intCast(@max(0, end_ms - start_ms));

    // If killed by timeout, report failure with exit_code = 1
    if (timed_out.load(.acquire)) {
        return ProcessResult{
            .exit_code = 1,
            .duration_ms = duration_ms,
            .success = false,
        };
    }

    const exit_code: u8 = switch (term) {
        .Exited => |code| code,
        .Signal => |_| 1,
        .Stopped => |_| 1,
        .Unknown => |_| 1,
    };

    return ProcessResult{
        .exit_code = exit_code,
        .duration_ms = duration_ms,
        .success = exit_code == 0,
    };
}

test "run: echo command exits successfully" {
    const allocator = std.testing.allocator;

    const result = try run(allocator, .{
        .cmd = "echo hello",
        .cwd = null,
        .env = null,
        .inherit_stdio = false,
    });

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "run: failing command returns non-zero exit code" {
    const allocator = std.testing.allocator;

    const result = try run(allocator, .{
        .cmd = "exit 42",
        .cwd = null,
        .env = null,
        .inherit_stdio = false,
    });

    try std.testing.expect(!result.success);
    try std.testing.expect(result.exit_code != 0);
}

test "run: empty command returns InvalidCommand error" {
    const allocator = std.testing.allocator;

    const result = run(allocator, .{
        .cmd = "",
        .cwd = null,
        .env = null,
        .inherit_stdio = false,
    });

    try std.testing.expectError(error.InvalidCommand, result);
}

test "run: timeout kills slow process" {
    const allocator = std.testing.allocator;

    // Sleep for 5 seconds, but timeout after 200ms
    const result = try run(allocator, .{
        .cmd = "sleep 5",
        .cwd = null,
        .env = null,
        .inherit_stdio = false,
        .timeout_ms = 200,
    });

    try std.testing.expect(!result.success);
    // Should complete well within the 5s sleep (killed by timeout)
    try std.testing.expect(result.duration_ms < 2000);
}

test "run: no timeout for fast process" {
    const allocator = std.testing.allocator;

    const result = try run(allocator, .{
        .cmd = "true",
        .cwd = null,
        .env = null,
        .inherit_stdio = false,
        .timeout_ms = 5000,
    });

    try std.testing.expect(result.success);
}

test "run: timing is non-negative" {
    const allocator = std.testing.allocator;

    const result = try run(allocator, .{
        .cmd = "true",
        .cwd = null,
        .env = null,
        .inherit_stdio = false,
    });

    try std.testing.expect(result.success);
    try std.testing.expect(result.duration_ms < 60_000);
}

test "run: env vars are passed to child process" {
    const allocator = std.testing.allocator;

    const env_pairs = [_][2][]const u8{
        .{ "ZR_TEST_VAR", "hello_zr" },
    };

    const result = try run(allocator, .{
        .cmd = "test \"$ZR_TEST_VAR\" = \"hello_zr\"",
        .cwd = null,
        .env = &env_pairs,
        .inherit_stdio = false,
    });

    try std.testing.expect(result.success);
}
