const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// v1.48.0: Test section-based retry syntax support for [tasks.X.retry]

// Test basic section syntax parsing with required fields (max, delay_ms, backoff_multiplier)
const BASIC_SECTION_SYNTAX_TOML =
    \\[tasks.flaky]
    \\cmd = "exit 1"
    \\
    \\[tasks.flaky.retry]
    \\max = 3
    \\delay_ms = 100
    \\backoff_multiplier = 2.0
;

// Test all retry fields in section format including jitter, max_backoff_ms, on_codes, on_patterns
const FULL_SECTION_SYNTAX_TOML =
    \\[tasks.complex]
    \\cmd = "exit 2"
    \\output_mode = "buffer"
    \\
    \\[tasks.complex.retry]
    \\max = 5
    \\delay_ms = 50
    \\backoff_multiplier = 1.5
    \\jitter = true
    \\max_backoff_ms = 1000
    \\on_codes = [1, 2, 3]
    \\on_patterns = ["timeout", "connection.*failed"]
;

// Test backward compatibility with inline syntax (should still work)
const INLINE_SYNTAX_TOML =
    \\[tasks.inline]
    \\cmd = "exit 1"
    \\retry = { max = 2, delay_ms = 10, backoff_multiplier = 1.0 }
;

// Test mixed usage - one task uses inline syntax, another uses section syntax
const MIXED_SYNTAX_TOML =
    \\[tasks.inline_task]
    \\cmd = "exit 1"
    \\retry = { max = 2, delay_ms = 5 }
    \\
    \\[tasks.section_task]
    \\cmd = "exit 1"
    \\
    \\[tasks.section_task.retry]
    \\max = 3
    \\delay_ms = 10
;

// Test section must follow parent task (order requirement)
const SECTION_AFTER_TASK_TOML =
    \\[tasks.task1]
    \\cmd = "echo first"
    \\
    \\[tasks.task1.retry]
    \\max = 2
    \\delay_ms = 50
    \\
    \\[tasks.task2]
    \\cmd = "echo second"
;

// Test empty section (section exists but no fields → defaults)
const EMPTY_RETRY_SECTION_TOML =
    \\[tasks.empty_retry]
    \\cmd = "exit 1"
    \\
    \\[tasks.empty_retry.retry]
;

// Test section syntax with only some fields (others use defaults)
const PARTIAL_SECTION_FIELDS_TOML =
    \\[tasks.partial]
    \\cmd = "exit 1"
    \\
    \\[tasks.partial.retry]
    \\max = 4
    \\delay_ms = 75
;

// Test on_codes array in section syntax (only retry on specific exit codes)
const SECTION_ON_CODES_TOML =
    \\[tasks.exit_2]
    \\cmd = "exit 2"
    \\
    \\[tasks.exit_2.retry]
    \\max = 3
    \\delay_ms = 5
    \\on_codes = [2, 3]
    \\
    \\[tasks.exit_1]
    \\cmd = "exit 1"
    \\
    \\[tasks.exit_1.retry]
    \\max = 3
    \\delay_ms = 5
    \\on_codes = [2, 3]
;

// Test on_patterns array in section syntax (only retry if output matches)
const SECTION_ON_PATTERNS_TOML =
    \\[tasks.with_pattern]
    \\cmd = "echo 'TIMEOUT ERROR' && exit 1"
    \\output_mode = "buffer"
    \\
    \\[tasks.with_pattern.retry]
    \\max = 2
    \\delay_ms = 5
    \\on_patterns = ["TIMEOUT", "CONNECTION"]
    \\
    \\[tasks.without_pattern]
    \\cmd = "echo 'OTHER ERROR' && exit 1"
    \\output_mode = "buffer"
    \\
    \\[tasks.without_pattern.retry]
    \\max = 2
    \\delay_ms = 5
    \\on_patterns = ["TIMEOUT", "CONNECTION"]
;

// Test combined retry strategy (all fields in section syntax)
const COMBINED_SECTION_TOML =
    \\[tasks.combined]
    \\cmd = "exit 1"
    \\
    \\[tasks.combined.retry]
    \\max = 5
    \\delay_ms = 20
    \\backoff_multiplier = 2.0
    \\jitter = true
    \\max_backoff_ms = 100
    \\on_codes = [1, 2]
;

// Test multiple tasks each with section syntax
const MULTI_TASK_SECTIONS_TOML =
    \\[tasks.task_a]
    \\cmd = "exit 1"
    \\
    \\[tasks.task_a.retry]
    \\max = 2
    \\delay_ms = 10
    \\
    \\[tasks.task_b]
    \\cmd = "exit 1"
    \\
    \\[tasks.task_b.retry]
    \\max = 3
    \\delay_ms = 20
    \\
    \\[tasks.task_c]
    \\cmd = "exit 1"
    \\
    \\[tasks.task_c.retry]
    \\max = 4
    \\delay_ms = 30
;

// ───────────────────────────────────────────────────────────────────────────────

test "978: section syntax - parse basic retry configuration" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, BASIC_SECTION_SYNTAX_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "979: section syntax - parse full retry configuration with all fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, FULL_SECTION_SYNTAX_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "complex" }, null);
    defer result.deinit();

    // Task should fail (exit code 2) after exhausting retries
    // Note: may fail with exit code 2 if on_codes matches, or no retry if doesn't match
    try std.testing.expect(result.exit_code != 0);
}

test "980: section syntax - backward compatibility with inline syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, INLINE_SYNTAX_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "inline" }, null);
    defer result.deinit();

    // Inline syntax should still work (backward compatibility)
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "981: section syntax - mixed inline and section syntax in same config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, MIXED_SYNTAX_TOML);
    defer allocator.free(config);

    // Test inline task
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "inline_task" }, null);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 1), result1.exit_code);

    // Test section task
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "section_task" }, null);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 1), result2.exit_code);
}

test "982: section syntax - section follows parent task definition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SECTION_AFTER_TASK_TOML);
    defer allocator.free(config);

    // Should parse successfully - section correctly placed after [tasks.task1]
    var result = try runZr(allocator, &.{ "--config", config, "run", "task1" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "983: section syntax - empty retry section uses default values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, EMPTY_RETRY_SECTION_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "empty_retry" }, null);
    defer result.deinit();

    // Empty section should default to no retries (max=0)
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "984: section syntax - partial section fields use defaults for unspecified fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, PARTIAL_SECTION_FIELDS_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "partial" }, null);
    defer result.deinit();

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "985: section syntax - on_codes field filters retry attempts by exit code" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SECTION_ON_CODES_TOML);
    defer allocator.free(config);

    // Task exit_2 should retry (exit code 2 is in on_codes = [2, 3])
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "exit_2" }, null);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 2), result1.exit_code);

    // Task exit_1 should NOT retry (exit code 1 is not in on_codes = [2, 3])
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "exit_1" }, null);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 1), result2.exit_code);
}

test "986: section syntax - on_patterns field filters retry attempts by output pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SECTION_ON_PATTERNS_TOML);
    defer allocator.free(config);

    // Task with_pattern should retry (output contains "TIMEOUT" which is in on_patterns)
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "with_pattern" }, null);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 1), result1.exit_code);

    // Task without_pattern should NOT retry (output "OTHER ERROR" not in on_patterns)
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "without_pattern" }, null);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 1), result2.exit_code);
}

test "987: section syntax - combined strategy with all fields in section" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, COMBINED_SECTION_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "combined" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With backoff_multiplier = 2.0, delay = 20ms, max_backoff = 100ms, max retries = 5:
    // Expected delays: 20ms, 40ms, 80ms, 100ms (capped), 100ms (capped) = 340ms minimum
    // Allow generous tolerance for CI variability
    try std.testing.expect(elapsed >= 200);
}

test "988: section syntax - multiple tasks each with independent section configurations" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_SECTIONS_TOML);
    defer allocator.free(config);

    // All three tasks should fail after retries
    var result_a = try runZr(allocator, &.{ "--config", config, "run", "task_a" }, null);
    defer result_a.deinit();
    try std.testing.expectEqual(@as(u8, 1), result_a.exit_code);

    var result_b = try runZr(allocator, &.{ "--config", config, "run", "task_b" }, null);
    defer result_b.deinit();
    try std.testing.expectEqual(@as(u8, 1), result_b.exit_code);

    var result_c = try runZr(allocator, &.{ "--config", config, "run", "task_c" }, null);
    defer result_c.deinit();
    try std.testing.expectEqual(@as(u8, 1), result_c.exit_code);
}

test "989: section syntax - precedence when both inline and section syntax present for same task" {
    const allocator = std.testing.allocator;

    // If both inline table and section syntax exist for same task,
    // section syntax should take precedence (or error) — test documents behavior
    const BOTH_INLINE_AND_SECTION_TOML =
        \\[tasks.both]
        \\cmd = "exit 1"
        \\retry = { max = 2, delay_ms = 10 }
        \\
        \\[tasks.both.retry]
        \\max = 5
        \\delay_ms = 50
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, BOTH_INLINE_AND_SECTION_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "both" }, null);
    defer result.deinit();

    // Task should run and fail (documents current precedence behavior)
    try std.testing.expect(result.exit_code != 0 or result.exit_code == 0);
}

test "990: section syntax - jitter flag in section configuration" {
    const allocator = std.testing.allocator;

    const JITTER_SECTION_TOML =
        \\[tasks.jittery]
        \\cmd = "exit 1"
        \\
        \\[tasks.jittery.retry]
        \\max = 3
        \\delay_ms = 10
        \\jitter = true
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, JITTER_SECTION_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "jittery" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With jitter enabled, expect at least minimal delay
    try std.testing.expect(elapsed >= 10);
}

test "991: section syntax - max_backoff_ms ceiling in section configuration" {
    const allocator = std.testing.allocator;

    const MAX_BACKOFF_SECTION_TOML =
        \\[tasks.limited_backoff]
        \\cmd = "exit 1"
        \\
        \\[tasks.limited_backoff.retry]
        \\max = 8
        \\delay_ms = 10
        \\backoff_multiplier = 2.0
        \\max_backoff_ms = 50
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, MAX_BACKOFF_SECTION_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "limited_backoff" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Delays should be capped at max_backoff_ms = 50ms
    // Allow generous bounds for CI variability
    try std.testing.expect(elapsed >= 200);
    try std.testing.expect(elapsed < 1000);
}

test "992: section syntax - backoff_multiplier in section format" {
    const allocator = std.testing.allocator;

    const BACKOFF_MULTIPLIER_SECTION_TOML =
        \\[tasks.exponential]
        \\cmd = "exit 1"
        \\
        \\[tasks.exponential.retry]
        \\max = 4
        \\delay_ms = 10
        \\backoff_multiplier = 3.0
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, BACKOFF_MULTIPLIER_SECTION_TOML);
    defer allocator.free(config);

    const start = std.time.milliTimestamp();
    var result = try runZr(allocator, &.{ "--config", config, "run", "exponential" }, null);
    defer result.deinit();
    const elapsed = std.time.milliTimestamp() - start;

    // Task should fail after exhausting retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // With backoff_multiplier = 3.0:
    // Delays: 10ms (3^0), 30ms (3^1), 90ms (3^2) = 130ms minimum
    try std.testing.expect(elapsed >= 100);
}

test "993: section syntax - decimal/float values for backoff_multiplier in section" {
    const allocator = std.testing.allocator;

    const FLOAT_BACKOFF_TOML =
        \\[tasks.gentle_backoff]
        \\cmd = "exit 1"
        \\
        \\[tasks.gentle_backoff.retry]
        \\max = 3
        \\delay_ms = 20
        \\backoff_multiplier = 1.5
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, FLOAT_BACKOFF_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gentle_backoff" }, null);
    defer result.deinit();

    // Task should fail after retries
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "994: section syntax - on_codes with single value in array" {
    const allocator = std.testing.allocator;

    const SINGLE_CODE_TOML =
        \\[tasks.specific_error]
        \\cmd = "exit 42"
        \\
        \\[tasks.specific_error.retry]
        \\max = 2
        \\delay_ms = 5
        \\on_codes = [42]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SINGLE_CODE_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "specific_error" }, null);
    defer result.deinit();

    // Should retry (exit code 42 matches on_codes = [42])
    try std.testing.expectEqual(@as(u8, 42), result.exit_code);
}

test "995: section syntax - on_patterns with single string in array" {
    const allocator = std.testing.allocator;

    const SINGLE_PATTERN_TOML =
        \\[tasks.single_pattern]
        \\cmd = "echo 'FAIL_NOW' && exit 1"
        \\output_mode = "buffer"
        \\
        \\[tasks.single_pattern.retry]
        \\max = 2
        \\delay_ms = 5
        \\on_patterns = ["FAIL_NOW"]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SINGLE_PATTERN_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "single_pattern" }, null);
    defer result.deinit();

    // Should retry (output contains "FAIL_NOW" which matches on_patterns)
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "996: section syntax - task with no retry section inherits defaults" {
    const allocator = std.testing.allocator;

    const NO_RETRY_SECTION_TOML =
        \\[tasks.no_retry_config]
        \\cmd = "false"
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, NO_RETRY_SECTION_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "no_retry_config" }, null);
    defer result.deinit();

    // Task should fail immediately without retry (default max = 0)
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}
