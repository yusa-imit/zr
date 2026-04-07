const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test failure hook execution after retries exhausted
const FAILURE_HOOK_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 2
    \\retry_delay_ms = 10
    \\hooks = [
    \\    { point = "failure", cmd = "echo 'Hook executed'" }
    \\]
;

// Test failure hook with retry backoff
const FAILURE_HOOK_BACKOFF_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 3
    \\retry_delay_ms = 5
    \\retry_backoff_multiplier = 2.0
    \\hooks = [
    \\    { point = "failure", cmd = "echo 'Retry exhausted'" }
    \\]
;

// Test multiple hooks with retry
const MULTIPLE_HOOKS_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 2
    \\retry_delay_ms = 5
    \\hooks = [
    \\    { point = "before", cmd = "echo 'Starting task'" },
    \\    { point = "after", cmd = "echo 'Task completed'" },
    \\    { point = "failure", cmd = "echo 'Task failed after retries'" }
    \\]
;

// Test success hook does not execute when retries exhausted
const SUCCESS_HOOK_NO_EXEC_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 1
    \\retry_delay_ms = 5
    \\hooks = [
    \\    { point = "success", cmd = "echo 'This should not execute'" },
    \\    { point = "failure", cmd = "echo 'This should execute'" }
    \\]
;

// Test eventual success after retry does not trigger failure hook
const SUCCESS_AFTER_RETRY_TOML =
    \\[tasks.eventually_succeeds]
    \\cmd = "test -f /tmp/zr_retry_success_marker || (touch /tmp/zr_retry_success_marker && exit 1)"
    \\retry_max = 2
    \\retry_delay_ms = 10
    \\hooks = [
    \\    { point = "success", cmd = "echo 'Success hook'" },
    \\    { point = "failure", cmd = "echo 'Failure hook'" }
    \\]
;

test "978: failure hook executes after retries exhausted" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, FAILURE_HOOK_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Failure hook should execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hook executed") != null);
}

test "979: failure hook with exponential backoff retry" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, FAILURE_HOOK_BACKOFF_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Failure hook should execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Retry exhausted") != null);

    // Should have retried with backoff (5ms, 10ms, 20ms = 35ms minimum)
    try std.testing.expect(elapsed >= 25);
}

test "980: multiple hooks execute in correct order with retry" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, MULTIPLE_HOOKS_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // All hooks should execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Starting task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task completed") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task failed after retries") != null);
}

test "981: success hook does not execute when task fails after retry" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SUCCESS_HOOK_NO_EXEC_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Success hook should NOT execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "This should not execute") == null);

    // Failure hook should execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "This should execute") != null);
}

test "982: success after retry triggers success hook, not failure hook" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SUCCESS_AFTER_RETRY_TOML);
    defer allocator.free(config);

    // Clean up marker file from potential previous test runs
    std.fs.deleteFileAbsolute("/tmp/zr_retry_success_marker") catch {};

    var result = try runZr(allocator, &.{ "--config", config, "run", "eventually_succeeds" }, null);
    defer result.deinit();
    defer std.fs.deleteFileAbsolute("/tmp/zr_retry_success_marker") catch {};

    // Task should eventually succeed after 1 retry
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Success hook should execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Success hook") != null);

    // Failure hook should NOT execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Failure hook") == null);
}
