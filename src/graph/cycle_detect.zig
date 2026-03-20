//! Cycle detection utilities for zr.
//!
//! **Migration Notice**: Core cycle detection now uses zuda's algorithm.
//! This module provides zr-specific result format (CycleDetectionResult).
//!
//! **Original**: 205 LOC custom implementation
//! **Now**: ~60 LOC wrapper using zuda cycle detection

const std = @import("std");
const DAG = @import("dag.zig").DAG;

/// Cycle detection result (zr-specific format).
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

/// Detect cycles in a DAG.
///
/// Returns a result indicating whether a cycle exists and the path if found.
///
/// **Example**:
/// ```zig
/// var result = try detectCycle(allocator, &dag);
/// defer result.deinit(allocator);
/// if (result.has_cycle) {
///     std.debug.print("Cycle: ", .{});
///     for (result.cycle_path.?.items) |node| {
///         std.debug.print("{s} -> ", .{node});
///     }
/// }
/// ```
///
/// Time: O(V + E) | Space: O(V)
pub fn detectCycle(allocator: std.mem.Allocator, dag: *const DAG) !CycleDetectionResult {
    // Use zuda's detectCycle method
    const cycle_opt = try dag.detectCycle();

    if (cycle_opt) |cycle_slice| {
        // Convert slice to ArrayList for compatibility with zr's API
        var cycle_list = std.ArrayList([]const u8){};
        errdefer {
            for (cycle_list.items) |node| {
                allocator.free(node);
            }
            cycle_list.deinit(allocator);
        }

        for (cycle_slice) |node| {
            try cycle_list.append(allocator, try allocator.dupe(u8, node));
        }

        // Free the slice returned by zuda
        allocator.free(cycle_slice);

        return CycleDetectionResult{
            .has_cycle = true,
            .cycle_path = cycle_list,
        };
    } else {
        return CycleDetectionResult{
            .has_cycle = false,
            .cycle_path = null,
        };
    }
}
