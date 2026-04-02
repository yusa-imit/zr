//! TUI Performance Profiler for zr
//!
//! Wraps sailor v1.31.0's profiling APIs (Profiler, MemoryTracker, EventLoopProfiler)
//! to provide comprehensive TUI performance analysis for identifying bottlenecks.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sailor = @import("sailor");

// Re-export sailor profiling types for convenience
pub const RenderProfile = sailor.profiler.RenderProfile;
pub const ProfilerFrame = sailor.profiler.ProfilerFrame;
pub const WidgetMetrics = sailor.profiler.WidgetMetrics;
pub const AllocEvent = sailor.profiler.AllocEvent;
pub const AllocStats = sailor.profiler.AllocStats;
pub const EventProcessingRecord = sailor.profiler.EventProcessingRecord;
pub const EventLoopStats = sailor.profiler.EventLoopStats;

/// Comprehensive TUI performance report
pub const PerformanceReport = struct {
    render_metrics: RenderMetrics,
    memory_metrics: MemoryMetrics,
    event_metrics: EventMetrics,

    pub const RenderMetrics = struct {
        total_scopes: usize,
        total_render_time_ns: u64,
        scope_stats: []ScopeStats,

        pub const ScopeStats = struct {
            name: []const u8,
            total_time_ns: u64,
            self_time_ns: u64,
            call_count: usize,
        };

        pub fn deinit(self: *RenderMetrics, allocator: Allocator) void {
            allocator.free(self.scope_stats);
        }
    };

    pub const MemoryMetrics = struct {
        hot_spots: []AllocStats,
        peak_usage_bytes: usize,
        current_usage_bytes: usize,

        pub fn deinit(self: *MemoryMetrics, allocator: Allocator) void {
            allocator.free(self.hot_spots);
        }
    };

    pub const EventMetrics = struct {
        event_stats: []EventLoopStats,
        slow_events: []EventProcessingRecord, // Events exceeding threshold
        overall_avg_latency_ns: u64,

        pub fn deinit(self: *EventMetrics, allocator: Allocator) void {
            allocator.free(self.event_stats);
            allocator.free(self.slow_events);
        }
    };

    pub fn deinit(self: *PerformanceReport, allocator: Allocator) void {
        self.render_metrics.deinit(allocator);
        self.memory_metrics.deinit(allocator);
        self.event_metrics.deinit(allocator);
    }
};

/// Integrated TUI profiler wrapping sailor v1.31.0 profiling tools
pub const TuiProfiler = struct {
    allocator: Allocator,
    render_profiler: sailor.profiler.Profiler,
    memory_tracker: sailor.profiler.MemoryTracker,
    event_profiler: sailor.profiler.EventLoopProfiler,
    enabled: bool,
    render_threshold_ms: f64,
    event_threshold_ms: f64,

    const Self = @This();

    /// Initialize TUI profiler with default thresholds
    pub fn init(allocator: Allocator) !Self {
        return initWithThresholds(allocator, 16.0, 16.0);
    }

    /// Initialize TUI profiler with custom thresholds
    pub fn initWithThresholds(
        allocator: Allocator,
        render_threshold_ms: f64,
        event_threshold_ms: f64,
    ) !Self {
        return Self{
            .allocator = allocator,
            .render_profiler = try sailor.profiler.Profiler.init(allocator, render_threshold_ms),
            .memory_tracker = try sailor.profiler.MemoryTracker.init(allocator),
            .event_profiler = try sailor.profiler.EventLoopProfiler.init(allocator, event_threshold_ms),
            .enabled = true,
            .render_threshold_ms = render_threshold_ms,
            .event_threshold_ms = event_threshold_ms,
        };
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        self.render_profiler.deinit();
        self.memory_tracker.deinit();
        self.event_profiler.deinit();
    }

    // ========================================================================
    // Render Profiling API
    // ========================================================================

    /// Begin a profiling scope (for nested render tracking)
    pub fn beginScope(self: *Self, name: []const u8) !void {
        if (!self.enabled) return;
        try self.render_profiler.beginScope(name);
    }

    /// End the current profiling scope
    pub fn endScope(self: *Self) !void {
        if (!self.enabled) return;
        try self.render_profiler.endScope();
    }

    // ========================================================================
    // Memory Profiling API
    // ========================================================================

    /// Track memory allocation
    pub fn trackMemory(self: *Self, location: []const u8, size: usize) !void {
        if (!self.enabled) return;
        try self.memory_tracker.recordAlloc(location, size);
    }

    /// Track memory free
    pub fn trackMemoryFree(self: *Self, location: []const u8, size: usize) !void {
        if (!self.enabled) return;
        try self.memory_tracker.recordFree(location, size);
    }

    // ========================================================================
    // Event Profiling API
    // ========================================================================

    /// Track event processing (returns RAII guard)
    pub fn trackEvent(self: *Self, event_type: []const u8, queue_depth: usize) sailor.profiler.EventGuard {
        return self.event_profiler.startEvent(event_type, queue_depth);
    }

    // ========================================================================
    // Report Generation
    // ========================================================================

    /// Generate comprehensive performance report
    pub fn generateReport(self: *Self) !PerformanceReport {
        var render_metrics = try self.generateRenderMetrics();
        errdefer render_metrics.deinit(self.allocator);

        var memory_metrics = try self.generateMemoryMetrics(10); // Top 10 hot spots
        errdefer memory_metrics.deinit(self.allocator);

        var event_metrics = try self.generateEventMetrics();
        errdefer event_metrics.deinit(self.allocator);

        return PerformanceReport{
            .render_metrics = render_metrics,
            .memory_metrics = memory_metrics,
            .event_metrics = event_metrics,
        };
    }

    fn generateRenderMetrics(self: *Self) !PerformanceReport.RenderMetrics {
        const flame_data = try self.render_profiler.flameGraphData(self.allocator);
        defer {
            for (flame_data) |*frame| {
                var mutable_frame = frame.*;
                mutable_frame.deinitRecursive(self.allocator);
            }
            self.allocator.free(flame_data);
        }

        var scope_stats: std.ArrayList(PerformanceReport.RenderMetrics.ScopeStats) = .{};
        errdefer scope_stats.deinit(self.allocator);

        var total_time: u64 = 0;
        for (flame_data) |*frame| {
            try collectScopeStats(self.allocator, &scope_stats, frame);
            total_time += frame.total_time_ns;
        }

        return PerformanceReport.RenderMetrics{
            .total_scopes = flame_data.len,
            .total_render_time_ns = total_time,
            .scope_stats = try scope_stats.toOwnedSlice(self.allocator),
        };
    }

    fn collectScopeStats(
        allocator: Allocator,
        list: *std.ArrayList(PerformanceReport.RenderMetrics.ScopeStats),
        frame: *const ProfilerFrame,
    ) !void {
        try list.append(allocator, .{
            .name = frame.name,
            .total_time_ns = frame.total_time_ns,
            .self_time_ns = frame.self_time_ns,
            .call_count = 1, // Each frame represents one call
        });

        for (frame.children) |*child| {
            try collectScopeStats(allocator, list, child);
        }
    }

    fn generateMemoryMetrics(self: *Self, top_n: usize) !PerformanceReport.MemoryMetrics {
        const hot_spots = try self.memory_tracker.getHotSpots(self.allocator, top_n);
        const peak = self.memory_tracker.totalPeakAllocated();
        const current = self.memory_tracker.totalCurrentAllocated();

        return PerformanceReport.MemoryMetrics{
            .hot_spots = hot_spots,
            .peak_usage_bytes = peak,
            .current_usage_bytes = current,
        };
    }

    fn generateEventMetrics(self: *Self) !PerformanceReport.EventMetrics {
        // Collect unique event types
        var event_types = std.StringHashMap(void).init(self.allocator);
        defer event_types.deinit();

        for (self.event_profiler.records.items) |record| {
            try event_types.put(record.event_type, {});
        }

        // Get stats for each event type
        var stats_list: std.ArrayList(EventLoopStats) = .{};
        errdefer stats_list.deinit(self.allocator);

        var iter = event_types.keyIterator();
        while (iter.next()) |event_type| {
            const stats = try self.event_profiler.getStats(event_type.*);
            try stats_list.append(self.allocator, stats);
        }

        const slow_events = try self.event_profiler.detectSlowEvents(self.allocator);
        const overall_avg = self.event_profiler.overallAverageLatency();

        return PerformanceReport.EventMetrics{
            .event_stats = try stats_list.toOwnedSlice(self.allocator),
            .slow_events = slow_events,
            .overall_avg_latency_ns = overall_avg,
        };
    }

    // ========================================================================
    // Flame Graph Export
    // ========================================================================

    /// Export flame graph data in JSON format
    pub fn exportFlameGraph(self: *Self, allocator: Allocator) ![]u8 {
        const flame_data = try self.render_profiler.flameGraphData(allocator);
        defer {
            for (flame_data) |*frame| {
                var mutable_frame = frame.*;
                mutable_frame.deinitRecursive(allocator);
            }
            allocator.free(flame_data);
        }

        var json_buf: std.ArrayList(u8) = .{};
        errdefer json_buf.deinit(allocator);

        const writer = json_buf.writer(allocator);
        try writer.writeAll("[");

        for (flame_data, 0..) |*frame, i| {
            if (i > 0) try writer.writeAll(",");
            try writeFrameJson(writer, frame);
        }

        try writer.writeAll("]");
        return json_buf.toOwnedSlice(allocator);
    }

    fn writeFrameJson(writer: anytype, frame: *const ProfilerFrame) !void {
        try writer.writeAll("{");
        try std.fmt.format(writer, "\"name\":\"{s}\",", .{frame.name});
        try std.fmt.format(writer, "\"total_time_ns\":{d},", .{frame.total_time_ns});
        try std.fmt.format(writer, "\"self_time_ns\":{d},", .{frame.self_time_ns});
        try writer.writeAll("\"children\":[");

        for (frame.children, 0..) |*child, i| {
            if (i > 0) try writer.writeAll(",");
            try writeFrameJson(writer, child);
        }

        try writer.writeAll("]}");
    }

    // ========================================================================
    // Utility
    // ========================================================================

    /// Reset all profiling data
    pub fn reset(self: *Self) void {
        // Profiler.reset() only clears profiles and current_frame, not root_scopes
        // We need to deinit and re-init to clear root_scopes completely
        self.render_profiler.deinit();
        self.render_profiler = sailor.profiler.Profiler.init(self.allocator, self.render_threshold_ms) catch unreachable;

        self.memory_tracker.reset();
        self.event_profiler.reset();
    }

    /// Enable profiling
    pub fn enable(self: *Self) void {
        self.enabled = true;
        self.memory_tracker.enable();
        self.event_profiler.enable();
    }

    /// Disable profiling
    pub fn disable(self: *Self) void {
        self.enabled = false;
        self.memory_tracker.disable();
        self.event_profiler.disable();
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "TuiProfiler init and deinit" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    try testing.expect(profiler.enabled);
    try testing.expectEqual(@as(f64, 16.0), profiler.render_profiler.threshold_ms);
    try testing.expectEqual(@as(f64, 16.0), profiler.event_profiler.latency_threshold_ms);
}

test "TuiProfiler custom thresholds" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, 8.0, 10.0);
    defer profiler.deinit();

    try testing.expectEqual(@as(f64, 8.0), profiler.render_profiler.threshold_ms);
    try testing.expectEqual(@as(f64, 10.0), profiler.event_profiler.latency_threshold_ms);
}

test "TuiProfiler nested scope tracking" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Nested render scopes: render -> widgets -> buffer_flush
    try profiler.beginScope("render");
    std.Thread.sleep(1_000_000); // 1ms
    try profiler.beginScope("widgets");
    std.Thread.sleep(500_000); // 0.5ms
    try profiler.beginScope("buffer_flush");
    std.Thread.sleep(200_000); // 0.2ms
    try profiler.endScope(); // buffer_flush
    try profiler.endScope(); // widgets
    try profiler.endScope(); // render

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Should have 1 root scope (render) with nested children
    try testing.expectEqual(@as(usize, 1), report.render_metrics.total_scopes);
    try testing.expect(report.render_metrics.total_render_time_ns > 1_000_000); // > 1ms

    // Scope stats should include all 3 scopes
    try testing.expectEqual(@as(usize, 3), report.render_metrics.scope_stats.len);
}

test "TuiProfiler memory allocation tracking" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Simulate allocations at different locations
    try profiler.trackMemory("widget_render", 1024);
    try profiler.trackMemory("event_buffer", 1024);
    try profiler.trackMemory("widget_render", 512);
    try profiler.trackMemory("widget_render", 256);

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Should have hot spots
    try testing.expect(report.memory_metrics.hot_spots.len > 0);
    try testing.expectEqual(@as(usize, 2816), report.memory_metrics.peak_usage_bytes); // 1024+1024+512+256
    try testing.expectEqual(@as(usize, 2816), report.memory_metrics.current_usage_bytes);

    // Top hot spot should be widget_render (1792 bytes total)
    const top_hot_spot = report.memory_metrics.hot_spots[0];
    try testing.expect(std.mem.eql(u8, "widget_render", top_hot_spot.location));
    try testing.expectEqual(@as(usize, 1792), top_hot_spot.total_allocated); // 1024+512+256
}

test "TuiProfiler event latency tracking" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Simulate event processing
    {
        var guard = profiler.trackEvent("key", 0);
        std.Thread.sleep(1_000_000); // 1ms
        try guard.end();
    }
    {
        var guard = profiler.trackEvent("mouse", 1);
        std.Thread.sleep(2_000_000); // 2ms
        try guard.end();
    }
    {
        var guard = profiler.trackEvent("key", 0);
        std.Thread.sleep(3_000_000); // 3ms
        try guard.end();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Should have stats for 2 event types (key, mouse)
    try testing.expectEqual(@as(usize, 2), report.event_metrics.event_stats.len);
    try testing.expect(report.event_metrics.overall_avg_latency_ns >= 2_000_000); // ~2ms avg
}

test "TuiProfiler report generation with empty profile" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Empty profile should have zero metrics
    try testing.expectEqual(@as(usize, 0), report.render_metrics.total_scopes);
    try testing.expectEqual(@as(u64, 0), report.render_metrics.total_render_time_ns);
    try testing.expectEqual(@as(usize, 0), report.render_metrics.scope_stats.len);
    try testing.expectEqual(@as(usize, 0), report.memory_metrics.hot_spots.len);
    try testing.expectEqual(@as(usize, 0), report.memory_metrics.peak_usage_bytes);
    try testing.expectEqual(@as(usize, 0), report.event_metrics.event_stats.len);
    try testing.expectEqual(@as(u64, 0), report.event_metrics.overall_avg_latency_ns);
}

test "TuiProfiler report generation with single sample" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Single scope
    try profiler.beginScope("single");
    std.Thread.sleep(500_000); // 0.5ms
    try profiler.endScope();

    // Single allocation
    try profiler.trackMemory("single_alloc", 100);

    // Single event
    {
        var guard = profiler.trackEvent("single_event", 0);
        std.Thread.sleep(500_000);
        try guard.end();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), report.render_metrics.total_scopes);
    try testing.expectEqual(@as(usize, 1), report.render_metrics.scope_stats.len);
    try testing.expectEqual(@as(usize, 1), report.memory_metrics.hot_spots.len);
    try testing.expectEqual(@as(usize, 1), report.event_metrics.event_stats.len);
}

test "TuiProfiler report with deep nesting" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Deep nesting: level1 -> level2 -> level3 -> level4 -> level5
    try profiler.beginScope("level1");
    try profiler.beginScope("level2");
    try profiler.beginScope("level3");
    try profiler.beginScope("level4");
    try profiler.beginScope("level5");
    std.Thread.sleep(100_000); // 0.1ms
    try profiler.endScope(); // level5
    try profiler.endScope(); // level4
    try profiler.endScope(); // level3
    try profiler.endScope(); // level2
    try profiler.endScope(); // level1

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Should have 1 root scope
    try testing.expectEqual(@as(usize, 1), report.render_metrics.total_scopes);
    // But 5 scope stats (all nested scopes)
    try testing.expectEqual(@as(usize, 5), report.render_metrics.scope_stats.len);
}

test "TuiProfiler flame graph export format" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    try profiler.beginScope("root");
    try profiler.beginScope("child1");
    try profiler.endScope();
    try profiler.beginScope("child2");
    try profiler.endScope();
    try profiler.endScope();

    const json = try profiler.exportFlameGraph(allocator);
    defer allocator.free(json);

    // Verify JSON format
    try testing.expect(json.len > 0);
    try testing.expect(std.mem.startsWith(u8, json, "["));
    try testing.expect(std.mem.endsWith(u8, json, "]"));
    try testing.expect(std.mem.indexOf(u8, json, "\"name\":\"root\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"total_time_ns\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"self_time_ns\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"children\"") != null);
}

test "TuiProfiler flame graph export with empty profile" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    const json = try profiler.exportFlameGraph(allocator);
    defer allocator.free(json);

    // Empty profile should produce "[]"
    try testing.expectEqualStrings("[]", json);
}

test "TuiProfiler event percentile calculation" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Record 100 events with latencies 0ms to 99ms
    // Simulate events with varying sleep times
    var i: usize = 0;
    while (i < 10) : (i += 1) { // Reduced to 10 for test speed
        const sleep_time = i * 1_000_000; // 0-9ms
        var guard = profiler.trackEvent("test", 0);
        std.Thread.sleep(sleep_time);
        try guard.end();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), report.event_metrics.event_stats.len);
    const stats = report.event_metrics.event_stats[0];

    // Verify percentiles exist and are calculated
    try testing.expect(stats.p95_latency_ns > 0);
    try testing.expect(stats.p99_latency_ns >= stats.p95_latency_ns);
}

test "TuiProfiler slow event detection" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, 16.0, 5.0); // 5ms event threshold
    defer profiler.deinit();

    // Fast event (minimal sleep to avoid threshold)
    {
        var guard = profiler.trackEvent("fast", 0);
        // No sleep - just record the event guard overhead
        try guard.end();
    }

    // Slow events (well above 5ms)
    {
        var guard = profiler.trackEvent("slow1", 0);
        std.Thread.sleep(10_000_000); // 10ms
        try guard.end();
    }
    {
        var guard = profiler.trackEvent("slow2", 0);
        std.Thread.sleep(15_000_000); // 15ms
        try guard.end();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Should detect 2 slow events (10ms and 15ms are > 5ms threshold)
    try testing.expectEqual(@as(usize, 2), report.event_metrics.slow_events.len);
}

test "TuiProfiler reset clears all data" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Add some data
    try profiler.beginScope("test");
    try profiler.endScope();
    try profiler.trackMemory("test", 100);
    {
        var guard = profiler.trackEvent("test", 0);
        try guard.end();
    }

    profiler.reset();

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // All metrics should be zero
    try testing.expectEqual(@as(usize, 0), report.render_metrics.total_scopes);
    try testing.expectEqual(@as(usize, 0), report.memory_metrics.hot_spots.len);
    try testing.expectEqual(@as(usize, 0), report.event_metrics.event_stats.len);
}

test "TuiProfiler enable/disable toggles all profilers" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Add data while enabled
    try profiler.trackMemory("test", 100);
    try testing.expectEqual(@as(usize, 1), profiler.memory_tracker.events.items.len);

    // Disable and try to add data
    profiler.disable();
    try profiler.trackMemory("test", 200);
    try testing.expectEqual(@as(usize, 1), profiler.memory_tracker.events.items.len); // Not recorded

    // Re-enable
    profiler.enable();
    try profiler.trackMemory("test", 300);
    try testing.expectEqual(@as(usize, 2), profiler.memory_tracker.events.items.len); // Recorded
}

test "TuiProfiler memory free tracking" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    try profiler.trackMemory("buffer", 1000);
    try profiler.trackMemory("buffer", 2000);
    try profiler.trackMemoryFree("buffer", 1000);

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Peak should be 3000, current should be 2000
    try testing.expectEqual(@as(usize, 3000), report.memory_metrics.peak_usage_bytes);
    try testing.expectEqual(@as(usize, 2000), report.memory_metrics.current_usage_bytes);
}

test "TuiProfiler scope stats accuracy" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    try profiler.beginScope("parent");
    std.Thread.sleep(1_000_000); // 1ms self
    try profiler.beginScope("child");
    std.Thread.sleep(500_000); // 0.5ms child
    try profiler.endScope();
    std.Thread.sleep(500_000); // 0.5ms more self
    try profiler.endScope();

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), report.render_metrics.scope_stats.len);

    // Parent scope
    const parent = report.render_metrics.scope_stats[0];
    try testing.expect(std.mem.eql(u8, "parent", parent.name));
    try testing.expect(parent.self_time_ns < parent.total_time_ns);
    try testing.expect(parent.self_time_ns >= 1_000_000); // At least 1ms self
    try testing.expect(parent.total_time_ns >= 2_000_000); // At least 2ms total

    // Child scope
    const child = report.render_metrics.scope_stats[1];
    try testing.expect(std.mem.eql(u8, "child", child.name));
    try testing.expect(child.total_time_ns >= 500_000); // At least 0.5ms
}

test "TuiProfiler multiple event types statistics" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Multiple key events
    {
        var guard = profiler.trackEvent("key", 0);
        std.Thread.sleep(1_000_000);
        try guard.end();
    }
    {
        var guard = profiler.trackEvent("key", 1);
        std.Thread.sleep(2_000_000);
        try guard.end();
    }
    {
        var guard = profiler.trackEvent("key", 2);
        std.Thread.sleep(3_000_000);
        try guard.end();
    }

    // Multiple mouse events
    {
        var guard = profiler.trackEvent("mouse", 0);
        std.Thread.sleep(4_000_000);
        try guard.end();
    }
    {
        var guard = profiler.trackEvent("mouse", 1);
        std.Thread.sleep(5_000_000);
        try guard.end();
    }

    // Single resize event
    {
        var guard = profiler.trackEvent("resize", 0);
        std.Thread.sleep(10_000_000);
        try guard.end();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Should have 3 event types
    try testing.expectEqual(@as(usize, 3), report.event_metrics.event_stats.len);

    // Overall average should be reasonable (events take time to execute)
    const overall_avg = report.event_metrics.overall_avg_latency_ns;
    try testing.expect(overall_avg > 0); // At least some latency
}

test "TuiProfiler flame graph with sibling scopes" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.init(allocator);
    defer profiler.deinit();

    try profiler.beginScope("root");
    try profiler.beginScope("sibling1");
    std.Thread.sleep(100_000);
    try profiler.endScope();
    try profiler.beginScope("sibling2");
    std.Thread.sleep(200_000);
    try profiler.endScope();
    try profiler.beginScope("sibling3");
    std.Thread.sleep(150_000);
    try profiler.endScope();
    try profiler.endScope();

    const json = try profiler.exportFlameGraph(allocator);
    defer allocator.free(json);

    // Should contain all sibling names
    try testing.expect(std.mem.indexOf(u8, json, "\"name\":\"root\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"name\":\"sibling1\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"name\":\"sibling2\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"name\":\"sibling3\"") != null);
}
