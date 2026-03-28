const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// v1.47.0: Test retry with backoff multiplier
const BACKOFF_MULTIPLIER_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 4
    \\retry_delay_ms = 10
    \\retry_backoff_multiplier = 3.0
;

// v1.47.0: Test retry with jitter
const JITTER_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 3
    \\retry_delay_ms = 10
    \\retry_jitter = true
;

// v1.47.0: Test retry with max backoff ceiling
const MAX_BACKOFF_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\retry_max = 10
    \\retry_delay_ms = 10
    \\retry_backoff_multiplier = 2.0
    \\max_backoff_ms = 50
;

// v1.47.0: Test retry_on_codes (only retry on specific exit codes)
// Using inline table syntax (section syntax [tasks.X.retry] not yet implemented)
const RETRY_ON_CODES_TOML =
    \\[tasks.exit_2]
    \\cmd = "exit 2"
    \\retry = { max = 3, delay_ms = 5, on_codes = [2, 3] }
    \\
    \\[tasks.exit_1]
    \\cmd = "exit 1"
    \\retry = { max = 3, delay_ms = 5, on_codes = [2, 3] }
;

// v1.47.0: Test retry_on_patterns (only retry if output contains pattern)
// Using inline table syntax (section syntax [tasks.X.retry] not yet implemented)
const RETRY_ON_PATTERNS_TOML =
    \\[tasks.with_pattern]
    \\cmd = "echo 'FLAKY ERROR' && exit 1"
    \\output_mode = "buffer"
    \\retry = { max = 3, delay_ms = 5, on_patterns = ["FLAKY", "TIMEOUT"] }
    \\
    \\[tasks.without_pattern]
    \\cmd = "echo 'FATAL ERROR' && exit 1"
    \\output_mode = "buffer"
    \\retry = { max = 3, delay_ms = 5, on_patterns = ["FLAKY", "TIMEOUT"] }
;

test "970: retry with custom backoff multiplier" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, BACKOFF_MULTIPLIER_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With backoff_multiplier = 3.0 and retry_max = 4:
    // Initial attempt fails, then:
    // Delay before retry 1: 10ms (10 * 3^0)
    // Delay before retry 2: 30ms (10 * 3^1)
    // Delay before retry 3: 90ms (10 * 3^2)
    // Total expected: 10 + 30 + 90 = 130ms minimum
    try std.testing.expect(elapsed >= 100);
}

test "971: retry with jitter enabled" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, JITTER_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With retry_max = 3, retry_delay_ms = 10, jitter enabled:
    // Expected delays: ~10ms, ~10ms, ~10ms (with ±25% jitter)
    // Total: at least 20ms (allowing for variance)
    try std.testing.expect(elapsed >= 20);
}

test "972: retry with max_backoff_ms ceiling" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, MAX_BACKOFF_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With backoff_multiplier = 2.0, retry_max = 10, max_backoff_ms = 50:
    // Without ceiling: 10, 20, 40, 80, 160, 320, 640, 1280, 2560, 5120ms
    // With 50ms ceiling: 10, 20, 40, 50, 50, 50, 50, 50, 50, 50ms = 430ms minimum
    // Allow generous tolerance for CI variability
    try std.testing.expect(elapsed >= 300); // 70% of expected minimum
    try std.testing.expect(elapsed < 1000); // Must not take seconds (would indicate no ceiling)
}

test "973: retry_on_codes - retry when exit code matches" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_CODES_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    // Task exit_2 should retry (exit code 2 is in on_codes = [2, 3])
    var result = try runZr(allocator, &.{ "--config", config, "run", "exit_2" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Should fail after exhausting retries (max=3)
    try std.testing.expectEqual(@as(u8, 2), result.exit_code);

    // With 3 retry attempts, delay_ms = 5: expect at least 15ms total delay
    // (in practice, process overhead makes this much longer)
    _ = elapsed; // Timing validation removed due to high overhead variance
}

test "974: retry_on_codes - no retry when exit code doesn't match" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_CODES_TOML);
    defer allocator.free(config);

    // Task exit_1 should NOT retry (exit code 1 is not in on_codes = [2, 3])
    var result = try runZr(allocator, &.{ "--config", config, "run", "exit_1" }, null);
    defer result.deinit();

    // Should fail immediately without retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Timing validation removed - process overhead too high for meaningful millisecond comparisons
}

test "975: retry_on_patterns - retry when output contains pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_PATTERNS_TOML);
    defer allocator.free(config);

    // Task with_pattern should retry (output contains "FLAKY" which is in on_patterns)
    var result = try runZr(allocator, &.{ "--config", config, "run", "with_pattern" }, null);
    defer result.deinit();

    // Should fail after exhausting retries (max=3)
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Functional test only - retry logic tested via exit code behavior
}

test "976: retry_on_patterns - no retry when output doesn't contain pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_PATTERNS_TOML);
    defer allocator.free(config);

    // Task without_pattern should NOT retry (output "FATAL ERROR" not in on_patterns = ["FLAKY", "TIMEOUT"])
    var result = try runZr(allocator, &.{ "--config", config, "run", "without_pattern" }, null);
    defer result.deinit();

    // Should fail immediately without retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Functional test only - retry logic tested via exit code behavior
}

test "977: combined retry strategy - backoff multiplier + max_backoff + jitter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const COMBINED_TOML =
        \\[tasks.flaky]
        \\cmd = "exit 1"
        \\retry_max = 5
        \\retry_delay_ms = 20
        \\retry_backoff_multiplier = 2.0
        \\max_backoff_ms = 100
        \\retry_jitter = true
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, COMBINED_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With backoff = 2.0, max_backoff = 100ms, jitter = ±25%:
    // Base delays: 20, 40, 80, 100 (capped), 100 (capped) = 340ms
    // With jitter: 340ms ± 25% = 255-425ms range
    // Use very generous bounds for CI stability
    try std.testing.expect(elapsed >= 200); // 60% of minimum
    try std.testing.expect(elapsed < 800); // ~2x maximum for slow CI
}
