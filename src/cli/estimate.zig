const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const history = @import("../history/store.zig");
const stats_mod = @import("../history/stats.zig");
const config_types = @import("../config/types.zig");

pub const OutputFormat = enum {
    text,
    json,
};

const StageEstimate = struct {
    name: []const u8,
    duration_ms: u64,
    tasks: [][]const u8,
    parallel: bool,
};

fn estimateWorkflow(
    allocator: Allocator,
    workflow: *const config_types.Workflow,
    workflow_name: []const u8,
    config: *const config_types.Config,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
    output_format: OutputFormat,
) !u8 {
    // Load history
    const history_path = try history.defaultHistoryPath(allocator);
    defer allocator.free(history_path);

    var store = try history.Store.init(allocator, history_path);
    defer store.deinit();

    var records = try store.loadLast(allocator, 1000);
    defer {
        for (records.items) |r| r.deinit(allocator);
        records.deinit(allocator);
    }

    // Calculate estimates for each stage
    var stage_estimates_list = try allocator.alloc(StageEstimate, workflow.stages.len);
    defer {
        for (stage_estimates_list) |*est| {
            allocator.free(est.tasks);
        }
        allocator.free(stage_estimates_list);
    }

    var total_duration_ms: u64 = 0;
    var has_any_history = false;

    for (workflow.stages, 0..) |stage, stage_idx| {
        // Calculate stage duration based on parallel flag
        var stage_duration_ms: u64 = 0;
        var max_task_duration: u64 = 0;
        var all_tasks_have_history = true;

        // Duplicate task names for storage
        var task_names = try allocator.alloc([]const u8, stage.tasks.len);
        errdefer allocator.free(task_names);
        for (stage.tasks, 0..) |task, i| {
            task_names[i] = task;
        }

        for (stage.tasks) |task_name| {
            // Verify task exists
            if (config.tasks.get(task_name) == null) {
                try color.printError(ew, use_color,
                    "estimate: Task '{s}' in workflow stage '{s}' not found\n",
                    .{ task_name, stage.name },
                );
                return 1;
            }

            // Get task statistics
            const task_stats = try stats_mod.calculateStats(records.items, task_name, allocator);
            if (task_stats) |stats| {
                has_any_history = true;
                if (stage.parallel) {
                    // Parallel: take max duration (critical path)
                    if (stats.avg_ms > max_task_duration) {
                        max_task_duration = stats.avg_ms;
                    }
                } else {
                    // Sequential: sum durations
                    stage_duration_ms += stats.avg_ms;
                }
            } else {
                all_tasks_have_history = false;
            }
        }

        // For parallel stages, use max duration
        if (stage.parallel) {
            stage_duration_ms = max_task_duration;
        }

        total_duration_ms += stage_duration_ms;

        stage_estimates_list[stage_idx] = .{
            .name = stage.name,
            .duration_ms = stage_duration_ms,
            .tasks = task_names,
            .parallel = stage.parallel,
        };
    }

    if (!has_any_history) {
        try color.printWarning(w, use_color,
            "No execution history found for tasks in workflow '{s}'\n\n  Hint: Run 'zr run {s}' first to build history\n",
            .{ workflow_name, workflow_name },
        );
        return 0;
    }

    // Print workflow estimation report
    switch (output_format) {
        .text => try printWorkflowEstimation(w, workflow_name, stage_estimates_list, total_duration_ms, use_color),
        .json => try printWorkflowEstimationJson(allocator, w, workflow_name, stage_estimates_list, total_duration_ms),
    }

    return 0;
}

fn printWorkflowEstimationJson(
    _: Allocator,
    w: *std.Io.Writer,
    workflow_name: []const u8,
    stages: []const StageEstimate,
    total_ms: u64,
) !void {
    try w.print("{{", .{});
    try w.print("\"workflow\":\"{s}\",", .{workflow_name});
    try w.print("\"total_duration_ms\":{d},", .{total_ms});
    try w.print("\"stages\":[", .{});

    for (stages, 0..) |stage, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{", .{});
        try w.print("\"name\":\"{s}\",", .{stage.name});
        try w.print("\"duration_ms\":{d},", .{stage.duration_ms});
        try w.print("\"parallel\":{s},", .{if (stage.parallel) "true" else "false"});
        try w.print("\"tasks\":[", .{});
        for (stage.tasks, 0..) |task, j| {
            if (j > 0) try w.print(",", .{});
            try w.print("\"{s}\"", .{task});
        }
        try w.print("]", .{});
        try w.print("}}", .{});
    }

    try w.print("]", .{});
    try w.print("}}\n", .{});
}

fn printWorkflowEstimation(
    w: *std.Io.Writer,
    workflow_name: []const u8,
    stages: []const StageEstimate,
    total_ms: u64,
    use_color: bool,
) !void {
    try color.printBold(w, use_color, "Estimation for workflow '{s}':\n\n", .{workflow_name});

    // Print per-stage breakdown
    try color.printBold(w, use_color, "  Stages:\n", .{});
    for (stages) |stage| {
        const stage_duration_f = @as(f64, @floatFromInt(stage.duration_ms));
        const mode = if (stage.parallel) "parallel" else "sequential";
        try w.print("    {s} ({s}): {s}\n", .{ stage.name, mode, formatDuration(stage_duration_f) });
    }

    // Print total estimated time
    try color.printBold(w, use_color, "\n  Total Estimated Time:\n", .{});
    const total_duration_f = @as(f64, @floatFromInt(total_ms));
    try w.print("    {s}\n", .{formatDuration(total_duration_f)});
    try w.print("\n", .{});
}

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
    // Load config to verify task/workflow exists
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    // Check if it's a workflow first, then fall back to task
    if (config.workflows.get(task_name)) |workflow| {
        return try estimateWorkflow(allocator, &workflow, task_name, &config, w, ew, use_color, output_format);
    }

    if (config.tasks.get(task_name) == null) {
        try color.printError(ew, use_color,
            "estimate: Task or workflow '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks and workflows\n",
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
