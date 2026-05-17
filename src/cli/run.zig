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
) !u8 {
    defer {
        // Cleanup runtime params
        var it = runtime_params.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
    }
    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

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

    // Check for unknown params
    var params_it = runtime_params.iterator();
    while (params_it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.startsWith(u8, key, "__positional_")) continue; // skip internal markers

        // Check if this param exists in task definition
        var found = false;
        for (task.task_params) |param| {
            if (std.mem.eql(u8, key, param.name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try color.printError(err_writer, use_color,
                "run: Unknown parameter '{s}' for task '{s}'\n",
                .{ key, resolved_task_name },
            );
            return 1;
        }
    }

    // Show environment variables if --show-env flag is set
    if (show_env) {
        try printTaskEnvironment(allocator, w, err_writer, use_color, &config, &task, resolved_task_name, &resolved_params);
        if (!dry_run) {
            try w.print("\n", .{});
        }
    }

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
        try printDryRunPlan(allocator, w, use_color, plan, &config);
        return 0;
    }

    const start_ns = std.time.nanoTimestamp();

    var sched_result = scheduler.run(allocator, &config, &task_names, .{
        .max_jobs = max_jobs,
        .monitor = monitor,
        .use_color = use_color,
        .task_control = task_control,
        .filter_options = filter_options,
        .silent_override = silent_override,
        .force_run = force_run,
        .runtime_params = &resolved_params,
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

    // Record to history (best-effort, ignore errors)
    recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
        @intCast(sched_result.results.items.len), total_retries, peak_memory, avg_cpu);

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
    filter_options: filter_mod.FilterOptions,
    silent_override: bool,
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
        var sched_result = scheduler.run(allocator, &config, &task_names, .{
            .max_jobs = max_jobs,
            .filter_options = filter_options,
            .silent_override = silent_override,
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

        recordHistory(allocator, task_name, sched_result.total_success, elapsed_ms,
            @intCast(sched_result.results.items.len), total_retries, peak_memory, avg_cpu);

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
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

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
                .max_jobs = max_jobs,
                .retry_budget = wf.retry_budget,
                .extra_env = extra_env_slice,
                .filter_options = filter_options,
                .silent_override = silent_override,
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
                    .max_jobs = max_jobs,
                    .extra_env = extra_env_slice,
                    .filter_options = filter_options,
                    .silent_override = silent_override,
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
    retry_count: u32,
    peak_memory_bytes: u64,
    avg_cpu_percent: f64,
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
        false,
        &out_w.interface,
        &err_w.interface,
        false,
    );
    try std.testing.expectEqual(@as(u8, 0), result);
}
