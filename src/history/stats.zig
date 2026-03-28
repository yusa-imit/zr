const std = @import("std");
const store = @import("store.zig");
const Record = store.Record;

/// Statistical summary of task durations.
pub const DurationStats = struct {
    /// Minimum duration in milliseconds.
    min_ms: u64,
    /// Maximum duration in milliseconds.
    max_ms: u64,
    /// Average duration in milliseconds.
    avg_ms: u64,
    /// 50th percentile (median) in milliseconds.
    p50_ms: u64,
    /// 90th percentile in milliseconds.
    p90_ms: u64,
    /// 99th percentile in milliseconds.
    p99_ms: u64,
    /// Standard deviation in milliseconds.
    std_dev_ms: f64,
    /// Number of samples used to calculate statistics.
    sample_count: usize,
};

/// Calculate statistics for a specific task from history records.
/// Returns null if no records found for the given task_name.
pub fn calculateStats(records: []const Record, task_name: []const u8, allocator: std.mem.Allocator) !?DurationStats {
    // Filter records by task name and collect durations
    var durations = std.ArrayList(u64){};
    defer durations.deinit(allocator);

    for (records) |record| {
        if (std.mem.eql(u8, record.task_name, task_name)) {
            try durations.append(allocator, record.duration_ms);
        }
    }

    if (durations.items.len == 0) return null;

    // Sort durations for percentile calculations
    std.mem.sort(u64, durations.items, {}, comptime std.sort.asc(u64));

    const n = durations.items.len;
    const sorted = durations.items;

    // Calculate min, max
    const min_ms = sorted[0];
    const max_ms = sorted[n - 1];

    // Calculate average
    var sum: u64 = 0;
    for (sorted) |d| sum += d;
    const avg_ms = sum / n;

    // Calculate percentiles using linear interpolation
    const p50_ms = calculatePercentile(sorted, 0.50);
    const p90_ms = calculatePercentile(sorted, 0.90);
    const p99_ms = calculatePercentile(sorted, 0.99);

    // Calculate standard deviation
    var variance_sum: f64 = 0.0;
    const avg_f64 = @as(f64, @floatFromInt(avg_ms));
    for (sorted) |d| {
        const diff = @as(f64, @floatFromInt(d)) - avg_f64;
        variance_sum += diff * diff;
    }
    const variance = variance_sum / @as(f64, @floatFromInt(n));
    const std_dev_ms = @sqrt(variance);

    return DurationStats{
        .min_ms = min_ms,
        .max_ms = max_ms,
        .avg_ms = avg_ms,
        .p50_ms = p50_ms,
        .p90_ms = p90_ms,
        .p99_ms = p99_ms,
        .std_dev_ms = std_dev_ms,
        .sample_count = n,
    };
}

/// Calculate a percentile from sorted values using linear interpolation.
fn calculatePercentile(sorted: []const u64, percentile: f64) u64 {
    const n = sorted.len;
    if (n == 1) return sorted[0];

    const index_f = percentile * @as(f64, @floatFromInt(n - 1));
    const index_floor = @as(usize, @intFromFloat(@floor(index_f)));
    const index_ceil = @min(index_floor + 1, n - 1);
    const frac = index_f - @floor(index_f);

    const val_floor = @as(f64, @floatFromInt(sorted[index_floor]));
    const val_ceil = @as(f64, @floatFromInt(sorted[index_ceil]));
    const interpolated = val_floor + frac * (val_ceil - val_floor);

    return @as(u64, @intFromFloat(@round(interpolated)));
}

/// Detect if a duration is anomalous compared to historical statistics.
/// Returns true if duration >= 2x p90 threshold.
pub fn isAnomaly(duration_ms: u64, stats: DurationStats) bool {
    return duration_ms >= 2 * stats.p90_ms;
}

/// Format statistics as a human-readable estimation string.
/// Example: "~1.2s (avg), 0.8-3.5s range"
/// Caller must free returned string.
pub fn formatEstimate(stats: DurationStats, allocator: std.mem.Allocator) ![]const u8 {
    // Determine appropriate unit based on average duration
    if (stats.avg_ms < 1000) {
        // Sub-second: use milliseconds
        return std.fmt.allocPrint(allocator, "~{d}ms (avg), {d}-{d}ms range", .{
            stats.avg_ms,
            stats.min_ms,
            stats.max_ms,
        });
    } else if (stats.avg_ms < 60000) {
        // Seconds
        const avg_s = @as(f64, @floatFromInt(stats.avg_ms)) / 1000.0;
        const min_s = @as(f64, @floatFromInt(stats.min_ms)) / 1000.0;
        const max_s = @as(f64, @floatFromInt(stats.max_ms)) / 1000.0;
        return std.fmt.allocPrint(allocator, "~{d:.1}s (avg), {d:.1}-{d:.1}s range", .{
            avg_s,
            min_s,
            max_s,
        });
    } else if (stats.avg_ms < 3600000) {
        // Minutes
        const avg_m = @as(f64, @floatFromInt(stats.avg_ms)) / 60000.0;
        const min_m = @as(f64, @floatFromInt(stats.min_ms)) / 60000.0;
        const max_m = @as(f64, @floatFromInt(stats.max_ms)) / 60000.0;
        return std.fmt.allocPrint(allocator, "~{d:.1}m (avg), {d:.1}-{d:.1}m range", .{
            avg_m,
            min_m,
            max_m,
        });
    } else {
        // Hours
        const avg_h = @as(f64, @floatFromInt(stats.avg_ms)) / 3600000.0;
        const min_h = @as(f64, @floatFromInt(stats.min_ms)) / 3600000.0;
        const max_h = @as(f64, @floatFromInt(stats.max_ms)) / 3600000.0;
        return std.fmt.allocPrint(allocator, "~{d:.1}h (avg), {d:.1}-{d:.1}h range", .{
            avg_h,
            min_h,
            max_h,
        });
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "calculateStats: empty history returns null" {
    const allocator = std.testing.allocator;
    const records: []const Record = &[_]Record{};

    const result = try calculateStats(records, "build", allocator);
    try std.testing.expectEqual(@as(?DurationStats, null), result);
}

test "calculateStats: no matching task returns null" {
    const allocator = std.testing.allocator;

    // Create records with different task names
    const r1 = Record{
        .timestamp = 1000,
        .task_name = "test",
        .success = true,
        .duration_ms = 100,
        .task_count = 1,
        .retry_count = 0,
    };
    const r2 = Record{
        .timestamp = 2000,
        .task_name = "lint",
        .success = true,
        .duration_ms = 50,
        .task_count = 1,
        .retry_count = 0,
    };

    const records = [_]Record{ r1, r2 };
    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expectEqual(@as(?DurationStats, null), result);
}

test "calculateStats: single record returns all stats equal to that value" {
    const allocator = std.testing.allocator;

    const r1 = Record{
        .timestamp = 1000,
        .task_name = "build",
        .success = true,
        .duration_ms = 1234,
        .task_count = 1,
        .retry_count = 0,
    };

    const records = [_]Record{r1};
    const result = try calculateStats(&records, "build", allocator);

    try std.testing.expect(result != null);
    const stats = result.?;

    // All values should equal the single duration
    try std.testing.expectEqual(@as(u64, 1234), stats.min_ms);
    try std.testing.expectEqual(@as(u64, 1234), stats.max_ms);
    try std.testing.expectEqual(@as(u64, 1234), stats.avg_ms);
    try std.testing.expectEqual(@as(u64, 1234), stats.p50_ms);
    try std.testing.expectEqual(@as(u64, 1234), stats.p90_ms);
    try std.testing.expectEqual(@as(u64, 1234), stats.p99_ms);
    try std.testing.expectEqual(@as(f64, 0.0), stats.std_dev_ms);
    try std.testing.expectEqual(@as(usize, 1), stats.sample_count);
}

test "calculateStats: multiple records same task correct min/max/avg" {
    const allocator = std.testing.allocator;

    // Durations: 100, 200, 300, 400, 500
    // Min: 100, Max: 500, Avg: 300
    const records = [_]Record{
        Record{
            .timestamp = 1000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 2000,
            .task_name = "build",
            .success = true,
            .duration_ms = 200,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 3000,
            .task_name = "build",
            .success = true,
            .duration_ms = 300,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 4000,
            .task_name = "build",
            .success = true,
            .duration_ms = 400,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 5000,
            .task_name = "build",
            .success = true,
            .duration_ms = 500,
            .task_count = 1,
            .retry_count = 0,
        },
    };

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    try std.testing.expectEqual(@as(u64, 100), stats.min_ms);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ms);
    try std.testing.expectEqual(@as(u64, 300), stats.avg_ms);
    try std.testing.expectEqual(@as(usize, 5), stats.sample_count);
}

test "calculateStats: filters by task name correctly" {
    const allocator = std.testing.allocator;

    // Mix of build (100, 300) and test (200, 400) tasks
    const records = [_]Record{
        Record{
            .timestamp = 1000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 2000,
            .task_name = "test",
            .success = true,
            .duration_ms = 200,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 3000,
            .task_name = "build",
            .success = true,
            .duration_ms = 300,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 4000,
            .task_name = "test",
            .success = true,
            .duration_ms = 400,
            .task_count = 1,
            .retry_count = 0,
        },
    };

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    // Should only include build tasks (100, 300)
    try std.testing.expectEqual(@as(u64, 100), stats.min_ms);
    try std.testing.expectEqual(@as(u64, 300), stats.max_ms);
    try std.testing.expectEqual(@as(u64, 200), stats.avg_ms); // (100 + 300) / 2
    try std.testing.expectEqual(@as(usize, 2), stats.sample_count);
}

test "calculateStats: p50 (median) calculation with odd count" {
    const allocator = std.testing.allocator;

    // Durations: 100, 200, 300, 400, 500 (sorted)
    // Median (p50) should be 300 (middle value)
    const records = [_]Record{
        Record{
            .timestamp = 1000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 2000,
            .task_name = "build",
            .success = true,
            .duration_ms = 300,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 3000,
            .task_name = "build",
            .success = true,
            .duration_ms = 500,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 4000,
            .task_name = "build",
            .success = true,
            .duration_ms = 200,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 5000,
            .task_name = "build",
            .success = true,
            .duration_ms = 400,
            .task_count = 1,
            .retry_count = 0,
        },
    };

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    try std.testing.expectEqual(@as(u64, 300), stats.p50_ms);
}

test "calculateStats: p50 (median) calculation with even count" {
    const allocator = std.testing.allocator;

    // Durations: 100, 200, 300, 400 (sorted)
    // Median should be (200 + 300) / 2 = 250
    const records = [_]Record{
        Record{
            .timestamp = 1000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 2000,
            .task_name = "build",
            .success = true,
            .duration_ms = 200,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 3000,
            .task_name = "build",
            .success = true,
            .duration_ms = 300,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 4000,
            .task_name = "build",
            .success = true,
            .duration_ms = 400,
            .task_count = 1,
            .retry_count = 0,
        },
    };

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    try std.testing.expectEqual(@as(u64, 250), stats.p50_ms);
}

test "calculateStats: p90 calculation" {
    const allocator = std.testing.allocator;

    // Create 10 records with durations 100, 200, ..., 1000
    // p90 should be at 90th percentile position
    var records: [10]Record = undefined;
    for (0..10) |i| {
        records[i] = Record{
            .timestamp = @intCast(1000 * (i + 1)),
            .task_name = "build",
            .success = true,
            .duration_ms = @intCast((i + 1) * 100),
            .task_count = 1,
            .retry_count = 0,
        };
    }

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    // p90 for 10 samples: position = 0.9 * (10 - 1) = 8.1 → interpolate between index 8 and 9
    // values[8] = 900, values[9] = 1000, so p90 ≈ 900 + 0.1 * (1000 - 900) = 910
    // Acceptable range: 900-1000 (implementation may vary)
    try std.testing.expect(stats.p90_ms >= 900 and stats.p90_ms <= 1000);
}

test "calculateStats: p99 calculation" {
    const allocator = std.testing.allocator;

    // Create 100 records with durations 10, 20, ..., 1000
    var records: [100]Record = undefined;
    for (0..100) |i| {
        records[i] = Record{
            .timestamp = @intCast(1000 * (i + 1)),
            .task_name = "build",
            .success = true,
            .duration_ms = @intCast((i + 1) * 10),
            .task_count = 1,
            .retry_count = 0,
        };
    }

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    // p99 for 100 samples: position = 0.99 * (100 - 1) = 98.01 → interpolate between index 98 and 99
    // values[98] = 990, values[99] = 1000, so p99 ≈ 990 + 0.01 * (1000 - 990) = 990.1
    // Acceptable range: 980-1000
    try std.testing.expect(stats.p99_ms >= 980 and stats.p99_ms <= 1000);
}

test "calculateStats: standard deviation calculation" {
    const allocator = std.testing.allocator;

    // Durations: 100, 200, 300, 400, 500
    // Mean = 300
    // Variance = [(100-300)^2 + (200-300)^2 + (300-300)^2 + (400-300)^2 + (500-300)^2] / 5
    //          = [40000 + 10000 + 0 + 10000 + 40000] / 5
    //          = 100000 / 5 = 20000
    // Std Dev = sqrt(20000) ≈ 141.42
    const records = [_]Record{
        Record{
            .timestamp = 1000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 2000,
            .task_name = "build",
            .success = true,
            .duration_ms = 200,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 3000,
            .task_name = "build",
            .success = true,
            .duration_ms = 300,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 4000,
            .task_name = "build",
            .success = true,
            .duration_ms = 400,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 5000,
            .task_name = "build",
            .success = true,
            .duration_ms = 500,
            .task_count = 1,
            .retry_count = 0,
        },
    };

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    // Allow small floating point error (within 1%)
    const expected_std_dev = 141.42;
    try std.testing.expect(@abs(stats.std_dev_ms - expected_std_dev) < 2.0);
}

test "calculateStats: zero variance dataset" {
    const allocator = std.testing.allocator;

    // All durations are identical (100ms)
    const records = [_]Record{
        Record{
            .timestamp = 1000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 2000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        Record{
            .timestamp = 3000,
            .task_name = "build",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
    };

    const result = try calculateStats(&records, "build", allocator);
    try std.testing.expect(result != null);
    const stats = result.?;

    // Standard deviation should be 0 (no variance)
    try std.testing.expectEqual(@as(f64, 0.0), stats.std_dev_ms);
}

test "isAnomaly: normal duration not anomalous" {
    const stats = DurationStats{
        .min_ms = 100,
        .max_ms = 500,
        .avg_ms = 300,
        .p50_ms = 300,
        .p90_ms = 450,
        .p99_ms = 490,
        .std_dev_ms = 100.0,
        .sample_count = 10,
    };

    // 400ms is normal (< 2x p90 = 900ms)
    try std.testing.expect(!isAnomaly(400, stats));
}

test "isAnomaly: exactly 2x p90 is anomalous" {
    const stats = DurationStats{
        .min_ms = 100,
        .max_ms = 500,
        .avg_ms = 300,
        .p50_ms = 300,
        .p90_ms = 450,
        .p99_ms = 490,
        .std_dev_ms = 100.0,
        .sample_count = 10,
    };

    // 900ms = 2 * 450ms (p90) → anomalous
    try std.testing.expect(isAnomaly(900, stats));
}

test "isAnomaly: greater than 2x p90 is anomalous" {
    const stats = DurationStats{
        .min_ms = 100,
        .max_ms = 500,
        .avg_ms = 300,
        .p50_ms = 300,
        .p90_ms = 450,
        .p99_ms = 490,
        .std_dev_ms = 100.0,
        .sample_count = 10,
    };

    // 1000ms > 2 * 450ms → anomalous
    try std.testing.expect(isAnomaly(1000, stats));
}

test "isAnomaly: just below 2x p90 threshold not anomalous" {
    const stats = DurationStats{
        .min_ms = 100,
        .max_ms = 500,
        .avg_ms = 300,
        .p50_ms = 300,
        .p90_ms = 450,
        .p99_ms = 490,
        .std_dev_ms = 100.0,
        .sample_count = 10,
    };

    // 899ms < 2 * 450ms = 900ms → not anomalous
    try std.testing.expect(!isAnomaly(899, stats));
}

test "isAnomaly: 3x p90 is anomalous" {
    const stats = DurationStats{
        .min_ms = 100,
        .max_ms = 500,
        .avg_ms = 300,
        .p50_ms = 300,
        .p90_ms = 450,
        .p99_ms = 490,
        .std_dev_ms = 100.0,
        .sample_count = 10,
    };

    // 1350ms = 3 * 450ms → highly anomalous
    try std.testing.expect(isAnomaly(1350, stats));
}

test "formatEstimate: basic formatting" {
    const allocator = std.testing.allocator;

    const stats = DurationStats{
        .min_ms = 100,
        .max_ms = 500,
        .avg_ms = 300,
        .p50_ms = 300,
        .p90_ms = 450,
        .p99_ms = 490,
        .std_dev_ms = 100.0,
        .sample_count = 10,
    };

    const result = try formatEstimate(stats, allocator);
    defer allocator.free(result);

    // Should contain average and range
    try std.testing.expect(std.mem.indexOf(u8, result, "0.3s") != null or
                          std.mem.indexOf(u8, result, "300ms") != null); // avg
    try std.testing.expect(std.mem.indexOf(u8, result, "0.1") != null or
                          std.mem.indexOf(u8, result, "100") != null); // min
    try std.testing.expect(std.mem.indexOf(u8, result, "0.5") != null or
                          std.mem.indexOf(u8, result, "500") != null); // max
}

test "formatEstimate: sub-second durations use milliseconds" {
    const allocator = std.testing.allocator;

    const stats = DurationStats{
        .min_ms = 10,
        .max_ms = 50,
        .avg_ms = 30,
        .p50_ms = 30,
        .p90_ms = 45,
        .p99_ms = 49,
        .std_dev_ms = 10.0,
        .sample_count = 10,
    };

    const result = try formatEstimate(stats, allocator);
    defer allocator.free(result);

    // Should use milliseconds for sub-second durations
    try std.testing.expect(std.mem.indexOf(u8, result, "ms") != null);
}

test "formatEstimate: multi-second durations use seconds" {
    const allocator = std.testing.allocator;

    const stats = DurationStats{
        .min_ms = 1000,
        .max_ms = 5000,
        .avg_ms = 3000,
        .p50_ms = 3000,
        .p90_ms = 4500,
        .p99_ms = 4900,
        .std_dev_ms = 1000.0,
        .sample_count = 10,
    };

    const result = try formatEstimate(stats, allocator);
    defer allocator.free(result);

    // Should use seconds for multi-second durations
    try std.testing.expect(std.mem.indexOf(u8, result, "s") != null);
    // Should show seconds (e.g., "3.0s", "1.0-5.0s")
    try std.testing.expect(std.mem.indexOf(u8, result, ".") != null);
}

test "formatEstimate: large durations use appropriate units" {
    const allocator = std.testing.allocator;

    const stats = DurationStats{
        .min_ms = 60_000, // 1 minute
        .max_ms = 180_000, // 3 minutes
        .avg_ms = 120_000, // 2 minutes
        .p50_ms = 120_000,
        .p90_ms = 162_000,
        .p99_ms = 177_000,
        .std_dev_ms = 30_000.0,
        .sample_count = 10,
    };

    const result = try formatEstimate(stats, allocator);
    defer allocator.free(result);

    // Should be human-readable (could be "2m", "120s", etc.)
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "avg") != null or
                          std.mem.indexOf(u8, result, "~") != null);
}
