const std = @import("std");
const platform = @import("platform.zig");

/// NUMA node information
pub const NumaNode = struct {
    id: u32,
    cpu_ids: []u32, // CPU IDs belonging to this NUMA node
    memory_mb: u64, // Total memory in MB (0 if unknown)

    pub fn deinit(self: NumaNode, allocator: std.mem.Allocator) void {
        allocator.free(self.cpu_ids);
    }
};

/// NUMA topology information
pub const NumaTopology = struct {
    nodes: []NumaNode,
    total_cpus: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *NumaTopology) void {
        for (self.nodes) |node| {
            node.deinit(self.allocator);
        }
        self.allocator.free(self.nodes);
    }

    /// Get the NUMA node ID for a given CPU ID.
    /// Returns null if the CPU is not found in any node.
    pub fn getCpuNode(self: *const NumaTopology, cpu_id: u32) ?u32 {
        for (self.nodes) |node| {
            for (node.cpu_ids) |id| {
                if (id == cpu_id) return node.id;
            }
        }
        return null;
    }

    /// Check if the system has multiple NUMA nodes.
    pub fn isNuma(self: *const NumaTopology) bool {
        return self.nodes.len > 1;
    }
};

/// Detect NUMA topology on the current system.
/// Returns a single-node topology on systems without NUMA or on detection failure.
pub fn detectTopology(allocator: std.mem.Allocator) !NumaTopology {
    const builtin = @import("builtin");
    const os_tag = builtin.os.tag;

    if (os_tag == .linux) {
        return detectLinux(allocator);
    } else if (os_tag == .windows) {
        return detectWindows(allocator);
    } else if (os_tag == .macos) {
        // macOS doesn't expose NUMA APIs (unified memory architecture)
        return detectFallback(allocator);
    } else {
        return detectFallback(allocator);
    }
}

/// Fallback: Create a single-node topology with all CPUs.
fn detectFallback(allocator: std.mem.Allocator) !NumaTopology {
    const cpu_count = try std.Thread.getCpuCount();
    const cpu_ids = try allocator.alloc(u32, cpu_count);
    for (cpu_ids, 0..) |*id, i| {
        id.* = @intCast(i);
    }

    const nodes = try allocator.alloc(NumaNode, 1);
    nodes[0] = .{
        .id = 0,
        .cpu_ids = cpu_ids,
        .memory_mb = 0, // Unknown
    };

    return NumaTopology{
        .nodes = nodes,
        .total_cpus = @intCast(cpu_count),
        .allocator = allocator,
    };
}

/// Detect NUMA topology on Linux by parsing /sys/devices/system/node/.
fn detectLinux(allocator: std.mem.Allocator) !NumaTopology {
    const node_dir = "/sys/devices/system/node";

    // Try to open the node directory
    var dir = std.fs.openDirAbsolute(node_dir, .{ .iterate = true }) catch {
        // NUMA not available or unsupported, fall back to single node
        return detectFallback(allocator);
    };
    defer dir.close();

    var nodes_list = std.ArrayList(NumaNode).init(allocator);
    errdefer {
        for (nodes_list.items) |node| node.deinit(allocator);
        nodes_list.deinit();
    }

    var total_cpus: u32 = 0;

    // Iterate over node directories (node0, node1, ...)
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "node")) continue;

        const node_id_str = entry.name[4..];
        const node_id = std.fmt.parseInt(u32, node_id_str, 10) catch continue;

        // Read cpulist file to get CPUs for this node
        var cpulist_path_buf: [256]u8 = undefined;
        const cpulist_path = std.fmt.bufPrint(&cpulist_path_buf, "{s}/{s}/cpulist", .{ node_dir, entry.name }) catch continue;

        const cpulist_content = dir.readFileAlloc(allocator, cpulist_path, 1024) catch continue;
        defer allocator.free(cpulist_content);

        // Parse cpulist (e.g., "0-3,8-11" means CPUs 0,1,2,3,8,9,10,11)
        const cpu_ids = try parseCpuList(allocator, std.mem.trim(u8, cpulist_content, "\n\r "));
        errdefer allocator.free(cpu_ids);

        total_cpus += @intCast(cpu_ids.len);

        try nodes_list.append(.{
            .id = node_id,
            .cpu_ids = cpu_ids,
            .memory_mb = 0, // TODO: Parse meminfo if needed
        });
    }

    if (nodes_list.items.len == 0) {
        // No NUMA nodes detected, fall back to single node
        return detectFallback(allocator);
    }

    return NumaTopology{
        .nodes = try nodes_list.toOwnedSlice(),
        .total_cpus = total_cpus,
        .allocator = allocator,
    };
}

/// Parse Linux cpulist format (e.g., "0-3,8-11" → [0,1,2,3,8,9,10,11]).
fn parseCpuList(allocator: std.mem.Allocator, cpulist: []const u8) ![]u32 {
    var result = std.ArrayList(u32).init(allocator);
    errdefer result.deinit();

    var ranges = std.mem.splitScalar(u8, cpulist, ',');
    while (ranges.next()) |range| {
        const trimmed = std.mem.trim(u8, range, " ");
        if (trimmed.len == 0) continue;

        if (std.mem.indexOfScalar(u8, trimmed, '-')) |dash_idx| {
            // Range format: "0-3"
            const start_str = trimmed[0..dash_idx];
            const end_str = trimmed[dash_idx + 1 ..];

            const start = try std.fmt.parseInt(u32, start_str, 10);
            const end = try std.fmt.parseInt(u32, end_str, 10);

            var i = start;
            while (i <= end) : (i += 1) {
                try result.append(i);
            }
        } else {
            // Single CPU: "8"
            const cpu_id = try std.fmt.parseInt(u32, trimmed, 10);
            try result.append(cpu_id);
        }
    }

    return result.toOwnedSlice();
}

/// Detect NUMA topology on Windows using GetLogicalProcessorInformationEx.
fn detectWindows(allocator: std.mem.Allocator) !NumaTopology {
    // Windows NUMA detection requires calling GetLogicalProcessorInformationEx with
    // RelationNumaNode to enumerate NUMA nodes and their processor masks.
    // This is complex to implement properly, so we'll fall back to single node for now.
    // TODO: Implement full Windows NUMA detection if needed.
    return detectFallback(allocator);
}

test "NumaTopology: getCpuNode" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 4);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;
    cpu_ids_0[2] = 2;
    cpu_ids_0[3] = 3;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 4);
    cpu_ids_1[0] = 4;
    cpu_ids_1[1] = 5;
    cpu_ids_1[2] = 6;
    cpu_ids_1[3] = 7;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 8192 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 8192 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 8,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(0));
    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(3));
    try testing.expectEqual(@as(?u32, 1), topology.getCpuNode(4));
    try testing.expectEqual(@as(?u32, 1), topology.getCpuNode(7));
    try testing.expectEqual(@as(?u32, null), topology.getCpuNode(99));
}

test "NumaTopology: isNuma" {
    const testing = std.testing;

    // Single node topology
    var cpu_ids_single = try testing.allocator.alloc(u32, 4);
    for (cpu_ids_single, 0..) |*id, i| {
        id.* = @intCast(i);
    }
    var nodes_single = try testing.allocator.alloc(NumaNode, 1);
    nodes_single[0] = .{ .id = 0, .cpu_ids = cpu_ids_single, .memory_mb = 0 };
    var topo_single = NumaTopology{
        .nodes = nodes_single,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topo_single.deinit();
    try testing.expect(!topo_single.isNuma());

    // Multi-node topology
    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;
    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;
    var nodes_multi = try testing.allocator.alloc(NumaNode, 2);
    nodes_multi[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes_multi[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 0 };
    var topo_multi = NumaTopology{
        .nodes = nodes_multi,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topo_multi.deinit();
    try testing.expect(topo_multi.isNuma());
}

test "parseCpuList: single range" {
    const testing = std.testing;
    const result = try parseCpuList(testing.allocator, "0-3");
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 4), result.len);
    try testing.expectEqual(@as(u32, 0), result[0]);
    try testing.expectEqual(@as(u32, 1), result[1]);
    try testing.expectEqual(@as(u32, 2), result[2]);
    try testing.expectEqual(@as(u32, 3), result[3]);
}

test "parseCpuList: multiple ranges" {
    const testing = std.testing;
    const result = try parseCpuList(testing.allocator, "0-1,4-5");
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 4), result.len);
    try testing.expectEqual(@as(u32, 0), result[0]);
    try testing.expectEqual(@as(u32, 1), result[1]);
    try testing.expectEqual(@as(u32, 4), result[2]);
    try testing.expectEqual(@as(u32, 5), result[3]);
}

test "parseCpuList: mixed ranges and singles" {
    const testing = std.testing;
    const result = try parseCpuList(testing.allocator, "0-1,3,5-6");
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 5), result.len);
    try testing.expectEqual(@as(u32, 0), result[0]);
    try testing.expectEqual(@as(u32, 1), result[1]);
    try testing.expectEqual(@as(u32, 3), result[2]);
    try testing.expectEqual(@as(u32, 5), result[3]);
    try testing.expectEqual(@as(u32, 6), result[4]);
}
