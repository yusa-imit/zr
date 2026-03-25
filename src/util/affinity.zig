const std = @import("std");
const platform = @import("platform.zig");
const numa = @import("numa.zig");

/// Set CPU affinity for the current thread to a specific CPU core.
/// This ensures the thread runs only on the specified core.
///
/// Returns error.UnsupportedPlatform if CPU affinity is not supported.
/// Returns error.InvalidCpuId if cpu_id exceeds the system's CPU limit.
/// Returns error.SetAffinityFailed if the system call fails.
pub fn setThreadAffinity(cpu_id: u32) !void {
    const builtin = @import("builtin");
    const os_tag = builtin.os.tag;

    if (os_tag == .linux) {
        return setThreadAffinityLinux(cpu_id);
    } else if (os_tag == .windows) {
        return setThreadAffinityWindows(cpu_id);
    } else if (os_tag == .macos or os_tag == .freebsd or os_tag == .openbsd) {
        // macOS and BSD don't support strict CPU affinity in the same way.
        // pthread_setaffinity_np is not available on macOS.
        // We can set thread affinity policy, but it's advisory, not guaranteed.
        return setThreadAffinityDarwin(cpu_id);
    } else {
        return error.UnsupportedPlatform;
    }
}

/// Set CPU affinity mask for the current thread (Linux).
fn setThreadAffinityLinux(cpu_id: u32) !void {
    // Use sched_setaffinity via libc
    const c = @cImport({
        @cDefine("_GNU_SOURCE", "");
        @cInclude("sched.h");
        @cInclude("pthread.h");
    });

    // CPU_ZERO and CPU_SET macros cannot be translated by Zig's translate-c
    // Use direct bit manipulation on cpu_set_t
    // cpu_set_t is an opaque bitset - we manually set the bit for cpu_id
    var cpu_set: c.cpu_set_t = undefined;
    @memset(std.mem.asBytes(&cpu_set), 0);

    // Set the bit for the target CPU
    // cpu_set_t is typically an array of longs
    const bits_per_byte = 8;
    const cpu_set_bytes = std.mem.asBytes(&cpu_set);
    const byte_index = cpu_id / bits_per_byte;
    const bit_offset = @as(u3, @intCast(cpu_id % bits_per_byte));

    if (byte_index >= cpu_set_bytes.len) {
        return error.InvalidCpuId;
    }

    cpu_set_bytes[byte_index] |= @as(u8, 1) << bit_offset;

    const tid = c.pthread_self();
    const result = c.pthread_setaffinity_np(tid, @sizeOf(c.cpu_set_t), &cpu_set);

    if (result != 0) {
        return error.SetAffinityFailed;
    }
}

/// Set CPU affinity for the current thread (Windows).
fn setThreadAffinityWindows(cpu_id: u32) !void {
    const windows = std.os.windows;

    // SetThreadAffinityMask takes a bitmask where each bit represents a logical processor
    const affinity_mask: usize = @as(usize, 1) << @intCast(cpu_id);

    const kernel32 = struct {
        extern "kernel32" fn SetThreadAffinityMask(
            hThread: windows.HANDLE,
            dwThreadAffinityMask: windows.DWORD_PTR,
        ) callconv(.c) windows.DWORD_PTR;
    }.SetThreadAffinityMask;

    const current_thread = windows.GetCurrentThread();
    const result = kernel32(current_thread, affinity_mask);

    if (result == 0) {
        return error.SetAffinityFailed;
    }
}

/// Set CPU affinity for the current thread (macOS/Darwin).
/// Note: macOS doesn't support strict CPU affinity. This uses thread affinity policy
/// which is advisory, not guaranteed.
fn setThreadAffinityDarwin(cpu_id: u32) !void {
    // macOS uses thread affinity policy, which is advisory
    // We'll use mach thread_policy_set with THREAD_AFFINITY_POLICY

    const c = @cImport({
        @cInclude("mach/mach.h");
        @cInclude("mach/thread_policy.h");
        @cInclude("pthread.h");
    });

    // Get mach thread port
    const mach_port = c.pthread_mach_thread_np(c.pthread_self());

    // Set affinity tag (advisory)
    var policy: c.thread_affinity_policy_data_t = undefined;
    policy.affinity_tag = @intCast(cpu_id);

    const result = c.thread_policy_set(
        mach_port,
        c.THREAD_AFFINITY_POLICY,
        @ptrCast(&policy),
        c.THREAD_AFFINITY_POLICY_COUNT,
    );

    if (result != c.KERN_SUCCESS) {
        return error.SetAffinityFailed;
    }
}

/// Set CPU affinity for a list of CPU IDs (affinity mask).
/// The thread can run on any of the specified cores.
pub fn setThreadAffinityMask(cpu_ids: []const u32) !void {
    const builtin = @import("builtin");
    const os_tag = builtin.os.tag;

    if (os_tag == .linux) {
        return setThreadAffinityMaskLinux(cpu_ids);
    } else if (os_tag == .windows) {
        return setThreadAffinityMaskWindows(cpu_ids);
    } else if (os_tag == .macos or os_tag == .freebsd or os_tag == .openbsd) {
        // macOS doesn't support affinity masks in the same way
        // Fall back to setting affinity to the first CPU in the list
        if (cpu_ids.len > 0) {
            return setThreadAffinityDarwin(cpu_ids[0]);
        }
        return error.EmptyAffinityMask;
    } else {
        return error.UnsupportedPlatform;
    }
}

fn setThreadAffinityMaskLinux(cpu_ids: []const u32) !void {
    const c = @cImport({
        @cDefine("_GNU_SOURCE", "");
        @cInclude("sched.h");
        @cInclude("pthread.h");
    });

    // CPU_ZERO and CPU_SET macros cannot be translated by Zig's translate-c
    // Use direct bit manipulation on cpu_set_t
    var cpu_set: c.cpu_set_t = undefined;
    @memset(std.mem.asBytes(&cpu_set), 0);

    const bits_per_byte = 8;
    const cpu_set_bytes = std.mem.asBytes(&cpu_set);

    for (cpu_ids) |cpu_id| {
        const byte_index = cpu_id / bits_per_byte;
        const bit_offset = @as(u3, @intCast(cpu_id % bits_per_byte));

        if (byte_index >= cpu_set_bytes.len) {
            return error.InvalidCpuId;
        }

        cpu_set_bytes[byte_index] |= @as(u8, 1) << bit_offset;
    }

    const tid = c.pthread_self();
    const result = c.pthread_setaffinity_np(tid, @sizeOf(c.cpu_set_t), &cpu_set);

    if (result != 0) {
        return error.SetAffinityFailed;
    }
}

fn setThreadAffinityMaskWindows(cpu_ids: []const u32) !void {
    const windows = std.os.windows;

    // Build bitmask from CPU IDs
    var affinity_mask: usize = 0;
    for (cpu_ids) |cpu_id| {
        affinity_mask |= @as(usize, 1) << @intCast(cpu_id);
    }

    const kernel32 = struct {
        extern "kernel32" fn SetThreadAffinityMask(
            hThread: windows.HANDLE,
            dwThreadAffinityMask: windows.DWORD_PTR,
        ) callconv(.c) windows.DWORD_PTR;
    }.SetThreadAffinityMask;

    const current_thread = windows.GetCurrentThread();
    const result = kernel32(current_thread, affinity_mask);

    if (result == 0) {
        return error.SetAffinityFailed;
    }
}

/// Get the current CPU ID the thread is running on.
/// Returns null if the platform doesn't support querying the current CPU.
pub fn getCurrentCpu() ?u32 {
    const builtin = @import("builtin");
    const os_tag = builtin.os.tag;

    if (os_tag == .linux) {
        return getCurrentCpuLinux();
    } else if (os_tag == .windows) {
        return getCurrentCpuWindows();
    } else {
        return null;
    }
}

fn getCurrentCpuLinux() ?u32 {
    const c = @cImport({
        @cDefine("_GNU_SOURCE", "");
        @cInclude("sched.h");
    });

    const cpu = c.sched_getcpu();
    if (cpu < 0) return null;
    return @intCast(cpu);
}

fn getCurrentCpuWindows() ?u32 {
    const windows = std.os.windows;

    const kernel32 = struct {
        extern "kernel32" fn GetCurrentProcessorNumber() callconv(.c) windows.DWORD;
    }.GetCurrentProcessorNumber;

    return @intCast(kernel32());
}

/// Set CPU affinity to all CPUs in a NUMA node.
/// This is NUMA-aware and ensures the thread runs only on CPUs belonging to the specified node.
pub fn setThreadAffinityToNumaNode(topology: *const numa.NumaTopology, node_id: u32) !void {
    // Find the node with the given ID
    for (topology.nodes) |node| {
        if (node.id == node_id) {
            // Set affinity to all CPUs in this node
            return setThreadAffinityMask(node.cpu_ids);
        }
    }
    return error.InvalidNumaNode;
}

/// Set CPU affinity to a preferred NUMA node for the current thread.
/// If the specified node is not found, falls back to the first available node.
pub fn setThreadAffinityToPreferredNumaNode(
    topology: *const numa.NumaTopology,
    preferred_node_id: u32,
) !void {
    // Try preferred node first
    for (topology.nodes) |node| {
        if (node.id == preferred_node_id) {
            return setThreadAffinityMask(node.cpu_ids);
        }
    }

    // Fallback to first node
    if (topology.nodes.len > 0) {
        return setThreadAffinityMask(topology.nodes[0].cpu_ids);
    }

    return error.NoNumaNodes;
}

/// Automatically set CPU affinity to the NUMA node of the current CPU.
/// This is useful for ensuring memory-local execution on NUMA systems.
pub fn setThreadAffinityToCurrentNumaNode(topology: *const numa.NumaTopology) !void {
    // Get current CPU
    const current_cpu = getCurrentCpu() orelse return error.CannotGetCurrentCpu;

    // Find which NUMA node this CPU belongs to
    const node_id = topology.getCpuNode(current_cpu) orelse return error.CpuNotInTopology;

    // Set affinity to all CPUs in that node
    return setThreadAffinityToNumaNode(topology, node_id);
}

test "affinity: basic API existence" {
    // This test just verifies the functions exist and can be called.
    // Actual functionality depends on OS support and permissions.
    const testing = std.testing;

    // Try to set affinity to CPU 0
    // This may fail on some systems (e.g., no permissions, unsupported OS)
    _ = setThreadAffinity(0) catch |err| {
        // Expected errors: UnsupportedPlatform, SetAffinityFailed
        try testing.expect(err == error.UnsupportedPlatform or err == error.SetAffinityFailed);
        return;
    };

    // If setThreadAffinity succeeded, try to get current CPU
    if (getCurrentCpu()) |cpu_id| {
        try testing.expect(cpu_id < 1024); // Sanity check
    }
}

test "affinity: mask API" {
    const testing = std.testing;

    const cpu_ids = [_]u32{ 0, 1 };

    _ = setThreadAffinityMask(&cpu_ids) catch |err| {
        try testing.expect(err == error.UnsupportedPlatform or err == error.SetAffinityFailed or err == error.InvalidCpuId);
        return;
    };
}

test "affinity: invalid CPU ID" {
    const testing = std.testing;

    // Test with an extremely high CPU ID that should exceed cpu_set_t limits
    // cpu_set_t is typically 1024 bits (128 bytes), so CPU ID 2048 should fail
    const result = setThreadAffinity(2048);

    if (result) |_| {
        // On some platforms, this might succeed (e.g., unsupported platforms just return OK)
        // This is acceptable behavior
    } else |err| {
        // Expected errors: InvalidCpuId on Linux, or other platform-specific errors
        try testing.expect(
            err == error.InvalidCpuId or
                err == error.UnsupportedPlatform or
                err == error.SetAffinityFailed,
        );
    }
}

test "affinity: setThreadAffinityToNumaNode" {
    const testing = std.testing;

    // Create a mock NUMA topology
    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(numa.NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 0 };

    var topology = numa.NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Try to set affinity to node 0
    _ = setThreadAffinityToNumaNode(&topology, 0) catch |err| {
        // Expected errors on platforms without affinity support
        try testing.expect(err == error.UnsupportedPlatform or err == error.SetAffinityFailed or err == error.InvalidCpuId);
        return;
    };

    // If it succeeded, we should now be on one of the CPUs in node 0
    // (can't guarantee which one due to OS scheduling)
}

test "affinity: setThreadAffinityToNumaNode invalid node" {
    const testing = std.testing;

    var cpu_ids = try testing.allocator.alloc(u32, 2);
    cpu_ids[0] = 0;
    cpu_ids[1] = 1;

    var nodes = try testing.allocator.alloc(numa.NumaNode, 1);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = 0 };

    var topology = numa.NumaTopology{
        .nodes = nodes,
        .total_cpus = 2,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Try to set affinity to non-existent node 99
    const result = setThreadAffinityToNumaNode(&topology, 99);
    try testing.expectError(error.InvalidNumaNode, result);
}

test "affinity: setThreadAffinityToPreferredNumaNode fallback" {
    const testing = std.testing;

    var cpu_ids_0 = try testing.allocator.alloc(u32, 2);
    cpu_ids_0[0] = 0;
    cpu_ids_0[1] = 1;

    var cpu_ids_1 = try testing.allocator.alloc(u32, 2);
    cpu_ids_1[0] = 2;
    cpu_ids_1[1] = 3;

    var nodes = try testing.allocator.alloc(numa.NumaNode, 2);
    nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids_0, .memory_mb = 0 };
    nodes[1] = .{ .id = 1, .cpu_ids = cpu_ids_1, .memory_mb = 0 };

    var topology = numa.NumaTopology{
        .nodes = nodes,
        .total_cpus = 4,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // Request node 99 (doesn't exist), should fall back to node 0
    _ = setThreadAffinityToPreferredNumaNode(&topology, 99) catch |err| {
        try testing.expect(err == error.UnsupportedPlatform or err == error.SetAffinityFailed or err == error.InvalidCpuId);
        return;
    };
}

test "affinity: setThreadAffinityToCurrentNumaNode" {
    const testing = std.testing;

    var topology = try numa.detectTopology(testing.allocator);
    defer topology.deinit();

    // Try to set affinity to current NUMA node
    _ = setThreadAffinityToCurrentNumaNode(&topology) catch |err| {
        // Expected errors: CannotGetCurrentCpu (unsupported platform), or affinity errors
        try testing.expect(
            err == error.CannotGetCurrentCpu or
                err == error.CpuNotInTopology or
                err == error.UnsupportedPlatform or
                err == error.SetAffinityFailed or
                err == error.InvalidCpuId or
                err == error.InvalidNumaNode,
        );
        return;
    };

    // If it succeeded, verify we're still on a valid CPU
    if (getCurrentCpu()) |cpu_id| {
        try testing.expect(cpu_id < topology.total_cpus);
    }
}

test "affinity: NUMA functions with empty topology" {
    const testing = std.testing;

    const nodes = try testing.allocator.alloc(numa.NumaNode, 0);
    var topology = numa.NumaTopology{
        .nodes = nodes,
        .total_cpus = 0,
        .allocator = testing.allocator,
    };
    defer topology.deinit();

    // All NUMA affinity functions should fail gracefully with empty topology
    const result1 = setThreadAffinityToNumaNode(&topology, 0);
    try testing.expectError(error.InvalidNumaNode, result1);

    const result2 = setThreadAffinityToPreferredNumaNode(&topology, 0);
    try testing.expectError(error.NoNumaNodes, result2);
}
