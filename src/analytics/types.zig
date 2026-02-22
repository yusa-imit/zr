const std = @import("std");

/// Task execution statistics
pub const TaskStats = struct {
    task_name: []const u8,
    total_runs: usize,
    successful_runs: usize,
    failed_runs: usize,
    avg_duration_ms: f64,
    min_duration_ms: u64,
    max_duration_ms: u64,
    cache_hits: usize,
    cache_misses: usize,

    pub fn cacheHitRate(self: TaskStats) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total)) * 100.0;
    }

    pub fn failureRate(self: TaskStats) f64 {
        if (self.total_runs == 0) return 0.0;
        return @as(f64, @floatFromInt(self.failed_runs)) / @as(f64, @floatFromInt(self.total_runs)) * 100.0;
    }
};

/// Time series data point for trend analysis
pub const TimeSeriesPoint = struct {
    timestamp: i64, // Unix timestamp
    duration_ms: u64,
    success: bool,
    cache_hit: bool,
};

/// Critical path node
pub const CriticalPathNode = struct {
    task_name: []const u8,
    duration_ms: u64,
    start_time: i64,
    end_time: i64,
};

/// Parallelization efficiency metrics
pub const ParallelizationMetrics = struct {
    total_wall_time_ms: u64, // Actual wall-clock time
    total_cpu_time_ms: u64, // Sum of all task durations
    theoretical_speedup: f64, // CPU time / wall time
    actual_parallelism: f64, // Average concurrent tasks
    efficiency: f64, // actual_parallelism / available_cores

    pub fn init(wall_time_ms: u64, cpu_time_ms: u64, available_cores: usize) ParallelizationMetrics {
        const theoretical = if (wall_time_ms > 0)
            @as(f64, @floatFromInt(cpu_time_ms)) / @as(f64, @floatFromInt(wall_time_ms))
        else
            0.0;

        const actual = if (wall_time_ms > 0)
            @as(f64, @floatFromInt(cpu_time_ms)) / @as(f64, @floatFromInt(wall_time_ms))
        else
            0.0;

        const eff = if (available_cores > 0)
            actual / @as(f64, @floatFromInt(available_cores))
        else
            0.0;

        return .{
            .total_wall_time_ms = wall_time_ms,
            .total_cpu_time_ms = cpu_time_ms,
            .theoretical_speedup = theoretical,
            .actual_parallelism = actual,
            .efficiency = eff * 100.0, // Convert to percentage
        };
    }
};

/// Complete analytics report
pub const AnalyticsReport = struct {
    allocator: std.mem.Allocator,
    task_stats: std.ArrayList(TaskStats),
    time_series: std.StringHashMap(std.ArrayList(TimeSeriesPoint)),
    critical_path: std.ArrayList(CriticalPathNode),
    parallelization: ParallelizationMetrics,
    overall_cache_hit_rate: f64,
    total_executions: usize,
    date_range_start: i64,
    date_range_end: i64,

    pub fn init(allocator: std.mem.Allocator) AnalyticsReport {
        return .{
            .allocator = allocator,
            .task_stats = std.ArrayList(TaskStats){},
            .time_series = std.StringHashMap(std.ArrayList(TimeSeriesPoint)).init(allocator),
            .critical_path = std.ArrayList(CriticalPathNode){},
            .parallelization = ParallelizationMetrics.init(0, 0, 1),
            .overall_cache_hit_rate = 0.0,
            .total_executions = 0,
            .date_range_start = 0,
            .date_range_end = 0,
        };
    }

    pub fn deinit(self: *AnalyticsReport) void {
        // Free task_name strings in task_stats
        for (self.task_stats.items) |stat| {
            self.allocator.free(stat.task_name);
        }
        self.task_stats.deinit(self.allocator);

        // Free time series data
        var it = self.time_series.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.time_series.deinit();

        // Free critical path strings
        for (self.critical_path.items) |node| {
            self.allocator.free(node.task_name);
        }
        self.critical_path.deinit(self.allocator);
    }
};

test "TaskStats cache hit rate calculation" {
    const stats = TaskStats{
        .task_name = "test",
        .total_runs = 10,
        .successful_runs = 8,
        .failed_runs = 2,
        .avg_duration_ms = 100.0,
        .min_duration_ms = 50,
        .max_duration_ms = 150,
        .cache_hits = 7,
        .cache_misses = 3,
    };

    try std.testing.expectApproxEqRel(70.0, stats.cacheHitRate(), 0.01);
}

test "TaskStats failure rate calculation" {
    const stats = TaskStats{
        .task_name = "test",
        .total_runs = 10,
        .successful_runs = 8,
        .failed_runs = 2,
        .avg_duration_ms = 100.0,
        .min_duration_ms = 50,
        .max_duration_ms = 150,
        .cache_hits = 0,
        .cache_misses = 0,
    };

    try std.testing.expectApproxEqRel(20.0, stats.failureRate(), 0.01);
}

test "ParallelizationMetrics efficiency calculation" {
    const metrics = ParallelizationMetrics.init(1000, 4000, 4);
    try std.testing.expectApproxEqRel(4.0, metrics.theoretical_speedup, 0.01);
    try std.testing.expectApproxEqRel(100.0, metrics.efficiency, 0.01);
}

test "AnalyticsReport init and deinit" {
    var report = AnalyticsReport.init(std.testing.allocator);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 0), report.task_stats.items.len);
    try std.testing.expectEqual(@as(usize, 0), report.total_executions);
}
