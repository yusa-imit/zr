const std = @import("std");
const DAG = @import("dag.zig").DAG;

/// Cycle detection result
pub const CycleDetectionResult = struct {
    has_cycle: bool,
    cycle_path: ?std.ArrayList([]const u8),

    pub fn deinit(self: *CycleDetectionResult, allocator: std.mem.Allocator) void {
        if (self.cycle_path) |*path| {
            for (path.items) |node| {
                allocator.free(node);
            }
            path.deinit(allocator);
        }
    }
};

/// Detect cycles in a DAG using Kahn's Algorithm
/// Returns a result indicating whether a cycle exists and the path if found
pub fn detectCycle(allocator: std.mem.Allocator, dag: *const DAG) !CycleDetectionResult {
    // Kahn's Algorithm for topological sort - if we can't sort all nodes, there's a cycle

    // Calculate in-degrees: each node's in-degree = number of its dependencies
    // Nodes with in-degree 0 have no dependencies (entry points)
    var in_degree = std.StringHashMap(usize).init(allocator);
    defer in_degree.deinit();

    var it = dag.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.value_ptr;
        try in_degree.put(entry.key_ptr.*, node.dependencies.items.len);
    }

    // Queue for nodes with in-degree 0 (no dependencies)
    var queue = std.ArrayList([]const u8){};
    defer queue.deinit(allocator);

    var degree_it = in_degree.iterator();
    while (degree_it.next()) |entry| {
        if (entry.value_ptr.* == 0) {
            try queue.append(allocator, entry.key_ptr.*);
        }
    }

    // Process nodes: when a node is processed, decrement all nodes that depend on it
    var processed_count: usize = 0;
    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        processed_count += 1;

        // Find all nodes that depend on `current` and reduce their in-degree
        it = dag.nodes.iterator();
        while (it.next()) |entry| {
            const node = entry.value_ptr;
            for (node.dependencies.items) |dep| {
                if (std.mem.eql(u8, dep, current)) {
                    const degree = in_degree.getPtr(entry.key_ptr.*) orelse continue;
                    degree.* -= 1;
                    if (degree.* == 0) {
                        try queue.append(allocator, entry.key_ptr.*);
                    }
                    break;
                }
            }
        }
    }

    // If we processed all nodes, there's no cycle
    if (processed_count == dag.nodes.count()) {
        return CycleDetectionResult{
            .has_cycle = false,
            .cycle_path = null,
        };
    }

    // There's a cycle - find nodes involved (those still with in-degree > 0)
    var cycle_nodes = std.ArrayList([]const u8){};
    errdefer cycle_nodes.deinit(allocator);

    degree_it = in_degree.iterator();
    while (degree_it.next()) |entry| {
        if (entry.value_ptr.* > 0) {
            try cycle_nodes.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
        }
    }

    return CycleDetectionResult{
        .has_cycle = true,
        .cycle_path = cycle_nodes,
    };
}

/// Check if adding an edge would create a cycle
pub fn wouldCreateCycle(allocator: std.mem.Allocator, dag: *DAG, from: []const u8, to: []const u8) !bool {
    // Create a temporary copy of the DAG
    var temp_dag = DAG.init(allocator);
    defer temp_dag.deinit();

    // Copy all nodes and edges
    var it = dag.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.value_ptr;
        try temp_dag.addNode(node.name);

        for (node.dependencies.items) |dep| {
            try temp_dag.addEdge(node.name, dep);
        }
    }

    // Add the proposed edge
    try temp_dag.addEdge(from, to);

    // Check for cycle
    var result = try detectCycle(allocator, &temp_dag);
    defer result.deinit(allocator);

    return result.has_cycle;
}

test "cycle detection: no cycle" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("deploy", "lint");

    var result = try detectCycle(allocator, &dag);
    defer result.deinit(allocator);

    try std.testing.expect(!result.has_cycle);
    try std.testing.expect(result.cycle_path == null);
}

test "cycle detection: simple cycle" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("a", "b");
    try dag.addEdge("b", "c");
    try dag.addEdge("c", "a");

    var result = try detectCycle(allocator, &dag);
    defer result.deinit(allocator);

    try std.testing.expect(result.has_cycle);
    try std.testing.expect(result.cycle_path != null);
    try std.testing.expect(result.cycle_path.?.items.len == 3);
}

test "cycle detection: self-referencing cycle" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("build", "build");

    var result = try detectCycle(allocator, &dag);
    defer result.deinit(allocator);

    try std.testing.expect(result.has_cycle);
}

test "cycle detection: would create cycle" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("b", "a");
    try dag.addEdge("c", "b");

    // Adding this edge would create a cycle
    const would_cycle = try wouldCreateCycle(allocator, &dag, "a", "c");
    try std.testing.expect(would_cycle);

    // This edge would not create a cycle
    const would_not_cycle = try wouldCreateCycle(allocator, &dag, "d", "c");
    try std.testing.expect(!would_not_cycle);
}

test "cycle detection: complex graph without cycle" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("lint", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("deploy", "lint");
    try dag.addEdge("package", "deploy");

    var result = try detectCycle(allocator, &dag);
    defer result.deinit(allocator);

    try std.testing.expect(!result.has_cycle);
}
