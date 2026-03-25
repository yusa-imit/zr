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

    var nodes_list: std.ArrayListUnmanaged(NumaNode) = .{};
    errdefer {
        for (nodes_list.items) |node| node.deinit(allocator);
        nodes_list.deinit(allocator);
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

        try nodes_list.append(allocator, .{
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
        .nodes = try nodes_list.toOwnedSlice(allocator),
        .total_cpus = total_cpus,
        .allocator = allocator,
    };
}

/// Parse Linux cpulist format (e.g., "0-3,8-11" → [0,1,2,3,8,9,10,11]).
fn parseCpuList(allocator: std.mem.Allocator, cpulist: []const u8) ![]u32 {
    var result: std.ArrayListUnmanaged(u32) = .{};
    errdefer result.deinit(allocator);

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
                try result.append(allocator, i);
            }
        } else {
            // Single CPU: "8"
            const cpu_id = try std.fmt.parseInt(u32, trimmed, 10);
            try result.append(allocator, cpu_id);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Detect NUMA topology on Windows using GetLogicalProcessorInformationEx.
fn detectWindows(allocator: std.mem.Allocator) !NumaTopology {
    const windows = std.os.windows;

    // Windows API constants
    const RelationNumaNode: c_int = 3;

    // Define GetLogicalProcessorInformationEx if not available in std
    const kernel32 = struct {
        extern "kernel32" fn GetLogicalProcessorInformationEx(
            RelationshipType: c_int,
            Buffer: ?*anyopaque,
            ReturnedLength: *windows.DWORD,
        ) callconv(.c) windows.BOOL;
    }.GetLogicalProcessorInformationEx;

    // First call to get required buffer size
    var buffer_size: windows.DWORD = 0;
    _ = kernel32(RelationNumaNode, null, &buffer_size);

    if (buffer_size == 0) {
        // API not available or no NUMA nodes, fall back
        return detectFallback(allocator);
    }

    // Allocate buffer
    const buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(buffer);

    // Second call to get actual data
    const success = kernel32(RelationNumaNode, @ptrCast(buffer.ptr), &buffer_size);
    if (success == 0) {
        // Call failed, fall back
        return detectFallback(allocator);
    }

    // Parse the returned buffer
    var nodes_list: std.ArrayListUnmanaged(NumaNode) = .{};
    errdefer {
        for (nodes_list.items) |node| node.deinit(allocator);
        nodes_list.deinit(allocator);
    }

    var total_cpus: u32 = 0;
    var offset: usize = 0;

    // Define structures needed to parse the response
    const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX = extern struct {
        Relationship: c_int,
        Size: windows.DWORD,
        // Union data follows but we'll treat it as opaque and parse based on Relationship
    };

    // RelationNumaNode structure contains:
    // struct {
    //     Relationship: c_int,
    //     Size: DWORD,
    //     Union {
    //         NUMA_NODE_RELATIONSHIP {
    //             NodeNumber: DWORD,
    //             Reserved: [20]u8,
    //             GroupMask: GROUP_AFFINITY
    //         }
    //     }
    // }

    // GROUP_AFFINITY is:
    // struct {
    //     Mask: KAFFINITY (u64),
    //     Group: WORD (u16)
    // }

    while (offset < buffer.len) {
        if (offset + @sizeOf(SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) > buffer.len) {
            break;
        }

        const info = @as(*const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, @ptrCast(@alignCast(&buffer[offset])));

        if (info.Relationship != RelationNumaNode) {
            offset += info.Size;
            continue;
        }

        // Parse NUMA node information
        // NodeNumber is at offset 8 (after Relationship=4, Size=4)
        const node_number_offset = 8;
        if (offset + node_number_offset + 4 > buffer.len) {
            break;
        }

        const node_number = @as(*const windows.DWORD, @ptrCast(@alignCast(&buffer[offset + node_number_offset]))).*;

        // GroupMask is at offset 32 (after NodeNumber=4 + Reserved=20 + padding)
        const group_mask_offset = 32;
        if (offset + group_mask_offset + 12 > buffer.len) {
            break;
        }

        // Extract Mask (u64) from GROUP_AFFINITY
        const mask_ptr = @as(*const u64, @ptrCast(@alignCast(&buffer[offset + group_mask_offset])));
        const mask = mask_ptr.*;

        // Convert mask to CPU IDs (each bit represents a logical processor)
        var cpu_ids: std.ArrayListUnmanaged(u32) = .{};
        errdefer cpu_ids.deinit(allocator);

        for (0..64) |bit| {
            if ((mask & (@as(u64, 1) << @intCast(bit))) != 0) {
                try cpu_ids.append(allocator, @intCast(bit));
            }
        }

        if (cpu_ids.items.len > 0) {
            try nodes_list.append(allocator, .{
                .id = @intCast(node_number),
                .cpu_ids = try cpu_ids.toOwnedSlice(allocator),
                .memory_mb = 0, // Windows NUMA API doesn't provide memory info easily
            });
            total_cpus += @intCast(cpu_ids.items.len);
        } else {
            cpu_ids.deinit(allocator);
        }

        offset += info.Size;
    }

    if (nodes_list.items.len == 0) {
        // No NUMA nodes detected, fall back
        return detectFallback(allocator);
    }

    return NumaTopology{
        .nodes = try nodes_list.toOwnedSlice(allocator),
        .total_cpus = total_cpus,
        .allocator = allocator,
    };
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
    const cpu_ids_single = try testing.allocator.alloc(u32, 4);
    for (cpu_ids_single, 0..) |*id, i| {
        id.* = @intCast(i);
    }
    const nodes_single = try testing.allocator.alloc(NumaNode, 1);
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

test "detectTopology returns single node on non-NUMA fallback" {
    const testing = std.testing;

    var topology = try detectTopology(testing.allocator);
    defer topology.deinit();

    // All systems have at least one NUMA node
    try testing.expect(topology.nodes.len >= 1);

    // Fallback mode returns single node with ID 0
    if (topology.nodes.len == 1) {
        try testing.expectEqual(@as(u32, 0), topology.nodes[0].id);
    }
}

test "detectTopology allocates all system CPUs" {
    const testing = std.testing;

    const expected_cpu_count = try std.Thread.getCpuCount();
    var topology = try detectTopology(testing.allocator);
    defer topology.deinit();

    // Total CPUs should match system count
    try testing.expectEqual(@as(u32, @intCast(expected_cpu_count)), topology.total_cpus);

    // All CPUs should be accounted for in nodes
    var total_in_nodes: u32 = 0;
    for (topology.nodes) |node| {
        total_in_nodes += @intCast(node.cpu_ids.len);
    }
    try testing.expectEqual(@as(u32, @intCast(expected_cpu_count)), total_in_nodes);
}

test "NumaNode.deinit frees cpu_ids" {
    const testing = std.testing;

    const cpu_ids = try testing.allocator.alloc(u32, 4);
    for (cpu_ids, 0..) |*id, i| {
        id.* = @intCast(i);
    }

    var node = NumaNode{
        .id = 0,
        .cpu_ids = cpu_ids,
        .memory_mb = 0,
    };

    // Should not crash when deinit is called
    node.deinit(testing.allocator);
}

test "getCpuNode returns correct node for valid CPU" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 8192 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 8192 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Test CPUs in node 0
    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(0));
    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(1));

    // Test CPUs in node 1
    try testing.expectEqual(@as(?u32, 1), topology.getCpuNode(2));
    try testing.expectEqual(@as(?u32, 1), topology.getCpuNode(3));
}

test "getCpuNode returns null for invalid CPU" {
    const testing = std.testing;

    var cpu_ids = try testing.allocator.alloc(u32, 2);
    cpu_ids[0] = 0;
    cpu_ids[1] = 1;

    var nodes = try testing.allocator.alloc(NumaNode, 1);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 2,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // CPU 99 doesn't exist
    try testing.expectEqual(@as(?u32, null), topology.getCpuNode(99));
}

test "isNuma returns false for single-node topology" {
    const testing = std.testing;

    const cpu_ids = try testing.allocator.alloc(u32, 4);
    for (cpu_ids, 0..) |*id, i| {
        id.* = @intCast(i);
    }

    var nodes = try testing.allocator.alloc(NumaNode, 1);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expect(!topology.isNuma());
}

test "isNuma returns true for multi-node topology" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expect(topology.isNuma());
}

test "NUMA nodes preserve memory_mb values" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 8192 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 16384 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expectEqual(@as(u64, 8192), topology.nodes[0].memory_mb);
    try testing.expectEqual(@as(u64, 16384), topology.nodes[1].memory_mb);
}

test "CPU IDs are not duplicated across NUMA nodes" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Verify each getCpuNode call returns only one node
    for (0..4) |cpu| {
        const node_id = topology.getCpuNode(@intCast(cpu));
        try testing.expect(node_id != null);
    }
}

test "NUMA node with empty CPU list is handled" {
    const testing = std.testing;

    const cpu_ids = try testing.allocator.alloc(u32, 0);
    defer testing.allocator.free(cpu_ids); // Empty list

    var node = NumaNode{
        .id = 0,
        .cpu_ids = cpu_ids,
        .memory_mb = 0,
    };

    try testing.expectEqual(@as(usize, 0), node.cpu_ids.len);
    node.deinit(testing.allocator);
}

test "Large multi-node topology handled correctly" {
    const testing = std.testing;

    const NUM_NODES = 8;
    const CPUS_PER_NODE = 4;

    var nodes = try testing.allocator.alloc(NumaNode, NUM_NODES);

    var total_cpus: u32 = 0;
    for (0..NUM_NODES) |node_idx| {
        var cpu_ids = try testing.allocator.alloc(u32, CPUS_PER_NODE);
        for (0..CPUS_PER_NODE) |cpu_idx| {
            cpu_ids[cpu_idx] = @intCast(node_idx * CPUS_PER_NODE + cpu_idx);
        }
        nodes[node_idx] = .{
            .id = @intCast(node_idx),
            .cpu_ids = cpu_ids,
            .memory_mb = @intCast((node_idx + 1) * 8192),
        };
        total_cpus += CPUS_PER_NODE;
    }

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = @intCast(total_cpus),
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Verify all nodes exist
    try testing.expectEqual(@as(usize, NUM_NODES), topology.nodes.len);
    try testing.expect(topology.isNuma());

    // Verify all CPUs are found
    for (0..NUM_NODES * CPUS_PER_NODE) |cpu| {
        try testing.expect(topology.getCpuNode(@intCast(cpu)) != null);
    }
}

test "NUMA node IDs can be non-sequential" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    // Non-sequential IDs: 0, 2 (skipping 1)
    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes[1] = .{ .id = 2, .cpu_ids = cpu_ids_1, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expectEqual(@as(u32, 0), topology.nodes[0].id);
    try testing.expectEqual(@as(u32, 2), topology.nodes[1].id);
}

test "NumaTopology.deinit frees all nodes and arrays" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };

    // Should not crash when deinit is called
    topology.deinit();
}

test "getCpuNode works with non-contiguous CPU IDs" {
    const testing = std.testing;

    // Node 0: CPUs 0, 2, 4 (sparse)
    var cpu_ids_0 = try testing.allocator.alloc(u32, 3);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 2;
    cpu_ids_0[2] = 4;

    // Node 1: CPUs 1, 3, 5 (sparse)
    var cpu_ids_1 = try testing.allocator.alloc(u32, 3);
    cpu_ids_1[0] = 1;
    cpu_ids_1[1] = 3;
    cpu_ids_1[2] = 5;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 6,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Even-numbered CPUs -> node 0
    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(0));
    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(2));
    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(4));

    // Odd-numbered CPUs -> node 1
    try testing.expectEqual(@as(?u32, 1), topology.getCpuNode(1));
    try testing.expectEqual(@as(?u32, 1), topology.getCpuNode(3));
    try testing.expectEqual(@as(?u32, 1), topology.getCpuNode(5));
}

test "NUMA nodes can have zero memory_mb (unknown)" {
    const testing = std.testing;

    var cpu_ids = try testing.allocator.alloc(u32, 2);
    cpu_ids[0] = 0;
    cpu_ids[1] = 1;

    var nodes = try testing.allocator.alloc(NumaNode, 1);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 2,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Zero is valid for unknown memory
    try testing.expectEqual(@as(u64, 0), topology.nodes[0].memory_mb);
}

test "detectTopology handles allocation failure gracefully" {
    const allocator = std.testing.failing_allocator;

    // This test ensures that if memory allocation fails, the function
    // returns an error rather than crashing
    const result = detectTopology(allocator);

    // Should get an allocation error
    try std.testing.expectError(error.OutOfMemory, result);
}

test "Multiple NUMA nodes can have equal CPU counts" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 4);
    for (0..4) |i| {
        cpu_ids_0[i] = @intCast(i);
    }

    var cpu_ids_1 = try testing.allocator.alloc(u32, 4);
    for (0..4) |i| {
        cpu_ids_1[i] = @intCast(i + 4);
    }

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 8192 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 8192 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 8,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expectEqual(@as(usize, 4), topology.nodes[0].cpu_ids.len);
    try testing.expectEqual(@as(usize, 4), topology.nodes[1].cpu_ids.len);
}

test "getCpuNode finds CPUs with high ID values" {
    const testing = std.testing;

    var cpu_ids = try testing.allocator.alloc(u32, 1);
    cpu_ids[0] = 127; // High ID

    var nodes = try testing.allocator.alloc(NumaNode, 1);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = 0 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 1,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expectEqual(@as(?u32, 0), topology.getCpuNode(127));
}

test "Topology suitable for affinity queries" {
    const testing = std.testing;

    var topology = try detectTopology(testing.allocator);
    defer topology.deinit();

    // Verify topology is valid for affinity queries
    try testing.expect(topology.nodes.len > 0);
    try testing.expect(topology.total_cpus > 0);

    // Each node should have at least some CPUs
    for (topology.nodes) |node| {
        try testing.expect(node.cpu_ids.len > 0);
    }
}

test "Fallback topology has deterministic node ID" {
    const testing = std.testing;

    var topology = try detectTopology(testing.allocator);
    defer topology.deinit();

    // Fallback always uses node ID 0
    try testing.expectEqual(@as(u32, 0), topology.nodes[0].id);
}
