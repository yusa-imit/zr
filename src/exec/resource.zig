const std = @import("std");
const builtin = @import("builtin");

/// C getpid() function (POSIX only)
const getpid = if (builtin.os.tag != .windows)
    @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" })
else
    undefined;

/// Cross-platform resource monitoring and limiting for task execution.
///
/// Platform-specific implementations:
/// - Linux: cgroups v2 for CPU/memory hard limits (requires systemd or manual setup)
/// - macOS: Polling-based soft limits (no kernel-level hard limits available)
/// - Windows: Job Objects for CPU/memory hard limits
///
/// Note: This is a Phase 3 feature from PRD §5.4. Provides:
/// - Hard limits on Linux (cgroups v2) and Windows (Job Objects)
/// - Soft limits on macOS (polling + SIGKILL)
/// - Cross-platform monitoring API

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
pub fn getProcessUsage(pid: if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.posix.pid_t) ?ResourceUsage {
    switch (comptime builtin.os.tag) {
        .linux => return getProcessUsageLinux(pid),
        .macos => return getProcessUsageMacOS(pid),
        .windows => return getProcessUsageWindows(pid),
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

/// Windows-specific resource usage via GetProcessMemoryInfo and GetProcessTimes
fn getProcessUsageWindows(handle: std.os.windows.HANDLE) ?ResourceUsage {
    const windows = std.os.windows;
    const PROCESS_MEMORY_COUNTERS = extern struct {
        cb: windows.DWORD,
        PageFaultCount: windows.DWORD,
        PeakWorkingSetSize: windows.SIZE_T,
        WorkingSetSize: windows.SIZE_T,
        QuotaPeakPagedPoolUsage: windows.SIZE_T,
        QuotaPagedPoolUsage: windows.SIZE_T,
        QuotaPeakNonPagedPoolUsage: windows.SIZE_T,
        QuotaNonPagedPoolUsage: windows.SIZE_T,
        PagefileUsage: windows.SIZE_T,
        PeakPagefileUsage: windows.SIZE_T,
    };

    const FILETIME = extern struct {
        dwLowDateTime: windows.DWORD,
        dwHighDateTime: windows.DWORD,
    };

    const GetProcessMemoryInfo = @extern(*const fn (
        windows.HANDLE,
        *PROCESS_MEMORY_COUNTERS,
        windows.DWORD,
    ) callconv(.c) windows.BOOL, .{ .name = "GetProcessMemoryInfo" });

    const GetProcessTimes = @extern(*const fn (
        windows.HANDLE,
        *FILETIME,
        *FILETIME,
        *FILETIME,
        *FILETIME,
    ) callconv(.c) windows.BOOL, .{ .name = "GetProcessTimes" });

    var mem_counters: PROCESS_MEMORY_COUNTERS = undefined;
    mem_counters.cb = @sizeOf(PROCESS_MEMORY_COUNTERS);

    // Get memory info
    if (GetProcessMemoryInfo(handle, &mem_counters, @sizeOf(PROCESS_MEMORY_COUNTERS)) == 0) {
        return null;
    }

    // Get CPU times
    var creation_time: FILETIME = undefined;
    var exit_time: FILETIME = undefined;
    var kernel_time: FILETIME = undefined;
    var user_time: FILETIME = undefined;

    if (GetProcessTimes(handle, &creation_time, &exit_time, &kernel_time, &user_time) == 0) {
        return null;
    }

    var usage = ResourceUsage{};
    usage.rss_bytes = mem_counters.WorkingSetSize;

    // Convert FILETIME (100ns intervals since 1601) to nanoseconds
    const user_ns = (@as(u64, user_time.dwHighDateTime) << 32 | user_time.dwLowDateTime) * 100;
    const kernel_ns = (@as(u64, kernel_time.dwHighDateTime) << 32 | kernel_time.dwLowDateTime) * 100;
    usage.cpu_time_ns = user_ns + kernel_ns;

    // CPU percent requires delta tracking, leave at 0
    usage.cpu_percent = 0.0;

    return usage;
}

/// Monitor resource usage of a child process (non-blocking).
/// This is a stub for Phase 3 implementation.
pub const ResourceMonitor = struct {
    pid: if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.posix.pid_t,
    max_cpu_cores: ?u32,
    max_memory_bytes: ?u64,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        pid: if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.posix.pid_t,
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

/// Hard resource limit enforcement using OS-specific mechanisms.
/// This provides kernel-level enforcement (not polling).
pub const HardLimitConfig = struct {
    max_memory_bytes: ?u64 = null,
    max_cpu_cores: ?u32 = null,
};

/// Platform-specific hard limit handle.
/// - Linux: cgroup path (must be cleaned up)
/// - Windows: Job Object handle (must be closed)
/// - macOS: null (no hard limits available)
pub const HardLimitHandle = switch (builtin.os.tag) {
    .linux => struct {
        cgroup_path: ?[]const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *@This()) void {
            if (self.cgroup_path) |path| {
                // Best-effort cleanup: remove cgroup directory
                std.fs.deleteTreeAbsolute(path) catch {};
                self.allocator.free(path);
            }
        }
    },
    .windows => struct {
        job_handle: ?std.os.windows.HANDLE,

        pub fn deinit(self: *@This()) void {
            if (self.job_handle) |handle| {
                const windows = std.os.windows;
                const CloseHandle = @extern(*const fn (windows.HANDLE) callconv(.c) windows.BOOL, .{ .name = "CloseHandle" });
                _ = CloseHandle(handle);
            }
        }
    },
    else => struct {
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    },
};

/// Create hard resource limits for a process (must be called BEFORE spawning).
/// Returns a handle that must be cleaned up with deinit().
pub fn createHardLimits(allocator: std.mem.Allocator, config: HardLimitConfig) !HardLimitHandle {
    switch (comptime builtin.os.tag) {
        .linux => return createCgroupV2(allocator, config),
        .windows => return createJobObject(config),
        else => return HardLimitHandle{}, // No-op for macOS and others
    }
}

/// Apply hard limits to a spawned process.
/// Must be called AFTER process spawn but BEFORE exec.
pub fn applyHardLimits(handle: *HardLimitHandle, pid: anytype) !void {
    switch (comptime builtin.os.tag) {
        .linux => try applyLinuxCgroup(handle, pid),
        .windows => try applyWindowsJob(handle, pid),
        else => {}, // No-op for macOS
    }
}

// ============================================================================
// Linux cgroups v2 implementation
// ============================================================================

fn createCgroupV2(allocator: std.mem.Allocator, config: HardLimitConfig) !HardLimitHandle {
    if (config.max_memory_bytes == null and config.max_cpu_cores == null) {
        return HardLimitHandle{ .cgroup_path = null, .allocator = allocator };
    }

    // Create a unique cgroup path under /sys/fs/cgroup/zr/
    const cgroup_base = "/sys/fs/cgroup/zr";

    // Try to create base directory (may already exist)
    std.fs.makeDirAbsolute(cgroup_base) catch |err| {
        if (err != error.PathAlreadyExists) {
            // If we can't create the base cgroup, fall back to soft limits
            return HardLimitHandle{ .cgroup_path = null, .allocator = allocator };
        }
    };

    // Create unique subdirectory using timestamp + random
    const timestamp = std.time.milliTimestamp();
    var prng = std.Random.DefaultPrng.init(@intCast(timestamp));
    const random = prng.random();
    const rand_suffix = random.int(u32);

    const cgroup_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{d}-{x}",
        .{ cgroup_base, timestamp, rand_suffix },
    );
    errdefer allocator.free(cgroup_path);

    // Create the cgroup directory
    std.fs.makeDirAbsolute(cgroup_path) catch |err| {
        allocator.free(cgroup_path);
        // Fall back to soft limits if cgroup creation fails
        if (err == error.AccessDenied) {
            return HardLimitHandle{ .cgroup_path = null, .allocator = allocator };
        }
        return err;
    };

    // Set memory limit if specified
    if (config.max_memory_bytes) |limit| {
        const memory_max_path = try std.fmt.allocPrint(allocator, "{s}/memory.max", .{cgroup_path});
        defer allocator.free(memory_max_path);

        const limit_str = try std.fmt.allocPrint(allocator, "{d}\n", .{limit});
        defer allocator.free(limit_str);

        const file = std.fs.openFileAbsolute(memory_max_path, .{ .mode = .write_only }) catch |err| {
            // Clean up cgroup on failure
            std.fs.deleteTreeAbsolute(cgroup_path) catch {};
            allocator.free(cgroup_path);
            if (err == error.AccessDenied) {
                return HardLimitHandle{ .cgroup_path = null, .allocator = allocator };
            }
            return err;
        };
        defer file.close();

        file.writeAll(limit_str) catch |err| {
            std.fs.deleteTreeAbsolute(cgroup_path) catch {};
            allocator.free(cgroup_path);
            return err;
        };
    }

    // Set CPU limit if specified (cpu.max format: "$MAX $PERIOD")
    // e.g., "100000 100000" = 1 core, "200000 100000" = 2 cores
    if (config.max_cpu_cores) |cores| {
        const cpu_max_path = try std.fmt.allocPrint(allocator, "{s}/cpu.max", .{cgroup_path});
        defer allocator.free(cpu_max_path);

        const period: u64 = 100000; // 100ms period (standard)
        const quota = cores * period;
        const limit_str = try std.fmt.allocPrint(allocator, "{d} {d}\n", .{ quota, period });
        defer allocator.free(limit_str);

        const file = std.fs.openFileAbsolute(cpu_max_path, .{ .mode = .write_only }) catch |err| {
            std.fs.deleteTreeAbsolute(cgroup_path) catch {};
            allocator.free(cgroup_path);
            if (err == error.AccessDenied) {
                return HardLimitHandle{ .cgroup_path = null, .allocator = allocator };
            }
            return err;
        };
        defer file.close();

        file.writeAll(limit_str) catch |err| {
            std.fs.deleteTreeAbsolute(cgroup_path) catch {};
            allocator.free(cgroup_path);
            return err;
        };
    }

    return HardLimitHandle{ .cgroup_path = cgroup_path, .allocator = allocator };
}

fn applyLinuxCgroup(handle: *HardLimitHandle, pid: std.posix.pid_t) !void {
    if (handle.cgroup_path == null) return; // Soft limits fallback

    const cgroup_path = handle.cgroup_path.?;
    const procs_path = try std.fmt.allocPrint(
        handle.allocator,
        "{s}/cgroup.procs",
        .{cgroup_path},
    );
    defer handle.allocator.free(procs_path);

    const pid_str = try std.fmt.allocPrint(handle.allocator, "{d}\n", .{pid});
    defer handle.allocator.free(pid_str);

    const file = try std.fs.openFileAbsolute(procs_path, .{ .mode = .write_only });
    defer file.close();

    try file.writeAll(pid_str);
}

// ============================================================================
// Windows Job Objects implementation
// ============================================================================

fn createJobObject(config: HardLimitConfig) !HardLimitHandle {
    if (comptime builtin.os.tag != .windows) unreachable;

    if (config.max_memory_bytes == null and config.max_cpu_cores == null) {
        return HardLimitHandle{ .job_handle = null };
    }

    const windows = std.os.windows;

    const CreateJobObjectW = @extern(*const fn (
        ?*anyopaque,
        ?[*:0]const u16,
    ) callconv(.c) ?windows.HANDLE, .{ .name = "CreateJobObjectW" });

    const SetInformationJobObject = @extern(*const fn (
        windows.HANDLE,
        windows.DWORD,
        ?*const anyopaque,
        windows.DWORD,
    ) callconv(.c) windows.BOOL, .{ .name = "SetInformationJobObject" });

    const job_handle = CreateJobObjectW(null, null) orelse {
        return HardLimitHandle{ .job_handle = null }; // Fallback to soft limits
    };
    errdefer {
        const CloseHandle = @extern(*const fn (windows.HANDLE) callconv(.c) windows.BOOL, .{ .name = "CloseHandle" });
        _ = CloseHandle(job_handle);
    }

    // Set memory limit if specified
    if (config.max_memory_bytes) |limit| {
        const JOBOBJECT_EXTENDED_LIMIT_INFORMATION = extern struct {
            BasicLimitInformation: extern struct {
                PerProcessUserTimeLimit: i64,
                PerJobUserTimeLimit: i64,
                LimitFlags: windows.DWORD,
                MinimumWorkingSetSize: windows.SIZE_T,
                MaximumWorkingSetSize: windows.SIZE_T,
                ActiveProcessLimit: windows.DWORD,
                Affinity: windows.ULONG_PTR,
                PriorityClass: windows.DWORD,
                SchedulingClass: windows.DWORD,
            },
            IoInfo: extern struct {
                ReadOperationCount: u64,
                WriteOperationCount: u64,
                OtherOperationCount: u64,
                ReadTransferCount: u64,
                WriteTransferCount: u64,
                OtherTransferCount: u64,
            },
            ProcessMemoryLimit: windows.SIZE_T,
            JobMemoryLimit: windows.SIZE_T,
            PeakProcessMemoryUsed: windows.SIZE_T,
            PeakJobMemoryUsed: windows.SIZE_T,
        };

        const JOB_OBJECT_LIMIT_PROCESS_MEMORY: windows.DWORD = 0x00000100;
        const JobObjectExtendedLimitInformation: windows.DWORD = 9;

        var limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std.mem.zeroes(JOBOBJECT_EXTENDED_LIMIT_INFORMATION);
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_PROCESS_MEMORY;
        limits.ProcessMemoryLimit = limit;

        const result = SetInformationJobObject(
            job_handle,
            JobObjectExtendedLimitInformation,
            &limits,
            @sizeOf(JOBOBJECT_EXTENDED_LIMIT_INFORMATION),
        );

        if (result == 0) {
            // If setting limits fails, close handle and fall back to soft limits
            const CloseHandle = @extern(*const fn (windows.HANDLE) callconv(.c) windows.BOOL, .{ .name = "CloseHandle" });
            _ = CloseHandle(job_handle);
            return HardLimitHandle{ .job_handle = null };
        }
    }

    // Note: CPU limit enforcement on Windows requires additional flags
    // and is more complex. For now, we focus on memory limits.
    // CPU can still be monitored via soft limits.
    _ = config.max_cpu_cores;

    return HardLimitHandle{ .job_handle = job_handle };
}

fn applyWindowsJob(handle: *HardLimitHandle, process_handle: std.os.windows.HANDLE) !void {
    if (comptime builtin.os.tag != .windows) unreachable;

    if (handle.job_handle == null) return; // Soft limits fallback

    const windows = std.os.windows;
    const AssignProcessToJobObject = @extern(*const fn (
        windows.HANDLE,
        windows.HANDLE,
    ) callconv(.c) windows.BOOL, .{ .name = "AssignProcessToJobObject" });

    const result = AssignProcessToJobObject(handle.job_handle.?, process_handle);
    if (result == 0) {
        return error.JobAssignmentFailed;
    }
}

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

test "getProcessUsage: self process (Windows)" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const GetCurrentProcess = @extern(*const fn () callconv(.c) windows.HANDLE, .{ .name = "GetCurrentProcess" });

    const self_handle = GetCurrentProcess();
    const usage = getProcessUsage(self_handle);

    // Should be able to read our own process stats
    try std.testing.expect(usage != null);

    if (usage) |u| {
        // Our process should have some memory
        try std.testing.expect(u.rss_bytes > 0);
        // CPU time should be non-negative (may be 0 for quick test)
        try std.testing.expect(u.cpu_time_ns >= 0);
    }
}

test "getProcessUsage: invalid handle returns null (Windows)" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    // Invalid handle (NULL)
    const invalid_handle: windows.HANDLE = @ptrFromInt(0);
    const usage = getProcessUsage(invalid_handle);
    try std.testing.expectEqual(@as(?ResourceUsage, null), usage);
}

test "HardLimitHandle: create and cleanup (Linux)" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // Test with memory limit only
    var handle = createHardLimits(allocator, .{
        .max_memory_bytes = 100 * 1024 * 1024, // 100MB
        .max_cpu_cores = null,
    }) catch {
        // If we don't have permission to create cgroups, skip test
        return error.SkipZigTest;
    };
    defer handle.deinit();

    // If cgroup creation succeeded, path should be non-null
    // (or null if we fell back to soft limits due to permissions)
    if (handle.cgroup_path) |path| {
        // Verify cgroup directory exists
        const dir = std.fs.openDirAbsolute(path, .{}) catch {
            try std.testing.expect(false); // Should exist
            return;
        };
        dir.close();
    }
}

test "HardLimitHandle: create with no limits returns no-op handle" {
    const allocator = std.testing.allocator;

    var handle = try createHardLimits(allocator, .{
        .max_memory_bytes = null,
        .max_cpu_cores = null,
    });
    defer handle.deinit();

    // Should return a no-op handle (null cgroup_path on Linux, null job_handle on Windows)
    if (comptime builtin.os.tag == .linux) {
        try std.testing.expectEqual(@as(?[]const u8, null), handle.cgroup_path);
    } else if (comptime builtin.os.tag == .windows) {
        try std.testing.expectEqual(@as(?std.os.windows.HANDLE, null), handle.job_handle);
    }
}

test "HardLimitHandle: create and cleanup (Windows)" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // Test with memory limit only
    var handle = try createHardLimits(allocator, .{
        .max_memory_bytes = 100 * 1024 * 1024, // 100MB
        .max_cpu_cores = null,
    });
    defer handle.deinit();

    // Job handle should be created
    try std.testing.expect(handle.job_handle != null);
}
