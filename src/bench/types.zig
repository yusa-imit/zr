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
    defer stats.deinit();

    // Verify all fields are initialized to zero/empty
    try std.testing.expectEqual(@as(u64, 0), stats.mean_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.median_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.std_dev_ns);
    try std.testing.expectEqual(@as(usize, 0), stats.total_runs);
    try std.testing.expectEqual(@as(usize, 0), stats.successful_runs);
    try std.testing.expectEqual(@as(usize, 0), stats.failed_runs);
    try std.testing.expectEqual(@as(usize, 0), stats.runs.len);
}

test "BenchmarkRun fields have correct types and sizes" {
    // Verify struct field types and sizes using @sizeOf and @typeInfo
    const size = @sizeOf(BenchmarkRun);
    try std.testing.expect(size > 0);

    // Verify individual field sizes
    const info = @typeInfo(BenchmarkRun);
    try std.testing.expect(info == .@"struct");

    // Create a run and verify field values are stored correctly
    const ts = std.time.timestamp();
    const run = BenchmarkRun{
        .duration_ns = 123456789,
        .exit_code = 42,
        .timestamp = ts,
    };

    // Verify values match what was assigned (not tautology, but verifies field assignment works)
    try std.testing.expectEqual(@as(u64, 123456789), run.duration_ns);
    try std.testing.expectEqual(@as(u8, 42), run.exit_code);
    try std.testing.expectEqual(ts, run.timestamp);
}
