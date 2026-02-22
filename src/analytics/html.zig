const std = @import("std");
const types = @import("types.zig");

/// Generate HTML report from analytics data
pub fn generateHtmlReport(allocator: std.mem.Allocator, report: *const types.AnalyticsReport) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    const writer = buf.writer(allocator);

    // HTML header
    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="UTF-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\  <title>zr Build Analytics Report</title>
        \\  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
        \\  <style>
        \\    * { margin: 0; padding: 0; box-sizing: border-box; }
        \\    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f5f5; padding: 20px; }
        \\    .container { max-width: 1400px; margin: 0 auto; }
        \\    h1 { color: #333; margin-bottom: 10px; }
        \\    .subtitle { color: #666; margin-bottom: 30px; }
        \\    .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        \\    .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        \\    .card h2 { font-size: 16px; color: #666; margin-bottom: 10px; }
        \\    .card .value { font-size: 32px; font-weight: bold; color: #333; }
        \\    .card .unit { font-size: 14px; color: #999; }
        \\    .chart-container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 30px; }
        \\    .chart-container h2 { font-size: 18px; color: #333; margin-bottom: 20px; }
        \\    canvas { max-height: 400px; }
        \\    table { width: 100%; border-collapse: collapse; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        \\    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; }
        \\    th { background: #f8f8f8; font-weight: 600; color: #666; font-size: 14px; }
        \\    td { color: #333; }
        \\    .success { color: #22c55e; }
        \\    .failure { color: #ef4444; }
        \\    .footer { text-align: center; color: #999; margin-top: 40px; font-size: 14px; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <div class="container">
        \\    <h1>zr Build Analytics Report</h1>
        \\
    );

    // Subtitle with date range
    if (report.date_range_start > 0 and report.date_range_end > 0) {
        try writer.print("    <p class=\"subtitle\">Analyzed {d} executions from {d} to {d}</p>\n", .{
            report.total_executions,
            report.date_range_start,
            report.date_range_end,
        });
    } else {
        try writer.print("    <p class=\"subtitle\">Analyzed {d} executions</p>\n", .{report.total_executions});
    }

    // Summary cards
    try writer.writeAll(
        \\    <div class="summary">
        \\
    );

    // Total executions card
    try writer.print(
        \\      <div class="card">
        \\        <h2>Total Executions</h2>
        \\        <div class="value">{d}</div>
        \\      </div>
        \\
    , .{report.total_executions});

    // Cache hit rate card
    try writer.print(
        \\      <div class="card">
        \\        <h2>Cache Hit Rate</h2>
        \\        <div class="value">{d:.1}<span class="unit">%</span></div>
        \\      </div>
        \\
    , .{report.overall_cache_hit_rate});

    // Parallelization efficiency card
    try writer.print(
        \\      <div class="card">
        \\        <h2>Parallelization Efficiency</h2>
        \\        <div class="value">{d:.1}<span class="unit">%</span></div>
        \\      </div>
        \\
    , .{report.parallelization.efficiency});

    // Speedup card
    try writer.print(
        \\      <div class="card">
        \\        <h2>Theoretical Speedup</h2>
        \\        <div class="value">{d:.2}<span class="unit">×</span></div>
        \\      </div>
        \\
    , .{report.parallelization.theoretical_speedup});

    try writer.writeAll(
        \\    </div>
        \\
    );

    // Task statistics table
    try writer.writeAll(
        \\    <div class="chart-container">
        \\      <h2>Task Statistics</h2>
        \\      <table>
        \\        <thead>
        \\          <tr>
        \\            <th>Task</th>
        \\            <th>Runs</th>
        \\            <th>Success Rate</th>
        \\            <th>Avg Duration</th>
        \\            <th>Min/Max</th>
        \\            <th>Cache Hit Rate</th>
        \\          </tr>
        \\        </thead>
        \\        <tbody>
        \\
    );

    for (report.task_stats.items) |stat| {
        const success_rate = if (stat.total_runs > 0)
            @as(f64, @floatFromInt(stat.successful_runs)) / @as(f64, @floatFromInt(stat.total_runs)) * 100.0
        else
            0.0;

        try writer.print(
            \\          <tr>
            \\            <td>{s}</td>
            \\            <td>{d}</td>
            \\            <td>{d:.1}%</td>
            \\            <td>{d:.0}ms</td>
            \\            <td>{d}ms / {d}ms</td>
            \\            <td>{d:.1}%</td>
            \\          </tr>
            \\
        , .{
            stat.task_name,
            stat.total_runs,
            success_rate,
            stat.avg_duration_ms,
            stat.min_duration_ms,
            stat.max_duration_ms,
            stat.cacheHitRate(),
        });
    }

    try writer.writeAll(
        \\        </tbody>
        \\      </table>
        \\    </div>
        \\
    );

    // Critical path
    if (report.critical_path.items.len > 0) {
        try writer.writeAll(
            \\    <div class="chart-container">
            \\      <h2>Critical Path (Slowest Tasks)</h2>
            \\      <table>
            \\        <thead>
            \\          <tr>
            \\            <th>Task</th>
            \\            <th>Duration</th>
            \\            <th>% of Total</th>
            \\          </tr>
            \\        </thead>
            \\        <tbody>
            \\
        );

        const total_critical_time: u64 = blk: {
            var sum: u64 = 0;
            for (report.critical_path.items) |node| sum += node.duration_ms;
            break :blk sum;
        };

        for (report.critical_path.items) |node| {
            const pct = if (total_critical_time > 0)
                @as(f64, @floatFromInt(node.duration_ms)) / @as(f64, @floatFromInt(total_critical_time)) * 100.0
            else
                0.0;

            try writer.print(
                \\          <tr>
                \\            <td>{s}</td>
                \\            <td>{d}ms</td>
                \\            <td>{d:.1}%</td>
                \\          </tr>
                \\
            , .{ node.task_name, node.duration_ms, pct });
        }

        try writer.writeAll(
            \\        </tbody>
            \\      </table>
            \\    </div>
            \\
        );
    }

    // Duration trend chart (Chart.js)
    if (report.task_stats.items.len > 0) {
        try writer.writeAll(
            \\    <div class="chart-container">
            \\      <h2>Task Duration Distribution</h2>
            \\      <canvas id="durationChart"></canvas>
            \\    </div>
            \\    <script>
            \\      const ctx = document.getElementById('durationChart');
            \\      new Chart(ctx, {
            \\        type: 'bar',
            \\        data: {
            \\          labels: [
        );

        for (report.task_stats.items, 0..) |stat, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("'{s}'", .{stat.task_name});
        }

        try writer.writeAll(
            \\],
            \\          datasets: [{
            \\            label: 'Average Duration (ms)',
            \\            data: [
        );

        for (report.task_stats.items, 0..) |stat, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{d:.0}", .{stat.avg_duration_ms});
        }

        try writer.writeAll(
            \\],
            \\            backgroundColor: 'rgba(59, 130, 246, 0.5)',
            \\            borderColor: 'rgb(59, 130, 246)',
            \\            borderWidth: 1
            \\          }]
            \\        },
            \\        options: {
            \\          responsive: true,
            \\          maintainAspectRatio: true,
            \\          scales: { y: { beginAtZero: true } }
            \\        }
            \\      });
            \\    </script>
            \\
        );
    }

    // Footer
    try writer.writeAll(
        \\    <div class="footer">
        \\      Generated by zr analytics — https://github.com/username/zr
        \\    </div>
        \\  </div>
        \\</body>
        \\</html>
        \\
    );

    return buf.toOwnedSlice(allocator);
}

test "generateHtmlReport basic" {
    var report = types.AnalyticsReport.init(std.testing.allocator);
    defer report.deinit();

    report.total_executions = 10;
    report.overall_cache_hit_rate = 75.5;
    report.parallelization = types.ParallelizationMetrics.init(1000, 3000, 4);

    const html = try generateHtmlReport(std.testing.allocator, &report);
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Build Analytics Report") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "10") != null); // Total executions
}
