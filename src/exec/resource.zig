const std = @import("std");
const builtin = @import("builtin");

/// C getpid() function
const getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });

/// Cross-platform resource monitoring and limiting for task execution.
///
/// Platform-specific implementations:
/// - Linux: cgroups v2 for CPU/memory limits
/// - macOS: getrusage() for monitoring (no hard limits without external tools)
/// - Windows: Job Objects for CPU/memory limits
///
/// Note: This is a Phase 3 feature from PRD §5.4. Currently provides:
/// - Basic monitoring (RSS, CPU time) on all platforms
/// - Future: Hard limits via OS-specific mechanisms

pub const ResourceUsage = struct {
    /// Resident set size (physical memory) in bytes
    rss_bytes: u64 = 0,
    /// CPU time used (user + system) in nanoseconds
    cpu_time_ns: u64 = 0,
    /// CPU usage percent (0-100 per core, so >100 possible)
    cpu_percent: f64 = 0.0,

    pub fn format(
        self: ResourceUsage,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("RSS: {} MB, CPU: {d:.1}%", .{
            self.rss_bytes / 1_048_576,
            self.cpu_percent,
        });
    }
};

/// Get current resource usage for a process.
/// Returns null if monitoring is not supported on this platform or PID not found.
pub fn getProcessUsage(pid: std.posix.pid_t) ?ResourceUsage {
    switch (comptime builtin.os.tag) {
        .linux => return getProcessUsageLinux(pid),
        .macos => return getProcessUsageMacOS(pid),
        else => return null,
    }
}

/// Linux-specific resource usage via /proc filesystem
fn getProcessUsageLinux(pid: std.posix.pid_t) ?ResourceUsage {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var usage = ResourceUsage{};

    // Read /proc/[pid]/status for VmRSS (resident set size)
    const status_path = std.fmt.allocPrint(allocator, "/proc/{d}/status", .{pid}) catch return null;
    const status_file = std.fs.openFileAbsolute(status_path, .{}) catch return null;
    defer status_file.close();

    const status_content = status_file.readToEndAlloc(allocator, 1024 * 1024) catch return null;

    // Parse VmRSS from status file (format: "VmRSS:     12345 kB")
    var lines = std.mem.splitScalar(u8, status_content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "VmRSS:")) {
            const trimmed = std.mem.trim(u8, line[6..], " \t");
            // Extract numeric part before " kB"
            const kb_pos = std.mem.indexOf(u8, trimmed, " kB") orelse continue;
            const kb_str = std.mem.trim(u8, trimmed[0..kb_pos], " \t");
            const kb = std.fmt.parseInt(u64, kb_str, 10) catch continue;
            usage.rss_bytes = kb * 1024;
            break;
        }
    }

    // Read /proc/[pid]/stat for CPU time
    const stat_path = std.fmt.allocPrint(allocator, "/proc/{d}/stat", .{pid}) catch return null;
    const stat_file = std.fs.openFileAbsolute(stat_path, .{}) catch return null;
    defer stat_file.close();

    const stat_content = stat_file.readToEndAlloc(allocator, 4096) catch return null;

    // Parse stat file: pid (comm) state ppid ... utime stime ...
    // We need fields 14 (utime) and 15 (stime) in clock ticks
    var fields = std.mem.splitScalar(u8, stat_content, ' ');
    var field_idx: usize = 0;
    var utime: u64 = 0;
    var stime: u64 = 0;

    // Skip first field (PID)
    _ = fields.next();
    field_idx += 1;

    // Skip comm field (enclosed in parentheses, may contain spaces)
    // Find the last ')' to handle comm with spaces
    const comm_start = std.mem.indexOf(u8, stat_content, "(") orelse return null;
    const comm_end = std.mem.lastIndexOf(u8, stat_content, ")") orelse return null;
    if (comm_end <= comm_start) return null;

    // Split remaining fields after comm
    const after_comm = std.mem.trim(u8, stat_content[comm_end + 1 ..], " ");
    var remaining_fields = std.mem.splitScalar(u8, after_comm, ' ');

    // Field 3 = state (skip), then we need to reach field 14 and 15 (utime, stime)
    // After comm: state ppid pgrp session tty_nr tpgid flags minflt cminflt majflt cmajflt utime stime
    // Position: 1    2    3    4       5      6     7     8      9       10     11      12    13
    field_idx = 0;
    while (remaining_fields.next()) |field| {
        field_idx += 1;
        if (field_idx == 12) { // utime
            utime = std.fmt.parseInt(u64, field, 10) catch 0;
        } else if (field_idx == 13) { // stime
            stime = std.fmt.parseInt(u64, field, 10) catch 0;
            break;
        }
    }

    // Convert clock ticks to nanoseconds
    // clock ticks = 100 per second on most Linux systems (USER_HZ=100)
    const ticks_per_sec: u64 = 100;
    const total_ticks = utime + stime;
    usage.cpu_time_ns = (total_ticks * std.time.ns_per_s) / ticks_per_sec;

    // CPU percent would require tracking time delta, so leave at 0 for now
    // (accurate CPU% requires: (delta_cpu_time / delta_wall_time) * 100)
    usage.cpu_percent = 0.0;

    return usage;
}

/// macOS-specific resource usage via proc_pidinfo
fn getProcessUsageMacOS(pid: std.posix.pid_t) ?ResourceUsage {
    // Use libproc's proc_pidinfo for task_info
    // We need to call proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, sizeof(info))
    const PROC_PIDTASKINFO: c_int = 4;

    const proc_taskinfo = extern struct {
        pti_virtual_size: u64,
        pti_resident_size: u64,
        pti_total_user: u64,
        pti_total_system: u64,
        pti_threads_user: u64,
        pti_threads_system: u64,
        pti_policy: i32,
        pti_faults: i32,
        pti_pageins: i32,
        pti_cow_faults: i32,
        pti_messages_sent: i32,
        pti_messages_received: i32,
        pti_syscalls_mach: i32,
        pti_syscalls_unix: i32,
        pti_csw: i32,
        pti_threadnum: i32,
        pti_numrunning: i32,
        pti_priority: i32,
    };

    const proc_pidinfo = @extern(*const fn (c_int, c_int, u64, ?*anyopaque, c_int) callconv(.c) c_int, .{
        .name = "proc_pidinfo",
    });

    var info: proc_taskinfo = undefined;
    const result = proc_pidinfo(
        @intCast(pid),
        PROC_PIDTASKINFO,
        0,
        &info,
        @sizeOf(proc_taskinfo),
    );

    if (result != @sizeOf(proc_taskinfo)) {
        return null;
    }

    var usage = ResourceUsage{};
    usage.rss_bytes = info.pti_resident_size;

    // Convert total_user + total_system from microseconds to nanoseconds
    usage.cpu_time_ns = (info.pti_total_user + info.pti_total_system) * 1000;

    // CPU percent requires delta tracking, leave at 0
    usage.cpu_percent = 0.0;

    return usage;
}

/// Monitor resource usage of a child process (non-blocking).
/// This is a stub for Phase 3 implementation.
pub const ResourceMonitor = struct {
    pid: std.posix.pid_t,
    max_cpu_cores: ?u32,
    max_memory_bytes: ?u64,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        pid: std.posix.pid_t,
        max_cpu_cores: ?u32,
        max_memory_bytes: ?u64,
    ) ResourceMonitor {
        return .{
            .pid = pid,
            .max_cpu_cores = max_cpu_cores,
            .max_memory_bytes = max_memory_bytes,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ResourceMonitor) void {
        _ = self;
    }

    /// Check current usage and enforce limits if exceeded.
    /// Returns true if process should be killed due to limit violation.
    pub fn checkLimits(self: *ResourceMonitor) bool {
        const usage = getProcessUsage(self.pid) orelse return false;

        // Memory limit enforcement
        if (self.max_memory_bytes) |limit| {
            if (usage.rss_bytes > limit) {
                // TODO: Kill process with SIGKILL (or TerminateProcess on Windows)
                return true;
            }
        }

        // CPU limit is informational only for now
        // (Actual CPU throttling requires cgroups/Job Objects)
        _ = self.max_cpu_cores;

        return false;
    }

    /// Get current resource usage snapshot
    pub fn getUsage(self: *ResourceMonitor) ?ResourceUsage {
        return getProcessUsage(self.pid);
    }
};

test "ResourceMonitor: basic init" {
    const allocator = std.testing.allocator;
    var monitor = ResourceMonitor.init(allocator, 1234, 4, 2 * 1024 * 1024 * 1024);
    defer monitor.deinit();

    try std.testing.expectEqual(@as(std.posix.pid_t, 1234), monitor.pid);
    try std.testing.expectEqual(@as(?u32, 4), monitor.max_cpu_cores);
    try std.testing.expectEqual(@as(?u64, 2 * 1024 * 1024 * 1024), monitor.max_memory_bytes);
}

test "getProcessUsage: self process (Linux)" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;

    const self_pid: std.posix.pid_t = @intCast(getpid());
    const usage = getProcessUsage(self_pid);

    // Should be able to read our own process stats
    try std.testing.expect(usage != null);

    if (usage) |u| {
        // Our process should have some memory
        try std.testing.expect(u.rss_bytes > 0);
        // CPU time should be non-negative (may be 0 for quick test)
        try std.testing.expect(u.cpu_time_ns >= 0);
    }
}

test "getProcessUsage: invalid PID returns null" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;

    // PID 999999 is unlikely to exist
    const usage = getProcessUsage(999999);
    try std.testing.expectEqual(@as(?ResourceUsage, null), usage);
}

test "getProcessUsage: self process (macOS)" {
    if (comptime builtin.os.tag != .macos) return error.SkipZigTest;

    const self_pid: std.posix.pid_t = @intCast(getpid());
    const usage = getProcessUsage(self_pid);

    // Should be able to read our own process stats
    try std.testing.expect(usage != null);

    if (usage) |u| {
        // Our process should have some memory
        try std.testing.expect(u.rss_bytes > 0);
        // CPU time should be non-negative (may be 0 for quick test)
        try std.testing.expect(u.cpu_time_ns >= 0);
    }
}

test "getProcessUsage: invalid PID returns null (macOS)" {
    if (comptime builtin.os.tag != .macos) return error.SkipZigTest;

    // PID 999999 is unlikely to exist
    const usage = getProcessUsage(999999);
    try std.testing.expectEqual(@as(?ResourceUsage, null), usage);
}
