const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const history = @import("../history/store.zig");
const stats_mod = @import("../history/stats.zig");

pub const OutputFormat = enum {
    text,
    json,
};

pub fn cmdEstimate(
    allocator: Allocator,
    task_name: []const u8,
    config_path: []const u8,
    _: usize, // limit parameter kept for API compatibility but unused (stats module handles all records)
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

    // Calculate statistics using shared stats module
    const task_stats = try stats_mod.calculateStats(records.items, task_name, allocator);

    if (task_stats == null) {
        try color.printWarning(w, use_color,
            "No execution history found for task '{s}'\n\n  Hint: Run 'zr run {s}' first to build history\n",
            .{ task_name, task_name },
        );
        return 0;
    }

    const stats = task_stats.?;

    // Also calculate success rate (not in stats module)
    var success_count: usize = 0;
    var total_count: usize = 0;
    for (records.items) |record| {
        if (std.mem.eql(u8, record.task_name, task_name)) {
            total_count += 1;
            if (record.success) success_count += 1;
        }
    }
    const success_rate = if (total_count > 0)
        @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(total_count)) * 100.0
    else 0.0;

    // Print estimation report
    switch (output_format) {
        .text => try printEstimation(w, task_name, stats, success_rate, use_color),
        .json => try printEstimationJson(allocator, w, task_name, stats, success_rate),
    }

    return 0;
}

// Removed: now using stats_mod.DurationStats

fn printEstimationJson(
    _: Allocator,
    w: *std.Io.Writer,
    task_name: []const u8,
    stats: stats_mod.DurationStats,
    success_rate: f64,
) !void {
    const avg_ms = @as(f64, @floatFromInt(stats.avg_ms));
    // Calculate coefficient of variation
    const cv = if (avg_ms > 0) (stats.std_dev_ms / avg_ms) * 100.0 else 0.0;

    // Determine confidence level
    const confidence = if (cv < 20.0)
        "high"
    else if (cv < 50.0)
        "medium"
    else
        "low";

    // Build JSON output
    try w.print("{{", .{});
    try w.print("\"task\":\"{s}\",", .{task_name});
    try w.print("\"sample_size\":{d},", .{stats.sample_count});
    try w.print("\"duration\":{{", .{});
    try w.print("\"avg_ms\":{d},", .{stats.avg_ms});
    try w.print("\"median_ms\":{d},", .{stats.p50_ms});
    try w.print("\"p90_ms\":{d},", .{stats.p90_ms});
    try w.print("\"p99_ms\":{d},", .{stats.p99_ms});
    try w.print("\"min_ms\":{d},", .{stats.min_ms});
    try w.print("\"max_ms\":{d}", .{stats.max_ms});
    try w.print("}},", .{});
    try w.print("\"variability\":{{", .{});
    try w.print("\"std_dev_ms\":{d:.2},", .{stats.std_dev_ms});
    try w.print("\"coefficient_of_variation\":{d:.2},", .{cv});
    try w.print("\"confidence\":\"{s}\"", .{confidence});
    try w.print("}},", .{});
    try w.print("\"reliability\":{{", .{});
    try w.print("\"success_rate\":{d:.2}", .{success_rate});
    try w.print("}}", .{});
    try w.print("}}\n", .{});
}

fn printEstimation(
    w: *std.Io.Writer,
    task_name: []const u8,
    stats: stats_mod.DurationStats,
    success_rate: f64,
    use_color: bool,
) !void {
    try color.printBold(w, use_color, "Estimation for task '{s}':\n\n", .{task_name});

    // Sample size
    try w.print("  Sample size:     {d} run(s)\n", .{stats.sample_count});

    // Duration estimates
    try color.printBold(w, use_color, "\n  Duration:\n", .{});
    const avg_ms_f = @as(f64, @floatFromInt(stats.avg_ms));
    try w.print("    Average:       {s}\n", .{formatDuration(avg_ms_f)});
    try w.print("    Median (p50):  {s}\n", .{formatDuration(@as(f64, @floatFromInt(stats.p50_ms)))});
    try w.print("    p90:           {s}\n", .{formatDuration(@as(f64, @floatFromInt(stats.p90_ms)))});
    try w.print("    p99:           {s}\n", .{formatDuration(@as(f64, @floatFromInt(stats.p99_ms)))});
    try w.print("    Range:         {s} - {s}\n", .{
        formatDuration(@as(f64, @floatFromInt(stats.min_ms))),
        formatDuration(@as(f64, @floatFromInt(stats.max_ms))),
    });

    // Variability
    const cv = if (avg_ms_f > 0) (stats.std_dev_ms / avg_ms_f) * 100.0 else 0.0;
    try color.printBold(w, use_color, "\n  Variability:\n", .{});
    try w.print("    Std Dev:       {s}\n", .{formatDuration(stats.std_dev_ms)});
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
    if (success_rate >= 95.0) {
        try color.printSuccess(w, use_color, "    Success Rate:  {d:.1}% ✓\n", .{success_rate});
    } else if (success_rate >= 80.0) {
        try color.printWarning(w, use_color, "    Success Rate:  {d:.1}% ⚠\n", .{success_rate});
    } else {
        try color.printError(w, use_color, "    Success Rate:  {d:.1}% ✗\n", .{success_rate});
    }

    // Anomaly threshold hint
    const anomaly_threshold = 2 * stats.p90_ms;
    try color.printBold(w, use_color, "\n  Anomaly Detection:\n", .{});
    try w.print("    Alert if >     {s} (2x p90)\n", .{formatDuration(@as(f64, @floatFromInt(anomaly_threshold)))});

    try w.print("\n", .{});
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

// Tests moved to history/stats.zig
// Integration tests in tests/estimate_test.zig
