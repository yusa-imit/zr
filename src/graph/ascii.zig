/// ASCII visualization for task dependency graphs.
/// Renders task dependencies as a tree structure in the terminal.
const std = @import("std");
const DAG = @import("dag.zig").DAG;
const color_mod = @import("../output/color.zig");

/// Options for ASCII graph rendering
pub const RenderOptions = struct {
    /// Use color output
    use_color: bool = true,
    /// Show task descriptions if available
    show_descriptions: bool = false,
    /// Highlight specific tasks (e.g., affected tasks)
    highlighted: []const []const u8 = &.{},
};

/// Render a task dependency graph as ASCII art
pub fn renderGraph(
    allocator: std.mem.Allocator,
    writer: anytype,
    dag: *DAG,
    options: RenderOptions,
) !void {
    // Get entry nodes (tasks with no dependencies)
    var entry_nodes = try dag.getEntryNodes(allocator);
    defer {
        for (entry_nodes.items) |node| allocator.free(node);
        entry_nodes.deinit(allocator);
    }

    if (entry_nodes.items.len == 0) {
        try writer.writeAll("No tasks defined.\n");
        return;
    }

    // Track visited nodes to avoid duplicate rendering
    var visited = std.StringHashMap(void).init(allocator);
    defer {
        var it = visited.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        visited.deinit();
    }

    // Header
    if (options.use_color) {
        try writer.writeAll(color_mod.Code.bold);
        try writer.writeAll(color_mod.Code.bright_cyan);
    }
    try writer.writeAll("Task Dependency Graph\n");
    if (options.use_color) {
        try writer.writeAll(color_mod.Code.reset);
    }
    try writer.writeAll("\n");

    // Sort entry nodes for consistent output
    std.mem.sort([]const u8, entry_nodes.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Render each entry node and its subtree
    for (entry_nodes.items, 0..) |entry, idx| {
        const is_last = idx == entry_nodes.items.len - 1;
        try renderNode(allocator, writer, dag, entry, "", is_last, &visited, options);
    }

    try writer.writeAll("\n");

    // Legend
    if (options.highlighted.len > 0) {
        if (options.use_color) {
            try writer.writeAll(color_mod.Code.dim);
        }
        try writer.writeAll("Legend: ");
        if (options.use_color) {
            try writer.writeAll(color_mod.Code.yellow);
        }
        try writer.writeAll("★");
        if (options.use_color) {
            try writer.writeAll(color_mod.Code.reset);
            try writer.writeAll(color_mod.Code.dim);
        }
        try writer.writeAll(" = highlighted\n");
        if (options.use_color) {
            try writer.writeAll(color_mod.Code.reset);
        }
    }
}

/// Render a single node and its dependents recursively
fn renderNode(
    allocator: std.mem.Allocator,
    writer: anytype,
    dag: *DAG,
    task_name: []const u8,
    prefix: []const u8,
    is_last: bool,
    visited: *std.StringHashMap(void),
    options: RenderOptions,
) !void {
    // Check if task is highlighted
    const is_highlighted = blk: {
        for (options.highlighted) |hl| {
            if (std.mem.eql(u8, hl, task_name)) break :blk true;
        }
        break :blk false;
    };

    // Draw the branch connector
    try writer.writeAll(prefix);
    if (is_last) {
        try writer.writeAll("└── ");
    } else {
        try writer.writeAll("├── ");
    }

    // Draw the task name with highlighting
    if (is_highlighted and options.use_color) {
        try writer.writeAll(color_mod.Code.yellow);
        try writer.writeAll("★ ");
    }

    if (options.use_color) {
        try writer.writeAll(color_mod.Code.bright_green);
    }
    try writer.writeAll(task_name);
    if (options.use_color) {
        try writer.writeAll(color_mod.Code.reset);
    }

    // Mark if already visited (circular reference or shared dependency)
    const was_visited = visited.contains(task_name);
    if (was_visited) {
        if (options.use_color) {
            try writer.writeAll(color_mod.Code.dim);
        }
        try writer.writeAll(" (see above)");
        if (options.use_color) {
            try writer.writeAll(color_mod.Code.reset);
        }
        try writer.writeAll("\n");
        return;
    }

    try writer.writeAll("\n");

    // Mark as visited
    try visited.put(try allocator.dupe(u8, task_name), {});

    // Get dependents (tasks that depend on this task)
    var dependents = std.ArrayList([]const u8){};
    defer {
        for (dependents.items) |dep| allocator.free(dep);
        dependents.deinit(allocator);
    }

    var it = dag.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.value_ptr;
        for (node.dependencies.items) |dep| {
            if (std.mem.eql(u8, dep, task_name)) {
                try dependents.append(allocator, try allocator.dupe(u8, node.name));
                break;
            }
        }
    }

    // Sort dependents for consistent output
    std.mem.sort([]const u8, dependents.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Render dependents recursively
    for (dependents.items, 0..) |dependent, idx| {
        const is_last_child = idx == dependents.items.len - 1;
        const new_prefix = if (is_last)
            try std.fmt.allocPrint(allocator, "{s}    ", .{prefix})
        else
            try std.fmt.allocPrint(allocator, "{s}│   ", .{prefix});
        defer allocator.free(new_prefix);

        try renderNode(allocator, writer, dag, dependent, new_prefix, is_last_child, visited, options);
    }
}

// Tests
test "renderGraph - simple chain" {
    const allocator = std.testing.allocator;
    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addNode("build");
    try dag.addNode("test");
    try dag.addNode("deploy");
    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try renderGraph(allocator, buf.writer(allocator), &dag, .{ .use_color = false });

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "deploy") != null);
}

test "renderGraph - parallel tasks" {
    const allocator = std.testing.allocator;
    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addNode("build-frontend");
    try dag.addNode("build-backend");
    try dag.addNode("deploy");
    try dag.addEdge("deploy", "build-frontend");
    try dag.addEdge("deploy", "build-backend");

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try renderGraph(allocator, buf.writer(allocator), &dag, .{ .use_color = false });

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "build-frontend") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "build-backend") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "deploy") != null);
}

test "renderGraph - with highlighting" {
    const allocator = std.testing.allocator;
    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addNode("build");
    try dag.addNode("test");
    try dag.addEdge("test", "build");

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const highlighted = [_][]const u8{"build"};
    try renderGraph(allocator, buf.writer(allocator), &dag, .{
        .use_color = false,
        .highlighted = &highlighted,
    });

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "★") != null);
}

test "renderGraph - empty graph" {
    const allocator = std.testing.allocator;
    var dag = DAG.init(allocator);
    defer dag.deinit();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try renderGraph(allocator, buf.writer(allocator), &dag, .{ .use_color = false });

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "No tasks") != null);
}
