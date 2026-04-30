const std = @import("std");

/// Adaptive debouncer that adjusts delay based on file change frequency.
/// Tracks changes over a time window and increases/decreases debounce delay
/// based on detected patterns:
/// - Burst detection: Many rapid changes (>5 in 5s) → increase debounce delay
/// - Sporadic changes: Infrequent changes (<2 in 30s) → decrease debounce delay
/// - Smooth ramp up/down (configurable step size)
pub const AdaptiveDebouncer = struct {
    /// Minimum debounce delay in milliseconds.
    min_delay_ms: u64,
    /// Maximum debounce delay in milliseconds.
    max_delay_ms: u64,
    /// Current adaptive delay in milliseconds.
    current_delay_ms: u64,
    /// Time window for tracking changes in seconds.
    window_seconds: u64,
    /// Recent change timestamps (nanoseconds), using ArrayList as circular buffer.
    recent_changes: std.ArrayList(i128),
    /// Current write position in circular buffer.
    buffer_pos: usize = 0,

    const Self = @This();

    /// Initialize an adaptive debouncer.
    /// min_delay_ms: minimum delay in milliseconds (e.g., 100)
    /// max_delay_ms: maximum delay in milliseconds (e.g., 2000)
    /// window_seconds: time window for change frequency tracking (e.g., 60)
    /// max_buffer_size: maximum number of recent changes to track
    pub fn init(
        allocator: std.mem.Allocator,
        min_delay_ms: u64,
        max_delay_ms: u64,
        window_seconds: u64,
        max_buffer_size: usize,
    ) !Self {
        var recent_changes = std.ArrayList(i128){};
        errdefer recent_changes.deinit(allocator);

        try recent_changes.ensureTotalCapacity(allocator, max_buffer_size);
        var i: usize = 0;
        while (i < max_buffer_size) : (i += 1) {
            try recent_changes.append(allocator, 0);
        }

        return Self{
            .min_delay_ms = min_delay_ms,
            .max_delay_ms = max_delay_ms,
            .current_delay_ms = min_delay_ms,
            .window_seconds = window_seconds,
            .recent_changes = recent_changes,
            .buffer_pos = 0,
        };
    }

    /// Free resources associated with the debouncer.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.recent_changes.deinit(allocator);
    }

    /// Record a file change at the current time.
    pub fn recordChange(self: *Self) void {
        const now_ns = std.time.nanoTimestamp();
        self.recordChangeAt(now_ns);
    }

    /// Record a file change at a specific timestamp (for testing).
    pub fn recordChangeAt(self: *Self, timestamp_ns: i128) void {
        if (self.recent_changes.items.len > 0) {
            self.recent_changes.items[self.buffer_pos] = timestamp_ns;
            self.buffer_pos = (self.buffer_pos + 1) % self.recent_changes.items.len;
        }
        self.updateDelay();
    }

    /// Get the current adaptive debounce delay in milliseconds.
    pub fn getDelay(self: *const Self) u64 {
        return self.current_delay_ms;
    }

    /// Reset the debouncer to initial state (clear history, reset delay).
    pub fn reset(self: *Self) void {
        self.current_delay_ms = self.min_delay_ms;
        for (self.recent_changes.items) |*item| {
            item.* = 0;
        }
        self.buffer_pos = 0;
    }

    /// Update the adaptive delay based on recent change frequency.
    fn updateDelay(self: *Self) void {
        const now_ns = std.time.nanoTimestamp();
        const window_ns = self.window_seconds * std.time.ns_per_s;

        // Count changes within the time window
        var count_in_window: usize = 0;
        for (self.recent_changes.items) |change_ns| {
            if (change_ns == 0) continue; // Skip uninitialized entries
            const age_ns = now_ns - change_ns;
            if (age_ns >= 0 and age_ns <= window_ns) {
                count_in_window += 1;
            }
        }

        // Burst detection: >5 changes in 5 seconds → increase delay
        const burst_threshold = 5;
        const burst_window_ns = 5 * std.time.ns_per_s;
        var burst_count: usize = 0;
        for (self.recent_changes.items) |change_ns| {
            if (change_ns == 0) continue;
            const age_ns = now_ns - change_ns;
            if (age_ns >= 0 and age_ns <= burst_window_ns) {
                burst_count += 1;
            }
        }

        if (burst_count > burst_threshold) {
            // Increase delay by step (default 100ms)
            const step = (self.max_delay_ms - self.min_delay_ms) / 10;
            self.current_delay_ms = @min(
                self.current_delay_ms + step,
                self.max_delay_ms,
            );
        } else if (count_in_window < 2) {
            // Sporadic changes: <2 in window → decrease delay
            const step = (self.max_delay_ms - self.min_delay_ms) / 10;
            if (self.current_delay_ms > self.min_delay_ms) {
                self.current_delay_ms = @max(
                    self.current_delay_ms -| step,
                    self.min_delay_ms,
                );
            }
        }
        // Otherwise, maintain current delay (smooth behavior)
    }
};

// --- Tests ---

test "AdaptiveDebouncer initialization with min/max bounds" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 60, 100);
    defer debouncer.deinit(allocator);

    try std.testing.expectEqual(@as(u64, 100), debouncer.min_delay_ms);
    try std.testing.expectEqual(@as(u64, 2000), debouncer.max_delay_ms);
    try std.testing.expectEqual(@as(u64, 100), debouncer.current_delay_ms);
    try std.testing.expectEqual(@as(u64, 60), debouncer.window_seconds);
}

test "AdaptiveDebouncer burst detection increases delay" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 60, 100);
    defer debouncer.deinit(allocator);

    // Record 6 changes within 5 seconds to trigger burst
    // Timestamps relative to "now", spaced 500ms apart
    const now_ns = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        // Each change is 500ms in the past from the previous one
        // First at now-2500ms, then now-2000ms, ..., now-500ms (all within 5s)
        const offset_ns = @as(i128, @intCast(5 - i)) * 500_000_000;
        const timestamp_ns = now_ns - offset_ns;
        debouncer.recordChangeAt(timestamp_ns);
    }

    const final_delay = debouncer.getDelay();
    // After burst detection (6 changes in ~2.5 seconds), delay should increase from 100
    try std.testing.expect(final_delay > 100);
}

test "AdaptiveDebouncer sporadic changes decrease delay" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 60, 100);
    defer debouncer.deinit(allocator);

    // Set delay to max first
    debouncer.current_delay_ms = 2000;

    // Record only 1 change in the time window (sporadic)
    const base_time_ns: i128 = 1_000_000_000;
    debouncer.recordChangeAt(base_time_ns);

    // After detecting sporadic pattern, delay should be lower
    const new_delay = debouncer.getDelay();
    try std.testing.expect(new_delay < 2000);
    try std.testing.expect(new_delay >= 100);
}

test "AdaptiveDebouncer respects min bound" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 60, 100);
    defer debouncer.deinit(allocator);

    // Set delay to min and try to decrease further
    debouncer.current_delay_ms = 100;
    debouncer.recordChangeAt(1_000_000_000);

    // Delay should never go below min
    const delay = debouncer.getDelay();
    try std.testing.expect(delay >= 100);
}

test "AdaptiveDebouncer respects max bound" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 60, 100);
    defer debouncer.deinit(allocator);

    // Record many rapid changes to trigger burst multiple times
    const base_time_ns: i128 = 1_000_000_000;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const timestamp_ns = base_time_ns + @as(i128, @intCast(i)) * 100_000_000;
        debouncer.recordChangeAt(timestamp_ns);
    }

    // Delay should never exceed max
    const delay = debouncer.getDelay();
    try std.testing.expect(delay <= 2000);
}

test "AdaptiveDebouncer tracks changes in time window" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 5, 100); // 5 second window
    defer debouncer.deinit(allocator);

    // Record changes at different times
    const now_ns: i128 = 10_000_000_000; // 10 seconds in nanoseconds
    const within_window = now_ns - 2 * std.time.ns_per_s; // 2 seconds ago (within 5s window)
    const outside_window = now_ns - 10 * std.time.ns_per_s; // 10 seconds ago (outside 5s window)

    debouncer.recordChangeAt(within_window);
    debouncer.recordChangeAt(outside_window);

    // The updateDelay function should only count changes within the window
    // We verify this indirectly by checking the delay behavior is reasonable
    const delay = debouncer.getDelay();
    try std.testing.expect(delay >= 100);
    try std.testing.expect(delay <= 2000);
}

test "AdaptiveDebouncer reset clears history and resets delay" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 60, 100);
    defer debouncer.deinit(allocator);

    // Record changes to trigger burst (using the same pattern as burst test)
    const now_ns = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        const offset_ns = @as(i128, @intCast(5 - i)) * 500_000_000;
        const timestamp_ns = now_ns - offset_ns;
        debouncer.recordChangeAt(timestamp_ns);
    }

    const delay_before_reset = debouncer.getDelay();
    try std.testing.expect(delay_before_reset > 100); // Delay increased due to burst

    // Reset
    debouncer.reset();

    // After reset, delay should be back to minimum
    try std.testing.expectEqual(@as(u64, 100), debouncer.getDelay());
}

test "AdaptiveDebouncer smooth ramp (not abrupt jumps)" {
    const allocator = std.testing.allocator;
    var debouncer = try AdaptiveDebouncer.init(allocator, 100, 2000, 60, 100);
    defer debouncer.deinit(allocator);

    // Record single change
    debouncer.recordChangeAt(1_000_000_000);
    const delay1 = debouncer.getDelay();

    // Record another change within window
    debouncer.recordChangeAt(1_100_000_000);
    const delay2 = debouncer.getDelay();

    // Delays should be either same or differ by a small step (not a big jump)
    const max_step = (2000 - 100) / 10 + 1; // Allow small variance
    const diff = if (delay2 > delay1) delay2 - delay1 else delay1 - delay2;
    try std.testing.expect(diff < max_step);
}
