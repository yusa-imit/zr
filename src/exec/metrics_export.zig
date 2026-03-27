const std = @import("std");
const Allocator = std.mem.Allocator;
const resource_monitor = @import("resource_monitor.zig");
const ResourceMetrics = resource_monitor.ResourceMetrics;
const WindowedMetrics = resource_monitor.WindowedMetrics;

/// Export format for metrics data
pub const ExportFormat = enum {
    json,
    csv,
};

/// Export options for metrics data
pub const ExportOptions = struct {
    /// Output file path (null = stdout)
    output_path: ?[]const u8 = null,
    /// Format to export (JSON or CSV)
    format: ExportFormat = .json,
    /// Pretty-print JSON output
    pretty_json: bool = true,
};

/// Export a single ResourceMetrics sample to a writer
pub fn exportMetrics(
    allocator: Allocator,
    metrics: []const ResourceMetrics,
    options: ExportOptions,
) !void {
    const output_file = if (options.output_path) |path|
        try std.fs.cwd().createFile(path, .{})
    else
        std.fs.File.stdout();
    defer if (options.output_path != null) output_file.close();

    const writer = output_file.deprecatedWriter();

    switch (options.format) {
        .json => try exportJson(allocator, metrics, writer, options.pretty_json),
        .csv => try exportCsv(metrics, writer),
    }
}

/// Export windowed metrics (5min/1hr/24hr) to a file
pub fn exportWindowedMetrics(
    allocator: Allocator,
    five_min: ?WindowedMetrics,
    one_hour: ?WindowedMetrics,
    twenty_four_hr: ?WindowedMetrics,
    options: ExportOptions,
) !void {
    const output_file = if (options.output_path) |path|
        try std.fs.cwd().createFile(path, .{})
    else
        std.fs.File.stdout();
    defer if (options.output_path != null) output_file.close();

    const writer = output_file.deprecatedWriter();

    switch (options.format) {
        .json => try exportWindowedJson(allocator, five_min, one_hour, twenty_four_hr, writer, options.pretty_json),
        .csv => try exportWindowedCsv(five_min, one_hour, twenty_four_hr, writer),
    }
}

/// Export metrics as JSON
fn exportJson(
    allocator: Allocator,
    metrics: []const ResourceMetrics,
    writer: anytype,
    pretty: bool,
) !void {
    if (pretty) {
        try writer.writeAll("[\n");
        for (metrics, 0..) |metric, i| {
            try writer.writeAll("  {\n");
            try writer.print("    \"timestamp_ms\": {d},\n", .{metric.timestamp_ms});
            try writer.print("    \"peak_memory_bytes\": {d},\n", .{metric.peak_memory_bytes});
            try writer.print("    \"avg_cpu_percent\": {d:.2},\n", .{metric.avg_cpu_percent});
            try writer.print("    \"total_io_ops\": {d}", .{metric.total_io_ops});

            if (metric.memory_breakdown) |breakdown| {
                try writer.writeAll(",\n    \"memory_breakdown\": {\n");
                try writer.print("      \"heap_memory_bytes\": {d},\n", .{breakdown.heap_memory_bytes});
                try writer.print("      \"stack_memory_bytes\": {d},\n", .{breakdown.stack_memory_bytes});
                try writer.print("      \"mapped_memory_bytes\": {d}\n", .{breakdown.mapped_memory_bytes});
                try writer.writeAll("    }\n");
            } else {
                try writer.writeAll("\n");
            }

            if (i < metrics.len - 1) {
                try writer.writeAll("  },\n");
            } else {
                try writer.writeAll("  }\n");
            }
        }
        try writer.writeAll("]\n");
    } else {
        // Compact JSON
        try writer.writeAll("[");
        for (metrics, 0..) |metric, i| {
            try writer.writeAll("{");
            try writer.print("\"timestamp_ms\":{d},", .{metric.timestamp_ms});
            try writer.print("\"peak_memory_bytes\":{d},", .{metric.peak_memory_bytes});
            try writer.print("\"avg_cpu_percent\":{d:.2},", .{metric.avg_cpu_percent});
            try writer.print("\"total_io_ops\":{d}", .{metric.total_io_ops});

            if (metric.memory_breakdown) |breakdown| {
                try writer.writeAll(",\"memory_breakdown\":{");
                try writer.print("\"heap_memory_bytes\":{d},", .{breakdown.heap_memory_bytes});
                try writer.print("\"stack_memory_bytes\":{d},", .{breakdown.stack_memory_bytes});
                try writer.print("\"mapped_memory_bytes\":{d}", .{breakdown.mapped_memory_bytes});
                try writer.writeAll("}");
            }

            try writer.writeAll("}");
            if (i < metrics.len - 1) {
                try writer.writeAll(",");
            }
        }
        try writer.writeAll("]\n");
    }

    _ = allocator; // Not used for JSON export (no allocations needed)
}

/// Export metrics as CSV
fn exportCsv(
    metrics: []const ResourceMetrics,
    writer: anytype,
) !void {
    // CSV header
    try writer.writeAll("timestamp_ms,peak_memory_bytes,avg_cpu_percent,total_io_ops,heap_memory_bytes,stack_memory_bytes,mapped_memory_bytes\n");

    // Data rows
    for (metrics) |metric| {
        try writer.print("{d},{d},{d:.2},{d}", .{
            metric.timestamp_ms,
            metric.peak_memory_bytes,
            metric.avg_cpu_percent,
            metric.total_io_ops,
        });

        if (metric.memory_breakdown) |breakdown| {
            try writer.print(",{d},{d},{d}\n", .{
                breakdown.heap_memory_bytes,
                breakdown.stack_memory_bytes,
                breakdown.mapped_memory_bytes,
            });
        } else {
            try writer.writeAll(",,,\n");
        }
    }
}

/// Export windowed metrics as JSON
fn exportWindowedJson(
    allocator: Allocator,
    five_min: ?WindowedMetrics,
    one_hour: ?WindowedMetrics,
    twenty_four_hr: ?WindowedMetrics,
    writer: anytype,
    pretty: bool,
) !void {
    _ = allocator; // Not used

    if (pretty) {
        try writer.writeAll("{\n");
        try writer.writeAll("  \"five_minutes\": ");
        try writeWindowedMetricJson(five_min, writer, "  ");
        try writer.writeAll(",\n  \"one_hour\": ");
        try writeWindowedMetricJson(one_hour, writer, "  ");
        try writer.writeAll(",\n  \"twenty_four_hours\": ");
        try writeWindowedMetricJson(twenty_four_hr, writer, "  ");
        try writer.writeAll("\n}\n");
    } else {
        try writer.writeAll("{\"five_minutes\":");
        try writeWindowedMetricJsonCompact(five_min, writer);
        try writer.writeAll(",\"one_hour\":");
        try writeWindowedMetricJsonCompact(one_hour, writer);
        try writer.writeAll(",\"twenty_four_hours\":");
        try writeWindowedMetricJsonCompact(twenty_four_hr, writer);
        try writer.writeAll("}\n");
    }
}

/// Write a single WindowedMetrics as pretty JSON
fn writeWindowedMetricJson(
    metric: ?WindowedMetrics,
    writer: anytype,
    indent: []const u8,
) !void {
    if (metric) |m| {
        try writer.writeAll("{\n");
        try writer.print("{s}  \"avg_memory_bytes\": {d},\n", .{ indent, m.avg_memory_bytes });
        try writer.print("{s}  \"peak_memory_bytes\": {d},\n", .{ indent, m.peak_memory_bytes });
        try writer.print("{s}  \"avg_cpu_percent\": {d:.2},\n", .{ indent, m.avg_cpu_percent });
        try writer.print("{s}  \"peak_cpu_percent\": {d:.2},\n", .{ indent, m.peak_cpu_percent });
        try writer.print("{s}  \"total_io_ops\": {d},\n", .{ indent, m.total_io_ops });
        try writer.print("{s}  \"sample_count\": {d},\n", .{ indent, m.sample_count });
        try writer.print("{s}  \"window_start_ms\": {d},\n", .{ indent, m.window_start_ms });
        try writer.print("{s}  \"window_end_ms\": {d}\n", .{ indent, m.window_end_ms });
        try writer.print("{s}}}", .{indent});
    } else {
        try writer.writeAll("null");
    }
}

/// Write a single WindowedMetrics as compact JSON
fn writeWindowedMetricJsonCompact(
    metric: ?WindowedMetrics,
    writer: anytype,
) !void {
    if (metric) |m| {
        try writer.writeAll("{");
        try writer.print("\"avg_memory_bytes\":{d},", .{m.avg_memory_bytes});
        try writer.print("\"peak_memory_bytes\":{d},", .{m.peak_memory_bytes});
        try writer.print("\"avg_cpu_percent\":{d:.2},", .{m.avg_cpu_percent});
        try writer.print("\"peak_cpu_percent\":{d:.2},", .{m.peak_cpu_percent});
        try writer.print("\"total_io_ops\":{d},", .{m.total_io_ops});
        try writer.print("\"sample_count\":{d},", .{m.sample_count});
        try writer.print("\"window_start_ms\":{d},", .{m.window_start_ms});
        try writer.print("\"window_end_ms\":{d}", .{m.window_end_ms});
        try writer.writeAll("}");
    } else {
        try writer.writeAll("null");
    }
}

/// Export windowed metrics as CSV
fn exportWindowedCsv(
    five_min: ?WindowedMetrics,
    one_hour: ?WindowedMetrics,
    twenty_four_hr: ?WindowedMetrics,
    writer: anytype,
) !void {
    // CSV header
    try writer.writeAll("window,avg_memory_bytes,peak_memory_bytes,avg_cpu_percent,peak_cpu_percent,total_io_ops,sample_count,window_start_ms,window_end_ms\n");

    // Data rows
    if (five_min) |m| {
        try writer.print("five_minutes,{d},{d},{d:.2},{d:.2},{d},{d},{d},{d}\n", .{
            m.avg_memory_bytes,
            m.peak_memory_bytes,
            m.avg_cpu_percent,
            m.peak_cpu_percent,
            m.total_io_ops,
            m.sample_count,
            m.window_start_ms,
            m.window_end_ms,
        });
    }

    if (one_hour) |m| {
        try writer.print("one_hour,{d},{d},{d:.2},{d:.2},{d},{d},{d},{d}\n", .{
            m.avg_memory_bytes,
            m.peak_memory_bytes,
            m.avg_cpu_percent,
            m.peak_cpu_percent,
            m.total_io_ops,
            m.sample_count,
            m.window_start_ms,
            m.window_end_ms,
        });
    }

    if (twenty_four_hr) |m| {
        try writer.print("twenty_four_hours,{d},{d},{d:.2},{d:.2},{d},{d},{d},{d}\n", .{
            m.avg_memory_bytes,
            m.peak_memory_bytes,
            m.avg_cpu_percent,
            m.peak_cpu_percent,
            m.total_io_ops,
            m.sample_count,
            m.window_start_ms,
            m.window_end_ms,
        });
    }
}

// Tests
test "exportMetrics JSON pretty" {
    const metrics = [_]ResourceMetrics{
        .{
            .timestamp_ms = 1000,
            .peak_memory_bytes = 1024 * 1024,
            .avg_cpu_percent = 25.5,
            .total_io_ops = 100,
            .memory_breakdown = .{
                .heap_memory_bytes = 512 * 1024,
                .stack_memory_bytes = 256 * 1024,
                .mapped_memory_bytes = 256 * 1024,
            },
        },
        .{
            .timestamp_ms = 2000,
            .peak_memory_bytes = 2048 * 1024,
            .avg_cpu_percent = 50.0,
            .total_io_ops = 200,
            .memory_breakdown = null,
        },
    };

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try exportJson(std.testing.allocator, &metrics, stream.writer(), true);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"timestamp_ms\": 1000") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"peak_memory_bytes\": 1048576") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"avg_cpu_percent\": 25.50") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"memory_breakdown\"") != null);
}

test "exportMetrics JSON compact" {
    const metrics = [_]ResourceMetrics{
        .{
            .timestamp_ms = 1000,
            .peak_memory_bytes = 1024,
            .avg_cpu_percent = 25.5,
            .total_io_ops = 100,
            .memory_breakdown = null,
        },
    };

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try exportJson(std.testing.allocator, &metrics, stream.writer(), false);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"timestamp_ms\":1000") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\n") != null); // Has final newline
    try std.testing.expect(std.mem.count(u8, output, "\n") == 1); // Only one newline at end
}

test "exportMetrics CSV" {
    const metrics = [_]ResourceMetrics{
        .{
            .timestamp_ms = 1000,
            .peak_memory_bytes = 1048576,
            .avg_cpu_percent = 25.50,
            .total_io_ops = 100,
            .memory_breakdown = .{
                .heap_memory_bytes = 524288,
                .stack_memory_bytes = 262144,
                .mapped_memory_bytes = 262144,
            },
        },
        .{
            .timestamp_ms = 2000,
            .peak_memory_bytes = 2097152,
            .avg_cpu_percent = 50.00,
            .total_io_ops = 200,
            .memory_breakdown = null,
        },
    };

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try exportCsv(&metrics, stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "timestamp_ms,peak_memory_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1000,1048576,25.50,100,524288,262144,262144") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "2000,2097152,50.00,200,,,") != null);
}

test "exportWindowedMetrics JSON pretty" {
    const five_min = WindowedMetrics{
        .avg_memory_bytes = 1024 * 1024,
        .peak_memory_bytes = 2048 * 1024,
        .avg_cpu_percent = 30.0,
        .peak_cpu_percent = 60.0,
        .total_io_ops = 500,
        .sample_count = 10,
        .window_start_ms = 1000,
        .window_end_ms = 6000,
    };

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try exportWindowedJson(std.testing.allocator, five_min, null, null, stream.writer(), true);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"five_minutes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"avg_memory_bytes\": 1048576") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"one_hour\": null") != null);
}

test "exportWindowedMetrics CSV" {
    const five_min = WindowedMetrics{
        .avg_memory_bytes = 1048576,
        .peak_memory_bytes = 2097152,
        .avg_cpu_percent = 30.0,
        .peak_cpu_percent = 60.0,
        .total_io_ops = 500,
        .sample_count = 10,
        .window_start_ms = 1000,
        .window_end_ms = 6000,
    };

    const one_hour = WindowedMetrics{
        .avg_memory_bytes = 1536 * 1024,
        .peak_memory_bytes = 3072 * 1024,
        .avg_cpu_percent = 40.0,
        .peak_cpu_percent = 80.0,
        .total_io_ops = 3000,
        .sample_count = 60,
        .window_start_ms = 1000,
        .window_end_ms = 61000,
    };

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try exportWindowedCsv(five_min, one_hour, null, stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "window,avg_memory_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "five_minutes,1048576,2097152,30.00,60.00") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "one_hour,1572864,3145728,40.00,80.00") != null);
}
