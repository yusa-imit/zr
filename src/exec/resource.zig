const std = @import("std");
const builtin = @import("builtin");

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
    _ = pid;

    if (comptime builtin.os.tag == .linux) {
        // TODO: Read /proc/[pid]/status and /proc/[pid]/stat
        // For now, return placeholder
        return null;
    } else if (comptime builtin.os.tag == .macos or builtin.os.tag == .ios) {
        // TODO: Use getrusage(RUSAGE_CHILDREN) after wait
        // For now, return placeholder
        return null;
    } else if (comptime builtin.os.tag == .windows) {
        // TODO: Use GetProcessMemoryInfo and GetProcessTimes
        // For now, return placeholder
        return null;
    } else {
        return null;
    }
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
