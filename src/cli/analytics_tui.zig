//! Interactive TUI dashboard for analytics data visualization
//!
//! Displays analytics data using sailor v1.6.0+ data visualization widgets:
//! - Histogram: Task duration distribution
//! - TimeSeriesChart: Build time trends over time
//! - ScatterPlot: Cache hit rate vs build time correlation
//!
//! Layout uses FlexBox from sailor v1.7.0 for responsive dashboard.
//!
//! NOTE: This is a minimal implementation. Full interactive TUI with sailor Terminal
//! requires sailor's alternate screen and event loop APIs which are not yet available.
//! For now, this generates a static dashboard snapshot.

const std = @import("std");
const sailor = @import("sailor");
const stui = sailor.tui;

const types = @import("../analytics/types.zig");
const collector = @import("../analytics/collector.zig");
const color = @import("../output/color.zig");

/// Entry point for `zr analytics --tui` command
pub fn cmdAnalyticsTui(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var limit: ?usize = null;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--limit") or std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: --limit requires a number\n", .{});
                return 1;
            }
            limit = std.fmt.parseInt(usize, args[i], 10) catch {
                std.debug.print("error: invalid limit value: {s}\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return 0;
        } else {
            std.debug.print("error: unknown flag: {s}\n", .{arg});
            try printHelp();
            return 1;
        }
    }

    // Collect analytics data
    var report = collector.collectAnalytics(allocator, limit) catch |err| {
        std.debug.print("error: failed to collect analytics: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer report.deinit();

    if (report.total_executions == 0) {
        std.debug.print("No execution history found. Run some tasks first with `zr run <task>`.\n", .{});
        return 0;
    }

    // Render dashboard to stdout
    try renderDashboard(allocator, &report);

    return 0;
}

/// Render the analytics dashboard to stdout
fn renderDashboard(allocator: std.mem.Allocator, report: *types.AnalyticsReport) !void {
    const screen_width: u16 = 120;
    const screen_height: u16 = 40;

    var buf = try stui.Buffer.init(allocator, screen_width, screen_height);
    defer buf.deinit();

    const full_area = stui.Rect.new(0, 0, screen_width, screen_height);

    // Use FlexBox for layout (3 rows: header, charts, footer)
    const flex = stui.flexbox.FlexBox.init(.vertical)
        .withJustifyContent(.flex_start)
        .withGap(1);

    const items = [_]stui.flexbox.FlexBox.Item{
        .{ .flex_grow = 0, .flex_basis = 4 }, // Header (4 rows)
        .{ .flex_grow = 1, .flex_basis = 0 }, // Charts (fill remaining space)
        .{ .flex_grow = 0, .flex_basis = 1 }, // Footer (1 row)
    };

    const rects = try flex.layout(allocator, full_area, &items);
    defer allocator.free(rects);

    // Render header
    try renderHeader(allocator, &buf, rects[0], report);

    // Render charts in horizontal layout
    try renderCharts(allocator, &buf, rects[1], report);

    // Render footer
    renderFooter(&buf, rects[2]);

    // Flush to stdout
    const stdout = std.fs.File.stdout();

    // Render buffer to stdout
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            if (buf.getConst(@intCast(x), @intCast(y))) |cell| {
                if (cell.char != 0) {
                    // Handle UTF-8 characters properly
                    var utf8_buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(@as(u21, @intCast(cell.char)), &utf8_buf) catch {
                        _ = try stdout.write("?");
                        continue;
                    };
                    _ = try stdout.write(utf8_buf[0..len]);
                } else {
                    _ = try stdout.write(" ");
                }
            } else {
                _ = try stdout.write(" ");
            }
        }
        _ = try stdout.write("\n");
    }
}

/// Render header with summary statistics
fn renderHeader(allocator: std.mem.Allocator, buffer: *stui.Buffer, area: stui.Rect, report: *types.AnalyticsReport) !void {
    const block = stui.widgets.Block.init()
        .withTitle("Analytics Dashboard", .top_left)
        .withTitleStyle(stui.Style{ .bold = true });

    const inner = block.inner(area);
    block.render(buffer, area);

    // Summary stats
    const summary = try std.fmt.allocPrint(
        allocator,
        "Total Executions: {d} | Cache Hit Rate: {d:.1}% | Date Range: {d} - {d}",
        .{
            report.total_executions,
            report.overall_cache_hit_rate,
            report.date_range_start,
            report.date_range_end,
        },
    );
    defer allocator.free(summary);

    buffer.setString(inner.x, inner.y, summary, .{});
}

/// Render charts in horizontal layout
fn renderCharts(allocator: std.mem.Allocator, buffer: *stui.Buffer, area: stui.Rect, report: *types.AnalyticsReport) !void {
    // Use FlexBox for 3-column chart layout
    const flex = stui.flexbox.FlexBox.init(.vertical)
        .withJustifyContent(.flex_start)
        .withGap(1);

    const items = [_]stui.flexbox.FlexBox.Item{
        .{ .flex_grow = 1, .flex_basis = 0 }, // Histogram
        .{ .flex_grow = 1, .flex_basis = 0 }, // TimeSeriesChart
        .{ .flex_grow = 1, .flex_basis = 0 }, // ScatterPlot
    };

    const rects = try flex.layout(allocator, area, &items);
    defer allocator.free(rects);

    // Render all three charts
    try renderHistogram(allocator, buffer, rects[0], report);
    try renderTimeSeriesChart(allocator, buffer, rects[1], report);
    try renderScatterPlot(allocator, buffer, rects[2], report);
}

/// Render task duration histogram
fn renderHistogram(allocator: std.mem.Allocator, buffer: *stui.Buffer, area: stui.Rect, report: *types.AnalyticsReport) !void {
    // Create duration bins (0-100ms, 100-500ms, 500-1s, 1-5s, 5s+)
    var bins = std.ArrayList(stui.widgets.Histogram.Bin){};
    defer bins.deinit(allocator);

    var counts = [_]u64{ 0, 0, 0, 0, 0 };
    for (report.task_stats.items) |stat| {
        const dur_ms = @as(u64, @intFromFloat(stat.avg_duration_ms));
        if (dur_ms < 100) {
            counts[0] += 1;
        } else if (dur_ms < 500) {
            counts[1] += 1;
        } else if (dur_ms < 1000) {
            counts[2] += 1;
        } else if (dur_ms < 5000) {
            counts[3] += 1;
        } else {
            counts[4] += 1;
        }
    }

    try bins.append(allocator, .{ .label = "0-100ms", .count = counts[0] });
    try bins.append(allocator, .{ .label = "100-500ms", .count = counts[1] });
    try bins.append(allocator, .{ .label = "500ms-1s", .count = counts[2] });
    try bins.append(allocator, .{ .label = "1-5s", .count = counts[3] });
    try bins.append(allocator, .{ .label = "5s+", .count = counts[4] });

    const hist = stui.widgets.Histogram.init(bins.items)
        .withBlock(stui.widgets.Block.init().withTitle("Task Duration Distribution", .top_left))
        .withBarStyle(.{ .fg = .green })
        .withOrientation(.vertical);

    hist.render(buffer, area);
}

/// Render time series chart for build time trends
fn renderTimeSeriesChart(allocator: std.mem.Allocator, buffer: *stui.Buffer, area: stui.Rect, report: *types.AnalyticsReport) !void {
    // Extract timestamps and durations from execution history
    var timestamps = std.ArrayList(i64){};
    defer timestamps.deinit(allocator);
    var values = std.ArrayList(f64){};
    defer values.deinit(allocator);

    // Use the last 50 executions for the trend line
    const max_points = @min(50, report.total_executions);
    var i: usize = 0;
    while (i < max_points and i < report.task_stats.items.len) : (i += 1) {
        const stat = report.task_stats.items[i];
        // Use index as X coordinate (not Unix timestamp - too large for u16)
        const timestamp: i64 = @as(i64, @intCast(i));
        const duration = @as(f64, @floatFromInt(@as(u64, @intFromFloat(stat.avg_duration_ms))));
        try timestamps.append(allocator, timestamp);
        try values.append(allocator, duration);
    }

    var chart = try stui.widgets.TimeSeriesChart.init(allocator, timestamps.items, values.items);
    defer chart.deinit();
    chart.block = stui.widgets.Block.init().withTitle("Build Time Trends", .top_left);
    chart.line_style = .{ .fg = .blue };
    chart.y_axis_label = "Duration (ms)";

    chart.render(buffer, area);
}

/// Render scatter plot for cache hit rate vs build time
fn renderScatterPlot(allocator: std.mem.Allocator, buffer: *stui.Buffer, area: stui.Rect, report: *types.AnalyticsReport) !void {
    // Extract cache hit rate and build time for each task
    var points = std.ArrayList(stui.widgets.ScatterPlot.Point){};
    defer points.deinit(allocator);

    for (report.task_stats.items) |stat| {
        // X-axis: cache hit rate (0-100%)
        const cache_hit_rate = if (stat.total_runs > 0)
            @as(f64, @floatFromInt(stat.cache_hits)) / @as(f64, @floatFromInt(stat.total_runs)) * 100.0
        else
            0.0;
        // Y-axis: average duration in ms
        const duration = stat.avg_duration_ms;
        try points.append(allocator, .{ .x = cache_hit_rate, .y = duration });
    }

    // Create a single series with all points
    const series = [_]stui.widgets.ScatterPlot.Series{
        .{
            .name = "Tasks",
            .points = points.items,
            .style = .{ .fg = .magenta },
            .marker = "●",
        },
    };

    var scatter = stui.widgets.ScatterPlot.init(&series)
        .withBlock(stui.widgets.Block.init().withTitle("Cache Hit Rate vs Build Time", .top_left));
    scatter.x_axis_label = "Cache Hit Rate (%)";
    scatter.y_axis_label = "Duration (ms)";

    scatter.render(buffer, area);
}

/// Render footer with help text
fn renderFooter(buffer: *stui.Buffer, area: stui.Rect) void {
    const footer = "Use 'zr analytics' for full HTML report | 'zr analytics --json' for JSON output";
    buffer.setString(area.x, area.y, footer, .{});
}

fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\Usage: zr analytics --tui [options]
        \\
        \\TUI dashboard for analytics data visualization (snapshot mode).
        \\
        \\Options:
        \\  -n, --limit <N>     Analyze only the last N executions
        \\  -h, --help          Show this help message
        \\
        \\Dashboard Panels:
        \\  - Task Duration Distribution (histogram)
        \\  - Build Time Trends (time series chart)
        \\  - Cache Hit Rate vs Build Time (scatter plot)
        \\
        \\Note: This displays a static snapshot using sailor v1.6.0+ data visualization
        \\      widgets. For interactive dashboards, use 'zr analytics' to generate an
        \\      HTML report.
        \\
    );
}

test "cmdAnalyticsTui help" {
    const result = try cmdAnalyticsTui(std.testing.allocator, &.{"--help"});
    try std.testing.expectEqual(@as(u8, 0), result);
}
