//! Topological sort utilities for zr.
//!
//! **Migration Notice**: Core topological sort now uses zuda's algorithm.
//! This module provides zr-specific helpers like getExecutionLevels().
//!
//! **Original**: 323 LOC custom implementation
//! **Now**: ~100 LOC wrapper using zuda topological_sort + execution level grouping

const std = @import("std");
const DAG = @import("dag.zig").DAG;

/// Result of execution level grouping.
/// Groups tasks into parallel execution levels (tasks in same level can run concurrently).
pub const ExecutionLevels = struct {
    levels: std.ArrayList(std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ExecutionLevels, allocator: std.mem.Allocator) void {
        for (self.levels.items) |*level| {
            for (level.items) |node| {
                allocator.free(node);
            }
            level.deinit(allocator);
        }
        self.levels.deinit(allocator);
    }
};

/// Group tasks into parallel execution levels.
///
/// Returns levels where all tasks in level N can execute in parallel,
/// and all tasks in level N+1 depend on at least one task in level ≤ N.
///
/// **Example**:
/// - Level 0: [build] (no dependencies)
/// - Level 1: [test, lint] (both depend on build, can run in parallel)
/// - Level 2: [deploy] (depends on test and lint)
///
/// Time: O(V + E) | Space: O(V)
pub fn getExecutionLevels(allocator: std.mem.Allocator, dag: *const DAG) !ExecutionLevels {
    var levels = std.ArrayList(std.ArrayList([]const u8)){};
    errdefer {
        for (levels.items) |*level| {
            for (level.items) |node| {
                allocator.free(node);
            }
            level.deinit(allocator);
        }
        levels.deinit(allocator);
    }

    // Track which nodes have been processed
    var processed = std.StringHashMap(bool).init(allocator);
    defer processed.deinit();

    // Initialize all nodes as unprocessed
    var vertex_it = dag.graph.vertexIterator();
    while (vertex_it.next()) |vertex| {
        try processed.put(vertex, false);
    }

    // Process levels until all nodes are processed
    while (true) {
        var current_level = std.ArrayList([]const u8){};
        errdefer {
            for (current_level.items) |node| {
                allocator.free(node);
            }
            current_level.deinit(allocator);
        }

        // Find nodes whose dependencies are all processed
        vertex_it = dag.graph.vertexIterator();
        while (vertex_it.next()) |vertex| {
            if (processed.get(vertex).?) {
                continue; // Already processed
            }

            // Check if all dependencies are processed
            var all_deps_processed = true;
            var neighbor_it = dag.graph.neighborIterator(vertex) catch continue;
            while (neighbor_it.next()) |neighbor| {
                if (!processed.get(neighbor).?) {
                    all_deps_processed = false;
                    break;
                }
            }

            if (all_deps_processed) {
                try current_level.append(allocator, try allocator.dupe(u8, vertex));
            }
        }

        if (current_level.items.len == 0) {
            // Check for cycle — if unprocessed nodes remain, it's a cycle
            var has_unprocessed = false;
            var proc_it = processed.iterator();
            while (proc_it.next()) |entry| {
                if (!entry.value_ptr.*) {
                    has_unprocessed = true;
                    break;
                }
            }
            current_level.deinit(allocator);
            if (has_unprocessed) {
                return error.CycleDetected;
            }
            break; // All nodes processed
        }

        // Mark current level as processed
        for (current_level.items) |node_name| {
            try processed.put(node_name, true);
        }

        try levels.append(allocator, current_level);
    }

    return ExecutionLevels{
        .levels = levels,
        .allocator = allocator,
    };
}
