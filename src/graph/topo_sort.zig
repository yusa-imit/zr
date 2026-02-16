const std = @import("std");
const DAG = @import("dag.zig").DAG;
const cycle_detect = @import("cycle_detect.zig");

/// Result of topological sort
pub const TopoSortResult = struct {
    /// Sorted task names in execution order
    /// If there are multiple valid orders, this is one of them
    order: std.ArrayList([]const u8),

    /// Indicates if the sort was successful
    success: bool,

    /// Error message if sort failed (e.g., due to cycle)
    error_message: ?[]const u8,

    pub fn deinit(self: *TopoSortResult, allocator: std.mem.Allocator) void {
        for (self.order.items) |node| {
            allocator.free(node);
        }
        self.order.deinit();

        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Perform topological sort using Kahn's Algorithm
/// Returns the sorted order of tasks for execution
pub fn topoSort(allocator: std.mem.Allocator, dag: *const DAG) !TopoSortResult {
    // First, check for cycles
    var cycle_result = try cycle_detect.detectCycle(allocator, dag);
    defer cycle_result.deinit(allocator);

    if (cycle_result.has_cycle) {
        var error_msg = std.ArrayList(u8).init(allocator);
        defer error_msg.deinit();

        try error_msg.appendSlice("Cycle detected in dependency graph: ");

        if (cycle_result.cycle_path) |path| {
            for (path.items, 0..) |node, i| {
                if (i > 0) try error_msg.appendSlice(" -> ");
                try error_msg.appendSlice(node);
            }
        }

        return TopoSortResult{
            .order = std.ArrayList([]const u8).init(allocator),
            .success = false,
            .error_message = try allocator.dupe(u8, error_msg.items),
        };
    }

    // Calculate in-degrees
    var in_degree = std.StringHashMap(usize).init(allocator);
    defer in_degree.deinit();

    var it = dag.nodes.iterator();
    while (it.next()) |entry| {
        try in_degree.put(entry.key_ptr.*, 0);
    }

    // Count incoming edges
    it = dag.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.value_ptr;
        for (node.dependencies.items) |dep| {
            const current = in_degree.get(dep) orelse 0;
            try in_degree.put(dep, current + 1);
        }
    }

    // Queue for nodes with in-degree 0
    var queue = std.ArrayList([]const u8).init(allocator);
    defer queue.deinit();

    var degree_it = in_degree.iterator();
    while (degree_it.next()) |entry| {
        if (entry.value_ptr.* == 0) {
            try queue.append(entry.key_ptr.*);
        }
    }

    // Result list
    var result = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (result.items) |node| {
            allocator.free(node);
        }
        result.deinit();
    }

    // Process nodes in topological order
    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        try result.append(try allocator.dupe(u8, current));

        const node = dag.nodes.get(current) orelse continue;

        // Reduce in-degree for all dependencies
        for (node.dependencies.items) |dep| {
            const degree = in_degree.getPtr(dep) orelse continue;
            degree.* -= 1;

            if (degree.* == 0) {
                try queue.append(dep);
            }
        }
    }

    return TopoSortResult{
        .order = result,
        .success = true,
        .error_message = null,
    };
}

/// Get execution levels - groups of tasks that can be executed in parallel
/// Level 0 = tasks with no dependencies
/// Level 1 = tasks that depend only on level 0 tasks, etc.
pub const ExecutionLevels = struct {
    levels: std.ArrayList(std.ArrayList([]const u8)),

    pub fn deinit(self: *ExecutionLevels, allocator: std.mem.Allocator) void {
        for (self.levels.items) |*level| {
            for (level.items) |node| {
                allocator.free(node);
            }
            level.deinit();
        }
        self.levels.deinit();
    }
};

/// Get execution levels for parallel execution planning
pub fn getExecutionLevels(allocator: std.mem.Allocator, dag: *const DAG) !ExecutionLevels {
    var levels = std.ArrayList(std.ArrayList([]const u8)).init(allocator);
    errdefer {
        for (levels.items) |*level| {
            for (level.items) |node| {
                allocator.free(node);
            }
            level.deinit();
        }
        levels.deinit();
    }

    // Track which nodes have been processed
    var processed = std.StringHashMap(bool).init(allocator);
    defer processed.deinit();

    var it = dag.nodes.iterator();
    while (it.next()) |entry| {
        try processed.put(entry.key_ptr.*, false);
    }

    // Process levels until all nodes are processed
    while (true) {
        var current_level = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (current_level.items) |node| {
                allocator.free(node);
            }
            current_level.deinit();
        }

        // Find nodes whose dependencies are all processed
        it = dag.nodes.iterator();
        while (it.next()) |entry| {
            const node_name = entry.key_ptr.*;
            const node = entry.value_ptr;

            if (processed.get(node_name).?) {
                continue;
            }

            var all_deps_processed = true;
            for (node.dependencies.items) |dep| {
                if (!processed.get(dep).?) {
                    all_deps_processed = false;
                    break;
                }
            }

            if (all_deps_processed) {
                try current_level.append(try allocator.dupe(u8, node_name));
            }
        }

        if (current_level.items.len == 0) {
            current_level.deinit();
            break;
        }

        // Mark current level as processed
        for (current_level.items) |node_name| {
            try processed.put(node_name, true);
        }

        try levels.append(current_level);
    }

    return ExecutionLevels{ .levels = levels };
}

test "topo sort: simple linear chain" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("c", "b");
    try dag.addEdge("b", "a");

    var result = try topoSort(allocator, &dag);
    defer result.deinit(allocator);

    try std.testing.expect(result.success);
    try std.testing.expect(result.order.items.len == 3);

    // a should come before b, b should come before c
    var a_idx: usize = 0;
    var b_idx: usize = 0;
    var c_idx: usize = 0;

    for (result.order.items, 0..) |node, i| {
        if (std.mem.eql(u8, node, "a")) a_idx = i;
        if (std.mem.eql(u8, node, "b")) b_idx = i;
        if (std.mem.eql(u8, node, "c")) c_idx = i;
    }

    try std.testing.expect(a_idx < b_idx);
    try std.testing.expect(b_idx < c_idx);
}

test "topo sort: parallel branches" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("deploy", "build-frontend");
    try dag.addEdge("deploy", "build-backend");
    try dag.addEdge("build-frontend", "install");
    try dag.addEdge("build-backend", "install");

    var result = try topoSort(allocator, &dag);
    defer result.deinit(allocator);

    try std.testing.expect(result.success);
    try std.testing.expect(result.order.items.len == 4);
}

test "topo sort: cycle detection" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("a", "b");
    try dag.addEdge("b", "c");
    try dag.addEdge("c", "a");

    var result = try topoSort(allocator, &dag);
    defer result.deinit(allocator);

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_message != null);
}

test "execution levels: simple case" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("lint", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("deploy", "lint");

    var levels = try getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    try std.testing.expect(levels.levels.items.len == 3);
    // Level 0: build
    try std.testing.expect(levels.levels.items[0].items.len == 1);
    // Level 1: test, lint (can run in parallel)
    try std.testing.expect(levels.levels.items[1].items.len == 2);
    // Level 2: deploy
    try std.testing.expect(levels.levels.items[2].items.len == 1);
}

test "execution levels: no dependencies" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addNode("a");
    try dag.addNode("b");
    try dag.addNode("c");

    var levels = try getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    try std.testing.expect(levels.levels.items.len == 1);
    try std.testing.expect(levels.levels.items[0].items.len == 3);
}
