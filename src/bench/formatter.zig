const std = @import("std");
const types = @import("types.zig");

const BenchmarkStats = types.BenchmarkStats;

/// Format duration in a human-readable way (ms, μs, ns).
fn formatDuration(ns: u64, buf: []u8) ![]const u8 {
    if (ns >= 1_000_000_000) {
        // >= 1s: show as seconds
        const s = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        return std.fmt.bufPrint(buf, "{d:.3}s", .{s});
    } else if (ns >= 1_000_000) {
        // >= 1ms: show as milliseconds
        const ms = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
        return std.fmt.bufPrint(buf, "{d:.3}ms", .{ms});
    } else if (ns >= 1_000) {
        // >= 1μs: show as microseconds
        const us = @as(f64, @floatFromInt(ns)) / 1_000.0;
        return std.fmt.bufPrint(buf, "{d:.3}μs", .{us});
    } else {
        // < 1μs: show as nanoseconds
        return std.fmt.bufPrint(buf, "{d}ns", .{ns});
    }
}

/// Print benchmark results in text format.
pub fn printText(writer: anytype, stats: *const BenchmarkStats) !void {
    var buf: [64]u8 = undefined;

    try writer.print("\n", .{});
    try writer.print("Benchmark Results:\n", .{});
    try writer.print("══════════════════\n\n", .{});

    try writer.print("Runs:       {d} total ({d} successful, {d} failed)\n", .{
        stats.total_runs,
        stats.successful_runs,
        stats.failed_runs,
    });

    const mean_str = try formatDuration(stats.mean_ns, &buf);
    try writer.print("Mean:       {s}\n", .{mean_str});

    const median_str = try formatDuration(stats.median_ns, buf[mean_str.len + 1 ..]);
    try writer.print("Median:     {s}\n", .{median_str});

    const min_str = try formatDuration(stats.min_ns, buf[0..32]);
    try writer.print("Min:        {s}\n", .{min_str});

    const max_str = try formatDuration(stats.max_ns, buf[32..]);
    try writer.print("Max:        {s}\n", .{max_str});

    const std_dev_str = try formatDuration(stats.std_dev_ns, buf[0..32]);
    try writer.print("Std Dev:    {s}\n", .{std_dev_str});

    // Calculate coefficient of variation (CV) as a percentage
    if (stats.mean_ns > 0) {
        const cv = @as(f64, @floatFromInt(stats.std_dev_ns)) / @as(f64, @floatFromInt(stats.mean_ns)) * 100.0;
        try writer.print("CV:         {d:.2}%\n", .{cv});
    }

    try writer.print("\n", .{});
}

/// Print benchmark results in JSON format.
pub fn printJson(writer: anytype, stats: *const BenchmarkStats) !void {
    try writer.print("{{\n", .{});
    try writer.print("  \"total_runs\": {d},\n", .{stats.total_runs});
    try writer.print("  \"successful_runs\": {d},\n", .{stats.successful_runs});
    try writer.print("  \"failed_runs\": {d},\n", .{stats.failed_runs});
    try writer.print("  \"mean_ns\": {d},\n", .{stats.mean_ns});
    try writer.print("  \"median_ns\": {d},\n", .{stats.median_ns});
    try writer.print("  \"min_ns\": {d},\n", .{stats.min_ns});
    try writer.print("  \"max_ns\": {d},\n", .{stats.max_ns});
    try writer.print("  \"std_dev_ns\": {d},\n", .{stats.std_dev_ns});
    try writer.print("  \"runs\": [\n", .{});

    for (stats.runs, 0..) |run, i| {
        try writer.print("    {{\n", .{});
        try writer.print("      \"duration_ns\": {d},\n", .{run.duration_ns});
        try writer.print("      \"exit_code\": {d},\n", .{run.exit_code});
        try writer.print("      \"timestamp\": {d}\n", .{run.timestamp});
        if (i < stats.runs.len - 1) {
            try writer.print("    }},\n", .{});
        } else {
            try writer.print("    }}\n", .{});
        }
    }

    try writer.print("  ]\n", .{});
    try writer.print("}}\n", .{});
}

/// Print benchmark results in CSV format.
pub fn printCsv(writer: anytype, stats: *const BenchmarkStats) !void {
    try writer.print("iteration,duration_ns,exit_code,timestamp\n", .{});

    for (stats.runs, 0..) |run, i| {
        try writer.print("{d},{d},{d},{d}\n", .{
            i + 1,
            run.duration_ns,
            run.exit_code,
            run.timestamp,
        });
    }
}

test "formatDuration" {
    var buf: [64]u8 = undefined;

    // Test nanoseconds
    const ns_str = try formatDuration(500, &buf);
    try std.testing.expectEqualStrings("500ns", ns_str);

    // Test microseconds
    const us_str = try formatDuration(1500, &buf);
    try std.testing.expectEqualStrings("1.500μs", us_str);

    // Test milliseconds
    const ms_str = try formatDuration(2_500_000, &buf);
    try std.testing.expectEqualStrings("2.500ms", ms_str);

    // Test seconds
    const s_str = try formatDuration(3_500_000_000, &buf);
    try std.testing.expectEqualStrings("3.500s", s_str);
}
