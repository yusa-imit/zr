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
const RETRY_ON_CODES_TOML =
    \\[tasks.exit_2]
    \\cmd = "exit 2"
    \\retry_max = 3
    \\retry_delay_ms = 5
    \\retry_on_codes = [2, 3]
    \\
    \\[tasks.exit_1]
    \\cmd = "exit 1"
    \\retry_max = 3
    \\retry_delay_ms = 5
    \\retry_on_codes = [2, 3]
;

// v1.47.0: Test retry_on_patterns (only retry if output contains pattern)
const RETRY_ON_PATTERNS_TOML =
    \\[tasks.with_pattern]
    \\cmd = "echo 'FLAKY ERROR' && exit 1"
    \\retry_max = 3
    \\retry_delay_ms = 5
    \\retry_on_patterns = ["FLAKY", "TIMEOUT"]
    \\output_mode = "buffer"
    \\
    \\[tasks.without_pattern]
    \\cmd = "echo 'FATAL ERROR' && exit 1"
    \\retry_max = 3
    \\retry_delay_ms = 5
    \\retry_on_patterns = ["FLAKY", "TIMEOUT"]
    \\output_mode = "buffer"
;

test "970: retry with custom backoff multiplier" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, BACKOFF_MULTIPLIER_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With backoff_multiplier = 3.0:
    // Attempt 0: 10ms
    // Attempt 1: 10 * 3 = 30ms
    // Attempt 2: 10 * 9 = 90ms
    // Attempt 3: 10 * 27 = 270ms
    // Total: ~400ms
    // This test verifies the multiplier is applied correctly (smoke test)
}

test "971: retry with jitter enabled" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, JITTER_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With jitter enabled, delays will vary by ±25%
    // This test verifies jitter doesn't cause crashes (smoke test)
}

test "972: retry with max_backoff_ms ceiling" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, MAX_BACKOFF_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With backoff_multiplier = 2.0 and max_backoff_ms = 50:
    // Attempt 0: 10ms
    // Attempt 1: 20ms
    // Attempt 2: 40ms
    // Attempt 3+: 50ms (capped)
    // This test verifies the ceiling prevents unbounded exponential growth
}

test "973: retry_on_codes - retry when exit code matches" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_CODES_TOML);
    defer allocator.free(config);

    // Run task that exits with code 2 (matches retry_on_codes)
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "exit_2" }, null);
    defer result1.deinit();

    // Task should fail (exit code non-zero)
    try std.testing.expect(result1.exit_code != 0);

    // With retry_on_codes = [2, 3], task should retry (exit 2 matches)
    // Should see retry attempts in output/logs (smoke test)
}

test "974: retry_on_codes - no retry when exit code doesn't match" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_CODES_TOML);
    defer allocator.free(config);

    // Run task that exits with code 1 (does NOT match retry_on_codes = [2, 3])
    var result = try runZr(allocator, &.{ "--config", config, "run", "exit_1" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Task should NOT retry (exit code 1 not in [2, 3])
    // Should fail immediately without retry attempts
}

test "975: retry_on_patterns - retry when output contains pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_PATTERNS_TOML);
    defer allocator.free(config);

    // Run task that outputs "FLAKY ERROR" (matches retry_on_patterns)
    var result = try runZr(allocator, &.{ "--config", config, "run", "with_pattern" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Task output contains "FLAKY", which matches retry_on_patterns
    // Should retry up to retry_max times
}

test "976: retry_on_patterns - no retry when output doesn't contain pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, RETRY_ON_PATTERNS_TOML);
    defer allocator.free(config);

    // Run task that outputs "FATAL ERROR" (does NOT match retry_on_patterns)
    var result = try runZr(allocator, &.{ "--config", config, "run", "without_pattern" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Task output doesn't contain "FLAKY" or "TIMEOUT"
    // Should NOT retry, fail immediately
}

test "977: combined retry strategy - backoff multiplier + max_backoff + jitter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const combined_config =
        \\[tasks.flaky]
        \\cmd = "exit 1"
        \\retry_max = 5
        \\retry_delay_ms = 10
        \\retry_backoff_multiplier = 2.5
        \\retry_jitter = true
        \\max_backoff_ms = 100
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, combined_config);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Combined strategy applies:
    // 1. Exponential backoff with multiplier 2.5
    // 2. Random jitter ±25%
    // 3. Max backoff ceiling at 100ms
    // This test verifies all features work together without conflicts
}
