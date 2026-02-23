const std = @import("std");
const types = @import("types.zig");
const history = @import("../history/store.zig");

/// Collects analytics data from execution history
pub fn collectAnalytics(allocator: std.mem.Allocator, limit: ?usize) !types.AnalyticsReport {
    return collectAnalyticsWithPath(allocator, limit, null);
}

fn collectAnalyticsWithPath(allocator: std.mem.Allocator, limit: ?usize, history_path: ?[]const u8) !types.AnalyticsReport {
    var report = types.AnalyticsReport.init(allocator);
    errdefer report.deinit();

    // Get history path
    const hist_path = if (history_path) |p|
        try allocator.dupe(u8, p)
    else
        try history.defaultHistoryPath(allocator);
    defer allocator.free(hist_path);

    // Load history store
    var store = try history.Store.init(allocator, hist_path);
    defer store.deinit();

    // Load records
    const effective_limit = limit orelse 1000; // Default to last 1000 executions
    var records = store.loadLast(allocator, effective_limit) catch |err| {
        if (err == error.FileNotFound) {
            return report; // Empty report
        }
        return err;
    };
    defer {
        for (records.items) |r| r.deinit(allocator);
        records.deinit(allocator);
    }

    if (records.items.len == 0) {
        return report;
    }

    // Set date range
    report.date_range_start = records.items[0].timestamp;
    report.date_range_end = records.items[records.items.len - 1].timestamp;
    report.total_executions = records.items.len;

    // Build task statistics map
    var task_map = std.StringHashMap(TaskStatsBuilder).init(allocator);
    defer {
        var it = task_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        task_map.deinit();
    }

    var total_wall_time: u64 = 0;
    var total_cpu_time: u64 = 0;
    var successful_count: usize = 0;
    var failed_count: usize = 0;

    // Process records
    for (records.items) |record| {
        total_wall_time = @max(total_wall_time, record.duration_ms);
        total_cpu_time += record.duration_ms;

        if (record.success) {
            successful_count += 1;
        } else {
            failed_count += 1;
        }

        const task_name = record.task_name;

        // Get or create stats builder
        const gop = try task_map.getOrPut(task_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = TaskStatsBuilder.init(allocator);
        }

        // Update stats
        try gop.value_ptr.addRun(
            record.duration_ms,
            record.success,
            false, // We don't track cache in current history format
            record.retry_count,
        );

        // Update time series
        try gop.value_ptr.addTimeSeriesPoint(.{
            .timestamp = record.timestamp,
            .duration_ms = record.duration_ms,
            .success = record.success,
            .cache_hit = false,
        });
    }

    // Build final task stats
    var task_iter = task_map.iterator();
    while (task_iter.next()) |entry| {
        const stats = try entry.value_ptr.build(allocator, entry.key_ptr.*);
        try report.task_stats.append(allocator, stats);

        // Transfer time series data
        const owned_key = try allocator.dupe(u8, entry.key_ptr.*);
        try report.time_series.put(owned_key, entry.value_ptr.time_series);
        // Transfer ownership - create empty list to prevent double-free
        entry.value_ptr.time_series = std.ArrayList(types.TimeSeriesPoint){};
    }

    // Cache hit rate is 0 (we don't track cache in current history format)
    report.overall_cache_hit_rate = 0.0;

    // Calculate parallelization metrics
    const available_cores = try std.Thread.getCpuCount();
    report.parallelization = types.ParallelizationMetrics.init(
        total_wall_time,
        total_cpu_time,
        available_cores,
    );

    // Build critical path (simplified: longest tasks)
    if (records.items.len > 0) {
        try buildCriticalPath(allocator, &report, records.items);
    }

    return report;
}

/// Helper to build task statistics incrementally
const TaskStatsBuilder = struct {
    allocator: std.mem.Allocator,
    total_runs: usize,
    successful_runs: usize,
    failed_runs: usize,
    total_duration_ms: u64,
    min_duration_ms: u64,
    max_duration_ms: u64,
    cache_hits: usize,
    cache_misses: usize,
    total_retries: u32,
    time_series: std.ArrayList(types.TimeSeriesPoint),

    fn init(allocator: std.mem.Allocator) TaskStatsBuilder {
        return .{
            .allocator = allocator,
            .total_runs = 0,
            .successful_runs = 0,
            .failed_runs = 0,
            .total_duration_ms = 0,
            .min_duration_ms = std.math.maxInt(u64),
            .max_duration_ms = 0,
            .cache_hits = 0,
            .cache_misses = 0,
            .total_retries = 0,
            .time_series = std.ArrayList(types.TimeSeriesPoint){},
        };
    }

    fn deinit(self: *TaskStatsBuilder, allocator: std.mem.Allocator) void {
        self.time_series.deinit(allocator);
    }

    fn addRun(self: *TaskStatsBuilder, duration_ms: u64, success: bool, cached: bool, retry_count: u32) !void {
        self.total_runs += 1;
        if (success) {
            self.successful_runs += 1;
        } else {
            self.failed_runs += 1;
        }

        self.total_duration_ms += duration_ms;
        self.min_duration_ms = @min(self.min_duration_ms, duration_ms);
        self.max_duration_ms = @max(self.max_duration_ms, duration_ms);
        self.total_retries += retry_count;

        if (cached) {
            self.cache_hits += 1;
        } else {
            self.cache_misses += 1;
        }
    }

    fn addTimeSeriesPoint(self: *TaskStatsBuilder, point: types.TimeSeriesPoint) !void {
        try self.time_series.append(self.allocator, point);
    }

    fn build(self: TaskStatsBuilder, allocator: std.mem.Allocator, task_name: []const u8) !types.TaskStats {
        const avg_duration = if (self.total_runs > 0)
            @as(f64, @floatFromInt(self.total_duration_ms)) / @as(f64, @floatFromInt(self.total_runs))
        else
            0.0;

        const avg_retries = if (self.total_runs > 0)
            @as(f64, @floatFromInt(self.total_retries)) / @as(f64, @floatFromInt(self.total_runs))
        else
            0.0;

        return .{
            .task_name = try allocator.dupe(u8, task_name),
            .total_runs = self.total_runs,
            .successful_runs = self.successful_runs,
            .failed_runs = self.failed_runs,
            .avg_duration_ms = avg_duration,
            .min_duration_ms = if (self.min_duration_ms == std.math.maxInt(u64)) 0 else self.min_duration_ms,
            .max_duration_ms = self.max_duration_ms,
            .cache_hits = self.cache_hits,
            .cache_misses = self.cache_misses,
            .total_retries = self.total_retries,
            .avg_retries_per_run = avg_retries,
        };
    }
};

/// Build critical path from execution history (top slowest tasks)
fn buildCriticalPath(allocator: std.mem.Allocator, report: *types.AnalyticsReport, records: []const history.Record) !void {
    // Sort records by duration (descending) to identify bottlenecks
    var sorted_records = try allocator.alloc(history.Record, records.len);
    defer allocator.free(sorted_records);

    @memcpy(sorted_records, records);

    // Simple critical path: tasks sorted by duration
    std.mem.sort(history.Record, sorted_records, {}, struct {
        fn lessThan(_: void, a: history.Record, b: history.Record) bool {
            return a.duration_ms > b.duration_ms;
        }
    }.lessThan);

    // Take top N tasks as critical path
    const critical_path_size = @min(5, sorted_records.len);
    for (sorted_records[0..critical_path_size]) |record| {
        const task_name = try allocator.dupe(u8, record.task_name);
        try report.critical_path.append(allocator, .{
            .task_name = task_name,
            .duration_ms = record.duration_ms,
            .start_time = record.timestamp,
            .end_time = record.timestamp + @as(i64, @intCast(record.duration_ms)),
        });
    }
}

test "collectAnalytics with empty history" {
    // Use a nonexistent path to ensure empty history
    var report = try collectAnalyticsWithPath(std.testing.allocator, null, "/tmp/nonexistent-zr-history-test.jsonl");
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 0), report.total_executions);
    try std.testing.expectEqual(@as(usize, 0), report.task_stats.items.len);
}

test "TaskStatsBuilder accumulation" {
    var builder = TaskStatsBuilder.init(std.testing.allocator);
    defer builder.deinit(std.testing.allocator);

    try builder.addRun(100, true, false, 0);
    try builder.addRun(200, true, true, 2);
    try builder.addRun(150, false, false, 3);

    try std.testing.expectEqual(@as(usize, 3), builder.total_runs);
    try std.testing.expectEqual(@as(usize, 2), builder.successful_runs);
    try std.testing.expectEqual(@as(usize, 1), builder.failed_runs);
    try std.testing.expectEqual(@as(u64, 100), builder.min_duration_ms);
    try std.testing.expectEqual(@as(u64, 200), builder.max_duration_ms);
    try std.testing.expectEqual(@as(usize, 1), builder.cache_hits);
    try std.testing.expectEqual(@as(usize, 2), builder.cache_misses);
    try std.testing.expectEqual(@as(u32, 5), builder.total_retries);
}
