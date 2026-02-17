const std = @import("std");

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
};

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
    const term = child.wait() catch return error.WaitFailed;

    const end_ms = std.time.milliTimestamp();
    const duration_ms: u64 = @intCast(@max(0, end_ms - start_ms));

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
