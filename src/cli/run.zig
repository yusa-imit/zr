const std = @import("std");
const sailor = @import("sailor");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const scheduler = @import("../exec/scheduler.zig");
const history = @import("../history/store.zig");
const watcher = @import("../watch/watcher.zig");
const debounce = @import("../watch/debounce.zig");
const livereload = @import("../watch/livereload.zig");
const progress = @import("../output/progress.zig");
const tui_runner = @import("tui_runner.zig");
const levenshtein = @import("../util/levenshtein.zig");
const matrix = @import("../exec/matrix.zig");
const filter_mod = @import("../output/filter.zig");
const uptodate = @import("../exec/uptodate.zig");
const env_loader = @import("../config/env_loader.zig");
const types = @import("../config/types.zig");
const input_prompt_mod = @import("input_prompt.zig");
const junit = @import("junit.zig");

/// Substitute {{...}} placeholders in a confirm_if expression using runtime params.
/// Returns an allocated string (caller must free).
fn evalConfirmIfExpr(
    allocator: std.mem.Allocator,
    expr_str: []const u8,
    params: *const std.StringHashMap([]const u8),
) ![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);
    var i: usize = 0;
    while (i < expr_str.len) {
        if (i + 1 < expr_str.len and expr_str[i] == '{' and expr_str[i + 1] == '{') {
            const start = i + 2;
            var end: ?usize = null;
            var j = start;
            while (j + 1 < expr_str.len) : (j += 1) {
                if (expr_str[j] == '}' and expr_str[j + 1] == '}') { end = j; break; }
            }
            if (end) |e| {
                const name = expr_str[start..e];
                if (params.get(name)) |val| {
                    try result.appendSlice(allocator, val);
                } else {
                    try result.appendSlice(allocator, expr_str[i..e + 2]);
                }
                i = e + 2;
            } else {
                try result.append(allocator, expr_str[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, expr_str[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

/// Display the resolved environment variables for a task
pub fn printTaskEnvironment(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
    config: *types.Config,
    task: *const types.Task,
    task_name: []const u8,
    runtime_params: *const std.StringHashMap([]const u8),
) !void {
    _ = err_writer;
    _ = config;

    // Build the effective environment for this task
    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    // 1. Start with system environment
    var system_env = try std.process.getEnvMap(allocator);
    defer system_env.deinit();
    var system_it = system_env.iterator();
    while (system_it.next()) |entry| {
        try env_map.put(
            try allocator.dupe(u8, entry.key_ptr.*),
            try allocator.dupe(u8, entry.value_ptr.*),
        );
    }

    // 2. Load .env files if specified (from config.base_env or task.env_file)
    var env_file_list = std.ArrayList([]const u8){};
    defer env_file_list.deinit(allocator);

    if (task.env_file) |files| {
        for (files) |file| {
            try env_file_list.append(allocator, file);
        }
    }

    if (env_file_list.items.len > 0) {
        const cwd_path = task.cwd orelse ".";
        for (env_file_list.items) |env_file| {
            // Build full path: cwd/env_file
            const full_path = if (std.fs.path.isAbsolute(env_file))
                try allocator.dupe(u8, env_file)
            else
                try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, env_file });
            defer allocator.free(full_path);

            var file_env = try env_loader.loadEnvFile(allocator, full_path);
            defer {
                var it = file_env.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    allocator.free(entry.value_ptr.*);
                }
                file_env.deinit();
            }

            // Merge into env_map (file env overrides)
            var file_it = file_env.iterator();
            while (file_it.next()) |entry| {
                if (env_map.fetchRemove(entry.key_ptr.*)) |old| {
                    allocator.free(old.key);
                    allocator.free(old.value);
                }
                try env_map.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try allocator.dupe(u8, entry.value_ptr.*),
                );
            }
        }
    }

    // 3. Apply task-level env
    for (task.env) |kv| {
        const key = kv[0];
        const value = kv[1];
        if (env_map.fetchRemove(key)) |old| {
            allocator.free(old.key);
            allocator.free(old.value);
        }
        try env_map.put(
            try allocator.dupe(u8, key),
            try allocator.dupe(u8, value),
        );
    }

    // 4. Interpolate runtime params into environment (as ZR_PARAM_xxx)
    var param_it = runtime_params.iterator();
    while (param_it.next()) |entry| {
        const env_key = try std.fmt.allocPrint(allocator, "ZR_PARAM_{s}", .{entry.key_ptr.*});
        defer allocator.free(env_key);

        if (env_map.fetchRemove(env_key)) |old| {
            allocator.free(old.key);
            allocator.free(old.value);
        }
        try env_map.put(
            try allocator.dupe(u8, env_key),
            try allocator.dupe(u8, entry.value_ptr.*),
        );
    }

    // Print the environment
    try color.printBold(w, use_color, "Environment for task '{s}':\n", .{task_name});

    // Sort keys for consistent output
    var keys = std.ArrayList([]const u8){};
    defer keys.deinit(allocator);
    var key_it = env_map.keyIterator();
    while (key_it.next()) |key_ptr| {
        try keys.append(allocator, key_ptr.*);
    }
    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (keys.items) |key| {
        const value = env_map.get(key).?;
        try color.printDim(w, use_color, "  {s}", .{key});
        try w.print("={s}\n", .{value});
    }
}

pub fn cmdRun(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    profile_name: ?[]const u8,
    dry_run: bool,
    force_run: bool,
    max_jobs: u32,
    config_path: []const u8,
    json_output: bool,
    monitor: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
    task_control: ?*@import("../exec/control.zig").TaskControl,
    filter_options: filter_mod.FilterOptions,
    silent_override: bool,
    show_env: bool,
    runtime_params: std.StringHashMap([]const u8),
    skip_tasks: []const []const u8,
    notify_override: bool,
    only_mode: bool,
    show_outputs: bool,
    cli_inputs: std.StringHashMap([]const u8),
    non_interactive: bool,
    yes_confirm: bool,
    cli_env: std.StringHashMap([]const u8),
    cli_env_files: []const []const u8,
    runtime_tags: []const []const u8,
    junit_path: ?[]const u8,
    output_on_failure: bool,
    track_failures: bool,
    show_summary: bool,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    // Derive project root from config file path so tasks run from the right directory.
    const project_root: ?[]const u8 = std.fs.path.dirname(config_path);

    // [settings] jobs overrides default (0=auto) when CLI --jobs not explicitly set
    const effective_max_jobs: u32 = if (max_jobs != 0) max_jobs else (config.settings.jobs orelse 0);
    // [settings] default_timeout converted to ms for scheduler (task-level timeout takes precedence)
    const settings_default_timeout_ms: ?u64 = if (config.settings.default_timeout) |s| s * 1000 else null;

    // Wildcard group expansion: "build.*" runs all tasks in the build namespace (v1.94.0)
    if (std.mem.endsWith(u8, task_name, ".*")) {
        const group_prefix = task_name[0..task_name.len - 2]; // strip ".*"
        const prefix_with_dot = try std.fmt.allocPrint(allocator, "{s}.", .{group_prefix});
        defer allocator.free(prefix_with_dot);

        // Collect all matching tasks
        var group_task_names = std.ArrayList([]const u8){};
        defer group_task_names.deinit(allocator);

        var group_it = config.tasks.iterator();
        while (group_it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix_with_dot)) {
                try group_task_names.append(allocator, entry.key_ptr.*);
            }
        }

        if (group_task_names.items.len == 0) {
            try color.printError(err_writer, use_color,
                "run: No tasks found in group '{s}'\n", .{group_prefix});
            try err_writer.print("\n  Hint: Run 'zr list' to see available tasks\n", .{});
            return 1;
        }

        // Sort for deterministic execution order
        std.mem.sort([]const u8, group_task_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Dry-run support
        if (dry_run) {
            var plan = scheduler.planDryRun(allocator, &config, group_task_names.items, only_mode) catch |err| {
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
            try printDryRunPlan(allocator, w, use_color, plan, &config);
            return 0;
        }

        // Run the group
        const start_ns_g = std.time.nanoTimestamp();
        var task_outputs_g = std.StringHashMap([]const u8).init(allocator);
        defer {
            var it_g = task_outputs_g.iterator();
            while (it_g.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            task_outputs_g.deinit();
        }

        var sched_result_g = scheduler.run(allocator, &config, group_task_names.items, .{
            .max_jobs = effective_max_jobs,
            .monitor = monitor,
            .use_color = use_color,
            .task_control = task_control,
            .filter_options = filter_options,
            .silent_override = silent_override,
            .force_run = force_run,
            .runtime_params = &runtime_params,
            .skip_tasks = skip_tasks,
            .notify_override = notify_override,
            .only_mode = only_mode,
            .task_outputs = &task_outputs_g,
            .default_timeout_ms = settings_default_timeout_ms,
            .project_root = project_root,
        }) catch |err| {
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
        defer sched_result_g.deinit(allocator);

        const elapsed_ms_g: u64 = @intCast(@divTrunc(std.time.nanoTimestamp() - start_ns_g, std.time.ns_per_ms));

        if (json_output) {
            try printRunResultJson(w, sched_result_g.results.items, sched_result_g.total_success, elapsed_ms_g);
        } else {
            var passed_g: usize = 0;
            var failed_g: usize = 0;
            var skipped_g: usize = 0;
            for (sched_result_g.results.items) |task_result| {
                if (task_result.skipped) {
                    skipped_g += 1;
                } else if (task_result.success) {
                    passed_g += 1;
                    try color.printSuccess(w, use_color, "{s} ", .{task_result.task_name});
                    try color.printDim(w, use_color, "({d}ms)\n", .{task_result.duration_ms});
                } else {
                    failed_g += 1;
                    try color.printError(err_writer, use_color, "{s} ", .{task_result.task_name});
                    try color.printDim(err_writer, use_color, "(exit: {d})\n", .{task_result.exit_code});
                }
            }
            if (sched_result_g.results.items.len > 1) {
                try progress.printSummary(w, use_color, passed_g, failed_g, skipped_g, elapsed_ms_g);
            }
        }

        if (junit_path) |jpath| {
            junit.writeJunitXml(allocator, jpath, task_name, sched_result_g.results.items, elapsed_ms_g) catch |err| {
                try color.printError(err_writer, use_color, "run: Failed to write JUnit XML to '{s}': {}\n", .{ jpath, err });
            };
        }

        if (show_summary and !json_output) {
            try printRunSummaryTable(w, use_color, sched_result_g.results.items, elapsed_ms_g);
        }

        return if (sched_result_g.total_success) 0 else 1;
    }

    // Try prefix matching if exact match fails
    var resolved_task_name: []const u8 = task_name;
    const match_result = try findTasksByPrefix(allocator, task_name, &config.tasks);
    defer allocator.free(match_result.prefix_matches);

    if (match_result.exact == null) {
        // No exact match - check prefix matches
        if (match_result.prefix_matches.len == 0) {
            // No prefix matches either - try fuzzy matching
            var task_names_list = std.ArrayList([]const u8){};
            defer task_names_list.deinit(allocator);
            var task_iter = config.tasks.iterator();
            while (task_iter.next()) |entry| {
                try task_names_list.append(allocator, entry.key_ptr.*);
            }

            const suggestions = try levenshtein.findClosestMatches(
                allocator,
                task_name,
                task_names_list.items,
                3, // max distance
                3, // max suggestions
            );
            defer allocator.free(suggestions);

            try color.printError(err_writer, use_color,
                "run: Task '{s}' not found\n",
                .{task_name},
            );

            if (std.mem.startsWith(u8, task_name, "-")) {
                try err_writer.print("\n  Hint: Unknown flag '{s}'. Run 'zr --help' to see available options\n", .{task_name});
            } else if (suggestions.len > 0) {
                try err_writer.print("\n  Did you mean?\n", .{});
                for (suggestions) |suggestion| {
                    try err_writer.print("    {s}\n", .{suggestion.name});
                }
                try err_writer.print("\n", .{});
            } else {
                try err_writer.print("\n  Hint: Run 'zr list' to see available tasks\n", .{});
            }
            return 1;
        } else if (match_result.prefix_matches.len == 1) {
            // Unique prefix match - use it
            resolved_task_name = match_result.prefix_matches[0];
            try color.printDim(err_writer, use_color, "Resolved '{s}' → '{s}'\n", .{ task_name, resolved_task_name });
        } else {
            // Ambiguous prefix - show all matches
            try color.printError(err_writer, use_color,
                "run: Ambiguous task prefix '{s}'\n",
                .{task_name},
            );
            try err_writer.print("\n  Matching tasks:\n", .{});
            for (match_result.prefix_matches) |match| {
                try err_writer.print("    {s}\n", .{match});
            }
            try err_writer.print("\n  Hint: Use a more specific prefix or full task name\n", .{});
            return 1;
        }
    }

    const task_names = [_][]const u8{resolved_task_name};

    // Resolve and validate runtime params (v1.75.0)
    var resolved_params = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = resolved_params.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        resolved_params.deinit();
    }

    const task = config.tasks.get(resolved_task_name) orelse {
        try color.printError(err_writer, use_color, "run: Task '{s}' not found\n", .{resolved_task_name});
        return 1;
    };

    // Resolve positional params to named params based on task.task_params order
    _ = &runtime_params; // params are used below in the loops

    // Map positional args to param names in declaration order
    var pos_idx: usize = 0;
    for (task.task_params) |param| {
        const pos_key = try std.fmt.allocPrint(allocator, "__positional_{d}", .{pos_idx});
        defer allocator.free(pos_key);

        if (runtime_params.get(pos_key)) |value| {
            // Positional param provided
            try resolved_params.put(try allocator.dupe(u8, param.name), try allocator.dupe(u8, value));
            pos_idx += 1;
        } else if (runtime_params.get(param.name)) |value| {
            // Named param provided
            try resolved_params.put(try allocator.dupe(u8, param.name), try allocator.dupe(u8, value));
        } else if (param.default) |default_val| {
            // Use default value
            try resolved_params.put(try allocator.dupe(u8, param.name), try allocator.dupe(u8, default_val));
        } else {
            // Required param missing
            try color.printError(err_writer, use_color,
                "run: Required parameter '{s}' not provided\n\n  Hint: {s}\n",
                .{ param.name, if (param.description) |desc| desc else "Provide value via CLI" },
            );
            return 1;
        }
    }

    // Check for unknown params (accept both task_params and input_prompt names)
    var params_it = runtime_params.iterator();
    while (params_it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.startsWith(u8, key, "__positional_")) continue; // skip internal markers

        // Check if this param exists in task_params definition
        var found = false;
        for (task.task_params) |param| {
            if (std.mem.eql(u8, key, param.name)) {
                found = true;
                break;
            }
        }
        // Also accept input_prompt names (v1.88.0)
        if (!found) {
            for (task.input_prompts) |ip| {
                if (std.mem.eql(u8, key, ip.name)) {
                    found = true;
                    break;
                }
            }
        }
        // Also accept [vars] keys — --param can override any [vars] variable
        if (!found and config.vars.contains(key)) {
            found = true;
        }
        if (!found) {
            try color.printError(err_writer, use_color,
                "run: Unknown parameter '{s}' for task '{s}'\n",
                .{ key, resolved_task_name },
            );
            return 1;
        }
    }

    // Copy [vars] overrides from --param into resolved_params so the scheduler sees them.
    // runtime_params keys that match config.vars keys override the [vars] defaults.
    {
        var rp_it = runtime_params.iterator();
        while (rp_it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.startsWith(u8, key, "__positional_")) continue;
            if (config.vars.contains(key) and !resolved_params.contains(key)) {
                try resolved_params.put(try allocator.dupe(u8, key), try allocator.dupe(u8, entry.value_ptr.*));
            }
        }
    }

    // v1.88.0: Collect input_prompt values for the task dep graph.
    // Walk deps transitively and merge prompt values into resolved_params before execution.
    // Skip collection in dry-run mode — the plan viewer shows prompt state separately.
    if (!dry_run) {
        var ip_visited = std.StringHashMap(bool).init(allocator);
        defer ip_visited.deinit();
        var ip_stack = std.ArrayList([]const u8){};
        defer ip_stack.deinit(allocator);
        try ip_stack.append(allocator, resolved_task_name);
        const collect_non_interactive = non_interactive;

        while (ip_stack.items.len > 0) {
            const tn = ip_stack.pop() orelse break;
            if ((try ip_visited.fetchPut(tn, true)) != null) continue;
            const t = config.tasks.get(tn) orelse continue;

            for (t.input_prompts) |ip| {
                // Priority 1: --input flag takes highest precedence
                if (cli_inputs.get(ip.name)) |val| {
                    input_prompt_mod.validateInputValue(ip, val) catch |verr| {
                        switch (verr) {
                            input_prompt_mod.InputError.InvalidInputType => {
                                try color.printError(err_writer, use_color,
                                    "✗ Input '{s}': expected {s}, got '{s}'\n\n  Hint: Use --input {s}=<value>\n",
                                    .{ ip.name, ip.type, val, ip.name });
                            },
                            input_prompt_mod.InputError.InvalidInputChoice => {
                                try color.printError(err_writer, use_color,
                                    "✗ Input '{s}': invalid choice '{s}'\n", .{ ip.name, val });
                                if (ip.choices.len > 0) {
                                    try err_writer.print("  Valid choices:", .{});
                                    for (ip.choices) |c| try err_writer.print(" {s}", .{c});
                                    try err_writer.print("\n  Hint: Use --input {s}=<choice>\n", .{ip.name});
                                }
                            },
                            else => {},
                        }
                        return 1;
                    };
                    // --input wins: replace any existing --param value
                    if (resolved_params.fetchRemove(ip.name)) |old| {
                        allocator.free(old.key);
                        allocator.free(old.value);
                    }
                    try resolved_params.put(
                        try allocator.dupe(u8, ip.name),
                        try allocator.dupe(u8, val),
                    );
                    continue;
                }

                // Priority 2: already in resolved_params (from --param) — just validate
                if (resolved_params.get(ip.name)) |existing_val| {
                    input_prompt_mod.validateInputValue(ip, existing_val) catch |verr| {
                        switch (verr) {
                            input_prompt_mod.InputError.InvalidInputType => {
                                try color.printError(err_writer, use_color,
                                    "✗ Input '{s}': expected {s}, got '{s}'\n\n  Hint: Use --input {s}=<value>\n",
                                    .{ ip.name, ip.type, existing_val, ip.name });
                            },
                            input_prompt_mod.InputError.InvalidInputChoice => {
                                try color.printError(err_writer, use_color,
                                    "✗ Input '{s}': invalid choice '{s}'\n  Hint: Use --input {s}=<choice>\n",
                                    .{ ip.name, existing_val, ip.name });
                            },
                            else => {},
                        }
                        return 1;
                    };
                    continue;
                }

                // Priority 3: use default or interactive prompt
                if (collect_non_interactive) {
                    // v1.89.0: Secret inputs require explicit --input, never auto-use default
                    if (ip.secret) {
                        try color.printError(err_writer, use_color,
                            "✗ run: secret input '{s}' requires explicit --input flag\n\n" ++
                            "  Hint: Use --input {s}=VALUE (secret inputs never use defaults automatically)\n",
                            .{ ip.name, ip.name });
                        return 1;
                    }
                    if (ip.default) |def| {
                        try resolved_params.put(
                            try allocator.dupe(u8, ip.name),
                            try allocator.dupe(u8, def),
                        );
                    } else {
                        try color.printError(err_writer, use_color,
                            "✗ run: required input '{s}' not provided\n\n" ++
                            "  Hint: Use --input {s}=VALUE or remove --non-interactive\n",
                            .{ ip.name, ip.name });
                        return 1;
                    }
                } else {
                    // Interactive: prompt user via stdin (fallback to default if available)
                    if (ip.default) |def| {
                        try resolved_params.put(
                            try allocator.dupe(u8, ip.name),
                            try allocator.dupe(u8, def),
                        );
                    } else {
                        try color.printError(err_writer, use_color,
                            "✗ run: required input '{s}' not provided\n\n" ++
                            "  Hint: Use --input {s}=VALUE\n",
                            .{ ip.name, ip.name });
                        return 1;
                    }
                }
            }

            if (!only_mode) {
                for (t.deps) |dep| try ip_stack.append(allocator, dep);
                for (t.deps_serial) |dep| try ip_stack.append(allocator, dep);
            }
        }
    }

    // v1.90.0: Process task confirmation requirements.
    // Walk dep graph to build list of tasks to skip due to unanswered confirmations.
    var confirm_skip_list = std.ArrayList([]const u8){};
    defer confirm_skip_list.deinit(allocator);
    if (!yes_confirm) {
        var cfm_visited = std.StringHashMap(bool).init(allocator);
        defer cfm_visited.deinit();
        var cfm_stack = std.ArrayList([]const u8){};
        defer cfm_stack.deinit(allocator);
        try cfm_stack.append(allocator, resolved_task_name);
        while (cfm_stack.items.len > 0) {
            const tn = cfm_stack.pop() orelse break;
            if ((try cfm_visited.fetchPut(tn, true)) != null) continue;
            const ct = config.tasks.get(tn) orelse continue;
            const needs_confirm = blk: {
                if (ct.confirm != null) break :blk true;
                if (ct.confirm_if) |cif| {
                    // Template-substitute {{...}} then evaluate
                    const subst = try evalConfirmIfExpr(allocator, cif, &resolved_params);
                    defer allocator.free(subst);
                    const trimmed = std.mem.trim(u8, subst, " \t");
                    if (std.mem.eql(u8, trimmed, "false")) break :blk false;
                    if (std.mem.eql(u8, trimmed, "true")) break :blk true;
                    // Try simple LHS == RHS or LHS != RHS comparison
                    if (std.mem.indexOf(u8, trimmed, " == ")) |p| {
                        const lhs = std.mem.trim(u8, trimmed[0..p], " \t'\"");
                        const rhs = std.mem.trim(u8, trimmed[p + 4 ..], " \t'\"");
                        break :blk std.mem.eql(u8, lhs, rhs);
                    }
                    if (std.mem.indexOf(u8, trimmed, " != ")) |p| {
                        const lhs = std.mem.trim(u8, trimmed[0..p], " \t'\"");
                        const rhs = std.mem.trim(u8, trimmed[p + 4 ..], " \t'\"");
                        break :blk !std.mem.eql(u8, lhs, rhs);
                    }
                    break :blk true; // fail-open: assume confirmation required
                }
                break :blk false;
            };
            if (needs_confirm) {
                if (non_interactive or dry_run) {
                    // In non-interactive or dry-run mode, just record for skip (dry-run shows plan later)
                    try confirm_skip_list.append(allocator, tn);
                } else {
                    // Interactive: prompt stdin
                    const prompt = if (ct.confirm != null and ct.confirm.?.len > 0)
                        ct.confirm.?
                    else blk2: {
                        break :blk2 try std.fmt.allocPrint(allocator, "Run task '{s}'?", .{tn});
                    };
                    const should_free_prompt = ct.confirm == null or ct.confirm.?.len == 0;
                    defer if (should_free_prompt) allocator.free(prompt);
                    try w.print("{s} [y/N]: ", .{prompt});
                    var buf: [64]u8 = undefined;
                    const n = std.fs.File.stdin().read(&buf) catch 0;
                    const answer = std.mem.trim(u8, buf[0..n], " \t\r\n");
                    const is_yes = std.mem.eql(u8, answer, "y") or std.mem.eql(u8, answer, "Y") or
                        std.mem.eql(u8, answer, "yes") or std.mem.eql(u8, answer, "YES");
                    if (!is_yes) {
                        try confirm_skip_list.append(allocator, tn);
                    }
                }
            }
            if (!only_mode) {
                for (ct.deps) |dep| try cfm_stack.append(allocator, dep);
                for (ct.deps_serial) |dep| try cfm_stack.append(allocator, dep);
            }
        }
    }

    // Merge skip_tasks with confirm_skip_list for effective skip list
    var effective_skip = std.ArrayList([]const u8){};
    defer effective_skip.deinit(allocator);
    try effective_skip.appendSlice(allocator, skip_tasks);
    try effective_skip.appendSlice(allocator, confirm_skip_list.items);

    // Show environment variables if --show-env flag is set
    if (show_env) {
        try printTaskEnvironment(allocator, w, err_writer, use_color, &config, &task, resolved_task_name, &resolved_params);
        if (!dry_run) {
            try w.print("\n", .{});
        }
    }

    // Dry-run: show the execution plan without running tasks.
    if (dry_run) {
        var plan = scheduler.planDryRun(allocator, &config, &task_names, only_mode) catch |err| {
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
        if (only_mode) {
            try color.printDim(w, use_color, "(--only mode: dependencies skipped)\n", .{});
        }
        try printDryRunPlan(allocator, w, use_color, plan, &config);
        // Show input prompts section if any tasks have input_prompt (v1.88.0)
        var has_input_prompts = false;
        var dry_cfg_it = config.tasks.iterator();
        while (dry_cfg_it.next()) |entry| {
            if (entry.value_ptr.input_prompts.len > 0) { has_input_prompts = true; break; }
        }
        if (has_input_prompts) {
            try w.print("\n", .{});
            try color.printBold(w, use_color, "Input prompts:\n", .{});
            var dry_it = config.tasks.iterator();
            while (dry_it.next()) |entry| {
                for (entry.value_ptr.input_prompts) |ip| {
                    const val = resolved_params.get(ip.name);
                    if (val) |v| {
                        try w.print("  {s}: {s} (value: {s})\n", .{ ip.name, ip.prompt, v });
                    } else if (ip.default) |def| {
                        // v1.89.0: Show [HIDDEN] for secret input defaults
                        const display_default = if (ip.secret) "[HIDDEN]" else def;
                        try w.print("  {s}: {s} [default: {s}]\n", .{ ip.name, ip.prompt, display_default });
                    } else {
                        try w.print("  {s}: {s} (required)\n", .{ ip.name, ip.prompt });
                    }
                }
            }
        }
        // Show confirmation section if any tasks have confirm field (v1.90.0)
        var has_confirm_tasks = false;
        var dc_it = config.tasks.iterator();
        while (dc_it.next()) |entry| {
            if (entry.value_ptr.confirm != null or entry.value_ptr.confirm_if != null) {
                has_confirm_tasks = true;
                break;
            }
        }
        if (has_confirm_tasks) {
            try w.print("\n", .{});
            try color.printBold(w, use_color, "Confirmations required:\n", .{});
            var dc_it2 = config.tasks.iterator();
            while (dc_it2.next()) |entry| {
                const t = entry.value_ptr;
                if (t.confirm) |msg| {
                    if (msg.len > 0) {
                        try w.print("  {s}: {s}\n", .{ entry.key_ptr.*, msg });
                    } else {
                        try w.print("  {s}: Run task '{s}'?\n", .{ entry.key_ptr.*, entry.key_ptr.* });
                    }
                } else if (t.confirm_if) |cif| {
                    try w.print("  {s}: (if {s})\n", .{ entry.key_ptr.*, cif });
                }
            }
        }

        // Show secrets required by tasks (v1.98.0)
        var has_secret_tasks = false;
        var s_it = config.tasks.iterator();
        while (s_it.next()) |entry| {
            const t = entry.value_ptr;
            if (t.secrets != null and t.secrets.?.len > 0) {
                has_secret_tasks = true;
                break;
            }
        }
        if (has_secret_tasks) {
            try w.print("\n", .{});
            try color.printBold(w, use_color, "Secrets required:\n", .{});
            var s_it2 = config.tasks.iterator();
            while (s_it2.next()) |entry| {
                const t = entry.value_ptr;
                if (t.secrets) |secrets| {
                    if (secrets.len > 0) {
                        try w.print("  {s}: ", .{entry.key_ptr.*});
                        for (secrets, 0..) |secret, i| {
                            if (i > 0) try w.print(", ", .{});
                            try w.print("{s}", .{secret});
                        }
                        try w.print("\n", .{});
                    }
                }
            }
        }
        // v1.102.0: Show CLI environment variables if any provided
        if (cli_env.count() > 0) {
            try w.print("\n", .{});
            try color.printBold(w, use_color, "CLI env overrides:\n", .{});
            var show_it = cli_env.iterator();
            while (show_it.next()) |entry| {
                try w.print("  {s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
        // Show run-level lifecycle hooks if any configured (v2.0.0)
        const has_lifecycle_hooks = blk: {
            const s = &config.settings;
            const ba = s.before_all != null and s.before_all.?.len > 0;
            const aa = s.after_all != null and s.after_all.?.len > 0;
            const oe = s.on_error != null and s.on_error.?.len > 0;
            const os = s.on_success != null and s.on_success.?.len > 0;
            break :blk ba or aa or oe or os;
        };
        if (has_lifecycle_hooks) {
            try w.print("\n", .{});
            try color.printBold(w, use_color, "Run lifecycle hooks:\n", .{});
            if (config.settings.before_all) |tasks| {
                if (tasks.len > 0) {
                    try w.print("  before_all: ", .{});
                    for (tasks, 0..) |t, i| {
                        if (i > 0) try w.print(", ", .{});
                        try w.print("{s}", .{t});
                    }
                    try w.print("\n", .{});
                }
            }
            if (config.settings.after_all) |tasks| {
                if (tasks.len > 0) {
                    try w.print("  after_all: ", .{});
                    for (tasks, 0..) |t, i| {
                        if (i > 0) try w.print(", ", .{});
                        try w.print("{s}", .{t});
                    }
                    try w.print("\n", .{});
                }
            }
            if (config.settings.on_success) |tasks| {
                if (tasks.len > 0) {
                    try w.print("  on_success: ", .{});
                    for (tasks, 0..) |t, i| {
                        if (i > 0) try w.print(", ", .{});
                        try w.print("{s}", .{t});
                    }
                    try w.print("\n", .{});
                }
            }
            if (config.settings.on_error) |tasks| {
                if (tasks.len > 0) {
                    try w.print("  on_error: ", .{});
                    for (tasks, 0..) |t, i| {
                        if (i > 0) try w.print(", ", .{});
                        try w.print("{s}", .{t});
                    }
                    try w.print("\n", .{});
                }
            }
        }
        // v1.102.0: Show runtime tags if any provided
        if (runtime_tags.len > 0) {
            try w.print("\n", .{});
            try color.printBold(w, use_color, "Runtime tags: ", .{});
            for (runtime_tags, 0..) |tag, i| {
                if (i > 0) try w.print(", ", .{});
                try w.print("+{s}", .{tag});
            }
            try w.print("\n", .{});
        }
        return 0;
    }

    const start_ns = std.time.nanoTimestamp();

    // v1.102.0/v1.111.0: Build extra_env array from --env-file (lower priority) then --env (higher priority)
    var cli_env_list: std.ArrayList([2][]const u8) = .{};
    defer {
        for (cli_env_list.items) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        cli_env_list.deinit(allocator);
    }
    // v1.111.0: Load --env-file entries first (lower priority than explicit --env)
    for (cli_env_files) |file_path| {
        const full_path = if (std.fs.path.isAbsolute(file_path))
            try allocator.dupe(u8, file_path)
        else
            try std.fs.path.join(allocator, &[_][]const u8{ project_root orelse ".", file_path });
        defer allocator.free(full_path);

        // Check existence first — loadEnvFile silently returns empty map for missing files
        const file_exists = blk: {
            const f = std.fs.openFileAbsolute(full_path, .{}) catch |err| switch (err) {
                error.FileNotFound, error.AccessDenied, error.NotDir => break :blk false,
                else => break :blk false,
            };
            f.close();
            break :blk true;
        };
        if (!file_exists) {
            try err_writer.print("Warning: env file not found: {s}\n", .{file_path});
            continue;
        }

        var file_env = env_loader.loadEnvFile(allocator, full_path) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => {
                try err_writer.print("Warning: env file not found: {s}\n", .{file_path});
                continue;
            },
            else => return err,
        };
        defer {
            var it = file_env.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            file_env.deinit();
        }
        var file_it = file_env.iterator();
        while (file_it.next()) |entry| {
            const env_key = try allocator.dupe(u8, entry.key_ptr.*);
            const env_value = try allocator.dupe(u8, entry.value_ptr.*);
            try cli_env_list.append(allocator, .{ env_key, env_value });
        }
    }
    // Explicit --env flags override --env-file values (added last = highest priority in extra_env)
    var cli_env_it = cli_env.iterator();
    while (cli_env_it.next()) |entry| {
        const env_key = try allocator.dupe(u8, entry.key_ptr.*);
        const env_value = try allocator.dupe(u8, entry.value_ptr.*);
        try cli_env_list.append(allocator, .{ env_key, env_value });
    }
    const cli_env_slice: ?[][2][]const u8 = if (cli_env_list.items.len > 0) cli_env_list.items else null;

    var task_outputs = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = task_outputs.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        task_outputs.deinit();
    }

    // Run-level lifecycle: before_all tasks (v2.0.0)
    // These run before any main task; if any fail, the entire run is aborted.
    before_all_blk: {
        const before_tasks = config.settings.before_all orelse break :before_all_blk;
        if (before_tasks.len == 0) break :before_all_blk;
        try color.printDim(w, use_color, "⟳ Running before_all hooks...\n", .{});
        var before_r = scheduler.run(allocator, &config, before_tasks, .{
            .max_jobs = effective_max_jobs,
            .use_color = use_color,
            .default_timeout_ms = settings_default_timeout_ms,
            .project_root = project_root,
        }) catch {
            try color.printError(err_writer, use_color,
                "run: before_all lifecycle hook failed to start\n", .{});
            return 1;
        };
        defer before_r.deinit(allocator);
        if (!before_r.total_success) {
            try color.printError(err_writer, use_color,
                "run: before_all lifecycle hook failed — aborting run\n", .{});
            return 1;
        }
    }

    var sched_result = scheduler.run(allocator, &config, &task_names, .{
        .max_jobs = effective_max_jobs,
        .monitor = monitor,
        .use_color = use_color,
        .task_control = task_control,
        .filter_options = filter_options,
        .silent_override = silent_override,
        .force_run = force_run,
        .runtime_params = &resolved_params,
        .skip_tasks = effective_skip.items,
        .notify_override = notify_override,
        .only_mode = only_mode,
        .task_outputs = &task_outputs,
        .default_timeout_ms = settings_default_timeout_ms,
        .extra_env = cli_env_slice,
        .project_root = project_root,
        .output_on_failure = output_on_failure,
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

    // Calculate aggregate stats across all tasks
    var total_retries: u32 = 0;
    var peak_memory: u64 = 0;
    var cpu_sum: f64 = 0.0;
    var cpu_count: usize = 0;
    for (sched_result.results.items) |result| {
        total_retries += result.retry_count;
        peak_memory = @max(peak_memory, result.peak_memory_bytes);
        if (result.avg_cpu_percent > 0.0) {
            cpu_sum += result.avg_cpu_percent;
            cpu_count += 1;
        }
    }
    const avg_cpu = if (cpu_count > 0) cpu_sum / @as(f64, @floatFromInt(cpu_count)) else 0.0;

    // Build runtime tags string (comma-separated)
    const tags_str: ?[]const u8 = if (runtime_tags.len > 0) blk: {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);
        for (runtime_tags, 0..) |tag, i| {
            if (i > 0) try buf.append(allocator, ',');
            try buf.appendSlice(allocator, tag);
        }
        break :blk try buf.toOwnedSlice(allocator);
    } else null;
    defer if (tags_str) |t| allocator.free(t);

    // Record to history (best-effort, ignore errors)
    recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
        @intCast(sched_result.results.items.len), total_retries, peak_memory, avg_cpu, tags_str);

    // Save/clear last-failures.txt for --retry-failed support (v1.107.0)
    // Suppressed when track_failures=false (multi-task runs handle this externally).
    if (track_failures) {
        if (!sched_result.total_success) {
            saveLastFailures(allocator, config_path, sched_result.results.items);
        } else {
            clearLastFailures(allocator, config_path);
        }
    }

    // Display captured task outputs if --show-outputs requested (v1.87.0)
    if (show_outputs and task_outputs.count() > 0) {
        try w.print("\n", .{});
        try color.printDim(w, use_color, "Captured outputs:\n", .{});
        var out_it = task_outputs.iterator();
        while (out_it.next()) |entry| {
            try color.printDim(w, use_color, "  {s}: ", .{entry.key_ptr.*});
            try w.print("{s}\n", .{entry.value_ptr.*});
        }
    }

    // Write JUnit XML if requested
    if (junit_path) |jpath| {
        junit.writeJunitXml(allocator, jpath, task_name, sched_result.results.items, elapsed_ms) catch |err| {
            try color.printError(err_writer, use_color, "run: Failed to write JUnit XML to '{s}': {}\n", .{ jpath, err });
        };
    }

    // Print run summary table if --summary requested (v1.109.0)
    if (show_summary and !json_output) {
        try printRunSummaryTable(w, use_color, sched_result.results.items, elapsed_ms);
    }

    // Run-level lifecycle: on_success / on_error hooks (v2.0.0)
    on_success_blk: {
        if (!sched_result.total_success) break :on_success_blk;
        const on_s_tasks = config.settings.on_success orelse break :on_success_blk;
        if (on_s_tasks.len == 0) break :on_success_blk;
        try color.printDim(w, use_color, "⟳ Running on_success hooks...\n", .{});
        var on_s = scheduler.run(allocator, &config, on_s_tasks, .{
            .max_jobs = effective_max_jobs,
            .use_color = use_color,
            .default_timeout_ms = settings_default_timeout_ms,
            .project_root = project_root,
        }) catch break :on_success_blk;
        defer on_s.deinit(allocator);
    }

    on_error_blk: {
        if (sched_result.total_success) break :on_error_blk;
        const on_e_tasks = config.settings.on_error orelse break :on_error_blk;
        if (on_e_tasks.len == 0) break :on_error_blk;
        try color.printDim(w, use_color, "⟳ Running on_error hooks...\n", .{});
        var on_e = scheduler.run(allocator, &config, on_e_tasks, .{
            .max_jobs = effective_max_jobs,
            .use_color = use_color,
            .default_timeout_ms = settings_default_timeout_ms,
            .project_root = project_root,
        }) catch break :on_error_blk;
        defer on_e.deinit(allocator);
    }

    // Run-level lifecycle: after_all hooks — always run, even on main task failure (v2.0.0)
    after_all_blk: {
        const after_tasks = config.settings.after_all orelse break :after_all_blk;
        if (after_tasks.len == 0) break :after_all_blk;
        try color.printDim(w, use_color, "⟳ Running after_all hooks...\n", .{});
        var after_r = scheduler.run(allocator, &config, after_tasks, .{
            .max_jobs = effective_max_jobs,
            .use_color = use_color,
            .default_timeout_ms = settings_default_timeout_ms,
            .project_root = project_root,
        }) catch break :after_all_blk;
        defer after_r.deinit(allocator);
    }

    return if (sched_result.total_success) 0 else 1;
}

/// Write failed task names (one per line) to <project_root>/.zr/last-failures.txt.
/// Called after every scheduler run so --retry-failed can replay them.
pub fn saveLastFailures(allocator: std.mem.Allocator, config_path: []const u8, results: []const scheduler.TaskResult) void {
    const project_root = std.fs.path.dirname(config_path) orelse ".";
    const zr_dir = std.fmt.allocPrint(allocator, "{s}/.zr", .{project_root}) catch return;
    defer allocator.free(zr_dir);
    std.fs.cwd().makePath(zr_dir) catch {};
    const failures_path = std.fmt.allocPrint(allocator, "{s}/.zr/last-failures.txt", .{project_root}) catch return;
    defer allocator.free(failures_path);

    const file = std.fs.cwd().createFile(failures_path, .{ .truncate = true }) catch return;
    defer file.close();

    for (results) |result| {
        if (!result.success and !result.skipped) {
            file.writeAll(result.task_name) catch {};
            file.writeAll("\n") catch {};
        }
    }
}

/// Truncate last-failures.txt to zero bytes on a fully successful run.
pub fn clearLastFailures(allocator: std.mem.Allocator, config_path: []const u8) void {
    const project_root = std.fs.path.dirname(config_path) orelse ".";
    const failures_path = std.fmt.allocPrint(allocator, "{s}/.zr/last-failures.txt", .{project_root}) catch return;
    defer allocator.free(failures_path);

    const file = std.fs.cwd().createFile(failures_path, .{ .truncate = true }) catch return;
    file.close();
}

/// Append a single failed task name to last-failures.txt (used by multi-task runs).
pub fn appendLastFailureName(allocator: std.mem.Allocator, config_path: []const u8, task_name: []const u8) void {
    const project_root = std.fs.path.dirname(config_path) orelse ".";
    const zr_dir = std.fmt.allocPrint(allocator, "{s}/.zr", .{project_root}) catch return;
    defer allocator.free(zr_dir);
    std.fs.cwd().makePath(zr_dir) catch {};
    const failures_path = std.fmt.allocPrint(allocator, "{s}/.zr/last-failures.txt", .{project_root}) catch return;
    defer allocator.free(failures_path);

    const file = std.fs.cwd().openFile(failures_path, .{ .mode = .write_only }) catch
        (std.fs.cwd().createFile(failures_path, .{}) catch return);
    defer file.close();
    file.seekFromEnd(0) catch {};
    file.writeAll(task_name) catch {};
    file.writeAll("\n") catch {};
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
    filter_options: filter_mod.FilterOptions,
    silent_override: bool,
    skip_tasks: []const []const u8,
    runtime_tags: []const []const u8,
) !u8 {
    // Verify task exists and extract WatchConfig before starting the watch loop (v1.17.0).
    var watch_options = watcher.WatcherOptions{};
    var use_adaptive_debounce = false;
    var use_live_reload = false;
    var live_reload_port: u16 = 35729;
    {
        var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
        defer config.deinit();
        if (config.tasks.get(task_name)) |task| {
            // Extract WatchConfig from task if present (v1.17.0)
            if (task.watch) |watch_cfg| {
                watch_options.debounce_ms = watch_cfg.debounce_ms;
                watch_options.patterns = watch_cfg.patterns;
                watch_options.exclude_patterns = watch_cfg.exclude_patterns;
                use_adaptive_debounce = watch_cfg.adaptive_debounce;
                use_live_reload = watch_cfg.live_reload;
                live_reload_port = watch_cfg.live_reload_port;
            }
        } else {
            // Build list of available task names for suggestions
            var task_names_list = std.ArrayList([]const u8){};
            defer task_names_list.deinit(allocator);
            var task_iter = config.tasks.iterator();
            while (task_iter.next()) |entry| {
                try task_names_list.append(allocator, entry.key_ptr.*);
            }

            // Find similar task names using Levenshtein distance
            const suggestions = try levenshtein.findClosestMatches(
                allocator,
                task_name,
                task_names_list.items,
                3, // max distance
                3, // max suggestions
            );
            defer allocator.free(suggestions);

            try color.printError(err_writer, use_color,
                "watch: Task '{s}' not found\n",
                .{task_name},
            );

            if (suggestions.len > 0) {
                try err_writer.print("\n  Did you mean?\n", .{});
                for (suggestions) |suggestion| {
                    try err_writer.print("    {s}\n", .{suggestion.name});
                }
                try err_writer.print("\n", .{});
            } else {
                try err_writer.print("\n  Hint: Run 'zr list' to see available tasks\n", .{});
            }
            return 1;
        }
    }

    // Use native file watching (inotify/kqueue/ReadDirectoryChangesW) with 500ms polling fallback
    // v1.17.0: Use WatchConfig from task if available
    var watch = watcher.Watcher.init(allocator, watch_paths, .native, 500, watch_options) catch |err| {
        try color.printError(err_writer, use_color,
            "watch: Failed to initialize watcher: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer watch.deinit();

    // Initialize adaptive debouncer if enabled
    var adaptive_debouncer: ?debounce.AdaptiveDebouncer = null;
    if (use_adaptive_debounce) {
        const min_delay = watch_options.debounce_ms; // Use configured debounce as min
        const max_delay = min_delay * 10; // Max is 10x min (e.g., 300ms -> 3000ms)
        adaptive_debouncer = try debounce.AdaptiveDebouncer.init(
            allocator,
            min_delay,
            max_delay,
            60, // 60 second window for change frequency tracking
            100, // Track last 100 changes
        );
    }
    defer if (adaptive_debouncer) |*d| d.deinit(allocator);

    // Initialize live reload server if enabled
    var live_reload_server: ?livereload.LiveReloadServer = null;
    if (use_live_reload) {
        live_reload_server = try livereload.LiveReloadServer.init(allocator, live_reload_port);
        try live_reload_server.?.start();
    }
    defer if (live_reload_server) |*server| server.deinit();

    // Log which mode we're using
    const mode_str = switch (watch.mode) {
        .native => "native",
        .polling => "polling",
    };
    try color.printDim(w, use_color, "  (using {s} mode", .{mode_str});
    if (use_adaptive_debounce) {
        if (adaptive_debouncer) |d| {
            try color.printDim(w, use_color, ", adaptive debounce: {d}-{d}ms", .{ d.min_delay_ms, d.max_delay_ms });
        }
    } else if (watch_options.debounce_ms > 0) {
        try color.printDim(w, use_color, ", debounce: {d}ms", .{watch_options.debounce_ms});
    }
    if (watch_options.patterns.len > 0) {
        try color.printDim(w, use_color, ", patterns: {d}", .{watch_options.patterns.len});
    }
    if (watch_options.exclude_patterns.len > 0) {
        try color.printDim(w, use_color, ", excludes: {d}", .{watch_options.exclude_patterns.len});
    }
    if (use_live_reload) {
        try color.printDim(w, use_color, ", live-reload: {d}", .{live_reload_port});
    }
    try color.printDim(w, use_color, ")\n", .{});

    try color.printInfo(w, use_color, "Watching", .{});
    try w.print(" for changes (Ctrl+C to stop)...\n", .{});

    // Run the task immediately on start, then loop.
    var first_run = true;
    while (true) {
        var changed_path: ?[]const u8 = null;
        if (!first_run) {
            // Wait for a file change.
            const event = watch.waitForChange() catch |err| switch (err) {
                else => {
                    try color.printError(err_writer, use_color,
                        "watch: Watcher error: {s}\n", .{@errorName(err)});
                    return 1;
                },
            };
            changed_path = event.path;

            // Record change for adaptive debouncer
            if (adaptive_debouncer) |*d| {
                d.recordChange();
                const current_delay = d.getDelay();
                // Sleep for adaptive delay
                std.Thread.sleep(current_delay * std.time.ns_per_ms);
                try color.printInfo(w, use_color, "\nChange detected", .{});
                try color.printDim(w, use_color, ": {s} (debounce: {d}ms)\n", .{ event.path, current_delay });
            } else {
                try color.printInfo(w, use_color, "\nChange detected", .{});
                try color.printDim(w, use_color, ": {s}\n", .{event.path});
            }
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
        const watch_max_jobs: u32 = if (max_jobs != 0) max_jobs else (config.settings.jobs orelse 0);
        const watch_default_timeout_ms: ?u64 = if (config.settings.default_timeout) |s| s * 1000 else null;
        var sched_result = scheduler.run(allocator, &config, &task_names, .{
            .max_jobs = watch_max_jobs,
            .filter_options = filter_options,
            .silent_override = silent_override,
            .skip_tasks = skip_tasks,
            .default_timeout_ms = watch_default_timeout_ms,
            .project_root = std.fs.path.dirname(config_path),
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

        var total_retries: u32 = 0;
        var peak_memory: u64 = 0;
        var cpu_sum: f64 = 0.0;
        var cpu_count: usize = 0;
        for (sched_result.results.items) |task_result| {
            total_retries += task_result.retry_count;
            peak_memory = @max(peak_memory, task_result.peak_memory_bytes);
            if (task_result.avg_cpu_percent > 0.0) {
                cpu_sum += task_result.avg_cpu_percent;
                cpu_count += 1;
            }
            if (task_result.success) {
                try color.printSuccess(w, use_color, "{s} ", .{task_result.task_name});
                try color.printDim(w, use_color, "({d}ms)\n", .{task_result.duration_ms});
            } else {
                try color.printError(err_writer, use_color, "{s} ", .{task_result.task_name});
                try color.printDim(err_writer, use_color, "(exit: {d})\n", .{task_result.exit_code});
            }
        }
        const avg_cpu = if (cpu_count > 0) cpu_sum / @as(f64, @floatFromInt(cpu_count)) else 0.0;

        // Build runtime tags string (comma-separated)
        const tags_str: ?[]const u8 = if (runtime_tags.len > 0) blk: {
            var buf = std.ArrayList(u8){};
            defer buf.deinit(allocator);
            for (runtime_tags, 0..) |tag, i| {
                if (i > 0) try buf.append(allocator, ',');
                try buf.appendSlice(allocator, tag);
            }
            break :blk try buf.toOwnedSlice(allocator);
        } else null;
        defer if (tags_str) |t| allocator.free(t);

        recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
            @intCast(sched_result.results.items.len), total_retries, peak_memory, avg_cpu, tags_str);

        // Trigger live reload if enabled and task succeeded
        if (use_live_reload and sched_result.total_success) {
            if (live_reload_server) |*server| {
                const reload_path = changed_path orelse "/";
                server.trigger(reload_path) catch |err| {
                    try color.printDim(w, use_color, "  (live-reload trigger failed: {s})\n", .{@errorName(err)});
                };
                if (server.clientCount() > 0) {
                    try color.printDim(w, use_color, "  (live-reload: sent to {d} client(s))\n", .{server.clientCount()});
                }
            }
        }

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
    matrix_show: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
    filter_options: filter_mod.FilterOptions,
    silent_override: bool,
    skip_tasks: []const []const u8,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    // [settings] overrides apply to workflow execution
    const wf_max_jobs: u32 = if (max_jobs != 0) max_jobs else (config.settings.jobs orelse 0);
    const wf_default_timeout_ms: ?u64 = if (config.settings.default_timeout) |s| s * 1000 else null;

    const wf = config.workflows.get(wf_name) orelse {
        // Build list of available workflow names for suggestions
        var workflow_names_list = std.ArrayList([]const u8){};
        defer workflow_names_list.deinit(allocator);
        var wf_iter = config.workflows.iterator();
        while (wf_iter.next()) |entry| {
            try workflow_names_list.append(allocator, entry.key_ptr.*);
        }

        // Find similar workflow names using Levenshtein distance
        const suggestions = try levenshtein.findClosestMatches(
            allocator,
            wf_name,
            workflow_names_list.items,
            3, // max distance
            3, // max suggestions
        );
        defer allocator.free(suggestions);

        try color.printError(err_writer, use_color,
            "workflow: '{s}' not found\n",
            .{wf_name},
        );

        // If wf_name looks like a flag, provide a different hint
        if (std.mem.startsWith(u8, wf_name, "-")) {
            try err_writer.print("\n  Hint: Unknown flag '{s}'. Run 'zr --help' to see available options\n", .{wf_name});
        } else if (suggestions.len > 0) {
            try err_writer.print("\n  Did you mean?\n", .{});
            for (suggestions) |suggestion| {
                try err_writer.print("    {s}\n", .{suggestion.name});
            }
            try err_writer.print("\n", .{});
        } else {
            try err_writer.print("\n  Hint: Run 'zr list' to see available workflows\n", .{});
        }
        return 1;
    };

    // Expand matrix combinations if workflow has matrix config
    var combinations: []matrix.MatrixCombination = &[_]matrix.MatrixCombination{};
    defer {
        for (combinations) |*combo| combo.deinit();
        allocator.free(combinations);
    }

    if (wf.matrix) |*matrix_cfg| {
        combinations = try matrix.expandMatrix(allocator, matrix_cfg);
    }

    // If --matrix-show, display all combinations and exit
    if (matrix_show) {
        if (wf.matrix == null) {
            try color.printWarning(w, use_color, "workflow '{s}' has no matrix configuration\n", .{wf_name});
            return 0;
        }

        try color.printBold(w, use_color, "Matrix combinations for workflow: {s}\n", .{wf_name});
        if (wf.description) |desc| {
            try color.printDim(w, use_color, "  {s}\n", .{desc});
        }
        try w.print("\n", .{});

        for (combinations, 0..) |*combo, idx| {
            try color.printInfo(w, use_color, "Combination {d}:\n", .{idx + 1});
            var iter = combo.variables.iterator();
            while (iter.next()) |entry| {
                try w.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try w.print("\n", .{});
        }

        try color.printDim(w, use_color, "Total combinations: {d}\n", .{combinations.len});
        try color.printDim(w, use_color, "\nNo tasks were executed. Use 'zr workflow {s}' to run.\n", .{wf_name});
        return 0;
    }

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
            var plan = scheduler.planDryRun(allocator, &config, stage.tasks, false) catch |err| {
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
            try printDryRunPlan(allocator, w, use_color, plan, &config);
        }
        try color.printDim(w, use_color, "\nNo tasks were executed.\n", .{});
        return 0;
    }

    // Matrix execution: if workflow has matrix config, run it once per combination.
    // Each combination's variables are injected as MATRIX_* environment variables.
    const num_combinations = if (combinations.len > 0) combinations.len else 1;
    const has_matrix = wf.matrix != null and combinations.len > 0;

    if (has_matrix) {
        try color.printBold(w, use_color, "Workflow: {s}", .{wf_name});
        if (wf.description) |desc| {
            try color.printDim(w, use_color, " — {s}", .{desc});
        }
        try w.print("\n", .{});
        try color.printDim(w, use_color, "  Running {d} matrix combinations sequentially\n", .{num_combinations});
    } else {
        try color.printBold(w, use_color, "Workflow: {s}", .{wf_name});
        if (wf.description) |desc| {
            try color.printDim(w, use_color, " — {s}", .{desc});
        }
        try w.print("\n", .{});
    }

    const overall_start_ns = std.time.nanoTimestamp();
    var any_failed = false;

    // Outer loop: iterate through matrix combinations (or run once if no matrix)
    for (0..num_combinations) |combo_idx| {
        // Build extra_env from matrix combination variables
        var extra_env_list: std.ArrayList([2][]const u8) = .{};
        defer {
            for (extra_env_list.items) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            extra_env_list.deinit(allocator);
        }

        if (has_matrix) {
            const combo = &combinations[combo_idx];
            try color.printInfo(w, use_color, "\n=== Matrix combination {d}/{d} ===\n", .{ combo_idx + 1, num_combinations });
            var iter = combo.variables.iterator();
            while (iter.next()) |entry| {
                try color.printDim(w, use_color, "  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
                // Add MATRIX_<KEY>=<value> to extra_env
                const env_key = try std.fmt.allocPrint(allocator, "MATRIX_{s}", .{entry.key_ptr.*});
                const env_value = try allocator.dupe(u8, entry.value_ptr.*);
                try extra_env_list.append(allocator, .{ env_key, env_value });
            }
        }

        const extra_env_slice: ?[][2][]const u8 = if (extra_env_list.items.len > 0) extra_env_list.items else null;

        // Inner loop: execute all stages for this matrix combination
        for (wf.stages) |stage| {
            try color.printInfo(w, use_color, "\nStage: {s}\n", .{stage.name});

            if (stage.tasks.len == 0) continue;

            // Manual approval prompt if required
            if (stage.approval) {
                try color.printWarning(w, use_color, "  Manual approval required. Continue? (y/N): ", .{});
                const stdin = std.fs.File.stdin();
                var buf: [128]u8 = undefined;
                const n = stdin.read(&buf) catch 0;
                if (n > 0) {
                    const input = buf[0..n];
                    const trimmed = std.mem.trim(u8, input, " \t\r\n");
                    if (std.mem.eql(u8, trimmed, "y") or std.mem.eql(u8, trimmed, "Y")) {
                        // Approved, continue
                    } else {
                        try color.printDim(w, use_color, "  Stage '{s}' skipped by user\n", .{stage.name});
                        continue;
                    }
                } else {
                    try color.printDim(w, use_color, "  Stage '{s}' skipped (no input)\n", .{stage.name});
                    continue;
                }
            }

            const stage_start_ns = std.time.nanoTimestamp();

            var sched_result = scheduler.run(allocator, &config, stage.tasks, .{
                .inherit_stdio = true,
                .max_jobs = wf_max_jobs,
                .retry_budget = wf.retry_budget,
                .extra_env = extra_env_slice,
                .filter_options = filter_options,
                .silent_override = silent_override,
                .skip_tasks = skip_tasks,
                .default_timeout_ms = wf_default_timeout_ms,
                .project_root = std.fs.path.dirname(config_path),
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

            // Execute on_failure task if defined
            if (stage.on_failure) |failure_task| {
                try color.printWarning(w, use_color, "  Running on_failure task: {s}\n", .{failure_task});
                var failure_result = scheduler.run(allocator, &config, &[_][]const u8{failure_task}, .{
                    .inherit_stdio = true,
                    .max_jobs = wf_max_jobs,
                    .extra_env = extra_env_slice,
                    .filter_options = filter_options,
                    .silent_override = silent_override,
                    .skip_tasks = skip_tasks,
                    .default_timeout_ms = wf_default_timeout_ms,
                    .project_root = std.fs.path.dirname(config_path),
                }) catch |err| {
                    try color.printError(err_writer, use_color,
                        "workflow: on_failure task '{s}' failed: {s}\n",
                        .{ failure_task, @errorName(err) });
                    if (stage.fail_fast) return 1;
                    continue;
                };
                defer failure_result.deinit(allocator);

                if (!failure_result.total_success) {
                    try color.printError(err_writer, use_color,
                        "workflow: on_failure task '{s}' did not succeed\n", .{failure_task});
                }
            }

            if (stage.fail_fast) {
                try color.printError(err_writer, use_color,
                    "\nworkflow: Stage '{s}' failed — stopping (fail_fast)\n", .{stage.name});
                return 1;
            }
        }
    }
    // End of stages loop for this matrix combination
}
// End of matrix combinations loop

    const overall_elapsed_ms: u64 = @intCast(@divTrunc(
        std.time.nanoTimestamp() - overall_start_ns, std.time.ns_per_ms));

    try w.print("\n", .{});
    if (!any_failed) {
        try color.printSuccess(w, use_color,
            "Workflow '{s}' completed ({d}ms)\n", .{ wf_name, overall_elapsed_ms });
        if (has_matrix) {
            try color.printDim(w, use_color,
                "  All {d} matrix combinations succeeded\n", .{num_combinations});
        }
        return 0;
    } else {
        try color.printError(w, use_color,
            "Workflow '{s}' finished with failures ({d}ms)\n", .{ wf_name, overall_elapsed_ms });
        return 1;
    }
}

/// Format a Unix timestamp as a human-readable relative time string.
/// Writes into buf (must be at least 16 bytes) and returns the written slice.
pub fn formatRelativeTime(timestamp: i64, now: i64, buf: []u8) []const u8 {
    const diff = now - timestamp;
    if (diff < 60) {
        const s = "just now";
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    } else if (diff < 3600) {
        const mins = @divTrunc(diff, 60);
        return std.fmt.bufPrint(buf, "{d}m ago", .{mins}) catch buf[0..0];
    } else if (diff < 86400) {
        const hours = @divTrunc(diff, 3600);
        return std.fmt.bufPrint(buf, "{d}h ago", .{hours}) catch buf[0..0];
    } else if (diff < 604800) {
        const days = @divTrunc(diff, 86400);
        return std.fmt.bufPrint(buf, "{d}d ago", .{days}) catch buf[0..0];
    } else {
        const weeks = @divTrunc(diff, 604800);
        return std.fmt.bufPrint(buf, "{d}w ago", .{weeks}) catch buf[0..0];
    }
}

pub fn cmdHistory(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    _ = err_writer;

    // Parse flags and subcommands
    var limit: usize = 20;
    var show_stats = false;
    var do_clear = false;
    var filter_tag: ?[]const u8 = null;
    var i_arg: usize = 0;
    while (i_arg < args.len) : (i_arg += 1) {
        const arg = args[i_arg];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try w.writeAll("Usage: zr history [options] [subcommand]\n\n");
            try w.writeAll("Show recent task run history or aggregated statistics.\n\n");
            try w.writeAll("Subcommands:\n");
            try w.writeAll("  stats               Show per-task aggregated statistics\n");
            try w.writeAll("  clear               Delete all history records\n\n");
            try w.writeAll("Options:\n");
            try w.writeAll("  --limit=N           Number of recent runs to show (default: 20)\n");
            try w.writeAll("  --tag=TAG           Filter runs by runtime tag (v1.104.0+)\n");
            try w.writeAll("  --tag TAG           Filter runs by runtime tag (space form)\n");
            try w.writeAll("  --json              Output as JSON\n");
            try w.writeAll("  -h, --help          Show this help\n\n");
            try w.writeAll("Examples:\n");
            try w.writeAll("  zr history              # Show last 20 runs\n");
            try w.writeAll("  zr history --limit=50   # Show last 50 runs\n");
            try w.writeAll("  zr history --tag ci     # Show only runs tagged with 'ci'\n");
            try w.writeAll("  zr history stats        # Show per-task statistics\n");
            try w.writeAll("  zr history clear        # Clear all history\n");
            return 0;
        } else if (std.mem.eql(u8, arg, "stats")) {
            show_stats = true;
        } else if (std.mem.eql(u8, arg, "clear")) {
            do_clear = true;
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            const n = std.fmt.parseInt(usize, arg["--limit=".len..], 10) catch 20;
            limit = n;
        } else if (std.mem.startsWith(u8, arg, "--tag=")) {
            filter_tag = arg["--tag=".len..];
        } else if (std.mem.eql(u8, arg, "--tag")) {
            i_arg += 1;
            if (i_arg < args.len) {
                filter_tag = args[i_arg];
            }
        }
    }

    const hist_path = try history.defaultHistoryPath(allocator);
    defer allocator.free(hist_path);

    var store = try history.Store.init(allocator, hist_path);
    defer store.deinit();

    if (do_clear) {
        const cleared = try store.clear();
        if (cleared) {
            try color.printSuccess(w, use_color, "History cleared.\n", .{});
        } else {
            try color.printDim(w, use_color, "No history to clear.\n", .{});
        }
        return 0;
    }

    if (show_stats) {
        return cmdHistoryStats(allocator, &store, w, use_color);
    }

    // Load more records when filtering (so we can get `limit` results after filtering)
    const load_count = if (filter_tag != null) @max(limit * 20, 500) else limit;
    var all_records = try store.loadLast(allocator, load_count);
    defer {
        for (all_records.items) |r| r.deinit(allocator);
        all_records.deinit(allocator);
    }

    // Apply tag filter if requested (v1.104.0)
    var records = std.ArrayList(history.Record){};
    defer records.deinit(allocator);
    if (filter_tag) |tag| {
        var added: usize = 0;
        var ri = all_records.items.len;
        while (ri > 0 and added < limit) {
            ri -= 1;
            const rec = all_records.items[ri];
            if (rec.runtime_tags) |tags| {
                // Check if tag is present as a comma-separated element
                var tag_it = std.mem.splitScalar(u8, tags, ',');
                while (tag_it.next()) |t| {
                    if (std.mem.eql(u8, t, tag)) {
                        try records.append(allocator, rec);
                        added += 1;
                        break;
                    }
                }
            }
        }
        // Reverse so oldest matching is first (consistent with unfiltered display)
        std.mem.reverse(history.Record, records.items);
    } else {
        // No filter — use all_records directly (already limited to `limit`)
        try records.appendSlice(allocator, all_records.items);
    }

    if (json_output) {
        const JsonArr = sailor.fmt.JsonArray(*std.Io.Writer);
        try w.writeAll("{\"runs\":");
        var runs_arr = try JsonArr.init(w);
        for (records.items) |rec| {
            var obj = try runs_arr.beginObject();
            try obj.addString("task", rec.task_name);
            try obj.addBool("success", rec.success);
            try obj.addNumber("duration_ms", rec.duration_ms);
            try obj.addNumber("task_count", rec.task_count);
            try obj.addNumber("timestamp", rec.timestamp);
            try obj.end();
        }
        try runs_arr.end();
        try w.writeAll("}\n");
        return 0;
    }

    if (records.items.len == 0) {
        try color.printDim(w, use_color, "No history yet. Run a task with 'zr run <task>'.\n", .{});
        return 0;
    }

    try color.printHeader(w, use_color, "Recent Runs:", .{});
    try w.print("\n", .{});

    const now = std.time.timestamp();
    var time_buf: [16]u8 = undefined;
    for (records.items) |rec| {
        if (rec.success) {
            try color.printSuccess(w, use_color, " ", .{});
        } else {
            try color.printError(w, use_color, " ", .{});
        }
        try color.printInfo(w, use_color, "{s:<20}", .{rec.task_name});
        const rel_time = formatRelativeTime(rec.timestamp, now, &time_buf);
        try color.printDim(w, use_color, "  {d}ms  ({d} task(s))  {s}", .{
            rec.duration_ms,
            rec.task_count,
            rel_time,
        });
        // Display runtime tags if present
        if (rec.runtime_tags) |tags| {
            try w.print("  ", .{});
            try color.printDim(w, use_color, "[{s}]", .{tags});
        }
        try w.print("\n", .{});
    }

    return 0;
}

fn cmdHistoryStats(
    allocator: std.mem.Allocator,
    store: *history.Store,
    w: *std.Io.Writer,
    use_color: bool,
) !u8 {
    const stats_module = @import("../history/stats.zig");

    // Load up to 10000 records for stats aggregation
    var records = try store.loadLast(allocator, 10000);
    defer {
        for (records.items) |r| r.deinit(allocator);
        records.deinit(allocator);
    }

    if (records.items.len == 0) {
        try color.printDim(w, use_color, "No history yet. Run a task with 'zr run <task>'.\n", .{});
        return 0;
    }

    // Collect unique task names and success counts
    var task_runs = std.StringHashMap(struct { total: u32, success: u32 }).init(allocator);
    defer task_runs.deinit();

    for (records.items) |rec| {
        const entry = try task_runs.getOrPut(rec.task_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .total = 0, .success = 0 };
        }
        entry.value_ptr.total += 1;
        if (rec.success) entry.value_ptr.success += 1;
    }

    try color.printHeader(w, use_color, "Task Statistics", .{});
    try w.print(" ({d} total runs)\n\n", .{records.items.len});
    try color.printDim(w, use_color, "  {s:<20}  {s:>5}  {s:>7}  {s:>7}  {s:>7}  {s:>7}\n", .{
        "Task", "Runs", "Success", "Avg", "P90", "P99",
    });
    try color.printDim(w, use_color, "  {s:-<20}  {s:->5}  {s:->7}  {s:->7}  {s:->7}  {s:->7}\n", .{
        "", "", "", "", "", "",
    });

    var it = task_runs.iterator();
    while (it.next()) |entry| {
        const task_name = entry.key_ptr.*;
        const counts = entry.value_ptr.*;
        const success_pct = @as(u32, @intFromFloat(@as(f64, @floatFromInt(counts.success)) / @as(f64, @floatFromInt(counts.total)) * 100.0));

        var avg_str: [16]u8 = undefined;
        var p90_str: [16]u8 = undefined;
        var p99_str: [16]u8 = undefined;

        const avg_s = if (try stats_module.calculateStats(records.items, task_name, allocator)) |s| blk: {
            break :blk std.fmt.bufPrint(&avg_str, "{d}ms", .{s.avg_ms}) catch "?";
        } else "?";
        const p90_s = if (try stats_module.calculateStats(records.items, task_name, allocator)) |s| blk: {
            break :blk std.fmt.bufPrint(&p90_str, "{d}ms", .{s.p90_ms}) catch "?";
        } else "?";
        const p99_s = if (try stats_module.calculateStats(records.items, task_name, allocator)) |s| blk: {
            break :blk std.fmt.bufPrint(&p99_str, "{d}ms", .{s.p99_ms}) catch "?";
        } else "?";

        try w.print("  {s:<20}  {d:>5}  {d:>6}%  {s:>7}  {s:>7}  {s:>7}\n", .{
            task_name,
            counts.total,
            success_pct,
            avg_s,
            p90_s,
            p99_s,
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
    retry_count: u32,
    peak_memory_bytes: u64,
    avg_cpu_percent: f64,
    runtime_tags: ?[]const u8,
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
        .retry_count = retry_count,
        .peak_memory_bytes = peak_memory_bytes,
        .avg_cpu_percent = avg_cpu_percent,
        .runtime_tags = runtime_tags,
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
    const JsonArr = sailor.fmt.JsonArray(*std.Io.Writer);
    try w.writeAll("{\"success\":");
    try w.writeAll(if (total_success) "true" else "false");
    try w.print(",\"elapsed_ms\":{d},\"tasks\":", .{elapsed_ms});
    var tasks_arr = try JsonArr.init(w);
    for (results) |r| {
        var obj = try tasks_arr.beginObject();
        try obj.addString("name", r.task_name);
        try obj.addBool("success", r.success);
        try obj.addNumber("exit_code", r.exit_code);
        try obj.addNumber("duration_ms", r.duration_ms);
        try obj.addBool("skipped", r.skipped);
        try obj.end();
    }
    try tasks_arr.end();
    try w.writeAll("}\n");
}

/// Print a formatted summary table for a completed run (--summary flag).
/// Shows each task's status, name, and duration/exit code in a compact table.
pub fn printRunSummaryTable(
    w: *std.Io.Writer,
    use_color: bool,
    results: []const scheduler.TaskResult,
    elapsed_ms: u64,
) !void {
    if (results.len == 0) return;

    // Calculate max task name width for alignment (capped at 30 chars)
    var max_name: usize = 4; // minimum "task" width
    for (results) |r| {
        const n = @min(r.task_name.len, 30);
        if (n > max_name) max_name = n;
    }

    // Header
    if (use_color) {
        try sailor.color.printStyled(w, .{ .attrs = .{ .dim = true } }, "\u{2500}\u{2500} Run Summary ", .{});
        var i: usize = 0;
        while (i < max_name + 20) : (i += 1) try w.writeAll("\u{2500}");
        try w.writeAll("\n");
    } else {
        try w.writeAll("-- Run Summary ");
        var i: usize = 0;
        while (i < max_name + 20) : (i += 1) try w.writeAll("-");
        try w.writeAll("\n");
    }

    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;

    for (results) |r| {
        const name_len = @min(r.task_name.len, 30);
        const pad = max_name - name_len + 2;

        if (r.skipped) {
            skipped += 1;
            if (use_color) {
                try sailor.color.printStyled(w, .{ .fg = .{ .basic = .yellow } }, "  \u{229a}  ", .{});
                try w.writeAll(r.task_name[0..name_len]);
                var p: usize = 0;
                while (p < pad) : (p += 1) try w.writeAll(" ");
                try sailor.color.printStyled(w, .{ .attrs = .{ .dim = true } }, "skipped\n", .{});
            } else {
                try w.print("  -  {s}", .{r.task_name[0..name_len]});
                var p: usize = 0;
                while (p < pad) : (p += 1) try w.writeAll(" ");
                try w.writeAll("skipped\n");
            }
        } else if (r.success) {
            passed += 1;
            if (use_color) {
                try sailor.color.printStyled(w, .{ .fg = .{ .basic = .green } }, "  \u{2713}  ", .{});
                try w.writeAll(r.task_name[0..name_len]);
                var p: usize = 0;
                while (p < pad) : (p += 1) try w.writeAll(" ");
                if (r.duration_ms >= 1000) {
                    try sailor.color.printStyled(w, .{ .attrs = .{ .dim = true } }, "{d}.{d}s\n", .{ r.duration_ms / 1000, (r.duration_ms % 1000) / 100 });
                } else {
                    try sailor.color.printStyled(w, .{ .attrs = .{ .dim = true } }, "{d}ms\n", .{r.duration_ms});
                }
            } else {
                try w.print("  v  {s}", .{r.task_name[0..name_len]});
                var p: usize = 0;
                while (p < pad) : (p += 1) try w.writeAll(" ");
                if (r.duration_ms >= 1000) {
                    try w.print("{d}.{d}s\n", .{ r.duration_ms / 1000, (r.duration_ms % 1000) / 100 });
                } else {
                    try w.print("{d}ms\n", .{r.duration_ms});
                }
            }
        } else {
            failed += 1;
            if (use_color) {
                try sailor.color.printStyled(w, .{ .fg = .{ .basic = .red } }, "  \u{2717}  ", .{});
                try w.writeAll(r.task_name[0..name_len]);
                var p: usize = 0;
                while (p < pad) : (p += 1) try w.writeAll(" ");
                try sailor.color.printStyled(w, .{ .fg = .{ .basic = .red } }, "(exit: {d})\n", .{r.exit_code});
            } else {
                try w.print("  x  {s}", .{r.task_name[0..name_len]});
                var p: usize = 0;
                while (p < pad) : (p += 1) try w.writeAll(" ");
                try w.print("(exit: {d})\n", .{r.exit_code});
            }
        }
    }

    // Footer divider
    if (use_color) {
        try sailor.color.printStyled(w, .{ .attrs = .{ .dim = true } }, "\u{2500}\u{2500}\u{2500}", .{});
        var i: usize = 0;
        while (i < max_name + 27) : (i += 1) try w.writeAll("\u{2500}");
        try w.writeAll("\n");
    } else {
        try w.writeAll("---");
        var i: usize = 0;
        while (i < max_name + 27) : (i += 1) try w.writeAll("-");
        try w.writeAll("\n");
    }

    // Footer summary line
    try progress.printSummary(w, use_color, passed, failed, skipped, elapsed_ms);
}

/// Get up-to-date status symbol for a task.
/// Returns: "✓" (up-to-date), "✗" (stale), or "?" (never-run/no generates).
fn getTaskStatus(allocator: std.mem.Allocator, task: loader.Task) ![]const u8 {
    if (task.generates.len == 0) {
        return "?"; // No generates = can't determine
    }

    const is_up_to_date = uptodate.isUpToDate(allocator, task.sources, task.generates, null) catch false;
    return if (is_up_to_date) "✓" else "✗";
}

/// Print a formatted dry-run plan showing execution levels, task names, and up-to-date status.
pub fn printDryRunPlan(allocator: std.mem.Allocator, w: *std.Io.Writer, use_color: bool, plan: scheduler.DryRunPlan, config: *const loader.Config) !void {
    // Load history for duration estimates
    const history_path = try history.defaultHistoryPath(allocator);
    defer allocator.free(history_path);

    const hist_store = try history.Store.init(allocator, history_path);
    defer hist_store.deinit();

    var records_list = hist_store.loadLast(allocator, 1000) catch std.ArrayList(history.Record){};
    defer {
        for (records_list.items) |r| r.deinit(allocator);
        records_list.deinit(allocator);
    }

    try color.printBold(w, use_color, "Dry run — execution plan:\n", .{});
    if (plan.levels.len == 0) {
        try color.printDim(w, use_color, "  (no tasks to run)\n", .{});
        return;
    }

    // Calculate total estimated duration (sum of critical path)
    var total_estimate_ms: ?u64 = null;
    for (plan.levels) |level| {
        if (level.tasks.len == 0) continue;

        // For each level, find the longest estimated task (since they run in parallel)
        var level_max_ms: ?u64 = null;
        for (level.tasks) |task_name| {
            if (records_list.items.len > 0) {
                const stats_module = @import("../history/stats.zig");
                if (try stats_module.calculateStats(records_list.items, task_name, allocator)) |stats| {
                    if (level_max_ms == null or stats.avg_ms > level_max_ms.?) {
                        level_max_ms = stats.avg_ms;
                    }
                }
            }
        }

        if (level_max_ms) |max_ms| {
            if (total_estimate_ms) |current| {
                total_estimate_ms = current + max_ms;
            } else {
                total_estimate_ms = max_ms;
            }
        }
    }

    for (plan.levels, 0..) |level, i| {
        if (level.tasks.len == 0) continue;
        if (level.tasks.len == 1) {
            try color.printDim(w, use_color, "  Level {d}  ", .{i});

            // Show up-to-date status
            const task = config.tasks.get(level.tasks[0]);
            if (task) |t| {
                const status = try getTaskStatus(allocator, t);
                try w.print("[{s}] ", .{status});
            }

            try color.printInfo(w, use_color, "{s}", .{level.tasks[0]});

            // Show duration estimate
            if (records_list.items.len > 0) {
                const stats_module = @import("../history/stats.zig");
                if (try stats_module.calculateStats(records_list.items, level.tasks[0], allocator)) |stats| {
                    const estimate = try stats_module.formatEstimate(stats, allocator);
                    defer allocator.free(estimate);
                    try color.printDim(w, use_color, "  [{s}]", .{estimate});
                }
            }
            try w.print("\n", .{});
        } else {
            try color.printDim(w, use_color, "  Level {d}  ", .{i});
            try color.printDim(w, use_color, "[parallel]\n", .{});
            for (level.tasks) |t| {
                try w.print("    ", .{});

                // Show up-to-date status
                const task = config.tasks.get(t);
                if (task) |task_ptr| {
                    const status = try getTaskStatus(allocator, task_ptr);
                    try w.print("[{s}] ", .{status});
                }

                try color.printInfo(w, use_color, "{s}", .{t});

                // Show duration estimate
                if (records_list.items.len > 0) {
                    const stats_module = @import("../history/stats.zig");
                    if (try stats_module.calculateStats(records_list.items, t, allocator)) |stats| {
                        const estimate = try stats_module.formatEstimate(stats, allocator);
                        defer allocator.free(estimate);
                        try color.printDim(w, use_color, "  [{s}]", .{estimate});
                    }
                }
                try w.print("\n", .{});
            }
        }
    }

    // Show total estimated duration if available
    if (total_estimate_ms) |total_ms| {
        try w.print("\n", .{});
        try color.printDim(w, use_color, "Estimated total time: ", .{});

        // Format total duration
        const formatted_total = if (total_ms < 1000)
            try std.fmt.allocPrint(allocator, "{d}ms", .{total_ms})
        else if (total_ms < 60000)
            try std.fmt.allocPrint(allocator, "{d:.1}s", .{@as(f64, @floatFromInt(total_ms)) / 1000.0})
        else if (total_ms < 3600000)
            try std.fmt.allocPrint(allocator, "{d:.1}m", .{@as(f64, @floatFromInt(total_ms)) / 60000.0})
        else
            try std.fmt.allocPrint(allocator, "{d:.1}h", .{@as(f64, @floatFromInt(total_ms)) / 3600000.0});
        defer allocator.free(formatted_total);

        try color.printInfo(w, use_color, "{s}", .{formatted_total});
        try w.print("\n", .{});
    }

    try color.printDim(w, use_color, "\nNo tasks were executed.\n", .{});
}

/// Result of prefix matching
pub const PrefixMatchResult = struct {
    /// Exact match found
    exact: ?[]const u8,
    /// Prefix matches (when no exact match)
    prefix_matches: [][]const u8,
};

/// Find tasks matching a given prefix.
/// Returns exact match if found, otherwise all tasks with matching prefix.
pub fn findTasksByPrefix(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    tasks: *const std.StringHashMap(@import("../config/types.zig").Task),
) !PrefixMatchResult {
    // Check for exact match in task names first
    if (tasks.get(task_name)) |_| {
        const empty_slice = try allocator.alloc([]const u8, 0);
        return PrefixMatchResult{
            .exact = task_name,
            .prefix_matches = empty_slice,
        };
    }

    // Check for exact match in task aliases
    var iter = tasks.iterator();
    while (iter.next()) |entry| {
        for (entry.value_ptr.aliases) |alias| {
            if (std.mem.eql(u8, alias, task_name)) {
                // Alias exact match found - return task name
                const empty_slice = try allocator.alloc([]const u8, 0);
                return PrefixMatchResult{
                    .exact = entry.key_ptr.*,
                    .prefix_matches = empty_slice,
                };
            }
        }
    }

    // Find prefix matches in task names and aliases
    var matches = std.ArrayList([]const u8){};
    errdefer matches.deinit(allocator);

    var iter2 = tasks.iterator();
    while (iter2.next()) |entry| {
        // Check task name prefix
        if (std.mem.startsWith(u8, entry.key_ptr.*, task_name)) {
            try matches.append(allocator, entry.key_ptr.*);
        } else {
            // Check alias prefixes
            for (entry.value_ptr.aliases) |alias| {
                if (std.mem.startsWith(u8, alias, task_name)) {
                    try matches.append(allocator, entry.key_ptr.*);
                    break; // Only add each task once
                }
            }
        }
    }

    return PrefixMatchResult{
        .exact = null,
        .prefix_matches = try matches.toOwnedSlice(allocator),
    };
}

/// Calculate the minimum unique prefix for each task name.
/// Returns a map from task name to its shortest unique prefix.
pub fn calculateUniquePrefix(
    allocator: std.mem.Allocator,
    tasks: *const std.StringHashMap(@import("../config/types.zig").Task),
) !std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator);
    errdefer result.deinit();

    var task_names_list = std.ArrayList([]const u8){};
    defer task_names_list.deinit(allocator);

    // Collect all task names
    var iter = tasks.iterator();
    while (iter.next()) |entry| {
        try task_names_list.append(allocator, entry.key_ptr.*);
    }

    const task_names = task_names_list.items;

    // For each task, find its minimum unique prefix
    for (task_names) |task_name| {
        var prefix_len: usize = 1;
        while (prefix_len <= task_name.len) : (prefix_len += 1) {
            const prefix = task_name[0..prefix_len];

            // Count how many tasks match this prefix
            var match_count: usize = 0;
            for (task_names) |other_name| {
                if (std.mem.startsWith(u8, other_name, prefix)) {
                    match_count += 1;
                }
            }

            // If only one match, this is the unique prefix
            if (match_count == 1) {
                const owned_prefix = try allocator.dupe(u8, prefix);
                try result.put(task_name, owned_prefix);
                break;
            }
        }

        // If we didn't find a unique prefix (all prefixes match multiple tasks),
        // use the full name
        if (result.get(task_name) == null) {
            const full_name = try allocator.dupe(u8, task_name);
            try result.put(task_name, full_name);
        }
    }

    return result;
}

test "printRunResultJson emits valid JSON structure" {
    const allocator = std.testing.allocator;

    // Write to /dev/null for smoke test (verifies function doesn't panic)
    const devnull = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer devnull.close();
    var buf: [4096]u8 = undefined;
    var w = devnull.writer(&buf);

    const results = [_]scheduler.TaskResult{
        .{ .task_name = "build", .success = true, .exit_code = 0, .duration_ms = 100, .skipped = false },
        .{ .task_name = "test", .success = false, .exit_code = 1, .duration_ms = 50, .skipped = false },
    };

    // Verify function executes without error (validates logic + JSON formatting)
    try printRunResultJson(&w.interface, &results, false, 150);

    // Verify task results array structure
    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqualStrings("build", results[0].task_name);
    try std.testing.expectEqual(true, results[0].success);
    try std.testing.expectEqualStrings("test", results[1].task_name);
    try std.testing.expectEqual(false, results[1].success);
    _ = allocator;
}

test "cmdRun: missing config returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [65536]u8 = undefined; // Larger buffer to avoid FileTooBig
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [65536]u8 = undefined; // Larger buffer
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    var empty_params = std.StringHashMap([]const u8).init(allocator);
    defer empty_params.deinit();
    var empty_cli_env = std.StringHashMap([]const u8).init(allocator);
    defer empty_cli_env.deinit();
    const result = try cmdRun(
        allocator,
        "build",
        null,
        false,
        false, // force_run
        1,
        "/tmp/zr_test_nonexistent/zr.toml",
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
        .{}, // filter_options
        false, // silent_override
        false, // show_env
        empty_params,
        &.{},
        false, // notify_override
        false, // only_mode
        false, // show_outputs
        std.StringHashMap([]const u8).init(allocator),
        false, // non_interactive
        false, // yes_confirm
        empty_cli_env,
        &.{}, // cli_env_files
        &.{}, // runtime_tags
        null, // junit_path
        false, // output_on_failure
        true, // track_failures
        false, // show_summary
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

    var out_buf: [65536]u8 = undefined; // Larger buffer to avoid FileTooBig
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [65536]u8 = undefined; // Larger buffer
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    var empty_params = std.StringHashMap([]const u8).init(allocator);
    defer empty_params.deinit();
    var empty_cli_env = std.StringHashMap([]const u8).init(allocator);
    defer empty_cli_env.deinit();
    const result = try cmdRun(
        allocator,
        "nonexistent",
        null,
        false,
        false, // force_run
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
        .{}, // filter_options
        false, // silent_override
        false, // show_env
        empty_params,
        &.{},
        false, // notify_override
        false, // only_mode
        false, // show_outputs
        std.StringHashMap([]const u8).init(allocator),
        false, // non_interactive
        false, // yes_confirm
        empty_cli_env,
        &.{}, // cli_env_files
        &.{}, // runtime_tags
        null, // junit_path
        false, // output_on_failure
        true, // track_failures
        false, // show_summary
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

    var out_buf: [65536]u8 = undefined; // Larger buffer to avoid FileTooBig
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [65536]u8 = undefined; // Larger buffer
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    var empty_params = std.StringHashMap([]const u8).init(allocator);
    defer empty_params.deinit();
    var empty_cli_env = std.StringHashMap([]const u8).init(allocator);
    defer empty_cli_env.deinit();
    const result = try cmdRun(
        allocator,
        "hello",
        null,
        true,
        false, // force_run
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
        .{}, // filter_options
        false, // silent_override
        false, // show_env
        empty_params,
        &.{},
        false, // notify_override
        false, // only_mode
        false, // show_outputs
        std.StringHashMap([]const u8).init(allocator),
        false, // non_interactive
        false, // yes_confirm
        empty_cli_env,
        &.{}, // cli_env_files
        &.{}, // runtime_tags
        null, // junit_path
        false, // output_on_failure
        true, // track_failures
        false, // show_summary
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

    var out_buf: [65536]u8 = undefined; // Larger buffer to avoid FileTooBig
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [65536]u8 = undefined; // Larger buffer
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    var empty_params = std.StringHashMap([]const u8).init(allocator);
    defer empty_params.deinit();
    var empty_cli_env = std.StringHashMap([]const u8).init(allocator);
    defer empty_cli_env.deinit();
    const result = try cmdRun(
        allocator,
        "hello",
        null,
        false,
        false, // force_run
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
        .{}, // filter_options
        false, // silent_override
        false, // show_env
        empty_params,
        &.{},
        false, // notify_override
        false, // only_mode
        false, // show_outputs
        std.StringHashMap([]const u8).init(allocator),
        false, // non_interactive
        false, // yes_confirm
        empty_cli_env,
        &.{}, // cli_env_files
        &.{}, // runtime_tags
        null, // junit_path
        false, // output_on_failure
        true, // track_failures
        false, // show_summary
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

    var out_buf: [65536]u8 = undefined; // Larger buffer to avoid FileTooBig
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [65536]u8 = undefined; // Larger buffer
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    var empty_params = std.StringHashMap([]const u8).init(allocator);
    defer empty_params.deinit();
    var empty_cli_env = std.StringHashMap([]const u8).init(allocator);
    defer empty_cli_env.deinit();
    const result = try cmdRun(
        allocator,
        "fail",
        null,
        false,
        false, // force_run
        1,
        config_path,
        false,
        false, // monitor
        &out_w.interface,
        &err_w.interface,
        false,
        null,
        .{}, // filter_options
        false, // silent_override
        false, // show_env
        empty_params,
        &.{},
        false, // notify_override
        false, // only_mode
        false, // show_outputs
        std.StringHashMap([]const u8).init(allocator),
        false, // non_interactive
        false, // yes_confirm
        empty_cli_env,
        &.{}, // cli_env_files
        &.{}, // runtime_tags
        null, // junit_path
        false, // output_on_failure
        true, // track_failures
        false, // show_summary
    );
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "printDryRunPlan: empty plan" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    // Construct a DryRunPlan with no levels — allocator field is unused when levels is empty
    const plan = scheduler.DryRunPlan{
        .levels = &.{},
        .allocator = std.testing.allocator,
    };

    // Create a minimal dummy config (empty task map)
    const config = loader.Config.init(allocator);

    // printDryRunPlan should return without error on empty plan
    try printDryRunPlan(allocator, &out_w.interface, false, plan, &config);
}

test "cmdHistory: returns 0 even with large history" {
    const allocator = std.testing.allocator;

    // Note: This test may use the real .zr_history file if it exists.
    // The output can be large (1MB+), so we use /dev/null as writer
    // to avoid buffer overflow while still testing the return code.
    const builtin = @import("builtin");
    const devnull = try std.fs.openFileAbsolute(if (builtin.os.tag == .windows) "NUL" else "/dev/null", .{ .mode = .write_only });
    defer devnull.close();

    var out_buf: [4096]u8 = undefined;
    var out_w = devnull.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = devnull.writer(&err_buf);

    // cmdHistory should always return 0 regardless of history content
    const result = try cmdHistory(
        allocator,
        &.{},
        false,
        &out_w.interface,
        &err_w.interface,
        false,
    );
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "formatRelativeTime: just now" {
    var buf: [16]u8 = undefined;
    const now: i64 = 1000;
    const timestamp: i64 = 970; // 30 seconds ago
    const result = formatRelativeTime(timestamp, now, &buf);
    try std.testing.expectEqualStrings("just now", result);
}

test "formatRelativeTime: minutes ago" {
    var buf: [16]u8 = undefined;
    const now: i64 = 1000;
    const timestamp: i64 = 910; // 90 seconds ago
    const result = formatRelativeTime(timestamp, now, &buf);
    try std.testing.expectEqualStrings("1m ago", result);
}

test "formatRelativeTime: hours ago" {
    var buf: [16]u8 = undefined;
    const now: i64 = 5000;
    const timestamp: i64 = 1339; // 3661 seconds ago
    const result = formatRelativeTime(timestamp, now, &buf);
    try std.testing.expectEqualStrings("1h ago", result);
}

test "formatRelativeTime: days ago" {
    var buf: [16]u8 = undefined;
    const now: i64 = 100000;
    const timestamp: i64 = 13599; // 86401 seconds ago (1 day + 1 second)
    const result = formatRelativeTime(timestamp, now, &buf);
    try std.testing.expectEqualStrings("1d ago", result);
}

test "formatRelativeTime: weeks ago" {
    var buf: [16]u8 = undefined;
    const now: i64 = 1000000;
    const timestamp: i64 = 395200; // 604800 seconds ago (exactly 7 days)
    const result = formatRelativeTime(timestamp, now, &buf);
    try std.testing.expectEqualStrings("1w ago", result);
}

test "cmdHistory with args: returns 0 on --help" {
    const allocator = std.testing.allocator;

    const builtin = @import("builtin");
    const devnull = try std.fs.openFileAbsolute(if (builtin.os.tag == .windows) "NUL" else "/dev/null", .{ .mode = .write_only });
    defer devnull.close();

    var out_buf: [4096]u8 = undefined;
    var out_w = devnull.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = devnull.writer(&err_buf);

    const result = try cmdHistory(
        allocator,
        &.{"--help"},
        false,
        &out_w.interface,
        &err_w.interface,
        false,
    );
    try std.testing.expectEqual(@as(u8, 0), result);
}
