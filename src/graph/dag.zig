const std = @import("std");

/// Directed Acyclic Graph (DAG) for task dependencies
pub const DAG = struct {
    /// Node represents a task in the dependency graph
    pub const Node = struct {
        name: []const u8,
        dependencies: std.ArrayList([]const u8),

        pub fn init(allocator: std.mem.Allocator, name: []const u8) !Node {
            return Node{
                .name = try allocator.dupe(u8, name),
                .dependencies = std.ArrayList([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            for (self.dependencies.items) |dep| {
                allocator.free(dep);
            }
            self.dependencies.deinit();
        }

        pub fn addDependency(self: *Node, allocator: std.mem.Allocator, dep: []const u8) !void {
            try self.dependencies.append(try allocator.dupe(u8, dep));
        }
    };

    nodes: std.StringHashMap(Node),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DAG {
        return .{
            .nodes = std.StringHashMap(Node).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DAG) void {
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            var node = entry.value_ptr;
            node.deinit(self.allocator);
        }
        self.nodes.deinit();
    }

    /// Add a node to the graph
    pub fn addNode(self: *DAG, name: []const u8) !void {
        if (self.nodes.contains(name)) {
            return;
        }

        const node = try Node.init(self.allocator, name);
        try self.nodes.put(try self.allocator.dupe(u8, name), node);
    }

    /// Add an edge from 'from' node to 'to' node (from depends on to)
    pub fn addEdge(self: *DAG, from: []const u8, to: []const u8) !void {
        try self.addNode(from);
        try self.addNode(to);

        var node = self.nodes.getPtr(from) orelse return error.NodeNotFound;
        try node.addDependency(self.allocator, to);
    }

    /// Get a node by name
    pub fn getNode(self: *DAG, name: []const u8) ?*Node {
        return self.nodes.getPtr(name);
    }

    /// Get the in-degree of a node (number of nodes that depend on it)
    pub fn getInDegree(self: *DAG, name: []const u8) usize {
        var count: usize = 0;
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            const node = entry.value_ptr;
            for (node.dependencies.items) |dep| {
                if (std.mem.eql(u8, dep, name)) {
                    count += 1;
                }
            }
        }
        return count;
    }

    /// Get all nodes with no dependencies (entry points)
    pub fn getEntryNodes(self: *DAG, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(allocator);
        errdefer result.deinit();

        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            const node = entry.value_ptr;
            if (node.dependencies.items.len == 0) {
                try result.append(try allocator.dupe(u8, node.name));
            }
        }

        return result;
    }

    /// Check if the graph is empty
    pub fn isEmpty(self: *DAG) bool {
        return self.nodes.count() == 0;
    }

    /// Get the number of nodes
    pub fn nodeCount(self: *DAG) usize {
        return self.nodes.count();
    }
};

test "DAG: basic node operations" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addNode("build");
    try dag.addNode("test");
    try dag.addNode("lint");

    try std.testing.expect(dag.nodeCount() == 3);
    try std.testing.expect(dag.getNode("build") != null);
    try std.testing.expect(dag.getNode("test") != null);
    try std.testing.expect(dag.getNode("lint") != null);
    try std.testing.expect(dag.getNode("nonexistent") == null);
}

test "DAG: add edges" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("deploy", "lint");

    const test_node = dag.getNode("test").?;
    try std.testing.expect(test_node.dependencies.items.len == 1);
    try std.testing.expectEqualStrings("build", test_node.dependencies.items[0]);

    const deploy_node = dag.getNode("deploy").?;
    try std.testing.expect(deploy_node.dependencies.items.len == 2);
}

test "DAG: get entry nodes" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");
    try dag.addNode("lint");

    var entry_nodes = try dag.getEntryNodes(allocator);
    defer {
        for (entry_nodes.items) |node| {
            allocator.free(node);
        }
        entry_nodes.deinit();
    }

    try std.testing.expect(entry_nodes.items.len == 2);
}

test "DAG: in-degree calculation" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("package", "test");

    try std.testing.expect(dag.getInDegree("build") == 1);
    try std.testing.expect(dag.getInDegree("test") == 2);
    try std.testing.expect(dag.getInDegree("deploy") == 0);
}
