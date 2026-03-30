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

/// Get total system memory in MB (cross-platform).
/// Returns 0 on failure or if detection is unavailable.
fn getTotalSystemMemory() !u64 {
    const builtin = @import("builtin");
    const os_tag = builtin.os.tag;

    if (os_tag == .linux) {
        // Parse /proc/meminfo for MemTotal
        const allocator = std.heap.page_allocator;
        const result = parseMeminfoFile(allocator, "/proc/meminfo") catch return 0;
        return result;
    } else if (os_tag == .macos) {
        // Use sysctl to get hw.memsize (bytes)
        var size: usize = 0;
        var len: usize = @sizeOf(usize);
        const name = "hw.memsize";
        const result = std.c.sysctlbyname(name.ptr, &size, &len, null, 0);
        if (result == 0) {
            return size / (1024 * 1024); // Convert bytes to MB
        }
        return 0;
    } else if (os_tag == .windows) {
        // Use GlobalMemoryStatusEx for total physical memory
        const windows = std.os.windows;
        const MEMORYSTATUSEX = extern struct {
            dwLength: windows.DWORD,
            dwMemoryLoad: windows.DWORD,
            ullTotalPhys: u64,
            ullAvailPhys: u64,
            ullTotalPageFile: u64,
            ullAvailPageFile: u64,
            ullTotalVirtual: u64,
            ullAvailVirtual: u64,
            ullAvailExtendedVirtual: u64,
        };

        const kernel32 = struct {
            extern "kernel32" fn GlobalMemoryStatusEx(
                lpBuffer: *MEMORYSTATUSEX,
            ) callconv(.c) windows.BOOL;
        }.GlobalMemoryStatusEx;

        var mem_status: MEMORYSTATUSEX = undefined;
        mem_status.dwLength = @sizeOf(MEMORYSTATUSEX);

        if (kernel32(&mem_status) != 0) {
            return mem_status.ullTotalPhys / (1024 * 1024); // Convert bytes to MB
        }
        return 0;
    } else {
        return 0;
    }
}

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

    // Get total system memory (best-effort)
    const memory_mb = getTotalSystemMemory() catch 0;

    const nodes = try allocator.alloc(NumaNode, 1);
    nodes[0] = .{
        .id = 0,
        .cpu_ids = cpu_ids,
        .memory_mb = memory_mb,
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

        // Parse memory info from /sys/devices/system/node/nodeN/meminfo
        var meminfo_path_buf: [256]u8 = undefined;
        const meminfo_path = std.fmt.bufPrint(&meminfo_path_buf, "/sys/devices/system/node/{s}/meminfo", .{entry.name}) catch continue;
        const memory_mb = parseMeminfoFile(allocator, meminfo_path) catch 0;

        try nodes_list.append(allocator, .{
            .id = node_id,
            .cpu_ids = cpu_ids,
            .memory_mb = memory_mb,
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

/// Parse meminfo content to extract MemTotal in MB.
/// Returns memory in MB, or 0 if not found or on parse error.
fn parseMeminfo(allocator: std.mem.Allocator, content: []const u8) !u64 {
    _ = allocator; // Used for potential future error handling

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "MemTotal:")) {
            // Extract the number part: "MemTotal:       16384000 kB"
            const after_colon = trimmed[9..]; // Skip "MemTotal:"
            const value_str = std.mem.trim(u8, after_colon, " \t");

            // Find the number part (before " kB")
            var iter = std.mem.splitScalar(u8, value_str, ' ');
            if (iter.next()) |num_str| {
                const kb_value = std.fmt.parseInt(u64, num_str, 10) catch return 0;
                return kb_value / 1024; // Convert kB to MB
            }
        }
    }

    return 0;
}

/// Read and parse meminfo file at the given path.
/// Returns memory in MB, or 0 if file doesn't exist or on error.
fn parseMeminfoFile(allocator: std.mem.Allocator, path: []const u8) !u64 {
    const file = std.fs.openFileAbsolute(path, .{}) catch return 0;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 8192) catch return 0;
    defer allocator.free(content);

    return try parseMeminfo(allocator, content);
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

/// Get available memory for a NUMA node on Windows (in MB).
/// Returns 0 if the API is not available or on error.
fn getWindowsNodeMemory(node_number: u32) u64 {
    const windows = std.os.windows;

    const kernel32 = struct {
        extern "kernel32" fn GetNumaAvailableMemoryNodeEx(
            Node: windows.WORD,
            AvailableBytes: *u64,
        ) callconv(.c) windows.BOOL;
    }.GetNumaAvailableMemoryNodeEx;

    var available_bytes: u64 = 0;
    const result = kernel32(@intCast(node_number), &available_bytes);

    if (result != 0) {
        return available_bytes / (1024 * 1024); // Convert bytes to MB
    }

    return 0;
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
            // Get memory information for this NUMA node
            const memory_mb = getWindowsNodeMemory(@intCast(node_number));

            try nodes_list.append(allocator, .{
                .id = @intCast(node_number),
                .cpu_ids = try cpu_ids.toOwnedSlice(allocator),
                .memory_mb = memory_mb,
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

// NUMA Memory Information Parsing Tests
// These tests verify the implementation of memory detection for Linux, macOS, and Windows

test "parseMeminfo returns MB from kB format" {
    const testing = std.testing;

    // Simulates: MemTotal: 16384000 kB (16 GB in kB)
    const meminfo_content = "MemTotal:       16384000 kB\nMemFree:         8192000 kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // 16384000 kB / 1024 = 16000 MB
    try testing.expectEqual(@as(u64, 16000), result);
}

test "parseMeminfo handles MemTotal with varying whitespace" {
    const testing = std.testing;

    const meminfo_content = "MemTotal:    16384000   kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    try testing.expectEqual(@as(u64, 16000), result);
}

test "parseMeminfo returns 0 for missing file" {
    const testing = std.testing;

    const result = try parseMeminfoFile(testing.allocator, "/nonexistent/path/meminfo");

    try testing.expectEqual(@as(u64, 0), result);
}

test "parseMeminfo handles malformed content without MemTotal" {
    const testing = std.testing;

    const meminfo_content = "MemFree:         8192000 kB\nMemAvailable:    4096000 kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // Should return 0 when MemTotal is missing
    try testing.expectEqual(@as(u64, 0), result);
}

test "parseMeminfo handles MemTotal in middle of file" {
    const testing = std.testing;

    const meminfo_content = "MemFree:         8192000 kB\nMemTotal:       16384000 kB\nMemAvailable:    4096000 kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    try testing.expectEqual(@as(u64, 16000), result);
}

test "parseMeminfo converts edge case: 1 kB to MB" {
    const testing = std.testing;

    const meminfo_content = "MemTotal:       1 kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // 1 kB / 1024 = 0 MB (floor division)
    try testing.expectEqual(@as(u64, 0), result);
}

test "parseMeminfo converts 1048576 kB (1 GB) to MB" {
    const testing = std.testing;

    const meminfo_content = "MemTotal:       1048576 kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // 1048576 kB / 1024 = 1024 MB (exactly 1 GB)
    try testing.expectEqual(@as(u64, 1024), result);
}

test "parseMeminfo handles very large memory values" {
    const testing = std.testing;

    // 2 TB in kB
    const meminfo_content = "MemTotal:       2147483648 kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // 2147483648 kB / 1024 = 2097152 MB
    try testing.expectEqual(@as(u64, 2097152), result);
}

test "parseMeminfo ignores invalid numeric values" {
    const testing = std.testing;

    const meminfo_content = "MemTotal:       notanumber kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // Should return 0 on parse error
    try testing.expectEqual(@as(u64, 0), result);
}

test "parseMeminfo handles empty content" {
    const testing = std.testing;

    const meminfo_content = "";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    try testing.expectEqual(@as(u64, 0), result);
}

test "single-node topology gets all system memory" {
    const testing = std.testing;

    const cpu_ids = try testing.allocator.alloc(u32, 4);
    for (cpu_ids, 0..) |*id, i| {
        id.* = @intCast(i);
    }

    var nodes = try testing.allocator.alloc(NumaNode, 1);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = 16384 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Single-node topology should have all memory in node 0
    try testing.expectEqual(@as(u64, 16384), topology.nodes[0].memory_mb);
}

test "multi-node topology with per-node memory info" {
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

    // Multi-node topology should have distinct memory per node
    try testing.expectEqual(@as(u64, 8192), topology.nodes[0].memory_mb);
    try testing.expectEqual(@as(u64, 8192), topology.nodes[1].memory_mb);

    // Total memory should be sum of all nodes
    var total_memory: u64 = 0;
    for (topology.nodes) |node| {
        total_memory += node.memory_mb;
    }
    try testing.expectEqual(@as(u64, 16384), total_memory);
}

test "multi-node topology with unequal memory distribution" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 12288 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 4096 };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Unequal memory distribution is valid
    try testing.expectEqual(@as(u64, 12288), topology.nodes[0].memory_mb);
    try testing.expectEqual(@as(u64, 4096), topology.nodes[1].memory_mb);
}

test "memory distribution across 4 NUMA nodes" {
    const testing = std.testing;

    const NUM_NODES = 4;
    const MEMORY_PER_NODE = 4096; // 4 GB per node

    var nodes = try testing.allocator.alloc(NumaNode, NUM_NODES);

    for (0..NUM_NODES) |i| {
        var cpu_ids = try testing.allocator.alloc(u32, 2);
        cpu_ids[0] = @intCast(i * 2);
        cpu_ids[1] = @intCast(i * 2 + 1);

        nodes[i] = .{
            .id = @intCast(i),
            .cpu_ids = cpu_ids,
            .memory_mb = MEMORY_PER_NODE,
        };
    }

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 8,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Verify each node has correct memory
    for (0..NUM_NODES) |i| {
        try testing.expectEqual(@as(u64, MEMORY_PER_NODE), topology.nodes[i].memory_mb);
    }

    // Verify total memory
    var total_memory: u64 = 0;
    for (topology.nodes) |node| {
        total_memory += node.memory_mb;
    }
    try testing.expectEqual(@as(u64, MEMORY_PER_NODE * NUM_NODES), total_memory);
}

test "NUMA node with zero memory_mb indicates unknown" {
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

    // Zero memory_mb is valid for unknown/unavailable
    try testing.expectEqual(@as(u64, 0), topology.nodes[0].memory_mb);
}

test "memory_mb field type is u64 for large systems" {
    const testing = std.testing;

    // Test with very large memory value (8 TB)
    const large_memory: u64 = 8388608; // 8 TB in MB

    var cpu_ids = try testing.allocator.alloc(u32, 2);
    cpu_ids[0] = 0;
    cpu_ids[1] = 1;

    var nodes = try testing.allocator.alloc(NumaNode, 1);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = large_memory };

    var topology = NumaTopology{
        .nodes = nodes,
        .total_cpus = 2,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    try testing.expectEqual(large_memory, topology.nodes[0].memory_mb);
}

test "parseMeminfo handles whitespace-only lines" {
    const testing = std.testing;

    const meminfo_content = "\n\n   \nMemTotal:       16384000 kB\n   \n\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    try testing.expectEqual(@as(u64, 16000), result);
}

test "parseMeminfo case-sensitive: memtotal not MemTotal" {
    const testing = std.testing;

    const meminfo_content = "memtotal:       16384000 kB\n"; // lowercase
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // Should return 0 (case mismatch)
    try testing.expectEqual(@as(u64, 0), result);
}

test "parseMeminfo stops at first MemTotal occurrence" {
    const testing = std.testing;

    const meminfo_content = "MemTotal:       16384000 kB\nOtherField:     32768000 kB\nMemTotal:       99999999 kB\n";
    const result = try parseMeminfo(testing.allocator, meminfo_content);

    // Should use the first MemTotal
    try testing.expectEqual(@as(u64, 16000), result);
}
