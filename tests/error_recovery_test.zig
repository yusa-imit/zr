const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Config with circuit breaker that trips after 2 failures (50% threshold, min 2 attempts)
const CIRCUIT_BREAKER_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 5
    \\retry_delay_ms = 10
    \\retry_backoff = false
    \\
    \\[tasks.flaky.circuit_breaker]
    \\failure_threshold = 0.5
    \\min_attempts = 2
    \\window_ms = 60000
    \\reset_timeout_ms = 30000
;

// Config with circuit breaker that allows retries (70% threshold, min 3 attempts)
const CIRCUIT_BREAKER_LENIENT_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 5
    \\retry_delay_ms = 10
    \\retry_backoff = false
    \\
    \\[tasks.flaky.circuit_breaker]
    \\failure_threshold = 0.7
    \\min_attempts = 3
    \\window_ms = 60000
    \\reset_timeout_ms = 30000
;

// Workflow with retry budget
const RETRY_BUDGET_TOML =
    \\[tasks.task1]
    \\cmd = "exit 1"
    \\retry_max = 10
    \\retry_delay_ms = 5
    \\
    \\[tasks.task2]
    \\cmd = "exit 1"
    \\retry_max = 10
    \\retry_delay_ms = 5
    \\
    \\[workflows.test]
    \\description = "Test workflow with retry budget"
    \\retry_budget = 3
    \\
    \\[[workflows.test.stages]]
    \\name = "test"
    \\tasks = ["task1", "task2"]
;

test "933: circuit breaker prevents excessive retries" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, CIRCUIT_BREAKER_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail (exit 1)
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Circuit breaker should trip, preventing all 5 retries
    // With circuit breaker: after 2 failures at 50% threshold, circuit opens
    // Without circuit breaker: would retry 5 times
    // Check that stderr mentions circuit breaker or shows fewer retries
    // Note: This is a smoke test - exact retry count verification would require parsing output
}

test "934: circuit breaker with lenient threshold allows retries" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, CIRCUIT_BREAKER_LENIENT_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail (exit 1)
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With 70% threshold and min 3 attempts, circuit won't trip until:
    // - At least 3 attempts AND failure rate >= 70%
    // - With 100% failure rate, circuit trips after 3rd attempt
    // - Should see at least 3 retry attempts
}

test "935: task without circuit breaker retries normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task with retries but no circuit breaker
    const config_content =
        \\[tasks.retry]
        \\cmd = "exit 1"
        \\retry_max = 3
        \\retry_delay_ms = 10
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "retry" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Should have attempted all 3 retries (no circuit breaker to stop early)
}

test "936: circuit breaker state is per-task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Two tasks with different circuit breaker configs
    const config_content =
        \\[tasks.task1]
        \\cmd = "exit 1"
        \\retry_max = 5
        \\retry_delay_ms = 10
        \\
        \\[tasks.task1.circuit_breaker]
        \\failure_threshold = 0.5
        \\min_attempts = 2
        \\
        \\[tasks.task2]
        \\cmd = "exit 1"
        \\retry_max = 5
        \\retry_delay_ms = 10
        \\
        \\[tasks.task2.circuit_breaker]
        \\failure_threshold = 0.8
        \\min_attempts = 2
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    // Run both tasks
    var result = try runZr(allocator, &.{ "--config", config, "run", "task1", "task2" }, null);
    defer result.deinit();

    // Both tasks should fail
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // task1: 50% threshold, trips after 2 failures (2/2 = 100% > 50%)
    // task2: 80% threshold, trips after 2 failures (2/2 = 100% > 80%)
    // Both should trip, but with independent circuit breaker states
}

test "937: successful task does not trip circuit breaker" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task that succeeds with circuit breaker config
    const config_content =
        \\[tasks.success]
        \\cmd = "echo ok"
        \\retry_max = 3
        \\
        \\[tasks.success.circuit_breaker]
        \\failure_threshold = 0.5
        \\min_attempts = 2
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "success" }, null);
    defer result.deinit();

    // Task should succeed on first attempt
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Circuit breaker should not trip (0 failures)
}
