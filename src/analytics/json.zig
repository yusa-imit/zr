//! JSON rendering of an analytics report.
//!
//! `generateJsonReport` writes the report's totals, parallelization metrics, per-task statistics,
//! critical path and time series as one pretty-printed JSON object. Task names and series keys
//! are written through `std.json.fmt`, so quotes, backslashes and control bytes are escaped.
//! Ownership: the returned slice is owned by the caller and freed with the same allocator; the
//! report is only read.

const std = @import("std");
const types = @import("types.zig");

/// Generate JSON report from analytics data
pub fn generateJsonReport(allocator: std.mem.Allocator, report: *const types.AnalyticsReport) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    const writer = buf.writer(allocator);

    try writer.writeAll("{\n");
    try writer.print("  \"total_executions\": {d},\n", .{report.total_executions});
    try writer.print("  \"overall_cache_hit_rate\": {d},\n", .{report.overall_cache_hit_rate});
    try writer.print("  \"date_range_start\": {d},\n", .{report.date_range_start});
    try writer.print("  \"date_range_end\": {d},\n", .{report.date_range_end});

    // Parallelization metrics
    try writer.writeAll("  \"parallelization\": {\n");
    try writer.print("    \"total_wall_time_ms\": {d},\n", .{report.parallelization.total_wall_time_ms});
    try writer.print("    \"total_cpu_time_ms\": {d},\n", .{report.parallelization.total_cpu_time_ms});
    try writer.print("    \"theoretical_speedup\": {d},\n", .{report.parallelization.theoretical_speedup});
    try writer.print("    \"actual_parallelism\": {d},\n", .{report.parallelization.actual_parallelism});
    try writer.print("    \"efficiency\": {d}\n", .{report.parallelization.efficiency});
    try writer.writeAll("  },\n");

    // Task statistics
    try writer.writeAll("  \"task_stats\": [\n");
    for (report.task_stats.items, 0..) |stat, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.writeAll("    {\n");
        try writer.print("      \"task_name\": {f},\n", .{std.json.fmt(stat.task_name, .{})});
        try writer.print("      \"total_runs\": {d},\n", .{stat.total_runs});
        try writer.print("      \"successful_runs\": {d},\n", .{stat.successful_runs});
        try writer.print("      \"failed_runs\": {d},\n", .{stat.failed_runs});
        try writer.print("      \"avg_duration_ms\": {d},\n", .{stat.avg_duration_ms});
        try writer.print("      \"min_duration_ms\": {d},\n", .{stat.min_duration_ms});
        try writer.print("      \"max_duration_ms\": {d},\n", .{stat.max_duration_ms});
        try writer.print("      \"cache_hits\": {d},\n", .{stat.cache_hits});
        try writer.print("      \"cache_misses\": {d},\n", .{stat.cache_misses});
        try writer.print("      \"cache_hit_rate\": {d},\n", .{stat.cacheHitRate()});
        try writer.print("      \"failure_rate\": {d},\n", .{stat.failureRate()});
        try writer.print("      \"peak_memory_bytes\": {d},\n", .{stat.peak_memory_bytes});
        try writer.print("      \"avg_memory_bytes\": {d},\n", .{stat.avg_memory_bytes});
        try writer.print("      \"avg_cpu_percent\": {d}\n", .{stat.avg_cpu_percent});
        try writer.writeAll("    }");
    }
    try writer.writeAll("\n  ],\n");

    // Critical path
    try writer.writeAll("  \"critical_path\": [\n");
    for (report.critical_path.items, 0..) |node, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.writeAll("    {\n");
        try writer.print("      \"task_name\": {f},\n", .{std.json.fmt(node.task_name, .{})});
        try writer.print("      \"duration_ms\": {d},\n", .{node.duration_ms});
        try writer.print("      \"start_time\": {d},\n", .{node.start_time});
        try writer.print("      \"end_time\": {d}\n", .{node.end_time});
        try writer.writeAll("    }");
    }
    try writer.writeAll("\n  ],\n");

    // Time series data
    try writer.writeAll("  \"time_series\": {\n");
    var it = report.time_series.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) try writer.writeAll(",\n");
        first = false;

        try writer.print("    {f}: [\n", .{std.json.fmt(entry.key_ptr.*, .{})});
        for (entry.value_ptr.items, 0..) |point, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.writeAll("      {\n");
            try writer.print("        \"timestamp\": {d},\n", .{point.timestamp});
            try writer.print("        \"duration_ms\": {d},\n", .{point.duration_ms});
            try writer.print("        \"success\": {s},\n", .{if (point.success) "true" else "false"});
            try writer.print("        \"cache_hit\": {s}\n", .{if (point.cache_hit) "true" else "false"});
            try writer.writeAll("      }");
        }
        try writer.writeAll("\n    ]");
    }
    try writer.writeAll("\n  }\n");

    try writer.writeAll("}\n");

    return buf.toOwnedSlice(allocator);
}

test "generateJsonReport basic" {
    var report = types.AnalyticsReport.init(std.testing.allocator);
    defer report.deinit();

    report.total_executions = 10;
    report.overall_cache_hit_rate = 75.5;

    const json = try generateJsonReport(std.testing.allocator, &report);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_executions\": 10") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"overall_cache_hit_rate\":") != null);
}

test "generateJsonReport escapes task names and series keys" {
    const gpa = std.testing.allocator;
    const name = "a\"b\\c\nd";

    var report = types.AnalyticsReport.init(gpa);
    defer report.deinit();

    try report.task_stats.append(gpa, .{
        .task_name = try gpa.dupe(u8, name),
        .total_runs = 1,
        .successful_runs = 1,
        .failed_runs = 0,
        .avg_duration_ms = 1.0,
        .min_duration_ms = 1,
        .max_duration_ms = 1,
        .cache_hits = 0,
        .cache_misses = 1,
        .total_retries = 0,
        .avg_retries_per_run = 0.0,
    });
    try report.critical_path.append(gpa, .{
        .task_name = try gpa.dupe(u8, name),
        .duration_ms = 1,
        .start_time = 0,
        .end_time = 1,
    });
    try report.time_series.put(try gpa.dupe(u8, name), std.ArrayList(types.TimeSeriesPoint){});

    const json = try generateJsonReport(gpa, &report);
    defer gpa.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, json, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    const stat = root.get("task_stats").?.array.items[0].object;
    try std.testing.expectEqualStrings(name, stat.get("task_name").?.string);
    const node = root.get("critical_path").?.array.items[0].object;
    try std.testing.expectEqualStrings(name, node.get("task_name").?.string);
    try std.testing.expect(root.get("time_series").?.object.get(name) != null);
}
