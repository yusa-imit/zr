// Integration test for zuda.compat.zr_dag drop-in replacement
//
// This test verifies that zuda's compatibility layer can replace zr's custom
// graph implementations (dag.zig, topo_sort.zig, cycle_detect.zig) without
// breaking existing functionality.

const std = @import("std");
const testing = std.testing;
const zuda = @import("zuda");

// Import zuda's compatibility layer
const zr_dag = zuda.compat.zr_dag;

test "zuda.compat.zr_dag - basic task dependency graph" {
    const allocator = testing.allocator;

    var dag = zr_dag.DAG.init(allocator);
    defer dag.deinit();

    // Build task dependency graph:
    //   build → test → deploy
    //   build → lint
    //   lint → deploy
    try dag.addNode("build");
    try dag.addNode("test");
    try dag.addNode("lint");
    try dag.addNode("deploy");

    try dag.addEdge("test", "build"); // test depends on build
    try dag.addEdge("deploy", "test"); // deploy depends on test
    try dag.addEdge("lint", "build"); // lint depends on build
    try dag.addEdge("deploy", "lint"); // deploy depends on lint

    // Verify node count
    try testing.expectEqual(@as(usize, 4), dag.nodeCount());

    // Verify no cycle exists
    const cycle = try dag.detectCycle();
    try testing.expect(cycle == null);

    // Get topological sort
    const sorted = try dag.topologicalSort();
    defer allocator.free(sorted);

    try testing.expectEqual(@as(usize, 4), sorted.len);

    // Verify ordering constraints:
    // - build must come before test and lint
    // - test and lint must come before deploy

    const build_idx = findIndex(sorted, "build");
    const test_idx = findIndex(sorted, "test");
    const lint_idx = findIndex(sorted, "lint");
    const deploy_idx = findIndex(sorted, "deploy");

    try testing.expect(build_idx < test_idx); // build before test
    try testing.expect(build_idx < lint_idx); // build before lint
    try testing.expect(test_idx < deploy_idx); // test before deploy
    try testing.expect(lint_idx < deploy_idx); // lint before deploy
}

test "zuda.compat.zr_dag - cycle detection" {
    const allocator = testing.allocator;

    var dag = zr_dag.DAG.init(allocator);
    defer dag.deinit();

    // Create cycle: A → B → C → A
    try dag.addNode("A");
    try dag.addNode("B");
    try dag.addNode("C");

    try dag.addEdge("A", "B"); // A depends on B
    try dag.addEdge("B", "C"); // B depends on C
    try dag.addEdge("C", "A"); // C depends on A (cycle!)

    // Cycle detection should find the cycle
    const cycle = try dag.detectCycle();
    try testing.expect(cycle != null);

    if (cycle) |c| {
        defer allocator.free(c);
        // Cycle should contain at least 2 vertices
        try testing.expect(c.len >= 2);
    }

    // Topological sort should fail
    const sorted_result = dag.topologicalSort();
    try testing.expectError(error.CycleDetected, sorted_result);
}

test "zuda.compat.zr_dag - entry nodes" {
    const allocator = testing.allocator;

    var dag = zr_dag.DAG.init(allocator);
    defer dag.deinit();

    // Create graph:
    //   build (entry)
    //   lint (entry)
    //   test (depends on build)
    //   deploy (depends on test and lint)

    try dag.addNode("build");
    try dag.addNode("lint");
    try dag.addNode("test");
    try dag.addNode("deploy");

    try dag.addEdge("test", "build");
    try dag.addEdge("deploy", "test");
    try dag.addEdge("deploy", "lint");

    // Get entry nodes (nodes with no dependencies = out-degree 0)
    var entry_nodes = try dag.getEntryNodes(allocator);
    defer {
        for (entry_nodes.items) |node| {
            allocator.free(node);
        }
        entry_nodes.deinit(allocator);
    }

    // Entry nodes should be build and lint (no dependencies)
    try testing.expectEqual(@as(usize, 2), entry_nodes.items.len);

    // Check if both build and lint are in entry_nodes
    const has_build = hasString(entry_nodes.items, "build");
    const has_lint = hasString(entry_nodes.items, "lint");

    try testing.expect(has_build);
    try testing.expect(has_lint);
}

test "zuda.compat.zr_dag - in-degree calculation" {
    const allocator = testing.allocator;

    var dag = zr_dag.DAG.init(allocator);
    defer dag.deinit();

    // Create graph:
    //   A → B → C
    //   A → C
    //
    // In-degrees:
    //   A: 0 (no incoming edges)
    //   B: 1 (A → B)
    //   C: 2 (B → C, A → C)

    try dag.addNode("A");
    try dag.addNode("B");
    try dag.addNode("C");

    try dag.addEdge("B", "A"); // B depends on A (A → B)
    try dag.addEdge("C", "B"); // C depends on B (B → C)
    try dag.addEdge("C", "A"); // C depends on A (A → C)

    try testing.expectEqual(@as(usize, 0), dag.getInDegree("A"));
    try testing.expectEqual(@as(usize, 1), dag.getInDegree("B"));
    try testing.expectEqual(@as(usize, 2), dag.getInDegree("C"));

    // Non-existent node returns 0
    try testing.expectEqual(@as(usize, 0), dag.getInDegree("NonExistent"));
}

test "zuda.compat.zr_dag - stress test with 1000 nodes" {
    const allocator = testing.allocator;

    var dag = zr_dag.DAG.init(allocator);
    defer dag.deinit();

    // Create linear chain: 0 → 1 → 2 → ... → 999
    var buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const id = try std.fmt.bufPrint(&buf, "task{d}", .{i});
        try dag.addNode(id);
    }

    i = 0;
    while (i < 999) : (i += 1) {
        const from = try std.fmt.bufPrint(&buf, "task{d}", .{i + 1});
        var to_buf: [32]u8 = undefined;
        const to = try std.fmt.bufPrint(&to_buf, "task{d}", .{i});
        try dag.addEdge(from, to); // from depends on to
    }

    // Verify node count
    try testing.expectEqual(@as(usize, 1000), dag.nodeCount());

    // No cycle should exist
    const cycle = try dag.detectCycle();
    try testing.expect(cycle == null);

    // Topological sort should succeed
    const sorted = try dag.topologicalSort();
    defer allocator.free(sorted);

    try testing.expectEqual(@as(usize, 1000), sorted.len);

    // Verify ordering (task0, task1, ..., task999)
    i = 0;
    while (i < 1000) : (i += 1) {
        const expected = try std.fmt.bufPrint(&buf, "task{d}", .{i});
        try testing.expectEqualStrings(expected, sorted[i]);
    }
}

// Helper functions

fn findIndex(slice: [][]const u8, target: []const u8) usize {
    for (slice, 0..) |item, idx| {
        if (std.mem.eql(u8, item, target)) {
            return idx;
        }
    }
    return slice.len; // not found
}

fn hasString(slice: [][]const u8, target: []const u8) bool {
    for (slice) |item| {
        if (std.mem.eql(u8, item, target)) {
            return true;
        }
    }
    return false;
}
