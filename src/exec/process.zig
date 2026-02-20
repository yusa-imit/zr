const std = @import("std");
const builtin = @import("builtin");
const platform = @import("../util/platform.zig");
const resource = @import("resource.zig");

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
    /// Optional maximum memory in bytes. If exceeded, process is killed.
    max_memory_bytes: ?u64 = null,
    /// Optional maximum CPU cores. Currently informational only.
    max_cpu_cores: ?u32 = null,
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

/// Context for resource limit monitoring thread.
const ResourceCtx = struct {
    pid: std.process.Child.Id,
    max_memory_bytes: ?u64,
    max_cpu_cores: ?u32,
    /// Written to true by watcher if it kills the process due to resource violation.
    limit_exceeded: *std.atomic.Value(bool),
    /// Written to true by main thread when child exits normally.
    done: *std.atomic.Value(bool),
};

fn resourceWatcher(ctx: ResourceCtx) void {
    // Check resources every 100ms
    const check_interval_ms: u64 = 100;
    while (!ctx.done.load(.acquire)) {
        std.Thread.sleep(check_interval_ms * std.time.ns_per_ms);
        if (ctx.done.load(.acquire)) return;

        // Get current resource usage
        const usage = resource.getProcessUsage(ctx.pid) orelse continue;

        // Check memory limit
        if (ctx.max_memory_bytes) |limit| {
            if (usage.rss_bytes > limit) {
                platform.killProcess(ctx.pid);
                ctx.limit_exceeded.store(true, .release);
                return;
            }
        }

        // CPU limit is informational only for now
        // (Hard CPU throttling requires cgroups/Job Objects)
        _ = ctx.max_cpu_cores;
    }
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

    // Create hard resource limits BEFORE spawning (Linux: cgroup, Windows: job object)
    var hard_limits = resource.createHardLimits(allocator, .{
        .max_memory_bytes = config.max_memory_bytes,
        .max_cpu_cores = config.max_cpu_cores,
    }) catch {
        // Fall back to soft limits if hard limit creation fails
        resource.HardLimitHandle{};
    };
    defer hard_limits.deinit();

    child.spawn() catch return error.SpawnFailed;

    // Apply hard limits to the spawned process
    resource.applyHardLimits(&hard_limits, child.id) catch {
        // If hard limit application fails, continue with soft limits
        // (The process is already running, so we don't fail the entire task)
    };

    // Optionally start a timeout watcher thread
    var timed_out = std.atomic.Value(bool).init(false);
    var limit_exceeded = std.atomic.Value(bool).init(false);
    var child_done = std.atomic.Value(bool).init(false);
    var maybe_timeout_thread: ?std.Thread = null;
    var maybe_resource_thread: ?std.Thread = null;

    if (config.timeout_ms) |timeout_ms| {
        const ctx = TimeoutCtx{
            .pid = child.id,
            .timeout_ms = timeout_ms,
            .timed_out = &timed_out,
            .done = &child_done,
        };
        maybe_timeout_thread = std.Thread.spawn(.{}, timeoutWatcher, .{ctx}) catch null;
    }

    // Optionally start resource monitoring thread
    if (config.max_memory_bytes != null or config.max_cpu_cores != null) {
        const ctx = ResourceCtx{
            .pid = child.id,
            .max_memory_bytes = config.max_memory_bytes,
            .max_cpu_cores = config.max_cpu_cores,
            .limit_exceeded = &limit_exceeded,
            .done = &child_done,
        };
        maybe_resource_thread = std.Thread.spawn(.{}, resourceWatcher, .{ctx}) catch null;
    }

    const term = child.wait() catch return error.WaitFailed;

    // Signal watchers that child is done
    child_done.store(true, .release);
    if (maybe_timeout_thread) |t| t.join();
    if (maybe_resource_thread) |t| t.join();

    const end_ms = std.time.milliTimestamp();
    const duration_ms: u64 = @intCast(@max(0, end_ms - start_ms));

    // If killed by timeout or resource limit, report failure with exit_code = 1
    if (timed_out.load(.acquire) or limit_exceeded.load(.acquire)) {
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

test "run: memory limit enforcement (Linux only)" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // Try to allocate 100MB, but limit to 10MB
    // This should trigger resource limit kill
    const result = try run(allocator, .{
        .cmd = "python3 -c 'import time; x = bytearray(100 * 1024 * 1024); time.sleep(1)'",
        .cwd = null,
        .env = null,
        .inherit_stdio = false,
        .max_memory_bytes = 10 * 1024 * 1024, // 10MB limit
    });

    // Process should be killed due to memory limit
    try std.testing.expect(!result.success);
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}
