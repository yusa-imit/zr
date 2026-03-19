const std = @import("std");

/// Retry strategy configuration for task execution (v1.47.0).
/// Replaces the simple retry_backoff boolean with a comprehensive retry policy.
pub const RetryStrategy = struct {
    /// Backoff multiplier. 1.0 = linear (constant delay), 2.0 = exponential (double each time).
    backoff_multiplier: f64 = 2.0,
    /// If true, add random jitter (±25%) to retry delays to prevent thundering herd.
    jitter: bool = false,
    /// Maximum delay between retries in milliseconds (ceiling for backoff calculation).
    max_backoff_ms: u64 = 60_000, // 60 seconds default
    /// If non-empty, only retry when exit code matches one of these codes.
    retry_on_codes: []const u8 = &[_]u8{},
    /// If non-empty, only retry when stdout/stderr contains one of these patterns.
    retry_on_patterns: []const []const u8 = &[_][]const u8{},

    /// Calculate the delay for a given retry attempt.
    /// Returns the delay in milliseconds, respecting max_backoff_ms ceiling.
    pub fn calculateDelay(
        self: *const RetryStrategy,
        base_delay_ms: u64,
        attempt: u32,
        rand: ?*std.Random,
    ) u64 {
        if (base_delay_ms == 0) return 0;

        // Calculate backoff: base_delay * (multiplier ^ attempt)
        const exponent = @as(f64, @floatFromInt(attempt));
        const multiplier_power = std.math.pow(f64, self.backoff_multiplier, exponent);
        const base_delay_f64 = @as(f64, @floatFromInt(base_delay_ms));
        var delay_f64 = base_delay_f64 * multiplier_power;

        // Apply max backoff ceiling
        const max_backoff_f64 = @as(f64, @floatFromInt(self.max_backoff_ms));
        if (delay_f64 > max_backoff_f64) {
            delay_f64 = max_backoff_f64;
        }

        var delay_ms = @as(u64, @intFromFloat(delay_f64));

        // Apply jitter if enabled (±25% random variance)
        if (self.jitter and rand != null) {
            const variance = @as(f64, @floatFromInt(delay_ms)) * 0.25;
            const jitter_range = @as(i64, @intFromFloat(variance * 2.0));
            const half_range = @divTrunc(jitter_range, 2);
            const jitter_offset = rand.?.intRangeAtMost(i64, -half_range, half_range);
            const delay_i64 = @as(i64, @intCast(delay_ms));
            const jittered = delay_i64 + jitter_offset;
            delay_ms = @intCast(@max(0, jittered));
        }

        return delay_ms;
    }

    /// Check if retry should happen based on exit code.
    /// Returns true if retry_on_codes is empty (any code) or exit code matches.
    pub fn shouldRetryOnExitCode(self: *const RetryStrategy, exit_code: u8) bool {
        if (self.retry_on_codes.len == 0) return true;

        for (self.retry_on_codes) |code| {
            if (code == exit_code) return true;
        }
        return false;
    }

    /// Check if retry should happen based on output pattern.
    /// Returns true if retry_on_patterns is empty (any output) or output contains a pattern.
    pub fn shouldRetryOnOutput(self: *const RetryStrategy, output: []const u8) bool {
        if (self.retry_on_patterns.len == 0) return true;

        for (self.retry_on_patterns) |pattern| {
            if (std.mem.indexOf(u8, output, pattern) != null) return true;
        }
        return false;
    }

    /// Check if retry should happen based on both exit code and output.
    pub fn shouldRetry(
        self: *const RetryStrategy,
        exit_code: u8,
        output: []const u8,
    ) bool {
        return self.shouldRetryOnExitCode(exit_code) and self.shouldRetryOnOutput(output);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RetryStrategy: linear backoff (multiplier=1.0)" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 1.0,
        .jitter = false,
        .max_backoff_ms = 60_000,
    };

    const base_delay: u64 = 1000; // 1 second

    // Linear backoff means delay stays constant
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 0, null));
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 1, null));
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 2, null));
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 5, null));
}

test "RetryStrategy: exponential backoff (multiplier=2.0)" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = false,
        .max_backoff_ms = 60_000,
    };

    const base_delay: u64 = 1000; // 1 second

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 0, null));
    try std.testing.expectEqual(@as(u64, 2000), strategy.calculateDelay(base_delay, 1, null));
    try std.testing.expectEqual(@as(u64, 4000), strategy.calculateDelay(base_delay, 2, null));
    try std.testing.expectEqual(@as(u64, 8000), strategy.calculateDelay(base_delay, 3, null));
    try std.testing.expectEqual(@as(u64, 16000), strategy.calculateDelay(base_delay, 4, null));
    try std.testing.expectEqual(@as(u64, 32000), strategy.calculateDelay(base_delay, 5, null));
}

test "RetryStrategy: max backoff ceiling enforcement" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = false,
        .max_backoff_ms = 10_000, // Cap at 10 seconds
    };

    const base_delay: u64 = 1000; // 1 second

    // Should cap at max_backoff_ms (10s) instead of continuing exponential growth
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 0, null));
    try std.testing.expectEqual(@as(u64, 2000), strategy.calculateDelay(base_delay, 1, null));
    try std.testing.expectEqual(@as(u64, 4000), strategy.calculateDelay(base_delay, 2, null));
    try std.testing.expectEqual(@as(u64, 8000), strategy.calculateDelay(base_delay, 3, null));
    try std.testing.expectEqual(@as(u64, 10_000), strategy.calculateDelay(base_delay, 4, null)); // Capped
    try std.testing.expectEqual(@as(u64, 10_000), strategy.calculateDelay(base_delay, 5, null)); // Capped
    try std.testing.expectEqual(@as(u64, 10_000), strategy.calculateDelay(base_delay, 10, null)); // Still capped
}

test "RetryStrategy: jitter adds variance to delays" {
    var prng = std.Random.DefaultPrng.init(42);
    var rand = prng.random();

    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = true,
        .max_backoff_ms = 60_000,
    };

    const base_delay: u64 = 1000;

    // With jitter enabled, delays should vary within ±25% of calculated value
    // Run multiple times to ensure variance
    var delays: [10]u64 = undefined;
    for (&delays, 0..) |*delay, i| {
        _ = i;
        delay.* = strategy.calculateDelay(base_delay, 2, &rand);
    }

    // Base delay for attempt 2 is 4000ms (1000 * 2^2)
    // With ±25% jitter, range is 3000-5000ms
    for (delays) |delay| {
        try std.testing.expect(delay >= 3000);
        try std.testing.expect(delay <= 5000);
    }

    // At least one delay should differ from the base (verify jitter is actually applied)
    var has_variance = false;
    for (delays) |delay| {
        if (delay != 4000) {
            has_variance = true;
            break;
        }
    }
    try std.testing.expect(has_variance);
}

test "RetryStrategy: jitter disabled produces consistent delays" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = false,
        .max_backoff_ms = 60_000,
    };

    const base_delay: u64 = 1000;

    // Without jitter, delays should be deterministic
    const delay1 = strategy.calculateDelay(base_delay, 2, null);
    const delay2 = strategy.calculateDelay(base_delay, 2, null);
    const delay3 = strategy.calculateDelay(base_delay, 2, null);

    try std.testing.expectEqual(delay1, delay2);
    try std.testing.expectEqual(delay2, delay3);
    try std.testing.expectEqual(@as(u64, 4000), delay1);
}

test "RetryStrategy: zero base delay returns zero" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = false,
        .max_backoff_ms = 60_000,
    };

    try std.testing.expectEqual(@as(u64, 0), strategy.calculateDelay(0, 0, null));
    try std.testing.expectEqual(@as(u64, 0), strategy.calculateDelay(0, 5, null));
}

test "RetryStrategy: retry on specific exit codes" {
    const codes = [_]u8{ 1, 2, 255 };
    const strategy = RetryStrategy{
        .retry_on_codes = &codes,
    };

    // Should retry on matching exit codes
    try std.testing.expect(strategy.shouldRetryOnExitCode(1));
    try std.testing.expect(strategy.shouldRetryOnExitCode(2));
    try std.testing.expect(strategy.shouldRetryOnExitCode(255));

    // Should NOT retry on non-matching exit codes
    try std.testing.expect(!strategy.shouldRetryOnExitCode(0));
    try std.testing.expect(!strategy.shouldRetryOnExitCode(3));
    try std.testing.expect(!strategy.shouldRetryOnExitCode(127));
}

test "RetryStrategy: retry on any exit code when list is empty" {
    const strategy = RetryStrategy{
        .retry_on_codes = &[_]u8{},
    };

    // Empty list means retry on any exit code
    try std.testing.expect(strategy.shouldRetryOnExitCode(0));
    try std.testing.expect(strategy.shouldRetryOnExitCode(1));
    try std.testing.expect(strategy.shouldRetryOnExitCode(2));
    try std.testing.expect(strategy.shouldRetryOnExitCode(255));
}

test "RetryStrategy: retry on output pattern match" {
    const patterns = [_][]const u8{
        "Connection refused",
        "Timeout",
        "Network unreachable",
    };
    const strategy = RetryStrategy{
        .retry_on_patterns = &patterns,
    };

    // Should retry when output contains a pattern
    try std.testing.expect(strategy.shouldRetryOnOutput("Error: Connection refused"));
    try std.testing.expect(strategy.shouldRetryOnOutput("Request failed: Timeout occurred"));
    try std.testing.expect(strategy.shouldRetryOnOutput("Network unreachable"));

    // Should NOT retry when output doesn't contain any pattern
    try std.testing.expect(!strategy.shouldRetryOnOutput("Success"));
    try std.testing.expect(!strategy.shouldRetryOnOutput("Error: Invalid argument"));
    try std.testing.expect(!strategy.shouldRetryOnOutput("Unknown error"));
}

test "RetryStrategy: retry on any output when pattern list is empty" {
    const strategy = RetryStrategy{
        .retry_on_patterns = &[_][]const u8{},
    };

    // Empty list means retry on any output
    try std.testing.expect(strategy.shouldRetryOnOutput(""));
    try std.testing.expect(strategy.shouldRetryOnOutput("Any error message"));
    try std.testing.expect(strategy.shouldRetryOnOutput("Connection refused"));
}

test "RetryStrategy: combined exit code and output conditions" {
    const codes = [_]u8{ 1, 2 };
    const patterns = [_][]const u8{"Connection refused"};
    const strategy = RetryStrategy{
        .retry_on_codes = &codes,
        .retry_on_patterns = &patterns,
    };

    // Should retry when BOTH exit code matches AND output contains pattern
    try std.testing.expect(strategy.shouldRetry(1, "Error: Connection refused"));
    try std.testing.expect(strategy.shouldRetry(2, "Fatal: Connection refused"));

    // Should NOT retry when exit code doesn't match (even if output matches)
    try std.testing.expect(!strategy.shouldRetry(0, "Error: Connection refused"));
    try std.testing.expect(!strategy.shouldRetry(255, "Connection refused"));

    // Should NOT retry when output doesn't match (even if exit code matches)
    try std.testing.expect(!strategy.shouldRetry(1, "Success"));
    try std.testing.expect(!strategy.shouldRetry(2, "Other error"));
}

test "RetryStrategy: combined conditions with empty lists (retry always)" {
    const strategy = RetryStrategy{
        .retry_on_codes = &[_]u8{},
        .retry_on_patterns = &[_][]const u8{},
    };

    // Empty lists mean retry on any combination
    try std.testing.expect(strategy.shouldRetry(0, ""));
    try std.testing.expect(strategy.shouldRetry(1, "Any error"));
    try std.testing.expect(strategy.shouldRetry(255, "Connection refused"));
}

test "RetryStrategy: exponential backoff with custom multiplier" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 1.5,
        .jitter = false,
        .max_backoff_ms = 60_000,
    };

    const base_delay: u64 = 1000;

    // Custom multiplier: 1s, 1.5s, 2.25s, 3.375s, 5.0625s
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 0, null));
    try std.testing.expectEqual(@as(u64, 1500), strategy.calculateDelay(base_delay, 1, null));
    try std.testing.expectEqual(@as(u64, 2250), strategy.calculateDelay(base_delay, 2, null));
    try std.testing.expectEqual(@as(u64, 3375), strategy.calculateDelay(base_delay, 3, null));
    try std.testing.expectEqual(@as(u64, 5062), strategy.calculateDelay(base_delay, 4, null));
}

test "RetryStrategy: aggressive exponential backoff (multiplier=3.0)" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 3.0,
        .jitter = false,
        .max_backoff_ms = 60_000,
    };

    const base_delay: u64 = 1000;

    // Aggressive backoff: 1s, 3s, 9s, 27s, 60s (capped)
    try std.testing.expectEqual(@as(u64, 1000), strategy.calculateDelay(base_delay, 0, null));
    try std.testing.expectEqual(@as(u64, 3000), strategy.calculateDelay(base_delay, 1, null));
    try std.testing.expectEqual(@as(u64, 9000), strategy.calculateDelay(base_delay, 2, null));
    try std.testing.expectEqual(@as(u64, 27000), strategy.calculateDelay(base_delay, 3, null));
    try std.testing.expectEqual(@as(u64, 60_000), strategy.calculateDelay(base_delay, 4, null)); // Capped at max
}

test "RetryStrategy: pattern matching is case-sensitive" {
    const patterns = [_][]const u8{"timeout"};
    const strategy = RetryStrategy{
        .retry_on_patterns = &patterns,
    };

    // Case-sensitive matching
    try std.testing.expect(strategy.shouldRetryOnOutput("Error: timeout"));
    try std.testing.expect(!strategy.shouldRetryOnOutput("Error: Timeout")); // Capital T
    try std.testing.expect(!strategy.shouldRetryOnOutput("Error: TIMEOUT")); // All caps
}

test "RetryStrategy: multiple pattern matches" {
    const patterns = [_][]const u8{ "error", "failed", "timeout" };
    const strategy = RetryStrategy{
        .retry_on_patterns = &patterns,
    };

    const output = "Connection error occurred, request failed due to timeout";

    // Should match because output contains all three patterns
    try std.testing.expect(strategy.shouldRetryOnOutput(output));
}

test "RetryStrategy: partial pattern match counts" {
    const patterns = [_][]const u8{"conn"};
    const strategy = RetryStrategy{
        .retry_on_patterns = &patterns,
    };

    // Substring matching (not whole word)
    try std.testing.expect(strategy.shouldRetryOnOutput("connection failed"));
    try std.testing.expect(strategy.shouldRetryOnOutput("reconnecting..."));
    try std.testing.expect(strategy.shouldRetryOnOutput("disconnected"));
}

test "RetryStrategy: max backoff smaller than base delay" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = false,
        .max_backoff_ms = 500, // Smaller than base delay
    };

    const base_delay: u64 = 1000;

    // Even first retry should be capped
    try std.testing.expectEqual(@as(u64, 500), strategy.calculateDelay(base_delay, 0, null));
    try std.testing.expectEqual(@as(u64, 500), strategy.calculateDelay(base_delay, 1, null));
    try std.testing.expectEqual(@as(u64, 500), strategy.calculateDelay(base_delay, 2, null));
}

test "RetryStrategy: jitter with zero delay" {
    var prng = std.Random.DefaultPrng.init(42);
    var rand = prng.random();

    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = true,
        .max_backoff_ms = 60_000,
    };

    // Zero base delay should always return zero, even with jitter
    try std.testing.expectEqual(@as(u64, 0), strategy.calculateDelay(0, 0, &rand));
    try std.testing.expectEqual(@as(u64, 0), strategy.calculateDelay(0, 5, &rand));
}

test "RetryStrategy: default values" {
    const strategy = RetryStrategy{};

    // Verify default values
    try std.testing.expectEqual(@as(f64, 2.0), strategy.backoff_multiplier);
    try std.testing.expect(!strategy.jitter);
    try std.testing.expectEqual(@as(u64, 60_000), strategy.max_backoff_ms);
    try std.testing.expectEqual(@as(usize, 0), strategy.retry_on_codes.len);
    try std.testing.expectEqual(@as(usize, 0), strategy.retry_on_patterns.len);
}

test "RetryStrategy: high attempt number doesn't overflow" {
    const strategy = RetryStrategy{
        .backoff_multiplier = 2.0,
        .jitter = false,
        .max_backoff_ms = 60_000,
    };

    const base_delay: u64 = 1000;

    // Very high attempt number should be capped at max_backoff_ms
    const delay = strategy.calculateDelay(base_delay, 100, null);
    try std.testing.expectEqual(@as(u64, 60_000), delay);
}

test "RetryStrategy: pattern matching with empty output" {
    const patterns = [_][]const u8{"error"};
    const strategy = RetryStrategy{
        .retry_on_patterns = &patterns,
    };

    // Empty output should not match
    try std.testing.expect(!strategy.shouldRetryOnOutput(""));
}

test "RetryStrategy: single exit code in list" {
    const codes = [_]u8{1};
    const strategy = RetryStrategy{
        .retry_on_codes = &codes,
    };

    try std.testing.expect(strategy.shouldRetryOnExitCode(1));
    try std.testing.expect(!strategy.shouldRetryOnExitCode(0));
    try std.testing.expect(!strategy.shouldRetryOnExitCode(2));
}

test "RetryStrategy: single pattern in list" {
    const patterns = [_][]const u8{"timeout"};
    const strategy = RetryStrategy{
        .retry_on_patterns = &patterns,
    };

    try std.testing.expect(strategy.shouldRetryOnOutput("timeout"));
    try std.testing.expect(!strategy.shouldRetryOnOutput("error"));
}
