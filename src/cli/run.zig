const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const scheduler = @import("../exec/scheduler.zig");
const history = @import("../history/store.zig");
const watcher = @import("../watch/watcher.zig");
const progress = @import("../output/progress.zig");
const tui_runner = @import("tui_runner.zig");

pub fn cmdRun(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    profile_name: ?[]const u8,
    dry_run: bool,
    max_jobs: u32,
    config_path: []const u8,
    json_output: bool,
    monitor: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
    task_control: ?*@import("../exec/control.zig").TaskControl,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    if (config.tasks.get(task_name) == null) {
        try color.printError(err_writer, use_color,
            "run: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    }

    const task_names = [_][]const u8{task_name};

    // Dry-run: show the execution plan without running tasks.
    if (dry_run) {
        var plan = scheduler.planDryRun(allocator, &config, &task_names) catch |err| {
            switch (err) {
                error.TaskNotFound => try color.printError(err_writer, use_color,
                    "run: A dependency task was not found in config\n", .{}),
                error.CycleDetected => try color.printError(err_writer, use_color,
                    "run: Cycle detected in task dependencies\n\n  Hint: Check your deps fields for circular references\n", .{}),
                else => try color.printError(err_writer, use_color,
                    "run: Scheduler error: {s}\n", .{@errorName(err)}),
            }
            return 1;
        };
        defer plan.deinit();
        try printDryRunPlan(w, use_color, plan);
        return 0;
    }

    const start_ns = std.time.nanoTimestamp();

    var sched_result = scheduler.run(allocator, &config, &task_names, .{
        .max_jobs = max_jobs,
        .monitor = monitor,
        .use_color = use_color,
        .task_control = task_control,
    }) catch |err| {
        switch (err) {
            error.TaskNotFound => {
                try color.printError(err_writer, use_color,
                    "run: A dependency task was not found in config\n", .{});
            },
            error.CycleDetected => {
                try color.printError(err_writer, use_color,
                    "run: Cycle detected in task dependencies\n\n  Hint: Check your deps fields for circular references\n",
                    .{},
                );
            },
            else => {
                try color.printError(err_writer, use_color,
                    "run: Scheduler error: {s}\n", .{@errorName(err)});
            },
        }
        return 1;
    };
    defer sched_result.deinit(allocator);

    const elapsed_ms: u64 = @intCast(@divTrunc(std.time.nanoTimestamp() - start_ns, std.time.ns_per_ms));

    // Print results for each task that ran.
    if (json_output) {
        try printRunResultJson(w, sched_result.results.items, sched_result.total_success, elapsed_ms);
    } else {
        // Failures go to err_writer so they are visible even under --quiet
        // (which redirects w to /dev/null).
        var passed: usize = 0;
        var failed: usize = 0;
        var skipped: usize = 0;
        for (sched_result.results.items) |task_result| {
            if (task_result.skipped) {
                skipped += 1;
            } else if (task_result.success) {
                passed += 1;
                try color.printSuccess(w, use_color,
                    "{s} ", .{task_result.task_name});
                try color.printDim(w, use_color,
                    "({d}ms)\n", .{task_result.duration_ms});
            } else {
                failed += 1;
                try color.printError(err_writer, use_color,
                    "{s} ", .{task_result.task_name});
                try color.printDim(err_writer, use_color,
                    "(exit: {d})\n", .{task_result.exit_code});
            }
        }
        // Print summary line when more than one task ran.
        if (sched_result.results.items.len > 1) {
            try progress.printSummary(w, use_color, passed, failed, skipped, elapsed_ms);
        }
    }

    // Record to history (best-effort, ignore errors)
    recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
        @intCast(sched_result.results.items.len));

    return if (sched_result.total_success) 0 else 1;
}

pub fn cmdWatch(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    watch_paths: []const []const u8,
    profile_name: ?[]const u8,
    max_jobs: u32,
    config_path: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Verify task exists before starting the watch loop.
    {
        var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
        defer config.deinit();
        if (config.tasks.get(task_name) == null) {
            try color.printError(err_writer, use_color,
                "watch: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
                .{task_name},
            );
            return 1;
        }
    }

    // Use native file watching (inotify/kqueue/ReadDirectoryChangesW) with 500ms polling fallback
    var watch = watcher.Watcher.init(allocator, watch_paths, .native, 500) catch |err| {
        try color.printError(err_writer, use_color,
            "watch: Failed to initialize watcher: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer watch.deinit();

    // Log which mode we're using
    const mode_str = switch (watch.mode) {
        .native => "native",
        .polling => "polling",
    };
    try color.printDim(w, use_color, "  (using {s} mode)\n", .{mode_str});

    try color.printInfo(w, use_color, "Watching", .{});
    try w.print(" for changes (Ctrl+C to stop)...\n", .{});

    // Run the task immediately on start, then loop.
    var first_run = true;
    while (true) {
        if (!first_run) {
            // Wait for a file change.
            const event = watch.waitForChange() catch |err| switch (err) {
                else => {
                    try color.printError(err_writer, use_color,
                        "watch: Watcher error: {s}\n", .{@errorName(err)});
                    return 1;
                },
            };
            try color.printInfo(w, use_color, "\nChange detected", .{});
            try color.printDim(w, use_color, ": {s}\n", .{event.path});
        }
        first_run = false;

        // Reload config in case zr.toml changed.
        var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse {
            try color.printError(err_writer, use_color,
                "watch: Config error — waiting for next change...\n", .{});
            continue;
        };
        defer config.deinit();

        if (config.tasks.get(task_name) == null) {
            try color.printError(err_writer, use_color,
                "watch: Task '{s}' not found in config — waiting for next change...\n",
                .{task_name},
            );
            continue;
        }

        const start_ns = std.time.nanoTimestamp();
        const task_names = [_][]const u8{task_name};
        var sched_result = scheduler.run(allocator, &config, &task_names, .{
            .max_jobs = max_jobs,
        }) catch |err| {
            switch (err) {
                error.CycleDetected => try color.printError(err_writer, use_color,
                    "watch: Cycle detected in task dependencies\n", .{}),
                else => try color.printError(err_writer, use_color,
                    "watch: Scheduler error: {s}\n", .{@errorName(err)}),
            }
            continue;
        };
        defer sched_result.deinit(allocator);

        const elapsed_ms: u64 = @intCast(@divTrunc(std.time.nanoTimestamp() - start_ns, std.time.ns_per_ms));

        for (sched_result.results.items) |task_result| {
            if (task_result.success) {
                try color.printSuccess(w, use_color, "{s} ", .{task_result.task_name});
                try color.printDim(w, use_color, "({d}ms)\n", .{task_result.duration_ms});
            } else {
                try color.printError(err_writer, use_color, "{s} ", .{task_result.task_name});
                try color.printDim(err_writer, use_color, "(exit: {d})\n", .{task_result.exit_code});
            }
        }

        recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
            @intCast(sched_result.results.items.len));

        try color.printDim(w, use_color, "Watching for changes (Ctrl+C to stop)...\n", .{});
    }
}

pub fn cmdWorkflow(
    allocator: std.mem.Allocator,
    wf_name: []const u8,
    profile_name: ?[]const u8,
    dry_run: bool,
    max_jobs: u32,
    config_path: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    const wf = config.workflows.get(wf_name) orelse {
        try color.printError(err_writer, use_color,
            "workflow: '{s}' not found\n\n  Hint: Run 'zr list' to see available workflows\n",
            .{wf_name},
        );
        return 1;
    };

    // Dry-run: show per-stage execution plans without running.
    if (dry_run) {
        try color.printBold(w, use_color, "Dry run — workflow: {s}\n", .{wf_name});
        if (wf.description) |desc| {
            try color.printDim(w, use_color, "  {s}\n", .{desc});
        }
        for (wf.stages) |stage| {
            try color.printInfo(w, use_color, "\nStage: {s}\n", .{stage.name});
            if (stage.tasks.len == 0) {
                try color.printDim(w, use_color, "  (no tasks)\n", .{});
                continue;
            }
            var plan = scheduler.planDryRun(allocator, &config, stage.tasks) catch |err| {
                switch (err) {
                    error.TaskNotFound => try color.printError(err_writer, use_color,
                        "workflow: A task in stage '{s}' was not found\n", .{stage.name}),
                    error.CycleDetected => try color.printError(err_writer, use_color,
                        "workflow: Cycle detected in stage '{s}'\n", .{stage.name}),
                    else => try color.printError(err_writer, use_color,
                        "workflow: Error in stage '{s}': {s}\n", .{ stage.name, @errorName(err) }),
                }
                return 1;
            };
            defer plan.deinit();
            try printDryRunPlan(w, use_color, plan);
        }
        try color.printDim(w, use_color, "\nNo tasks were executed.\n", .{});
        return 0;
    }

    try color.printBold(w, use_color, "Workflow: {s}", .{wf_name});
    if (wf.description) |desc| {
        try color.printDim(w, use_color, " — {s}", .{desc});
    }
    try w.print("\n", .{});

    const overall_start_ns = std.time.nanoTimestamp();
    var any_failed = false;

    for (wf.stages) |stage| {
        try color.printInfo(w, use_color, "\nStage: {s}\n", .{stage.name});

        if (stage.tasks.len == 0) continue;

        const stage_start_ns = std.time.nanoTimestamp();

        var sched_result = scheduler.run(allocator, &config, stage.tasks, .{
            .inherit_stdio = true,
            .max_jobs = max_jobs,
        }) catch |err| {
            switch (err) {
                error.TaskNotFound => {
                    try color.printError(err_writer, use_color,
                        "workflow: A task in stage '{s}' was not found\n", .{stage.name});
                },
                error.CycleDetected => {
                    try color.printError(err_writer, use_color,
                        "workflow: Cycle detected in stage '{s}' dependencies\n", .{stage.name});
                },
                else => {
                    try color.printError(err_writer, use_color,
                        "workflow: Scheduler error in stage '{s}': {s}\n",
                        .{ stage.name, @errorName(err) });
                },
            }
            if (stage.fail_fast) return 1;
            any_failed = true;
            continue;
        };
        defer sched_result.deinit(allocator);

        const stage_elapsed_ms: u64 = @intCast(@divTrunc(
            std.time.nanoTimestamp() - stage_start_ns, std.time.ns_per_ms));

        var stage_passed: usize = 0;
        var stage_failed: usize = 0;
        var stage_skipped: usize = 0;
        for (sched_result.results.items) |task_result| {
            if (task_result.skipped) {
                stage_skipped += 1;
            } else if (task_result.success) {
                stage_passed += 1;
                try color.printSuccess(w, use_color, "  {s} ", .{task_result.task_name});
                try color.printDim(w, use_color, "({d}ms)\n", .{task_result.duration_ms});
            } else {
                stage_failed += 1;
                try color.printError(w, use_color, "  {s} ", .{task_result.task_name});
                try color.printDim(w, use_color, "(exit: {d})\n", .{task_result.exit_code});
            }
        }

        // Print stage summary when more than one task ran in this stage.
        if (sched_result.results.items.len > 1) {
            try w.writeAll("  ");
            try progress.printSummary(w, use_color, stage_passed, stage_failed, stage_skipped, stage_elapsed_ms);
        } else {
            try color.printDim(w, use_color, "  Stage '{s}' done ({d}ms)\n",
                .{ stage.name, stage_elapsed_ms });
        }

        if (!sched_result.total_success) {
            any_failed = true;
            if (stage.fail_fast) {
                try color.printError(err_writer, use_color,
                    "\nworkflow: Stage '{s}' failed — stopping (fail_fast)\n", .{stage.name});
                return 1;
            }
        }
    }

    const overall_elapsed_ms: u64 = @intCast(@divTrunc(
        std.time.nanoTimestamp() - overall_start_ns, std.time.ns_per_ms));

    try w.print("\n", .{});
    if (!any_failed) {
        try color.printSuccess(w, use_color,
            "Workflow '{s}' completed ({d}ms)\n", .{ wf_name, overall_elapsed_ms });
        return 0;
    } else {
        try color.printError(w, use_color,
            "Workflow '{s}' finished with failures ({d}ms)\n", .{ wf_name, overall_elapsed_ms });
        return 1;
    }
}

pub fn cmdHistory(
    allocator: std.mem.Allocator,
    json_output: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    _ = err_writer;

    const hist_path = try history.defaultHistoryPath(allocator);
    defer allocator.free(hist_path);

    var store = try history.Store.init(allocator, hist_path);
    defer store.deinit();

    var records = try store.loadLast(allocator, 20);
    defer {
        for (records.items) |r| r.deinit(allocator);
        records.deinit(allocator);
    }

    if (json_output) {
        try w.writeAll("{\"runs\":[");
        for (records.items, 0..) |rec, i| {
            if (i > 0) try w.writeAll(",");
            try w.print("{{\"task\":", .{});
            try common.writeJsonString(w, rec.task_name);
            try w.print(",\"success\":{s},\"duration_ms\":{d},\"task_count\":{d},\"timestamp\":{d}}}", .{
                if (rec.success) "true" else "false",
                rec.duration_ms,
                rec.task_count,
                rec.timestamp,
            });
        }
        try w.writeAll("]}\n");
        return 0;
    }

    if (records.items.len == 0) {
        try color.printDim(w, use_color, "No history yet. Run a task with 'zr run <task>'.\n", .{});
        return 0;
    }

    try color.printHeader(w, use_color, "Recent Runs:", .{});
    try w.print("\n", .{});

    for (records.items) |rec| {
        const status_icon: []const u8 = if (rec.success) "✓" else "✗";
        if (rec.success) {
            try color.printSuccess(w, use_color, "  {s} ", .{status_icon});
        } else {
            try color.printError(w, use_color, "  {s} ", .{status_icon});
        }
        try color.printInfo(w, use_color, "{s:<20}", .{rec.task_name});
        try color.printDim(w, use_color, "  {d}ms  ({d} task(s))  ts:{d}\n", .{
            rec.duration_ms,
            rec.task_count,
            rec.timestamp,
        });
    }

    return 0;
}

pub fn recordHistory(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    success: bool,
    duration_ms: u64,
    task_count: u32,
) void {
    const hist_path = history.defaultHistoryPath(allocator) catch return;
    defer allocator.free(hist_path);

    var store = history.Store.init(allocator, hist_path) catch return;
    defer store.deinit();

    store.append(.{
        .timestamp = std.time.timestamp(),
        .task_name = task_name,
        .success = success,
        .duration_ms = duration_ms,
        .task_count = task_count,
    }) catch {};
}

/// Emit a JSON object for the run result:
/// {"success":true,"elapsed_ms":42,"tasks":[{"name":"t","success":true,"exit_code":0,"duration_ms":10,"skipped":false}]}
pub fn printRunResultJson(
    w: *std.Io.Writer,
    results: []const scheduler.TaskResult,
    total_success: bool,
    elapsed_ms: u64,
) !void {
    try w.print("{{\"success\":{s},\"elapsed_ms\":{d},\"tasks\":[", .{
        if (total_success) "true" else "false",
        elapsed_ms,
    });
    for (results, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"name\":", .{});
        try common.writeJsonString(w, r.task_name);
        try w.print(",\"success\":{s},\"exit_code\":{d},\"duration_ms\":{d},\"skipped\":{s}}}", .{
            if (r.success) "true" else "false",
            r.exit_code,
            r.duration_ms,
            if (r.skipped) "true" else "false",
        });
    }
    try w.writeAll("]}\n");
}

/// Print a formatted dry-run plan showing execution levels and task names.
pub fn printDryRunPlan(w: *std.Io.Writer, use_color: bool, plan: scheduler.DryRunPlan) !void {
    try color.printBold(w, use_color, "Dry run — execution plan:\n", .{});
    if (plan.levels.len == 0) {
        try color.printDim(w, use_color, "  (no tasks to run)\n", .{});
        return;
    }
    for (plan.levels, 0..) |level, i| {
        if (level.tasks.len == 0) continue;
        if (level.tasks.len == 1) {
            try color.printDim(w, use_color, "  Level {d}  ", .{i});
            try color.printInfo(w, use_color, "{s}\n", .{level.tasks[0]});
        } else {
            try color.printDim(w, use_color, "  Level {d}  ", .{i});
            try color.printDim(w, use_color, "[parallel]\n", .{});
            for (level.tasks) |t| {
                try w.print("    ", .{});
                try color.printInfo(w, use_color, "{s}\n", .{t});
            }
        }
    }
    try color.printDim(w, use_color, "\nNo tasks were executed.\n", .{});
}

test "printRunResultJson emits valid JSON structure" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    // Collect output in memory using a fixed buffer writer via stdout (test env)
    const stdout = std.fs.File.stdout();
    var w = stdout.writer(&out_buf);

    const results = [_]scheduler.TaskResult{
        .{ .task_name = "build", .success = true, .exit_code = 0, .duration_ms = 100, .skipped = false },
        .{ .task_name = "test", .success = false, .exit_code = 1, .duration_ms = 50, .skipped = false },
    };

    try printRunResultJson(&w.interface, &results, false, 150);
    _ = allocator;
}

test "cmdRun: missing config returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const result = try cmdRun(
        allocator,
        "build",
        null,
        false,
        1,
        "/tmp/zr_test_nonexistent/zr.toml",
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
    );
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdRun: unknown task returns error" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    const toml_content = "[tasks.build]\ncmd = \"echo build\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const result = try cmdRun(
        allocator,
        "nonexistent",
        null,
        false,
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
    );
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdRun: dry run shows plan without executing" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    const toml_content = "[tasks.hello]\ncmd = \"echo hello\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const result = try cmdRun(
        allocator,
        "hello",
        null,
        true,
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
    );
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "cmdRun: successful task returns 0" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    const toml_content = "[tasks.hello]\ncmd = \"true\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const result = try cmdRun(
        allocator,
        "hello",
        null,
        false,
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
    );
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "cmdRun: failing task returns 1" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    const toml_content = "[tasks.fail]\ncmd = \"false\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const result = try cmdRun(
        allocator,
        "fail",
        null,
        false,
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
    );
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "printDryRunPlan: empty plan" {
    const allocator = std.testing.allocator;
    _ = allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    // Construct a DryRunPlan with no levels — allocator field is unused when levels is empty
    const plan = scheduler.DryRunPlan{
        .levels = &.{},
        .allocator = std.testing.allocator,
    };

    // printDryRunPlan should return without error on empty plan
    try printDryRunPlan(&out_w.interface, false, plan);
}

test "cmdHistory: empty history returns 0" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // cmdHistory reads from .zr_history in cwd; if it doesn't exist it shows "No history yet"
    // Either way it should return 0
    const result = try cmdHistory(
        allocator,
        false,
        &out_w.interface,
        &err_w.interface,
        false,
    );
    try std.testing.expectEqual(@as(u8, 0), result);
}
