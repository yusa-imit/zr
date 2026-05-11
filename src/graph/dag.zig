//! DAG (Directed Acyclic Graph) implementation using zuda
//!
//! This module provides zr's DAG interface using zuda's optimized graph implementation.
//!
//! **Migration**: zr v1.83.0+ uses zuda v2.0.4+ for core graph operations
//! **Benefits**: Uses battle-tested zuda graph algorithms, improved cache locality
//! **Compatibility**: Exposes necessary APIs for zr's graph algorithms (topo_sort, cycle_detect, ascii)

const std = @import("std");
const zuda = @import("zuda");

const ZudaGraph = zuda.containers.graphs.AdjacencyList([]const u8, void, StringContext, StringContext.hash, StringContext.eql);

const StringContext = struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
        return std.hash.Wyhash.hash(0, key);
    }
    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

/// Directed Acyclic Graph (DAG) for task dependencies
pub const DAG = struct {
    /// Internal zuda graph (exposed for compatibility with topo_sort, cycle_detect, ascii)
    graph: ZudaGraph,
    allocator: std.mem.Allocator,

    /// Node represents a task in the dependency graph
    /// This is a compatibility structure - actual nodes are managed by zuda internally
    pub const Node = struct {
        name: []const u8,
        dependencies: std.ArrayList([]const u8),

        pub fn init(allocator: std.mem.Allocator, name: []const u8) !Node {
            return Node{
                .name = try allocator.dupe(u8, name),
                .dependencies = std.ArrayList([]const u8){},
            };
        }

        pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            for (self.dependencies.items) |dep| {
                allocator.free(dep);
            }
            self.dependencies.deinit(allocator);
        }

        pub fn addDependency(self: *Node, allocator: std.mem.Allocator, dep: []const u8) !void {
            try self.dependencies.append(allocator, try allocator.dupe(u8, dep));
        }
    };

    /// Pseudo-HashMap for compatibility with code that iterates dag.nodes
    pub const NodesMap = struct {
        dag: *const DAG,

        pub const Iterator = struct {
            vertex_it: @TypeOf(@as(ZudaGraph, undefined).vertexIterator()),
            dag: *const DAG,

            pub const Entry = struct {
                key_ptr: []const u8,
                value_ptr: Node,
            };

            pub fn next(self: *Iterator) ?Entry {
                const vertex = self.vertex_it.next() orelse return null;

                // Get dependencies for this vertex (outgoing edges)
                var deps = std.ArrayList([]const u8){};
                if (self.dag.graph.getNeighbors(vertex)) |neighbors| {
                    for (neighbors) |edge| {
                        deps.append(self.dag.allocator, edge.target) catch continue;
                    }
                }

                return Entry{
                    .key_ptr = vertex,
                    .value_ptr = Node{
                        .name = vertex,
                        .dependencies = deps,
                    },
                };
            }
        };

        pub fn iterator(self: NodesMap) Iterator {
            return .{
                .vertex_it = self.dag.graph.vertexIterator(),
                .dag = self.dag,
            };
        }

        pub fn getPtr(self: NodesMap, name: []const u8) ?*Node {
            _ = self;
            _ = name;
            // Not supported - nodes are managed internally by zuda
            return null;
        }

        pub fn contains(self: NodesMap, name: []const u8) bool {
            return self.dag.graph.containsVertex(name);
        }

        pub fn count(self: NodesMap) usize {
            return self.dag.graph.vertexCount();
        }
    };

    /// Expose nodes as a pseudo-map for compatibility
    pub fn nodes(self: *const DAG) NodesMap {
        return .{ .dag = self };
    }

    pub fn init(allocator: std.mem.Allocator) DAG {
        return .{
            .graph = ZudaGraph.init(allocator, .{}, true), // directed=true
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DAG) void {
        self.graph.deinit();
    }

    /// Add a node to the graph
    pub fn addNode(self: *DAG, name: []const u8) std.mem.Allocator.Error!void {
        // Check if already exists
        if (self.graph.containsVertex(name)) {
            return; // Already exists, nothing to do
        }

        // Duplicate the string to match zr's ownership semantics
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        self.graph.addVertex(owned_name) catch |err| switch (err) {
            error.VertexExists => {
                self.allocator.free(owned_name);
                return;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// Add an edge from 'from' node to 'to' node (from depends on to)
    pub fn addEdge(self: *DAG, from: []const u8, to: []const u8) std.mem.Allocator.Error!void {
        try self.addNode(from);
        try self.addNode(to);

        // Check if edge already exists
        if (self.graph.containsEdge(from, to)) {
            return; // Already exists, nothing to do
        }

        self.graph.addEdge(from, to, {}) catch |err| switch (err) {
            error.VertexExists => return,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// Get a node by name
    /// Returns an allocated Node that must be freed by the caller via node.deinit(allocator) + allocator.destroy(node)
    /// Returns null if the node doesn't exist
    pub fn getNode(self: *DAG, name: []const u8) ?*Node {
        if (!self.graph.containsVertex(name)) {
            return null;
        }

        const node = self.allocator.create(Node) catch return null;
        errdefer self.allocator.destroy(node);

        node.* = Node{
            .name = self.allocator.dupe(u8, name) catch {
                self.allocator.destroy(node);
                return null;
            },
            .dependencies = std.ArrayList([]const u8){},
        };
        errdefer {
            self.allocator.free(node.name);
            self.allocator.destroy(node);
        }

        // Get outgoing edges (dependencies)
        if (self.graph.getNeighbors(name)) |neighbors| {
            for (neighbors) |edge| {
                node.dependencies.append(
                    self.allocator,
                    self.allocator.dupe(u8, edge.target) catch continue,
                ) catch continue;
            }
        }

        return node;
    }

    /// Get the in-degree of a node (number of nodes that depend on it)
    pub fn getInDegree(self: *DAG, name: []const u8) usize {
        if (!self.graph.containsVertex(name)) {
            return 0;
        }
        return self.graph.inDegree(name);
    }

    /// Get all nodes with no dependencies (entry points)
    pub fn getEntryNodes(self: *DAG, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8){};
        errdefer result.deinit(allocator);

        var vertex_it = self.graph.vertexIterator();
        while (vertex_it.next()) |vertex| {
            // Entry nodes have out-degree 0 (no outgoing edges = no dependencies)
            const out_deg = self.graph.outDegree(vertex);
            if (out_deg == 0) {
                try result.append(allocator, try allocator.dupe(u8, vertex));
            }
        }

        return result;
    }

    /// Check if the graph is empty
    pub fn isEmpty(self: *DAG) bool {
        return self.graph.vertexCount() == 0;
    }

    /// Get the number of nodes
    pub fn nodeCount(self: *DAG) usize {
        return self.graph.vertexCount();
    }
};

// Tests migrated from original dag.zig

test "DAG: basic node operations" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addNode("build");
    try dag.addNode("test");
    try dag.addNode("lint");

    try std.testing.expect(dag.nodeCount() == 3);
    try std.testing.expect(!dag.isEmpty());
}

test "DAG: add edges" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("deploy", "lint");

    try std.testing.expect(dag.nodeCount() == 4); // test, build, deploy, lint
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
        entry_nodes.deinit(allocator);
    }

    try std.testing.expect(entry_nodes.items.len == 2); // build and lint
}

test "DAG: in-degree calculation" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("package", "test");

    try std.testing.expect(dag.getInDegree("build") == 1); // test depends on build
    try std.testing.expect(dag.getInDegree("test") == 2); // deploy and package depend on test
    try std.testing.expect(dag.getInDegree("deploy") == 0); // nothing depends on deploy
}

test "DAG: deinit cleans up memory" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    try dag.addNode("task1");
    try dag.addNode("task2");
    try dag.addEdge("task1", "task2");

    // Verify graph was created
    try std.testing.expect(dag.nodeCount() == 2);

    // Clean up - should not leak
    dag.deinit();
}

test "DAG: isEmpty" {
    const allocator = std.testing.allocator;

    var dag = DAG.init(allocator);
    defer dag.deinit();

    try std.testing.expect(dag.isEmpty());

    try dag.addNode("task1");
    try std.testing.expect(!dag.isEmpty());
}
