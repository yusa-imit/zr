const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");

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
    w: *std.Io.Writer,
    config: *const types.Config,
    task_name: []const u8,
    idx: usize,
    use_color: bool,
) !void {
    const task = config.tasks.get(task_name).?;

    try w.print("\n  [{d}] ", .{idx});
    try color.printBold(w, use_color, "{s}", .{task_name});
    try w.print("\n      Command: {s}\n", .{task.cmd});

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
fn printDependencyTree(
    allocator: Allocator,
    w: *std.Io.Writer,
    config: *const types.Config,
    task_name: []const u8,
) !void {
    const task = config.tasks.get(task_name).?;

    try w.print("{s}\n", .{task_name});

    var all_deps = std.ArrayList([]const u8){};
    defer all_deps.deinit(allocator);

    for (task.deps) |dep| {
        try all_deps.append(allocator, dep);
    }
    for (task.deps_serial) |dep| {
        try all_deps.append(allocator, dep);
    }
    for (task.deps_if) |dep_if| {
        try all_deps.append(allocator, dep_if.task);
    }
    for (task.deps_optional) |dep| {
        try all_deps.append(allocator, dep);
    }

    for (all_deps.items, 0..) |dep, i| {
        const is_last = (i == all_deps.items.len - 1);
        if (is_last) {
            try w.print("└── {s}\n", .{dep});
        } else {
            try w.print("├── {s}\n", .{dep});
        }
    }
}

/// Print task execution plan in JSON format
fn printTaskJson(
    _: Allocator,
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
        try w.print("}}", .{});
    }

    try w.print("],", .{});
    try w.print("\"total\":{d}", .{ordered_tasks.len});
    try w.print("}}", .{});
}

pub fn cmdExplain(
    allocator: Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Parse arguments
    var format = ExplainOutputFormat.text;
    var task_name: ?[]const u8 = null;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try w.print("Usage: zr explain <task> [options]\n\n", .{});
            try w.print("Show execution plan for a task, including all dependencies in topological order.\n\n", .{});
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
            if (task_name == null) {
                task_name = arg;
            }
        }
    }

    // Require a task name
    if (task_name == null) {
        try color.printError(err_writer, use_color,
            "explain: A task name is required\n\n  Usage: zr explain <task> [--tree] [--json]\n",
            .{},
        );
        return 1;
    }

    // Load config
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const config_path = std.fs.cwd().realpath(common.CONFIG_FILE, &path_buf) catch {
        try color.printError(err_writer, use_color, "explain: No {s} found\n", .{common.CONFIG_FILE});
        return 1;
    };

    var config = loader.loadFromFile(allocator, config_path) catch |err| {
        try color.printError(err_writer, use_color, "explain: Failed to load config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer config.deinit();

    // Check that the task exists
    if (config.tasks.get(task_name.?) == null) {
        try color.printError(err_writer, use_color,
            "explain: Task '{s}' not found\n",
            .{task_name.?},
        );
        return 1;
    }

    // Collect all dependencies in topological order
    var visited = std.StringHashMap(bool).init(allocator);
    defer visited.deinit();

    var ordered_tasks = std.ArrayList([]const u8){};
    defer ordered_tasks.deinit(allocator);

    try collectTaskDeps(allocator, &config, task_name.?, &visited, &ordered_tasks);

    // Output based on format
    switch (format) {
        .text => {
            try w.print("Execution plan for: {s}\n", .{task_name.?});
            try w.print("Tasks to run ({d}):\n", .{ordered_tasks.items.len});

            for (ordered_tasks.items, 1..) |name, idx| {
                try printTaskText(w, &config, name, idx, use_color);
            }

            try w.print("\nEstimated total: {d} tasks\n", .{ordered_tasks.items.len});
        },
        .tree => {
            try printDependencyTree(allocator, w, &config, task_name.?);
        },
        .json => {
            try printTaskJson(allocator, w, &config, task_name.?, ordered_tasks.items);
        },
    }

    return 0;
}
