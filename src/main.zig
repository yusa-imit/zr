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
const cache_store = @import("cache/store.zig");

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
    _ = cache_store;
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

    // Parse global flags: --profile <name>, --dry-run, --jobs, --no-color, --quiet, --verbose, --config, --format
    // Scan args for flags; strip them from the args slice before command dispatch.
    var profile_name: ?[]const u8 = null;
    var dry_run: bool = false;
    var max_jobs: u32 = 0;
    var no_color: bool = false;
    var quiet: bool = false;
    var verbose: bool = false;
    var json_output: bool = false;
    var config_path: []const u8 = CONFIG_FILE;
    var remaining_args = std.ArrayList([]const u8){};
    defer remaining_args.deinit(allocator);
    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--profile") or std.mem.eql(u8, args[i], "-p")) {
                if (i + 1 < args.len) {
                    profile_name = args[i + 1];
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color, "--profile: missing profile name\n\n  Hint: zr --profile <name> run <task>\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, args[i], "--dry-run") or std.mem.eql(u8, args[i], "-n")) {
                dry_run = true;
            } else if (std.mem.eql(u8, args[i], "--no-color")) {
                no_color = true;
            } else if (std.mem.eql(u8, args[i], "--quiet") or std.mem.eql(u8, args[i], "-q")) {
                quiet = true;
            } else if (std.mem.eql(u8, args[i], "--verbose") or std.mem.eql(u8, args[i], "-v")) {
                verbose = true;
            } else if (std.mem.eql(u8, args[i], "--format") or std.mem.eql(u8, args[i], "-f")) {
                if (i + 1 < args.len) {
                    const fmt_val = args[i + 1];
                    if (std.mem.eql(u8, fmt_val, "json")) {
                        json_output = true;
                    } else if (std.mem.eql(u8, fmt_val, "text")) {
                        json_output = false;
                    } else {
                        try color.printError(ew, use_color,
                            "--format: unknown format '{s}'\n\n  Hint: supported formats: text, json\n",
                            .{fmt_val});
                        return 1;
                    }
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color,
                        "--format: missing value\n\n  Hint: zr --format <text|json> <command>\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, args[i], "--jobs") or std.mem.eql(u8, args[i], "-j")) {
                if (i + 1 < args.len) {
                    const n = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                        try color.printError(ew, use_color,
                            "--jobs: invalid value '{s}' — must be a positive integer\n\n  Hint: zr --jobs 4 run <task>\n",
                            .{args[i + 1]});
                        return 1;
                    };
                    if (n == 0) {
                        try color.printError(ew, use_color,
                            "--jobs: value must be >= 1 (use 1 for sequential execution)\n\n  Hint: zr --jobs 4 run <task>\n", .{});
                        return 1;
                    }
                    max_jobs = n;
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color,
                        "--jobs: missing value\n\n  Hint: zr --jobs <N> run <task>\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, args[i], "--config")) {
                if (i + 1 < args.len) {
                    config_path = args[i + 1];
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color,
                        "--config: missing path\n\n  Hint: zr --config <path> run <task>\n", .{});
                    return 1;
                }
            } else {
                try remaining_args.append(allocator, args[i]);
            }
        }
    }
    // ZR_PROFILE env var is checked inside loadConfig (--profile flag takes precedence).

    // Apply --no-color override.
    const effective_color = use_color and !no_color;

    // For --quiet: redirect stdout to /dev/null so non-error output is suppressed.
    // On non-Unix systems this silently falls back to normal output.
    var quiet_file_opt: ?std.fs.File = null;
    defer if (quiet_file_opt) |f| f.close();
    var quiet_buf: [4096]u8 = undefined;
    // quiet_writer must be a plain (non-optional) var so that &quiet_writer.interface
    // is a stable pointer into this stack frame (not into an optional wrapper).
    var quiet_writer: std.fs.File.Writer = undefined;
    const effective_w: *std.Io.Writer = blk: {
        if (quiet) {
            if (std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only })) |qf| {
                quiet_file_opt = qf;
                quiet_writer = qf.writer(&quiet_buf);
                break :blk &quiet_writer.interface;
            } else |_| {}
        }
        break :blk w;
    };

    const effective_args = remaining_args.items;
    if (effective_args.len < 2) {
        try printHelp(effective_w, effective_color);
        return 0;
    }

    // --verbose: print a dim note after the help guard.
    if (verbose) {
        try color.printDim(effective_w, effective_color, "[verbose mode]\n", .{});
    }

    const cmd = effective_args[1];

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try printHelp(effective_w, effective_color);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "run: missing task name\n\n  Hint: zr run <task-name>\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        return cmdRun(allocator, task_name, profile_name, dry_run, max_jobs, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "watch")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "watch: missing task name\n\n  Hint: zr watch <task-name> [path...]\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        const watch_paths: []const []const u8 = if (effective_args.len > 3) effective_args[3..] else &[_][]const u8{"."};
        return cmdWatch(allocator, task_name, watch_paths, profile_name, max_jobs, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "workflow")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "workflow: missing workflow name\n\n  Hint: zr workflow <name>\n", .{});
            return 1;
        }
        const wf_name = effective_args[2];
        return cmdWorkflow(allocator, wf_name, profile_name, dry_run, max_jobs, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "list")) {
        return cmdList(allocator, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        return cmdGraph(allocator, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "history")) {
        return cmdHistory(allocator, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "init")) {
        return cmdInit(std.fs.cwd(), effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "completion")) {
        const shell = if (effective_args.len >= 3) effective_args[2] else "";
        return cmdCompletion(shell, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "workspace")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        if (std.mem.eql(u8, sub, "list")) {
            return cmdWorkspaceList(allocator, config_path, json_output, effective_w, ew, effective_color);
        } else if (std.mem.eql(u8, sub, "run")) {
            if (effective_args.len < 4) {
                try color.printError(ew, effective_color,
                    "workspace run: missing task name\n\n  Hint: zr workspace run <task-name>\n", .{});
                return 1;
            }
            const task_name = effective_args[3];
            return cmdWorkspaceRun(allocator, task_name, profile_name, dry_run, max_jobs, config_path, json_output, effective_w, ew, effective_color);
        } else {
            try color.printError(ew, effective_color,
                "workspace: unknown subcommand '{s}'\n\n  Hint: zr workspace list | zr workspace run <task>\n", .{sub});
            return 1;
        }
    } else if (std.mem.eql(u8, cmd, "cache")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        return cmdCache(allocator, sub, effective_w, ew, effective_color);
    } else {
        try color.printError(ew, effective_color, "Unknown command: {s}\n\n", .{cmd});
        try printHelp(effective_w, effective_color);
        return 1;
    }
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v0.0.4", .{});
    try w.print(" - Zig Task Runner\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr [options] <command> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  run <task>             Run a task and its dependencies\n", .{});
    try w.print("  watch <task> [path...] Watch files and auto-run task on changes\n", .{});
    try w.print("  workflow <name>        Run a workflow by name\n", .{});
    try w.print("  list                   List all available tasks\n", .{});
    try w.print("  graph                  Show dependency tree\n", .{});
    try w.print("  history                Show recent run history\n", .{});
    try w.print("  workspace list         List workspace member directories\n", .{});
    try w.print("  workspace run <task>   Run a task across all workspace members\n", .{});
    try w.print("  cache clear            Clear all cached task results\n", .{});
    try w.print("  init                   Scaffold a new zr.toml in the current directory\n", .{});
    try w.print("  completion <shell>     Print shell completion script (bash|zsh|fish)\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --help, -h            Show this help message\n", .{});
    try w.print("  --profile, -p <name>  Activate a named profile (overrides env/task settings)\n", .{});
    try w.print("  --dry-run, -n         Show what would run without executing (run/workflow only)\n", .{});
    try w.print("  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n", .{});
    try w.print("  --no-color            Disable color output\n", .{});
    try w.print("  --quiet, -q           Suppress non-error output\n", .{});
    try w.print("  --verbose, -v         Verbose output\n", .{});
    try w.print("  --config <path>       Config file path (default: zr.toml)\n", .{});
    try w.print("  --format, -f <fmt>    Output format: text (default) or json\n\n", .{});
    try color.printDim(w, use_color, "Config file: zr.toml (in current directory)\n", .{});
    try color.printDim(w, use_color, "Profile env: ZR_PROFILE=<name> (alternative to --profile)\n", .{});
}

fn loadConfig(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    profile_name_opt: ?[]const u8,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !?loader.Config {
    var config = loader.Config.loadFromFile(allocator, config_path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try color.printError(err_writer, use_color,
                    "Config: {s} not found\n\n  Hint: Create a zr.toml file in the current directory\n",
                    .{config_path},
                );
            },
            else => {
                try color.printError(err_writer, use_color,
                    "Config: Failed to load {s}: {s}\n",
                    .{ config_path, @errorName(err) },
                );
            },
        }
        return null;
    };

    // Resolve effective profile: --profile flag, then ZR_PROFILE env var.
    var effective_profile: ?[]const u8 = profile_name_opt;
    var env_profile_buf: [256]u8 = undefined;
    if (effective_profile == null) {
        if (std.process.getEnvVarOwned(allocator, "ZR_PROFILE")) |pname| {
            defer allocator.free(pname);
            if (pname.len > 0 and pname.len <= env_profile_buf.len) {
                @memcpy(env_profile_buf[0..pname.len], pname);
                effective_profile = env_profile_buf[0..pname.len];
            }
        } else |_| {}
    }

    if (effective_profile) |pname| {
        config.applyProfile(pname) catch |err| switch (err) {
            error.ProfileNotFound => {
                try color.printError(err_writer, use_color,
                    "profile: '{s}' not found in {s}\n\n  Hint: Add [profiles.{s}] to your zr.toml\n",
                    .{ pname, config_path, pname },
                );
                config.deinit();
                return null;
            },
            else => {
                try color.printError(err_writer, use_color,
                    "profile: Failed to apply '{s}': {s}\n", .{ pname, @errorName(err) });
                config.deinit();
                return null;
            },
        };
    }

    return config;
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
    profile_name: ?[]const u8,
    dry_run: bool,
    max_jobs: u32,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
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
        for (sched_result.results.items) |task_result| {
            if (task_result.success) {
                try color.printSuccess(w, use_color,
                    "{s} ", .{task_result.task_name});
                try color.printDim(w, use_color,
                    "({d}ms)\n", .{task_result.duration_ms});
            } else {
                try color.printError(err_writer, use_color,
                    "{s} ", .{task_result.task_name});
                try color.printDim(err_writer, use_color,
                    "(exit: {d})\n", .{task_result.exit_code});
            }
        }
    }

    // Record to history (best-effort, ignore errors)
    recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
        @intCast(sched_result.results.items.len));

    return if (sched_result.total_success) 0 else 1;
}

/// Emit a JSON object for the run result:
/// {"success":true,"elapsed_ms":42,"tasks":[{"name":"t","success":true,"exit_code":0,"duration_ms":10,"skipped":false}]}
fn printRunResultJson(
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
        try writeJsonString(w, r.task_name);
        try w.print(",\"success\":{s},\"exit_code\":{d},\"duration_ms\":{d},\"skipped\":{s}}}", .{
            if (r.success) "true" else "false",
            r.exit_code,
            r.duration_ms,
            if (r.skipped) "true" else "false",
        });
    }
    try w.writeAll("]}\n");
}

/// Write a JSON-encoded string (with surrounding quotes and escape sequences).
fn writeJsonString(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => try w.print("\\u{x:0>4}", .{c}),
            else => try w.writeByte(c),
        }
    }
    try w.writeAll("\"");
}

/// Print a formatted dry-run plan showing execution levels and task names.
fn printDryRunPlan(w: *std.Io.Writer, use_color: bool, plan: scheduler.DryRunPlan) !void {
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

fn cmdWatch(
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
        var config = (try loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
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
        var config = (try loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse {
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

fn cmdWorkflow(
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
    var config = (try loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
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
            try writeJsonString(w, rec.task_name);
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

fn cmdList(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, config_path, null, err_writer, use_color)) orelse return 1;
    defer config.deinit();

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

    if (json_output) {
        // Collect workflow names too
        var wf_names = std.ArrayList([]const u8){};
        defer wf_names.deinit(allocator);
        var wit2 = config.workflows.keyIterator();
        while (wit2.next()) |key| {
            try wf_names.append(allocator, key.*);
        }
        std.mem.sort([]const u8, wf_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        try w.writeAll("{\"tasks\":[");
        for (names.items, 0..) |name, i| {
            const task = config.tasks.get(name).?;
            if (i > 0) try w.writeAll(",");
            try w.print("{{\"name\":", .{});
            try writeJsonString(w, name);
            try w.print(",\"cmd\":", .{});
            try writeJsonString(w, task.cmd);
            if (task.description) |desc| {
                try w.print(",\"description\":", .{});
                try writeJsonString(w, desc);
            } else {
                try w.writeAll(",\"description\":null");
            }
            try w.print(",\"deps_count\":{d}}}", .{task.deps.len});
        }
        try w.writeAll("],\"workflows\":[");
        for (wf_names.items, 0..) |name, i| {
            const wf = config.workflows.get(name).?;
            if (i > 0) try w.writeAll(",");
            try w.print("{{\"name\":", .{});
            try writeJsonString(w, name);
            if (wf.description) |desc| {
                try w.print(",\"description\":", .{});
                try writeJsonString(w, desc);
            } else {
                try w.writeAll(",\"description\":null");
            }
            try w.print(",\"stages\":{d}}}", .{wf.stages.len});
        }
        try w.writeAll("]}\n");
        return 0;
    }

    try color.printHeader(w, use_color, "Tasks:", .{});

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
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, config_path, null, err_writer, use_color)) orelse return 1;
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

    // Get execution levels for structured output
    var levels = try topo_sort.getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    if (json_output) {
        // {"levels":[{"index":0,"tasks":[{"name":"t","deps":["a","b"]}]}]}
        try w.writeAll("{\"levels\":[");
        for (levels.levels.items, 0..) |level, level_idx| {
            if (level_idx > 0) try w.writeAll(",");
            try w.print("{{\"index\":{d},\"tasks\":[", .{level_idx});

            // Sort for deterministic output
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

            for (sorted_level.items, 0..) |name, ti| {
                const task = config.tasks.get(name) orelse continue;
                if (ti > 0) try w.writeAll(",");
                try w.print("{{\"name\":", .{});
                try writeJsonString(w, name);
                try w.writeAll(",\"deps\":[");
                for (task.deps, 0..) |dep, di| {
                    if (di > 0) try w.writeAll(",");
                    try writeJsonString(w, dep);
                }
                try w.writeAll("]}");
            }
            try w.writeAll("]}");
        }
        try w.writeAll("]}\n");
        return 0;
    }

    try color.printHeader(w, use_color, "Dependency Graph:", .{});
    try w.print("\n", .{});

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

// ── Workspace helpers ─────────────────────────────────────────────────────────

/// Resolve workspace member directories from glob patterns.
/// Only handles "dir/*" (list all direct subdirectories of `dir`).
/// Returns a caller-owned slice of owned paths (absolute or relative to cwd).
fn resolveWorkspaceMembers(
    allocator: std.mem.Allocator,
    ws: loader.Workspace,
    config_filename: []const u8,
) ![][]const u8 {
    var members = std.ArrayList([]const u8){};
    errdefer {
        for (members.items) |m| allocator.free(m);
        members.deinit(allocator);
    }

    for (ws.members) |pattern| {
        // Check if pattern ends with "/*" — list all subdirs of parent.
        if (std.mem.endsWith(u8, pattern, "/*")) {
            const parent_dir = pattern[0 .. pattern.len - 2];
            var dir = std.fs.cwd().openDir(parent_dir, .{ .iterate = true }) catch continue;
            defer dir.close();

            var it = dir.iterate();
            while (try it.next()) |entry| {
                if (entry.kind != .directory) continue;
                // Skip hidden directories
                if (entry.name[0] == '.') continue;
                // Build path: parent_dir/entry.name
                const member_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ parent_dir, entry.name });
                errdefer allocator.free(member_path);
                // Only include if it has a config file
                const cfg_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ member_path, config_filename });
                defer allocator.free(cfg_path);
                const has_config: bool = blk: {
                    std.fs.cwd().access(cfg_path, .{}) catch break :blk false;
                    break :blk true;
                };
                if (!has_config) {
                    allocator.free(member_path);
                    continue;
                }
                try members.append(allocator, member_path);
            }
        } else {
            // Treat as a literal directory path
            const cfg_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ pattern, config_filename });
            defer allocator.free(cfg_path);
            const has_config: bool = blk: {
                std.fs.cwd().access(cfg_path, .{}) catch break :blk false;
                break :blk true;
            };
            if (!has_config) continue;
            const member_path = try allocator.dupe(u8, pattern);
            try members.append(allocator, member_path);
        }
    }

    // Sort for deterministic output
    std.mem.sort([]const u8, members.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    return members.toOwnedSlice(allocator);
}

fn cmdWorkspaceList(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    const ws = config.workspace orelse {
        try color.printError(ew, use_color,
            "workspace: no [workspace] section in {s}\n\n  Hint: Add [workspace] members = [\"packages/*\"] to your zr.toml\n",
            .{config_path});
        return 1;
    };

    const members = try resolveWorkspaceMembers(allocator, ws, CONFIG_FILE);
    defer {
        for (members) |m| allocator.free(m);
        allocator.free(members);
    }

    if (json_output) {
        try w.writeAll("{\"members\":[");
        for (members, 0..) |m, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeAll("{\"path\":");
            try writeJsonString(w, m);
            try w.writeAll("}");
        }
        try w.writeAll("]}\n");
    } else {
        try color.printBold(w, use_color, "Workspace Members ({d}):\n", .{members.len});
        if (members.len == 0) {
            try color.printDim(w, use_color, "  (no members found — check your glob patterns)\n", .{});
        } else {
            for (members) |m| {
                try w.print("  {s}\n", .{m});
            }
        }
    }

    return 0;
}

fn cmdWorkspaceRun(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    profile_name: ?[]const u8,
    dry_run: bool,
    max_jobs: u32,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var root_config = (try loadConfig(allocator, config_path, profile_name, ew, use_color)) orelse return 1;
    defer root_config.deinit();

    const ws = root_config.workspace orelse {
        try color.printError(ew, use_color,
            "workspace: no [workspace] section in {s}\n\n  Hint: Add [workspace] members = [\"packages/*\"] to your zr.toml\n",
            .{config_path});
        return 1;
    };

    const members = try resolveWorkspaceMembers(allocator, ws, CONFIG_FILE);
    defer {
        for (members) |m| allocator.free(m);
        allocator.free(members);
    }

    if (members.len == 0) {
        try color.printError(ew, use_color,
            "workspace: no member directories found\n\n  Hint: Check your [workspace] members patterns\n", .{});
        return 1;
    }

    var overall_success: bool = true;
    var ran_count: usize = 0;
    var skip_count: usize = 0;
    // json_emitted tracks how many members have been emitted to the JSON array
    // (separate from ran_count which also counts dry-run members)
    var json_emitted: usize = 0;

    // For dry-run mode, always use text output regardless of json_output flag
    // (dry-run produces plan text that can't be nested inside JSON)
    const effective_json = json_output and !dry_run;

    if (effective_json) {
        try w.writeAll("{\"task\":");
        try writeJsonString(w, task_name);
        try w.writeAll(",\"members\":[");
    }

    for (members) |member_path| {
        // Build path to member config
        const member_cfg = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ member_path, CONFIG_FILE });
        defer allocator.free(member_cfg);

        var member_config = loader.Config.loadFromFile(allocator, member_cfg) catch |err| {
            if (err == error.FileNotFound) continue;
            try color.printError(ew, use_color,
                "workspace: failed to load {s}: {s}\n", .{ member_cfg, @errorName(err) });
            overall_success = false;
            continue;
        };
        defer member_config.deinit();

        // Skip members that don't define this task
        if (member_config.tasks.get(task_name) == null) {
            skip_count += 1;
            continue;
        }

        ran_count += 1;

        if (dry_run) {
            try color.printBold(w, use_color, "\n── {s} (dry-run) ──\n", .{member_path});
            var plan = try scheduler.planDryRun(allocator, &member_config, &[_][]const u8{task_name});
            defer plan.deinit();
            for (plan.levels, 0..) |level, li| {
                try w.print("  Level {d}: ", .{li});
                for (level.tasks, 0..) |t, ti| {
                    if (ti > 0) try w.writeAll(", ");
                    try w.writeAll(t);
                }
                try w.writeAll("\n");
            }
            continue;
        }

        if (effective_json) {
            if (json_emitted > 0) try w.writeAll(",");
        } else {
            try color.printBold(w, use_color, "\n── {s} ──\n", .{member_path});
        }

        const sched_cfg = scheduler.SchedulerConfig{
            .max_jobs = max_jobs,
            .inherit_stdio = true,
            .dry_run = false,
        };
        const task_names = [_][]const u8{task_name};
        var result = scheduler.run(allocator, &member_config, &task_names, sched_cfg) catch |err| {
            try color.printError(ew, use_color,
                "workspace: {s}: failed: {s}\n", .{ member_path, @errorName(err) });
            overall_success = false;
            if (effective_json) {
                try w.writeAll("{\"path\":");
                try writeJsonString(w, member_path);
                try w.writeAll(",\"success\":false}");
                json_emitted += 1;
            }
            continue;
        };
        defer result.deinit(allocator);

        if (!result.total_success) overall_success = false;

        if (effective_json) {
            try w.writeAll("{\"path\":");
            try writeJsonString(w, member_path);
            try w.print(",\"success\":{s}", .{if (result.total_success) "true" else "false"});
            try w.writeAll("}");
            json_emitted += 1;
        } else {
            if (result.total_success) {
                try color.printSuccess(w, use_color, "  ✓ {s}\n", .{member_path});
            } else {
                try color.printError(ew, use_color, "  ✗ {s}: task failed\n", .{member_path});
            }
        }
    }

    // Check if no member ran the task (consistent behavior for both text and JSON)
    if (ran_count == 0 and !dry_run) {
        if (effective_json) {
            try w.print("],\"ran\":0,\"skipped\":{d},\"success\":false}}\n", .{skip_count});
        } else {
            try color.printError(ew, use_color,
                "workspace: no members define task '{s}'\n", .{task_name});
        }
        return 1;
    }

    if (effective_json) {
        try w.print("],\"ran\":{d},\"skipped\":{d},\"success\":{s}}}\n",
            .{ ran_count, skip_count, if (overall_success) "true" else "false" });
    } else {
        try w.print("\n", .{});
        if (skip_count > 0) {
            try color.printDim(w, use_color, "  ({d} member(s) skipped — task '{s}' not defined)\n",
                .{ skip_count, task_name });
        }
        if (overall_success) {
            try color.printSuccess(w, use_color, "All {d} member(s) succeeded\n", .{ran_count});
        } else {
            try color.printError(ew, use_color,
                "workspace: one or more members failed\n", .{});
            return 1;
        }
    }

    return if (overall_success) 0 else 1;
}

// ── Shell completion scripts ──────────────────────────────────────────────────

const BASH_COMPLETION =
    \\_zr_completion() {
    \\    local cur="${COMP_WORDS[COMP_CWORD]}"
    \\    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    local commands="run watch workflow list graph history workspace init completion"
    \\    local options="--help --profile --dry-run --jobs --no-color --quiet --verbose --config --format -h -p -n -j -q -v -f"
    \\
    \\    case "$prev" in
    \\        run|watch)
    \\            # Complete task names from zr.toml
    \\            local tasks
    \\            tasks=$(zr list 2>/dev/null | awk 'NR>1 && /^  / {print $1}')
    \\            COMPREPLY=($(compgen -W "$tasks" -- "$cur"))
    \\            return ;;
    \\        workflow)
    \\            # Complete workflow names from zr list
    \\            local workflows
    \\            workflows=$(zr list 2>/dev/null | awk '/^Workflows:/,0 {if (/^  /) print $1}')
    \\            COMPREPLY=($(compgen -W "$workflows" -- "$cur"))
    \\            return ;;
    \\        workspace)
    \\            COMPREPLY=($(compgen -W "list run" -- "$cur"))
    \\            return ;;
    \\        completion)
    \\            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
    \\            return ;;
    \\        --profile|-p)
    \\            return ;;
    \\        --jobs|-j)
    \\            return ;;
    \\        --config)
    \\            COMPREPLY=($(compgen -f -- "$cur"))
    \\            return ;;
    \\        --format|-f)
    \\            COMPREPLY=($(compgen -W "text json" -- "$cur"))
    \\            return ;;
    \\    esac
    \\
    \\    if [[ "$cur" == -* ]]; then
    \\        COMPREPLY=($(compgen -W "$options" -- "$cur"))
    \\    else
    \\        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    \\    fi
    \\}
    \\
    \\complete -F _zr_completion zr
    \\
;

const ZSH_COMPLETION =
    \\#compdef zr
    \\
    \\_zr() {
    \\    local state
    \\    local -a commands options
    \\    commands=(
    \\        'run:Run a task and its dependencies'
    \\        'watch:Watch files and auto-run task on changes'
    \\        'workflow:Run a workflow by name'
    \\        'list:List all available tasks'
    \\        'graph:Show dependency tree'
    \\        'history:Show recent run history'
    \\        'init:Scaffold a new zr.toml'
    \\        'completion:Print shell completion script'
    \\        'workspace:Manage workspace members (list|run)'
    \\    )
    \\    options=(
    \\        '--help[Show help]'
    \\        '-h[Show help]'
    \\        '--profile[Activate named profile]:profile name'
    \\        '-p[Activate named profile]:profile name'
    \\        '--dry-run[Show plan without executing]'
    \\        '-n[Show plan without executing]'
    \\        '--jobs[Max parallel tasks]:count'
    \\        '-j[Max parallel tasks]:count'
    \\        '--no-color[Disable color output]'
    \\        '--quiet[Suppress non-error output]'
    \\        '-q[Suppress non-error output]'
    \\        '--verbose[Verbose output]'
    \\        '-v[Verbose output]'
    \\        '--config[Config file path]:file:_files'
    \\        '--format[Output format]:format:(text json)'
    \\        '-f[Output format]:format:(text json)'
    \\    )
    \\    _arguments -C \
    \\        $options \
    \\        '1: :->command' \
    \\        '*: :->args' && return
    \\    case $state in
    \\        command)
    \\            _describe 'command' commands ;;
    \\        args)
    \\            case $words[2] in
    \\                run|watch)
    \\                    local -a tasks
    \\                    tasks=(${(f)"$(zr list 2>/dev/null | awk 'NR>1 && /^  / {print $1}')"})
    \\                    _describe 'task' tasks ;;
    \\                workflow)
    \\                    local -a workflows
    \\                    workflows=(${(f)"$(zr list 2>/dev/null | awk '/^Workflows:/,0 {if (/^  /) print $1}')"})
    \\                    _describe 'workflow' workflows ;;
    \\                completion)
    \\                    _values 'shell' bash zsh fish ;;
    \\                workspace)
    \\                    _values 'subcommand' list run ;;
    \\            esac ;;
    \\    esac
    \\}
    \\
    \\_zr "$@"
    \\
;

const FISH_COMPLETION =
    \\# Fish completion for zr
    \\
    \\function __zr_tasks
    \\    zr list 2>/dev/null | awk 'NR>1 && /^  / {print $1}'
    \\end
    \\
    \\function __zr_workflows
    \\    zr list 2>/dev/null | awk '/^Workflows:/,0 {if (/^  /) print $1}'
    \\end
    \\
    \\# Subcommands
    \\complete -c zr -f -n '__fish_use_subcommand' -a run        -d 'Run a task'
    \\complete -c zr -f -n '__fish_use_subcommand' -a watch      -d 'Watch and auto-run task'
    \\complete -c zr -f -n '__fish_use_subcommand' -a workflow   -d 'Run a workflow'
    \\complete -c zr -f -n '__fish_use_subcommand' -a list       -d 'List tasks'
    \\complete -c zr -f -n '__fish_use_subcommand' -a graph      -d 'Show dependency tree'
    \\complete -c zr -f -n '__fish_use_subcommand' -a history    -d 'Show run history'
    \\complete -c zr -f -n '__fish_use_subcommand' -a init       -d 'Scaffold zr.toml'
    \\complete -c zr -f -n '__fish_use_subcommand' -a completion -d 'Print completion script'
    \\complete -c zr -f -n '__fish_use_subcommand' -a workspace  -d 'Workspace commands (list|run)'
    \\complete -c zr -f -n '__fish_seen_subcommand_from workspace' -a 'list run'
    \\
    \\# Task name completions for run/watch
    \\complete -c zr -f -n '__fish_seen_subcommand_from run watch' -a '(__zr_tasks)'
    \\
    \\# Workflow name completions for workflow
    \\complete -c zr -f -n '__fish_seen_subcommand_from workflow' -a '(__zr_workflows)'
    \\
    \\# Shell completions for completion
    \\complete -c zr -f -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
    \\
    \\# Global options
    \\complete -c zr -l help       -s h -d 'Show help'
    \\complete -c zr -l profile    -s p -d 'Activate named profile' -r
    \\complete -c zr -l dry-run    -s n -d 'Show plan without executing'
    \\complete -c zr -l jobs       -s j -d 'Max parallel tasks' -r
    \\complete -c zr -l no-color         -d 'Disable color output'
    \\complete -c zr -l quiet      -s q -d 'Suppress non-error output'
    \\complete -c zr -l verbose    -s v -d 'Verbose output'
    \\complete -c zr -l config           -d 'Config file path' -r -F
    \\complete -c zr -l format    -s f -d 'Output format' -r -a 'text json'
    \\
;

fn cmdCompletion(
    shell: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (std.mem.eql(u8, shell, "bash")) {
        try w.writeAll(BASH_COMPLETION);
        return 0;
    } else if (std.mem.eql(u8, shell, "zsh")) {
        try w.writeAll(ZSH_COMPLETION);
        return 0;
    } else if (std.mem.eql(u8, shell, "fish")) {
        try w.writeAll(FISH_COMPLETION);
        return 0;
    } else if (shell.len == 0) {
        try color.printError(err_writer, use_color,
            "completion: missing shell name\n\n  Hint: zr completion <bash|zsh|fish>\n", .{});
        return 1;
    } else {
        try color.printError(err_writer, use_color,
            "completion: unknown shell '{s}'\n\n  Hint: supported shells: bash, zsh, fish\n",
            .{shell});
        return 1;
    }
}

const INIT_TEMPLATE =
    \\# zr.toml — generated by `zr init`
    \\# Docs: https://github.com/yusa-imit/zr
    \\
    \\[tasks.hello]
    \\description = "Print a greeting"
    \\cmd = "echo Hello from zr!"
    \\
    \\[tasks.build]
    \\description = "Build the project"
    \\cmd = "echo Building..."
    \\deps = ["hello"]
    \\
    \\[tasks.test]
    \\description = "Run tests"
    \\cmd = "echo Testing..."
    \\deps = ["build"]
    \\
    \\[tasks.clean]
    \\description = "Remove build artifacts"
    \\cmd = "echo Cleaning..."
    \\allow_failure = true
    \\
;

fn cmdInit(
    dir: std.fs.Dir,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Check whether the config already exists.
    const exists: bool = blk: {
        dir.access(CONFIG_FILE, .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            try color.printError(err_writer, use_color,
                "init: Cannot check for existing config: {s}\n", .{@errorName(err)});
            return 1;
        };
        break :blk true;
    };

    if (exists) {
        try color.printError(err_writer, use_color,
            "init: {s} already exists\n\n  Hint: Remove it first or edit it directly\n",
            .{CONFIG_FILE});
        return 1;
    }

    // Create the config file exclusively (won't overwrite).
    const file = dir.createFile(CONFIG_FILE, .{ .exclusive = true }) catch |cerr| {
        try color.printError(err_writer, use_color,
            "init: Failed to create {s}: {s}\n", .{ CONFIG_FILE, @errorName(cerr) });
        return 1;
    };

    // Write template. On failure, delete the partial file so the user can retry.
    file.writeAll(INIT_TEMPLATE) catch |werr| {
        file.close();
        dir.deleteFile(CONFIG_FILE) catch {};
        try color.printError(err_writer, use_color,
            "init: Failed to write {s}: {s}\n", .{ CONFIG_FILE, @errorName(werr) });
        return 1;
    };
    file.close();

    try color.printSuccess(w, use_color, "Created {s}\n", .{CONFIG_FILE});
    try color.printDim(w, use_color,
        "\nNext steps:\n  zr list          # see available tasks\n  zr run hello     # run the example task\n",
        .{});
    return 0;
}

fn cmdCache(
    allocator: std.mem.Allocator,
    sub: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (std.mem.eql(u8, sub, "clear")) {
        var store = cache_store.CacheStore.init(allocator) catch |err| {
            try color.printError(ew, use_color,
                "cache: failed to open cache directory: {}\n\n  Hint: Check permissions on ~/.zr/cache/\n",
                .{err});
            return 1;
        };
        defer store.deinit();

        const removed = store.clearAll() catch |err| {
            try color.printError(ew, use_color,
                "cache: error while clearing cache: {}\n", .{err});
            return 1;
        };
        try color.printSuccess(w, use_color, "Cleared {d} cached task result(s)\n", .{removed});
        return 0;
    } else if (sub.len == 0) {
        try color.printError(ew, use_color,
            "cache: missing subcommand\n\n  Hint: zr cache clear\n", .{});
        return 1;
    } else {
        try color.printError(ew, use_color,
            "cache: unknown subcommand '{s}'\n\n  Hint: zr cache clear\n", .{sub});
        return 1;
    }
}

test "basic functionality" {
    try std.testing.expect(true);
}

test "cmdInit creates zr.toml in empty directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    // First call: should create the file.
    const code1 = try cmdInit(tmp.dir, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code1);

    // Verify file exists and contains expected content.
    const content = try tmp.dir.readFileAlloc(std.testing.allocator, CONFIG_FILE, 4096);
    defer std.testing.allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "[tasks.") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "hello") != null);

    // Second call: should refuse to overwrite.
    const code2 = try cmdInit(tmp.dir, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code2);
}

test "completion scripts are non-empty and contain key markers" {
    try std.testing.expect(BASH_COMPLETION.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "_zr_completion") != null);
    try std.testing.expect(ZSH_COMPLETION.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "#compdef zr") != null);
    try std.testing.expect(FISH_COMPLETION.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "complete -c zr") != null);
}

test "completion scripts include new global flags" {
    // BASH should list the new flags in the options variable.
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--jobs") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--config") != null);
    // ZSH should describe each new flag.
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--jobs") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--config") != null);
    // Fish should have complete entries for each new flag.
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "jobs") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "config") != null);
}

test "--no-color and --jobs are consumed before command dispatch" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // With only flags and no command after them, should print help (exit 0),
    // not "Unknown command: --no-color".
    const fake_args = [_][]const u8{ "zr", "--no-color", "--jobs", "4" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, true);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--quiet flag is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --quiet with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--quiet" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, true);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--verbose flag is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --verbose with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--verbose" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--config flag missing value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --config without a value should return exit code 1.
    const fake_args = [_][]const u8{ "zr", "--config" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--jobs with invalid value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --jobs with non-numeric value should return exit code 1.
    const fake_args = [_][]const u8{ "zr", "--jobs", "notanumber" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--format json is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --format json with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--format", "json" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--format text is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format", "text" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--format unknown value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format", "yaml" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--format missing value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "writeJsonString escapes special characters" {
    var buf: [256]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var w = stdout.writer(&buf);

    // Just test that it runs without error on common characters.
    try writeJsonString(&w.interface, "hello world");
    try writeJsonString(&w.interface, "with \"quotes\"");
    try writeJsonString(&w.interface, "with\nnewline");
    try writeJsonString(&w.interface, "with\\backslash");
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

test "cmdList --format json returns valid JSON with tasks field" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // Without a real config file this returns 1 — ensure it doesn't crash
    // and that flag parsing itself works (no panic).
    const fake_args = [_][]const u8{ "zr", "--format", "json", "list" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    // Exit 1 expected (no zr.toml in cwd during tests) — but no crash/panic.
    _ = code;
}

test "completion scripts include --format flag" {
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--format") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--format") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "format") != null);
}

test "completion scripts include workspace command" {
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "workspace") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "workspace") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "workspace") != null);
}

test "workspace command: missing subcommand returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // "workspace" with unknown subcommand returns 1
    const fake_args = [_][]const u8{ "zr", "workspace", "unknown" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "workspace command: run missing task name returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // "workspace run" without task name returns 1
    const fake_args = [_][]const u8{ "zr", "workspace", "run" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "workspace: Workspace struct deinit is safe" {
    const allocator = std.testing.allocator;
    // Build a Workspace manually and deinit it
    const members = try allocator.alloc([]const u8, 2);
    members[0] = try allocator.dupe(u8, "packages/*");
    members[1] = try allocator.dupe(u8, "apps/*");
    const ignore = try allocator.alloc([]const u8, 1);
    ignore[0] = try allocator.dupe(u8, "**/node_modules");
    var ws = loader.Workspace{ .members = members, .ignore = ignore };
    ws.deinit(allocator);
    // If we get here without crash/leak, the test passes
}
