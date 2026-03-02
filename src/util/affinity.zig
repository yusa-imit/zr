const std = @import("std");
const platform = @import("platform.zig");

/// Set CPU affinity for the current thread to a specific CPU core.
/// This ensures the thread runs only on the specified core.
///
/// Returns error.UnsupportedPlatform if CPU affinity is not supported.
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

    var cpu_set: c.cpu_set_t = undefined;
    c.CPU_ZERO(&cpu_set);
    c.CPU_SET(@intCast(cpu_id), &cpu_set);

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

    var cpu_set: c.cpu_set_t = undefined;
    c.CPU_ZERO(&cpu_set);

    for (cpu_ids) |cpu_id| {
        c.CPU_SET(@intCast(cpu_id), &cpu_set);
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
        try testing.expect(err == error.UnsupportedPlatform or err == error.SetAffinityFailed);
        return;
    };
}
