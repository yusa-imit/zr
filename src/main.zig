const std = @import("std");
const loader = @import("config/loader.zig");
const expr = @import("config/expr.zig");
const dag_mod = @import("graph/dag.zig");
const topo_sort = @import("graph/topo_sort.zig");
const cycle_detect = @import("graph/cycle_detect.zig");
const scheduler = @import("exec/scheduler.zig");
const process = @import("exec/process.zig");
const color = @import("output/color.zig");
const history = @import("history/store.zig");
const watcher = @import("watch/watcher.zig");

// Ensure tests in all imported modules are included in test binary
comptime {
    _ = loader;
    _ = expr;
    _ = dag_mod;
    _ = topo_sort;
    _ = cycle_detect;
    _ = scheduler;
    _ = process;
    _ = color;
    _ = history;
    _ = watcher;
}

const CONFIG_FILE = "zr.toml";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var out_buf: [8192]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_writer = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_writer = stderr_file.writer(&err_buf);

    const use_color = color.isTty(stdout);
    const result = run(allocator, args, &out_writer.interface, &err_writer.interface, use_color);

    // Always flush both writers before exiting
    out_writer.interface.flush() catch {};
    err_writer.interface.flush() catch {};

    if (result) |exit_code| {
        if (exit_code != 0) std.process.exit(exit_code);
    } else |err| {
        return err;
    }
}

/// Inner run function that returns an exit code.
/// Returns 0 for success, non-zero for failure.
fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (args.len < 2) {
        try printHelp(w, use_color);
        return 0;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try printHelp(w, use_color);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) {
            try color.printError(ew, use_color, "run: missing task name\n\n  Hint: zr run <task-name>\n", .{});
            return 1;
        }
        const task_name = args[2];
        return cmdRun(allocator, task_name, w, ew, use_color);
    } else if (std.mem.eql(u8, cmd, "watch")) {
        if (args.len < 3) {
            try color.printError(ew, use_color, "watch: missing task name\n\n  Hint: zr watch <task-name> [path...]\n", .{});
            return 1;
        }
        const task_name = args[2];
        const watch_paths: []const []const u8 = if (args.len > 3) args[3..] else &[_][]const u8{"."};
        return cmdWatch(allocator, task_name, watch_paths, w, ew, use_color);
    } else if (std.mem.eql(u8, cmd, "workflow")) {
        if (args.len < 3) {
            try color.printError(ew, use_color, "workflow: missing workflow name\n\n  Hint: zr workflow <name>\n", .{});
            return 1;
        }
        const wf_name = args[2];
        return cmdWorkflow(allocator, wf_name, w, ew, use_color);
    } else if (std.mem.eql(u8, cmd, "list")) {
        return cmdList(allocator, w, ew, use_color);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        return cmdGraph(allocator, w, ew, use_color);
    } else if (std.mem.eql(u8, cmd, "history")) {
        return cmdHistory(allocator, w, ew, use_color);
    } else {
        try color.printError(ew, use_color, "Unknown command: {s}\n\n", .{cmd});
        try printHelp(w, use_color);
        return 1;
    }
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v0.0.4", .{});
    try w.print(" - Zig Task Runner\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr <command> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  run <task>             Run a task and its dependencies\n", .{});
    try w.print("  watch <task> [path...] Watch files and auto-run task on changes\n", .{});
    try w.print("  workflow <name>        Run a workflow by name\n", .{});
    try w.print("  list                   List all available tasks\n", .{});
    try w.print("  graph                  Show dependency tree\n", .{});
    try w.print("  history                Show recent run history\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --help, -h   Show this help message\n\n", .{});
    try color.printDim(w, use_color, "Config file: zr.toml (in current directory)\n", .{});
}

fn loadConfig(
    allocator: std.mem.Allocator,
    err_writer: *std.Io.Writer,
) !?loader.Config {
    // Color is disabled for config errors since we don't have a TTY handle here;
    // callers should pass use_color if needed. For simplicity, detect directly.
    const use_color = color.isTty(std.fs.File.stderr());
    return loader.Config.loadFromFile(allocator, CONFIG_FILE) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try color.printError(err_writer, use_color,
                    "Config: {s} not found\n\n  Hint: Create a zr.toml file in the current directory\n",
                    .{CONFIG_FILE},
                );
            },
            else => {
                try color.printError(err_writer, use_color,
                    "Config: Failed to load {s}: {s}\n",
                    .{ CONFIG_FILE, @errorName(err) },
                );
            },
        }
        return null;
    };
}

fn buildDag(allocator: std.mem.Allocator, config: *const loader.Config) !dag_mod.DAG {
    var dag = dag_mod.DAG.init(allocator);
    errdefer dag.deinit();

    var it = config.tasks.iterator();
    while (it.next()) |entry| {
        const task = entry.value_ptr;
        try dag.addNode(task.name);
        for (task.deps) |dep| {
            try dag.addEdge(task.name, dep);
        }
    }

    return dag;
}

fn cmdRun(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    if (config.tasks.get(task_name) == null) {
        try color.printError(err_writer, use_color,
            "run: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    }

    const start_ns = std.time.nanoTimestamp();

    const task_names = [_][]const u8{task_name};
    var sched_result = scheduler.run(allocator, &config, &task_names, .{}) catch |err| {
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

    // Print results for each task that ran
    for (sched_result.results.items) |task_result| {
        if (task_result.success) {
            try color.printSuccess(w, use_color,
                "{s} ", .{task_result.task_name});
            try color.printDim(w, use_color,
                "({d}ms)\n", .{task_result.duration_ms});
        } else {
            try color.printError(w, use_color,
                "{s} ", .{task_result.task_name});
            try color.printDim(w, use_color,
                "(exit: {d})\n", .{task_result.exit_code});
        }
    }

    // Record to history (best-effort, ignore errors)
    recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
        @intCast(sched_result.results.items.len));

    return if (sched_result.total_success) 0 else 1;
}

fn cmdWatch(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    watch_paths: []const []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Verify task exists before starting the watch loop.
    {
        var config = (try loadConfig(allocator, err_writer)) orelse return 1;
        defer config.deinit();
        if (config.tasks.get(task_name) == null) {
            try color.printError(err_writer, use_color,
                "watch: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
                .{task_name},
            );
            return 1;
        }
    }

    var watch = watcher.Watcher.init(allocator, watch_paths, 500) catch |err| {
        try color.printError(err_writer, use_color,
            "watch: Failed to initialize watcher: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer watch.deinit();

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
        var config = (try loadConfig(allocator, err_writer)) orelse {
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
        var sched_result = scheduler.run(allocator, &config, &task_names, .{}) catch |err| {
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
                try color.printError(w, use_color, "{s} ", .{task_result.task_name});
                try color.printDim(w, use_color, "(exit: {d})\n", .{task_result.exit_code});
            }
        }

        recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
            @intCast(sched_result.results.items.len));

        try color.printDim(w, use_color, "Watching for changes (Ctrl+C to stop)...\n", .{});
    }
}

fn cmdWorkflow(
    allocator: std.mem.Allocator,
    wf_name: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    const wf = config.workflows.get(wf_name) orelse {
        try color.printError(err_writer, use_color,
            "workflow: '{s}' not found\n\n  Hint: Run 'zr list' to see available workflows\n",
            .{wf_name},
        );
        return 1;
    };

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

        for (sched_result.results.items) |task_result| {
            if (task_result.success) {
                try color.printSuccess(w, use_color, "  {s} ", .{task_result.task_name});
                try color.printDim(w, use_color, "({d}ms)\n", .{task_result.duration_ms});
            } else {
                try color.printError(w, use_color, "  {s} ", .{task_result.task_name});
                try color.printDim(w, use_color, "(exit: {d})\n", .{task_result.exit_code});
            }
        }

        try color.printDim(w, use_color, "  Stage '{s}' done ({d}ms)\n",
            .{ stage.name, stage_elapsed_ms });

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

fn recordHistory(
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

fn cmdHistory(
    allocator: std.mem.Allocator,
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

fn cmdList(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    try color.printHeader(w, use_color, "Tasks:", .{});

    // Collect task names for sorted output
    var names = std.ArrayList([]const u8){};
    defer names.deinit(allocator);

    var it = config.tasks.keyIterator();
    while (it.next()) |key| {
        try names.append(allocator, key.*);
    }

    // Sort for deterministic output
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (names.items) |name| {
        const task = config.tasks.get(name).?;
        try w.print("  ", .{});
        try color.printInfo(w, use_color, "{s:<20}", .{name});
        if (task.description) |desc| {
            try color.printDim(w, use_color, " {s}", .{desc});
        }
        try w.print("\n", .{});
    }

    if (config.workflows.count() > 0) {
        try w.print("\n", .{});
        try color.printHeader(w, use_color, "Workflows:", .{});

        var wf_names = std.ArrayList([]const u8){};
        defer wf_names.deinit(allocator);

        var wit = config.workflows.keyIterator();
        while (wit.next()) |key| {
            try wf_names.append(allocator, key.*);
        }
        std.mem.sort([]const u8, wf_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (wf_names.items) |name| {
            const wf = config.workflows.get(name).?;
            try w.print("  ", .{});
            try color.printInfo(w, use_color, "{s:<20}", .{name});
            if (wf.description) |desc| {
                try color.printDim(w, use_color, " {s}", .{desc});
            }
            try color.printDim(w, use_color, " ({d} stages)", .{wf.stages.len});
            try w.print("\n", .{});
        }
    }

    return 0;
}

fn cmdGraph(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // Check for cycles first
    var cycle_result = try cycle_detect.detectCycle(allocator, &dag);
    defer cycle_result.deinit(allocator);

    if (cycle_result.has_cycle) {
        try color.printError(err_writer, use_color,
            "graph: Cycle detected in dependency graph\n\n  Hint: Check your deps fields for circular references\n",
            .{},
        );
        return 1;
    }

    try color.printHeader(w, use_color, "Dependency Graph:", .{});
    try w.print("\n", .{});

    // Get execution levels for structured output
    var levels = try topo_sort.getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    for (levels.levels.items, 0..) |level, level_idx| {
        try color.printDim(w, use_color, "  Level {d}:\n", .{level_idx});

        // Sort names within level for deterministic output
        var sorted_level = std.ArrayList([]const u8){};
        defer sorted_level.deinit(allocator);

        for (level.items) |name| {
            try sorted_level.append(allocator, name);
        }
        std.mem.sort([]const u8, sorted_level.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (sorted_level.items) |name| {
            const task = config.tasks.get(name) orelse continue;
            try w.print("    ", .{});
            try color.printInfo(w, use_color, "{s}", .{name});
            if (task.deps.len > 0) {
                try color.printDim(w, use_color, " -> [", .{});
                for (task.deps, 0..) |dep, i| {
                    if (i > 0) try color.printDim(w, use_color, ", ", .{});
                    try color.printDim(w, use_color, "{s}", .{dep});
                }
                try color.printDim(w, use_color, "]", .{});
            }
            try w.print("\n", .{});
        }
    }

    return 0;
}

test "basic functionality" {
    try std.testing.expect(true);
}
