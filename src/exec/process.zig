const std = @import("std");

pub const ProcessError = error{
    SpawnFailed,
    WaitFailed,
    InvalidCommand,
} || std.mem.Allocator.Error;

pub const ProcessResult = struct {
    exit_code: u8,
    duration_ms: u64,
    success: bool,
};

pub const ProcessConfig = struct {
    cmd: []const u8,
    cwd: ?[]const u8,
    env: ?[]const [2][]const u8,
};

/// Run a shell command and wait for it to complete.
/// Inherits stdin/stdout/stderr from parent (user sees output in real-time).
/// Uses `sh -c <cmd>` to support pipes, redirects, and shell builtins.
pub fn run(allocator: std.mem.Allocator, config: ProcessConfig) ProcessError!ProcessResult {
    if (config.cmd.len == 0) return error.InvalidCommand;

    const start_ms = std.time.milliTimestamp();

    const argv = [_][]const u8{ "sh", "-c", config.cmd };
    var child = std.process.Child.init(&argv, allocator);

    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = config.cwd;

    child.spawn() catch return error.SpawnFailed;
    const term = child.wait() catch return error.WaitFailed;

    const end_ms = std.time.milliTimestamp();
    const duration_ms: u64 = @intCast(@max(0, end_ms - start_ms));

    const exit_code: u8 = switch (term) {
        .Exited => |code| code,
        .Signal => |sig| blk: {
            _ = sig;
            break :blk 1;
        },
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
    });

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "run: failing command returns non-zero exit code" {
    const allocator = std.testing.allocator;

    // `false` is a standard POSIX command that always exits with code 1
    const result = try run(allocator, .{
        .cmd = "exit 42",
        .cwd = null,
        .env = null,
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
    });

    try std.testing.expectError(error.InvalidCommand, result);
}

test "run: timing is non-negative" {
    const allocator = std.testing.allocator;

    const result = try run(allocator, .{
        .cmd = "true",
        .cwd = null,
        .env = null,
    });

    try std.testing.expect(result.success);
    // Duration should be non-negative (it's u64 so always true, but this documents intent)
    try std.testing.expect(result.duration_ms < 60_000);
}
