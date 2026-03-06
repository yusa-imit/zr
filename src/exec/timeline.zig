const std = @import("std");

/// Event type in task execution timeline.
pub const EventType = enum {
    /// Task was queued for execution.
    queued,
    /// Task execution started (process spawned).
    started,
    /// Task process paused (via interactive control).
    paused,
    /// Task process resumed (via interactive control).
    resumed,
    /// Task execution completed (success or failure).
    completed,
    /// Task was skipped due to condition evaluation.
    skipped,
    /// Task execution was cancelled by user.
    cancelled,
    /// Task retry attempt started.
    retry_started,
    /// Task hit timeout limit.
    timeout,
    /// Task hit memory limit.
    memory_limit,
};

/// A single event in the task execution timeline.
pub const TimelineEvent = struct {
    /// Event type.
    event_type: EventType,
    /// Task name.
    task_name: []const u8,
    /// Timestamp in nanoseconds (monotonic).
    timestamp_ns: u64,
    /// Additional context (e.g., "retry 2/3", "timeout after 30s").
    context: ?[]const u8 = null,

    pub fn format(
        self: TimelineEvent,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const elapsed_ms = self.timestamp_ns / std.time.ns_per_ms;
        try writer.print("[{d}ms] {s}: {s}", .{
            elapsed_ms,
            self.task_name,
            @tagName(self.event_type),
        });
        if (self.context) |ctx| {
            try writer.print(" ({s})", .{ctx});
        }
    }
};

/// Timeline tracking for task execution.
pub const Timeline = struct {
    allocator: std.mem.Allocator,
    /// Start time (monotonic) for relative timestamps.
    start_time_ns: u64,
    /// List of events in chronological order.
    events: std.ArrayList(TimelineEvent),
    /// Whether timeline tracking is enabled.
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) Timeline {
        return .{
            .allocator = allocator,
            .start_time_ns = @as(u64, @intCast(@max(0, std.time.nanoTimestamp()))),
            .events = std.ArrayList(TimelineEvent){},
        };
    }

    pub fn deinit(self: *Timeline) void {
        for (self.events.items) |event| {
            self.allocator.free(event.task_name);
            if (event.context) |ctx| {
                self.allocator.free(ctx);
            }
        }
        self.events.deinit(self.allocator);
    }

    /// Record a new event in the timeline.
    pub fn recordEvent(
        self: *Timeline,
        event_type: EventType,
        task_name: []const u8,
        context: ?[]const u8,
    ) !void {
        if (!self.enabled) return;

        const now = @as(u64, @intCast(@max(0, std.time.nanoTimestamp())));
        const relative_ns = now - self.start_time_ns;

        const event = TimelineEvent{
            .event_type = event_type,
            .task_name = try self.allocator.dupe(u8, task_name),
            .timestamp_ns = relative_ns,
            .context = if (context) |ctx| try self.allocator.dupe(u8, ctx) else null,
        };

        try self.events.append(self.allocator, event);
    }

    /// Get the duration between two events for a specific task.
    pub fn getDuration(
        self: *const Timeline,
        task_name: []const u8,
        start_type: EventType,
        end_type: EventType,
    ) ?u64 {
        var start_ns: ?u64 = null;
        var end_ns: ?u64 = null;

        for (self.events.items) |event| {
            if (!std.mem.eql(u8, event.task_name, task_name)) continue;

            if (event.event_type == start_type and start_ns == null) {
                start_ns = event.timestamp_ns;
            }
            if (event.event_type == end_type and start_ns != null) {
                end_ns = event.timestamp_ns;
                break;
            }
        }

        if (start_ns != null and end_ns != null) {
            return end_ns.? - start_ns.?;
        }
        return null;
    }

    /// Get all events for a specific task.
    pub fn getTaskEvents(
        self: *const Timeline,
        allocator: std.mem.Allocator,
        task_name: []const u8,
    ) !std.ArrayList(TimelineEvent) {
        var result = std.ArrayList(TimelineEvent){};
        errdefer result.deinit(allocator);

        for (self.events.items) |event| {
            if (std.mem.eql(u8, event.task_name, task_name)) {
                try result.append(allocator, event);
            }
        }

        return result;
    }

    /// Format the timeline as a string.
    pub fn formatTimeline(self: *const Timeline, writer: anytype) !void {
        if (self.events.items.len == 0) {
            try writer.writeAll("Timeline: (no events)\n");
            return;
        }

        try writer.writeAll("Task Execution Timeline:\n");
        for (self.events.items) |event| {
            try event.format("", .{}, writer);
            try writer.writeByte('\n');
        }
    }

    /// Analyze the timeline and return statistics.
    pub const TimelineStats = struct {
        total_duration_ms: u64,
        task_count: usize,
        longest_task: ?[]const u8,
        longest_duration_ms: u64,
        retry_count: usize,
        skip_count: usize,
        cancel_count: usize,
        timeout_count: usize,
    };

    pub fn analyze(self: *const Timeline, allocator: std.mem.Allocator) !TimelineStats {
        var stats = TimelineStats{
            .total_duration_ms = 0,
            .task_count = 0,
            .longest_task = null,
            .longest_duration_ms = 0,
            .retry_count = 0,
            .skip_count = 0,
            .cancel_count = 0,
            .timeout_count = 0,
        };

        if (self.events.items.len == 0) return stats;

        // Calculate total duration from first to last event
        stats.total_duration_ms = self.events.items[self.events.items.len - 1].timestamp_ns / std.time.ns_per_ms;

        // Track unique tasks and their durations
        var task_durations = std.StringHashMap(u64).init(allocator);
        defer task_durations.deinit();

        for (self.events.items) |event| {
            switch (event.event_type) {
                .completed => {
                    const duration = self.getDuration(event.task_name, .started, .completed);
                    if (duration) |d| {
                        try task_durations.put(event.task_name, d / std.time.ns_per_ms);
                    }
                },
                .retry_started => stats.retry_count += 1,
                .skipped => stats.skip_count += 1,
                .cancelled => stats.cancel_count += 1,
                .timeout => stats.timeout_count += 1,
                else => {},
            }
        }

        stats.task_count = task_durations.count();

        // Find longest task
        var it = task_durations.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > stats.longest_duration_ms) {
                stats.longest_duration_ms = entry.value_ptr.*;
                stats.longest_task = entry.key_ptr.*;
            }
        }

        return stats;
    }
};

test "Timeline basic operations" {
    var timeline = Timeline.init(std.testing.allocator);
    defer timeline.deinit();

    try timeline.recordEvent(.queued, "build", null);
    try timeline.recordEvent(.started, "build", null);
    try timeline.recordEvent(.completed, "build", "exit 0");

    try std.testing.expectEqual(@as(usize, 3), timeline.events.items.len);
}

test "Timeline getDuration" {
    var timeline = Timeline.init(std.testing.allocator);
    defer timeline.deinit();

    try timeline.recordEvent(.started, "build", null);
    std.Thread.sleep(10 * std.time.ns_per_ms); // Sleep 10ms
    try timeline.recordEvent(.completed, "build", null);

    const duration = timeline.getDuration("build", .started, .completed);
    try std.testing.expect(duration != null);
    try std.testing.expect(duration.? >= 10 * std.time.ns_per_ms);
}

test "Timeline getTaskEvents" {
    var timeline = Timeline.init(std.testing.allocator);
    defer timeline.deinit();

    try timeline.recordEvent(.queued, "build", null);
    try timeline.recordEvent(.queued, "test", null);
    try timeline.recordEvent(.started, "build", null);
    try timeline.recordEvent(.started, "test", null);
    try timeline.recordEvent(.completed, "build", null);

    var build_events = try timeline.getTaskEvents(std.testing.allocator, "build");
    defer build_events.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), build_events.items.len);
    try std.testing.expectEqualStrings("build", build_events.items[0].task_name);
}

test "Timeline analyze" {
    var timeline = Timeline.init(std.testing.allocator);
    defer timeline.deinit();

    try timeline.recordEvent(.queued, "build", null);
    try timeline.recordEvent(.started, "build", null);
    try timeline.recordEvent(.completed, "build", null);
    try timeline.recordEvent(.skipped, "test", "condition false");
    try timeline.recordEvent(.retry_started, "deploy", "retry 1/3");

    const stats = try timeline.analyze(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), stats.task_count);
    try std.testing.expectEqual(@as(usize, 1), stats.skip_count);
    try std.testing.expectEqual(@as(usize, 1), stats.retry_count);
}
