const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");
const history_store = @import("../history/store.zig");
const stats_mod = @import("../history/stats.zig");
const scheduler = @import("../exec/scheduler.zig");

const ExplainOutputFormat = enum {
    text,
    tree,
    json,
};

/// Collect all tasks that a given task depends on (recursively).
/// Returns a deduped list in topological order (dependencies before dependents).
fn collectTaskDeps(
    allocator: Allocator,
    config: *const types.Config,
    task_name: []const u8,
    visited: *std.StringHashMap(bool),
    order: *std.ArrayList([]const u8),
) !void {
    // If already visited, skip
    if (visited.get(task_name) != null) {
        return;
    }

    // Mark as visited
    try visited.put(task_name, true);

    // Get the task
    const task = config.tasks.get(task_name) orelse {
        return error.TaskNotFound;
    };

    // Recursively visit all dependencies
    for (task.deps) |dep| {
        try collectTaskDeps(allocator, config, dep, visited, order);
    }

    // Add this task to the order (after its dependencies)
    try order.append(allocator, task_name);
}

/// Print task details in text format (standard output)
fn printTaskText(
    allocator: Allocator,
    w: *std.Io.Writer,
    config: *const types.Config,
    task_name: []const u8,
    idx: usize,
    use_color: bool,
    est_ms: ?u64,
) !void {
    const task = config.tasks.get(task_name).?;

    try w.print("\n  [{d}] ", .{idx});
    try color.printBold(w, use_color, "{s}", .{task_name});
    if (est_ms) |ms| {
        if (ms >= 60_000) {
            try w.print(" (~{d}m estimated)", .{ms / 60_000});
        } else if (ms >= 1_000) {
            try w.print(" (~{d}s estimated)", .{ms / 1_000});
        } else {
            try w.print(" (~{d}ms estimated)", .{ms});
        }
    }
    try w.print("\n      Command: {s}\n", .{task.cmd});

    // Print working directory if set
    if (task.cwd) |cwd| {
        // Check if cwd was inherited from group config (v1.95.0)
        const cwd_from_group = blk: {
            if (std.mem.indexOf(u8, task_name, ".")) |dot| {
                const group_name = task_name[0..dot];
                if (config.group_configs.get(group_name)) |gc| {
                    if (gc.cwd) |gcwd| break :blk std.mem.eql(u8, gcwd, cwd);
                }
            }
            break :blk false;
        };
        if (cwd_from_group) {
            const dot = std.mem.indexOf(u8, task_name, ".").?;
            try w.print("      Dir: {s}  (inherited from group: {s})\n", .{ cwd, task_name[0..dot] });
        } else {
            try w.print("      Dir: {s}\n", .{cwd});
        }
    }

    // Print timeout if set
    if (task.timeout_ms) |ms| {
        // Check if timeout was inherited from group config (v1.95.0)
        const timeout_from_group = blk: {
            if (std.mem.indexOf(u8, task_name, ".")) |dot| {
                const group_name = task_name[0..dot];
                if (config.group_configs.get(group_name)) |gc| {
                    if (gc.timeout_ms) |gms| break :blk gms == ms;
                }
            }
            break :blk false;
        };
        if (timeout_from_group) {
            const dot = std.mem.indexOf(u8, task_name, ".").?;
            if (ms % 60_000 == 0) {
                try w.print("      Timeout: {d}m  (inherited from group: {s})\n", .{ ms / 60_000, task_name[0..dot] });
            } else if (ms % 1_000 == 0) {
                try w.print("      Timeout: {d}s  (inherited from group: {s})\n", .{ ms / 1_000, task_name[0..dot] });
            } else {
                try w.print("      Timeout: {d}ms  (inherited from group: {s})\n", .{ ms, task_name[0..dot] });
            }
        } else {
            if (ms % 60_000 == 0) {
                try w.print("      Timeout: {d}m\n", .{ms / 60_000});
            } else if (ms % 1_000 == 0) {
                try w.print("      Timeout: {d}s\n", .{ms / 1_000});
            } else {
                try w.print("      Timeout: {d}ms\n", .{ms});
            }
        }
    }

    // Print cache flag
    if (task.cache) {
        try w.print("      Cache: enabled\n", .{});
    }

    // Print share_output env var name (v1.87.0)
    if (task.share_output) {
        const sanitized = scheduler.sanitizeTaskNameForEnv(allocator, task_name) catch null;
        if (sanitized) |s| {
            defer allocator.free(s);
            try w.print("      Share output: ZR_OUTPUT_{s}\n", .{s});
        }
    }

    // Print skip_if condition
    if (task.skip_if) |cond| {
        try w.print("      Skip if: {s}\n", .{cond});
    }

    // Print env vars if set
    if (task.env.len > 0) {
        try w.print("      Env:\n", .{});
        for (task.env) |pair| {
            try w.print("        {s}={s}\n", .{ pair[0], pair[1] });
        }
    }

    // Print required_env if set
    if (task.required_env) |req| {
        if (req.len > 0) {
            try w.print("      Required env:", .{});
            for (req) |name| {
                try w.print(" {s}", .{name});
            }
            try w.print("\n", .{});
        }
    }

    // Print input_prompts if set (v1.88.0)
    if (task.input_prompts.len > 0) {
        try w.print("      Input prompts:\n", .{});
        for (task.input_prompts) |ip| {
            if (ip.default) |def| {
                // v1.89.0: Show [HIDDEN] for secret inputs
                const display_default = if (ip.secret) "[HIDDEN]" else def;
                try w.print("        {s}: {s} [default: {s}]\n", .{ ip.name, ip.prompt, display_default });
            } else {
                try w.print("        {s}: {s} (required)\n", .{ ip.name, ip.prompt });
            }
        }
    }

    // Print redact if set (v1.89.0)
    if (task.redact.len > 0) {
        try w.print("      Redact: [", .{});
        for (task.redact, 0..) |r, i| {
            if (i > 0) try w.print(", ", .{});
            try w.print("{s}", .{r});
        }
        try w.print("]\n", .{});
    }

    // Print confirm field if set (v1.90.0)
    if (task.confirm) |msg| {
        if (msg.len > 0) {
            try w.print("      Confirmation: {s}\n", .{msg});
        } else {
            try w.print("      Confirmation: true\n", .{});
        }
    } else if (task.confirm_if) |cif| {
        try w.print("      Confirmation: (if {s})\n", .{cif});
    }

    // Print sources if set
    if (task.sources.len > 0) {
        try w.print("      Sources:", .{});
        for (task.sources) |src| {
            try w.print(" {s}", .{src});
        }
        try w.print("\n", .{});
    }

    // Print dependencies
    try w.print("      Dependencies: ", .{});
    const total_deps = task.deps.len + task.deps_serial.len + task.deps_if.len + task.deps_optional.len;
    if (total_deps == 0) {
        try w.print("(none)\n", .{});
    } else {
        var dep_count: usize = 0;
        for (task.deps) |dep| {
            if (dep_count > 0) try w.print(", ", .{});
            try w.print("{s}", .{dep});
            dep_count += 1;
        }
        for (task.deps_serial) |dep| {
            if (dep_count > 0) try w.print(", ", .{});
            try w.print("{s}", .{dep});
            dep_count += 1;
        }
        for (task.deps_if) |dep_if| {
            if (dep_count > 0) try w.print(", ", .{});
            try w.print("{s}", .{dep_if.task});
            dep_count += 1;
        }
        for (task.deps_optional) |dep| {
            if (dep_count > 0) try w.print(", ", .{});
            try w.print("{s}", .{dep});
            dep_count += 1;
        }
        try w.print("\n", .{});
    }
}

/// Print tree visualization of dependencies
fn printDependencyTreeRecursive(
    allocator: Allocator,
    w: *std.Io.Writer,
    config: *const types.Config,
    task_name: []const u8,
    prefix: []const u8,
    is_root: bool,
    seen: *std.StringHashMap(void),
) !void {
    if (!is_root) {
        try w.print("{s}", .{task_name});
    } else {
        try w.print("{s}\n", .{task_name});
    }

    const already_seen = seen.get(task_name) != null;
    if (already_seen) {
        try w.print(" (already shown)\n", .{});
        return;
    }
    if (!is_root) try w.print("\n", .{});
    try seen.put(task_name, {});

    const task = config.tasks.get(task_name) orelse return;

    var all_deps = std.ArrayList([]const u8){};
    defer all_deps.deinit(allocator);

    for (task.deps) |dep| try all_deps.append(allocator, dep);
    for (task.deps_serial) |dep| try all_deps.append(allocator, dep);
    for (task.deps_if) |dep_if| try all_deps.append(allocator, dep_if.task);
    for (task.deps_optional) |dep| try all_deps.append(allocator, dep);

    for (all_deps.items, 0..) |dep, i| {
        const dep_is_last = (i == all_deps.items.len - 1);
        const connector = if (dep_is_last) "└── " else "├── ";
        const child_prefix = if (dep_is_last)
            try std.fmt.allocPrint(allocator, "{s}    ", .{prefix})
        else
            try std.fmt.allocPrint(allocator, "{s}│   ", .{prefix});
        defer allocator.free(child_prefix);

        try w.print("{s}{s}", .{ prefix, connector });
        try printDependencyTreeRecursive(allocator, w, config, dep, child_prefix, false, seen);
    }
}

/// Print tree visualization of dependencies (recursive, full DAG)
fn printDependencyTree(
    allocator: Allocator,
    w: *std.Io.Writer,
    config: *const types.Config,
    task_name: []const u8,
) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    try printDependencyTreeRecursive(allocator, w, config, task_name, "", true, &seen);
}

/// Print task execution plan in JSON format
fn printTaskJson(
    allocator: Allocator,
    w: *std.Io.Writer,
    config: *const types.Config,
    _: []const u8,
    ordered_tasks: []const []const u8,
) !void {
    try w.print("{{", .{});
    try w.print("\"tasks\":[", .{});

    for (ordered_tasks, 0..) |name, i| {
        if (i > 0) try w.print(",", .{});

        const task = config.tasks.get(name).?;
        try w.print("{{", .{});
        try w.print("\"name\":\"{s}\",", .{name});
        try w.print("\"cmd\":\"{s}\",", .{task.cmd});
        try w.print("\"deps\":[", .{});

        for (task.deps, 0..) |dep, j| {
            if (j > 0) try w.print(",", .{});
            try w.print("\"{s}\"", .{dep});
        }

        try w.print("]", .{});

        // Include share_output env var name if applicable (v1.87.0)
        if (task.share_output) {
            const sanitized = scheduler.sanitizeTaskNameForEnv(allocator, name) catch null;
            if (sanitized) |s| {
                defer allocator.free(s);
                try w.print(",\"share_output_env_var\":\"ZR_OUTPUT_{s}\"", .{s});
            }
        }

        // Include input_prompts array (v1.88.0)
        if (task.input_prompts.len > 0) {
            try w.print(",\"input_prompts\":[", .{});
            for (task.input_prompts, 0..) |ip, pi| {
                if (pi > 0) try w.print(",", .{});
                try w.print("{{\"name\":\"{s}\",\"prompt\":\"{s}\"", .{ ip.name, ip.prompt });
                if (ip.default) |def| {
                    // v1.89.0: Show [HIDDEN] for secret inputs
                    const display_default = if (ip.secret) "[HIDDEN]" else def;
                    try w.print(",\"default\":\"{s}\"", .{display_default});
                }
                if (!std.mem.eql(u8, ip.type, "string")) try w.print(",\"type\":\"{s}\"", .{ip.type});
                if (ip.choices.len > 0) {
                    try w.print(",\"choices\":[", .{});
                    for (ip.choices, 0..) |c, ci| {
                        if (ci > 0) try w.print(",", .{});
                        try w.print("\"{s}\"", .{c});
                    }
                    try w.print("]", .{});
                }
                try w.print("}}", .{});
            }
            try w.print("]", .{});
        }

        // Include redact array (v1.89.0)
        if (task.redact.len > 0) {
            try w.print(",\"redact\":[", .{});
            for (task.redact, 0..) |r, ri| {
                if (ri > 0) try w.print(",", .{});
                try w.print("\"{s}\"", .{r});
            }
            try w.print("]", .{});
        }

        // Include confirm field (v1.90.0)
        if (task.confirm) |msg| {
            if (msg.len > 0) {
                try w.print(",\"confirm\":\"{s}\"", .{msg});
            } else {
                try w.print(",\"confirm\":true", .{});
            }
        } else if (task.confirm_if) |cif| {
            try w.print(",\"confirm_if\":\"{s}\"", .{cif});
        }

        try w.print("}}", .{});
    }

    try w.print("],", .{});
    try w.print("\"total\":{d}", .{ordered_tasks.len});
    try w.print("}}", .{});
}

pub fn cmdExplain(
    allocator: Allocator,
    args: []const []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Parse arguments
    var format = ExplainOutputFormat.text;
    var task_names = std.ArrayList([]const u8){};
    defer task_names.deinit(allocator);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try w.print("Usage: zr explain <task> [<task>...] [options]\n\n", .{});
            try w.print("Show execution plan for one or more tasks, including all dependencies in topological order.\n\n", .{});
            try w.print("Options:\n", .{});
            try w.print("  --tree              Display dependencies as a tree\n", .{});
            try w.print("  --json              Output in JSON format\n", .{});
            try w.print("  --help              Show this help message\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--tree")) {
            format = .tree;
        } else if (std.mem.eql(u8, arg, "--json")) {
            format = .json;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            try task_names.append(allocator, arg);
        }
    }

    // Require at least one task name
    if (task_names.items.len == 0) {
        try color.printError(err_writer, use_color,
            "explain: A task name is required\n\n  Usage: zr explain <task> [--tree] [--json]\n",
            .{},
        );
        return 1;
    }

    // Load config
    var config = loader.loadFromFile(allocator, config_path) catch |err| {
        try color.printError(err_writer, use_color, "✗ [explain]: Failed to load config: {s}\n\n  Hint: Ensure a valid zr.toml exists or use --config <path>\n", .{@errorName(err)});
        return 1;
    };
    defer config.deinit();

    // Validate all task names exist
    for (task_names.items) |task_name| {
        if (config.tasks.get(task_name) == null) {
            try color.printError(err_writer, use_color,
                "explain: Task '{s}' not found\n",
                .{task_name},
            );
            return 1;
        }
    }

    // Collect all dependencies in topological order for all tasks
    // Use a shared visited map to deduplicate across all named tasks
    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();

    var ordered_tasks = std.ArrayList([]const u8){};
    defer ordered_tasks.deinit(allocator);

    for (task_names.items) |task_name| {
        try collectTaskDeps(allocator, &config, task_name, &visited, &ordered_tasks);
    }

    // Load history for duration estimates (best-effort; ignore errors)
    var history_records: ?std.ArrayList(history_store.Record) = null;
    defer if (history_records) |*recs| {
        for (recs.items) |r| r.deinit(allocator);
        recs.deinit(allocator);
    };
    if (history_store.defaultHistoryPath(allocator)) |hist_path| {
        defer allocator.free(hist_path);
        if (history_store.Store.init(allocator, hist_path)) |store| {
            defer store.deinit();
            if (store.loadLast(allocator, 1000)) |recs| {
                history_records = recs;
            } else |_| {}
        } else |_| {}
    } else |_| {}

    // Output based on format
    switch (format) {
        .text => {
            if (task_names.items.len == 1) {
                try w.print("Execution plan for: {s}\n", .{task_names.items[0]});
            } else {
                try w.print("Execution plan for {d} tasks:\n", .{task_names.items.len});
            }
            try w.print("Tasks to run ({d}):\n", .{ordered_tasks.items.len});

            var total_est_ms: u64 = 0;
            var all_have_history = true;

            for (ordered_tasks.items, 1..) |name, idx| {
                var est_ms: ?u64 = null;
                if (history_records) |recs| {
                    if (stats_mod.calculateStats(recs.items, name, allocator)) |maybe_stats| {
                        if (maybe_stats) |task_stats| {
                            est_ms = task_stats.avg_ms;
                            total_est_ms += task_stats.avg_ms;
                        } else {
                            all_have_history = false;
                        }
                    } else |_| {
                        all_have_history = false;
                    }
                } else {
                    all_have_history = false;
                }
                try printTaskText(allocator, w, &config, name, idx, use_color, est_ms);
            }

            if (all_have_history and history_records != null and ordered_tasks.items.len > 0) {
                if (total_est_ms >= 60_000) {
                    try w.print("\nEstimated total: {d} tasks (~{d}m)\n", .{ ordered_tasks.items.len, total_est_ms / 60_000 });
                } else if (total_est_ms >= 1_000) {
                    try w.print("\nEstimated total: {d} tasks (~{d}s)\n", .{ ordered_tasks.items.len, total_est_ms / 1_000 });
                } else if (total_est_ms > 0) {
                    try w.print("\nEstimated total: {d} tasks (~{d}ms)\n", .{ ordered_tasks.items.len, total_est_ms });
                } else {
                    try w.print("\nEstimated total: {d} tasks\n", .{ordered_tasks.items.len});
                }
            } else {
                try w.print("\nEstimated total: {d} tasks\n", .{ordered_tasks.items.len});
            }
        },
        .tree => {
            // For tree format with multiple tasks, print each task's tree
            for (task_names.items) |task_name| {
                if (task_names.items.len > 1) {
                    try w.print("\nDependency tree for: {s}\n", .{task_name});
                }
                try printDependencyTree(allocator, w, &config, task_name);
            }
        },
        .json => {
            try printTaskJson(allocator, w, &config, "", ordered_tasks.items);
        },
    }

    return 0;
}

const parser = @import("../config/parser.zig");

// Note: printTaskText, printDependencyTree, printTaskJson use *std.Io.Writer
// which requires a live file handle — covered by integration tests (15000-15008).

test "collectTaskDeps single task with no deps returns only that task" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.build]
        \\cmd = "zig build"
    );
    defer config.deinit();

    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();

    var order = std.ArrayList([]const u8){};
    defer order.deinit(allocator);

    try collectTaskDeps(allocator, &config, "build", &visited, &order);

    try std.testing.expectEqual(@as(usize, 1), order.items.len);
    try std.testing.expectEqualStrings("build", order.items[0]);
}

test "collectTaskDeps with linear chain returns tasks in dependency-first order" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.a]
        \\cmd = "echo a"
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\[tasks.c]
        \\cmd = "echo c"
        \\deps = ["b"]
    );
    defer config.deinit();

    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();

    var order = std.ArrayList([]const u8){};
    defer order.deinit(allocator);

    try collectTaskDeps(allocator, &config, "c", &visited, &order);

    // a must come before b, b must come before c
    try std.testing.expectEqual(@as(usize, 3), order.items.len);
    try std.testing.expectEqualStrings("a", order.items[0]);
    try std.testing.expectEqualStrings("b", order.items[1]);
    try std.testing.expectEqualStrings("c", order.items[2]);
}

test "collectTaskDeps deduplicates shared dependencies" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\[tasks.left]
        \\cmd = "echo left"
        \\deps = ["setup"]
        \\[tasks.right]
        \\cmd = "echo right"
        \\deps = ["setup"]
        \\[tasks.merge]
        \\cmd = "echo merge"
        \\deps = ["left", "right"]
    );
    defer config.deinit();

    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();

    var order = std.ArrayList([]const u8){};
    defer order.deinit(allocator);

    try collectTaskDeps(allocator, &config, "merge", &visited, &order);

    // setup should appear exactly once even though both left and right depend on it
    var setup_count: usize = 0;
    for (order.items) |name| {
        if (std.mem.eql(u8, name, "setup")) setup_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), setup_count);
    try std.testing.expectEqual(@as(usize, 4), order.items.len);
}

test "collectTaskDeps with self-cycle does not infinite-loop" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.loop]
        \\cmd = "echo loop"
        \\deps = ["loop"]
    );
    defer config.deinit();

    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();

    var order = std.ArrayList([]const u8){};
    defer order.deinit(allocator);

    // Should not stack-overflow; visited map prevents re-entering "loop"
    try collectTaskDeps(allocator, &config, "loop", &visited, &order);
    try std.testing.expectEqual(@as(usize, 1), order.items.len);
}

test "collectTaskDeps nonexistent task returns error" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.build]
        \\cmd = "zig build"
    );
    defer config.deinit();

    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();

    var order = std.ArrayList([]const u8){};
    defer order.deinit(allocator);

    const result = collectTaskDeps(allocator, &config, "nonexistent", &visited, &order);
    try std.testing.expectError(error.TaskNotFound, result);
}

test "Task with share_output=true field is correctly parsed" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.fetch-data]
        \\cmd = "echo data"
        \\share_output = true
    );
    defer config.deinit();

    const task = config.tasks.get("fetch-data").?;
    // Verify share_output field is correctly set
    try std.testing.expect(task.share_output == true);
}

test "Task with default (no share_output) has share_output=false" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.build]
        \\cmd = "echo building"
    );
    defer config.deinit();

    const task = config.tasks.get("build").?;
    // Verify share_output defaults to false when not specified
    try std.testing.expect(task.share_output == false);
}

test "Task with share_output=false is correctly parsed" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.compile]
        \\cmd = "zig build"
        \\share_output = false
    );
    defer config.deinit();

    const task = config.tasks.get("compile").?;
    // Verify explicit share_output=false is honored
    try std.testing.expect(task.share_output == false);
}

test "input_prompt shown in explain text output" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\input_prompt = [{name="ENV", prompt="Target environment:", default="staging"}]
    );
    defer config.deinit();

    const task = config.tasks.get("deploy").?;
    // Verify input_prompt field is correctly parsed
    try std.testing.expect(task.input_prompts.len > 0);
    const prompt = task.input_prompts[0];
    try std.testing.expectEqualStrings("ENV", prompt.name);
    try std.testing.expectEqualStrings("Target environment:", prompt.prompt);
}

test "input_prompt shown in explain JSON output" {
    const allocator = std.testing.allocator;
    var config = try parser.parseToml(allocator,
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\input_prompt = [{name="VERSION", prompt="Version tag:", default="v1.0.0"}]
    );
    defer config.deinit();

    const task = config.tasks.get("deploy").?;
    // Verify input_prompts array is populated
    try std.testing.expect(task.input_prompts.len == 1);
    try std.testing.expectEqualStrings("VERSION", task.input_prompts[0].name);
    try std.testing.expectEqualStrings("v1.0.0", task.input_prompts[0].default.?);
}
