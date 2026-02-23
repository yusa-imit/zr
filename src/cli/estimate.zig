const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const history = @import("../history/store.zig");

pub const OutputFormat = enum {
    text,
    json,
};

pub fn cmdEstimate(
    allocator: Allocator,
    task_name: []const u8,
    config_path: []const u8,
    limit: usize,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
    output_format: OutputFormat,
) !u8 {
    // Load config to verify task exists
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    if (config.tasks.get(task_name) == null) {
        try color.printError(ew, use_color,
            "estimate: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    }

    // Load history
    const history_path = try history.defaultHistoryPath(allocator);
    defer allocator.free(history_path);

    var store = try history.Store.init(allocator, history_path);
    defer store.deinit();

    var records = try store.loadLast(allocator, 1000); // Load last 1000 records
    defer {
        for (records.items) |r| r.deinit(allocator);
        records.deinit(allocator);
    }

    // Filter records for this specific task
    var task_records = std.ArrayList(history.Record){};
    defer task_records.deinit(allocator);

    for (records.items) |record| {
        if (std.mem.eql(u8, record.task_name, task_name)) {
            try task_records.append(allocator, .{
                .timestamp = record.timestamp,
                .task_name = record.task_name,
                .success = record.success,
                .duration_ms = record.duration_ms,
                .task_count = record.task_count,
                .retry_count = record.retry_count,
            });
        }
    }

    if (task_records.items.len == 0) {
        try color.printWarning(w, use_color,
            "No execution history found for task '{s}'\n\n  Hint: Run 'zr run {s}' first to build history\n",
            .{ task_name, task_name },
        );
        return 0;
    }

    // Limit to last N records
    const start_idx = if (task_records.items.len > limit) task_records.items.len - limit else 0;
    const limited_records = task_records.items[start_idx..];

    // Calculate statistics
    const stats = calculateStats(limited_records);

    // Print estimation report
    switch (output_format) {
        .text => try printEstimation(w, task_name, limited_records, stats, use_color),
        .json => try printEstimationJson(allocator, w, task_name, limited_records, stats),
    }

    return 0;
}

const Stats = struct {
    mean_ms: f64,
    median_ms: u64,
    min_ms: u64,
    max_ms: u64,
    std_dev: f64,
    success_rate: f64,
};

fn calculateStats(records: []const history.Record) Stats {
    if (records.len == 0) {
        return .{
            .mean_ms = 0,
            .median_ms = 0,
            .min_ms = 0,
            .max_ms = 0,
            .std_dev = 0,
            .success_rate = 0,
        };
    }

    // Calculate mean
    var sum: u64 = 0;
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;
    var success_count: usize = 0;

    for (records) |r| {
        sum += r.duration_ms;
        if (r.duration_ms < min) min = r.duration_ms;
        if (r.duration_ms > max) max = r.duration_ms;
        if (r.success) success_count += 1;
    }

    const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(records.len));

    // Calculate standard deviation
    var variance_sum: f64 = 0;
    for (records) |r| {
        const diff = @as(f64, @floatFromInt(r.duration_ms)) - mean;
        variance_sum += diff * diff;
    }
    const variance = variance_sum / @as(f64, @floatFromInt(records.len));
    const std_dev = @sqrt(variance);

    // Calculate median (sort a copy)
    var durations_buf: [1000]u64 = undefined;
    const dur_len = @min(records.len, 1000);
    for (records[0..dur_len], 0..) |r, i| {
        durations_buf[i] = r.duration_ms;
    }
    std.mem.sort(u64, durations_buf[0..dur_len], {}, std.sort.asc(u64));
    const median = durations_buf[dur_len / 2];

    const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(records.len)) * 100.0;

    return .{
        .mean_ms = mean,
        .median_ms = median,
        .min_ms = min,
        .max_ms = max,
        .std_dev = std_dev,
        .success_rate = success_rate,
    };
}

fn printEstimationJson(
    _: Allocator,
    w: *std.Io.Writer,
    task_name: []const u8,
    records: []const history.Record,
    stats: Stats,
) !void {
    // Calculate coefficient of variation
    const cv = if (stats.mean_ms > 0) (stats.std_dev / stats.mean_ms) * 100.0 else 0.0;

    // Determine confidence level
    const confidence = if (cv < 20.0)
        "high"
    else if (cv < 50.0)
        "medium"
    else
        "low";

    // Calculate trend
    var trend: []const u8 = "stable";
    var trend_percentage: f64 = 0.0;
    if (records.len >= 6) {
        const recent_end = records.len;
        const recent_start = records.len - 3;
        const older_end = recent_start;
        const older_start = if (older_end >= 3) older_end - 3 else 0;

        const recent_avg = calculateAverage(records[recent_start..recent_end]);
        const older_avg = calculateAverage(records[older_start..older_end]);

        if (recent_avg < older_avg) {
            trend = "faster";
            trend_percentage = ((older_avg - recent_avg) / older_avg) * 100.0;
        } else if (recent_avg > older_avg) {
            trend = "slower";
            trend_percentage = ((recent_avg - older_avg) / older_avg) * 100.0;
        }
    }

    // Build JSON output
    try w.print("{{", .{});
    try w.print("\"task\":\"{s}\",", .{task_name});
    try w.print("\"sample_size\":{d},", .{records.len});
    try w.print("\"duration\":{{", .{});
    try w.print("\"mean_ms\":{d:.2},", .{stats.mean_ms});
    try w.print("\"median_ms\":{d},", .{stats.median_ms});
    try w.print("\"min_ms\":{d},", .{stats.min_ms});
    try w.print("\"max_ms\":{d}", .{stats.max_ms});
    try w.print("}},", .{});
    try w.print("\"variability\":{{", .{});
    try w.print("\"std_dev_ms\":{d:.2},", .{stats.std_dev});
    try w.print("\"coefficient_of_variation\":{d:.2},", .{cv});
    try w.print("\"confidence\":\"{s}\"", .{confidence});
    try w.print("}},", .{});
    try w.print("\"reliability\":{{", .{});
    try w.print("\"success_rate\":{d:.2}", .{stats.success_rate});
    try w.print("}}", .{});
    if (records.len >= 6) {
        try w.print(",\"trend\":{{", .{});
        try w.print("\"direction\":\"{s}\",", .{trend});
        try w.print("\"percentage\":{d:.2}", .{trend_percentage});
        try w.print("}}", .{});
    }
    try w.print("}}\n", .{});
}

fn printEstimation(
    w: *std.Io.Writer,
    task_name: []const u8,
    records: []const history.Record,
    stats: Stats,
    use_color: bool,
) !void {
    try color.printBold(w, use_color, "Estimation for task '{s}':\n\n", .{task_name});

    // Sample size
    try w.print("  Sample size:     {d} run(s)\n", .{records.len});

    // Duration estimates
    try color.printBold(w, use_color, "\n  Duration:\n", .{});
    try w.print("    Mean:          {s}\n", .{formatDuration(stats.mean_ms)});
    try w.print("    Median:        {s}\n", .{formatDuration(@as(f64, @floatFromInt(stats.median_ms)))});
    try w.print("    Range:         {s} - {s}\n", .{
        formatDuration(@as(f64, @floatFromInt(stats.min_ms))),
        formatDuration(@as(f64, @floatFromInt(stats.max_ms))),
    });

    // Variability
    const cv = if (stats.mean_ms > 0) (stats.std_dev / stats.mean_ms) * 100.0 else 0.0;
    try color.printBold(w, use_color, "\n  Variability:\n", .{});
    try w.print("    Std Dev:       {s}\n", .{formatDuration(stats.std_dev)});
    try w.print("    Coeff. Var:    {d:.1}%\n", .{cv});

    // Confidence
    const confidence = if (cv < 20.0)
        "High (consistent)"
    else if (cv < 50.0)
        "Medium (some variance)"
    else
        "Low (highly variable)";

    try w.print("    Confidence:    {s}\n", .{confidence});

    // Success rate
    try color.printBold(w, use_color, "\n  Reliability:\n", .{});
    if (stats.success_rate >= 95.0) {
        try color.printSuccess(w, use_color, "    Success Rate:  {d:.1}% ✓\n", .{stats.success_rate});
    } else if (stats.success_rate >= 80.0) {
        try color.printWarning(w, use_color, "    Success Rate:  {d:.1}% ⚠\n", .{stats.success_rate});
    } else {
        try color.printError(w, use_color, "    Success Rate:  {d:.1}% ✗\n", .{stats.success_rate});
    }

    // Trend analysis (last 3 vs previous)
    if (records.len >= 6) {
        const recent_end = records.len;
        const recent_start = records.len - 3;
        const older_end = recent_start;
        const older_start = if (older_end >= 3) older_end - 3 else 0;

        const recent_avg = calculateAverage(records[recent_start..recent_end]);
        const older_avg = calculateAverage(records[older_start..older_end]);

        try color.printBold(w, use_color, "\n  Trend:\n", .{});
        if (recent_avg < older_avg) {
            const improvement = ((older_avg - recent_avg) / older_avg) * 100.0;
            try color.printSuccess(w, use_color, "    Getting faster ↓ ({d:.1}% improvement)\n", .{improvement});
        } else if (recent_avg > older_avg) {
            const degradation = ((recent_avg - older_avg) / older_avg) * 100.0;
            try color.printWarning(w, use_color, "    Getting slower ↑ ({d:.1}% slower)\n", .{degradation});
        } else {
            try w.print("    Stable → (no significant change)\n", .{});
        }
    }

    try w.print("\n", .{});
}

fn calculateAverage(records: []const history.Record) f64 {
    if (records.len == 0) return 0;
    var sum: u64 = 0;
    for (records) |r| sum += r.duration_ms;
    return @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(records.len));
}

fn formatDuration(ms: f64) []const u8 {
    const ms_int: u64 = @intFromFloat(ms);
    if (ms_int < 1000) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d}ms", .{ms_int}) catch "?ms";
    } else if (ms_int < 60_000) {
        const s = @as(f64, @floatFromInt(ms_int)) / 1000.0;
        return std.fmt.allocPrint(std.heap.page_allocator, "{d:.1}s", .{s}) catch "?s";
    } else {
        const m = @as(f64, @floatFromInt(ms_int)) / 60_000.0;
        return std.fmt.allocPrint(std.heap.page_allocator, "{d:.1}min", .{m}) catch "?min";
    }
}

// Tests
test "calculateStats empty" {
    const stats = calculateStats(&.{});
    try std.testing.expectEqual(@as(f64, 0), stats.mean_ms);
    try std.testing.expectEqual(@as(u64, 0), stats.median_ms);
}

test "calculateStats single record" {
    const records = [_]history.Record{.{
        .timestamp = 1000,
        .task_name = "test",
        .success = true,
        .duration_ms = 500,
        .task_count = 1,
        .retry_count = 0,
    }};
    const stats = calculateStats(&records);
    try std.testing.expectEqual(@as(f64, 500), stats.mean_ms);
    try std.testing.expectEqual(@as(u64, 500), stats.median_ms);
    try std.testing.expectEqual(@as(u64, 500), stats.min_ms);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ms);
    try std.testing.expectEqual(@as(f64, 100.0), stats.success_rate);
}

test "calculateStats multiple records" {
    const records = [_]history.Record{
        .{
            .timestamp = 1000,
            .task_name = "test",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        .{
            .timestamp = 2000,
            .task_name = "test",
            .success = true,
            .duration_ms = 200,
            .task_count = 1,
            .retry_count = 0,
        },
        .{
            .timestamp = 3000,
            .task_name = "test",
            .success = false,
            .duration_ms = 300,
            .task_count = 1,
            .retry_count = 0,
        },
    };
    const stats = calculateStats(&records);
    try std.testing.expectEqual(@as(f64, 200), stats.mean_ms);
    try std.testing.expectEqual(@as(u64, 200), stats.median_ms);
    try std.testing.expectEqual(@as(u64, 100), stats.min_ms);
    try std.testing.expectEqual(@as(u64, 300), stats.max_ms);
    try std.testing.expectApproxEqAbs(@as(f64, 66.67), stats.success_rate, 0.1);
}

test "calculateAverage" {
    const records = [_]history.Record{
        .{
            .timestamp = 1000,
            .task_name = "test",
            .success = true,
            .duration_ms = 100,
            .task_count = 1,
            .retry_count = 0,
        },
        .{
            .timestamp = 2000,
            .task_name = "test",
            .success = true,
            .duration_ms = 300,
            .task_count = 1,
            .retry_count = 0,
        },
    };
    const avg = calculateAverage(&records);
    try std.testing.expectEqual(@as(f64, 200), avg);
}

// Note: JSON output format testing is done via integration tests
// See tests/integration.zig for JSON format validation
