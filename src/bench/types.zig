const std = @import("std");

/// A single benchmark run result.
pub const BenchmarkRun = struct {
    duration_ns: u64,
    exit_code: u8,
    timestamp: i64,
};

/// Statistical summary of benchmark runs.
pub const BenchmarkStats = struct {
    mean_ns: u64,
    median_ns: u64,
    min_ns: u64,
    max_ns: u64,
    std_dev_ns: u64,
    runs: []const BenchmarkRun,
    total_runs: usize,
    successful_runs: usize,
    failed_runs: usize,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BenchmarkStats {
        return .{
            .mean_ns = 0,
            .median_ns = 0,
            .min_ns = 0,
            .max_ns = 0,
            .std_dev_ns = 0,
            .runs = &[_]BenchmarkRun{},
            .total_runs = 0,
            .successful_runs = 0,
            .failed_runs = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BenchmarkStats) void {
        self.allocator.free(self.runs);
    }
};

/// Configuration for benchmark execution.
pub const BenchmarkConfig = struct {
    task_name: []const u8,
    iterations: usize = 10,
    warmup_runs: usize = 2,
    config_path: ?[]const u8 = null,
    profile: ?[]const u8 = null,
    quiet: bool = false,
    /// Output format: text, json, csv
    format: enum { text, json, csv } = .text,
};

test "BenchmarkStats init/deinit" {
    const allocator = std.testing.allocator;
    var stats = BenchmarkStats.init(allocator);
    stats.deinit();
}

test "BenchmarkRun size" {
    const run = BenchmarkRun{
        .duration_ns = 1000000,
        .exit_code = 0,
        .timestamp = std.time.timestamp(),
    };
    try std.testing.expect(run.duration_ns == 1000000);
    try std.testing.expect(run.exit_code == 0);
}
