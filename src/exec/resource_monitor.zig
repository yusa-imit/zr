const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("../util/platform.zig");

/// Resource usage metrics for a single task
pub const ResourceMetrics = struct {
    /// Peak memory usage in bytes
    peak_memory_bytes: u64,
    /// Average CPU usage percentage (0-100)
    avg_cpu_percent: f64,
    /// Total I/O operations (reads + writes)
    total_io_ops: u64,
    /// Timestamp when metrics were collected
    timestamp_ms: i64,
};

/// Real-time resource monitor for tracking task execution metrics
pub const ResourceMonitor = struct {
    allocator: Allocator,
    /// Circular buffer for storing recent metrics
    metrics_buffer: std.ArrayListUnmanaged(ResourceMetrics),
    /// Maximum number of metrics to keep in buffer
    max_buffer_size: usize,
    /// Current monitoring state
    is_monitoring: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, max_buffer_size: usize) !Self {
        return Self{
            .allocator = allocator,
            .metrics_buffer = .{},
            .max_buffer_size = max_buffer_size,
            .is_monitoring = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.metrics_buffer.deinit(self.allocator);
    }

    /// Start monitoring a task
    pub fn startMonitoring(self: *Self) void {
        self.is_monitoring = true;
    }

    /// Stop monitoring and return final metrics
    pub fn stopMonitoring(self: *Self) void {
        self.is_monitoring = false;
    }

    /// Record a metrics snapshot
    pub fn recordMetrics(self: *Self, metrics: ResourceMetrics) !void {
        if (!self.is_monitoring) return;

        // Add to circular buffer
        if (self.metrics_buffer.items.len >= self.max_buffer_size) {
            // Remove oldest item (FIFO)
            _ = self.metrics_buffer.orderedRemove(0);
        }

        try self.metrics_buffer.append(self.allocator, metrics);
    }

    /// Get all metrics in the buffer
    pub fn getMetrics(self: *const Self) []const ResourceMetrics {
        return self.metrics_buffer.items;
    }

    /// Get the latest metrics snapshot
    pub fn getLatestMetrics(self: *const Self) ?ResourceMetrics {
        if (self.metrics_buffer.items.len == 0) return null;
        return self.metrics_buffer.items[self.metrics_buffer.items.len - 1];
    }

    /// Calculate average metrics across all recorded snapshots
    pub fn getAverageMetrics(self: *const Self) ?ResourceMetrics {
        if (self.metrics_buffer.items.len == 0) return null;

        var total_memory: u64 = 0;
        var total_cpu: f64 = 0.0;
        var total_io: u64 = 0;
        var latest_timestamp: i64 = 0;

        for (self.metrics_buffer.items) |m| {
            total_memory += m.peak_memory_bytes;
            total_cpu += m.avg_cpu_percent;
            total_io += m.total_io_ops;
            if (m.timestamp_ms > latest_timestamp) {
                latest_timestamp = m.timestamp_ms;
            }
        }

        const count: f64 = @floatFromInt(self.metrics_buffer.items.len);
        return ResourceMetrics{
            .peak_memory_bytes = @intFromFloat(@as(f64, @floatFromInt(total_memory)) / count),
            .avg_cpu_percent = total_cpu / count,
            .total_io_ops = @intFromFloat(@as(f64, @floatFromInt(total_io)) / count),
            .timestamp_ms = latest_timestamp,
        };
    }

    /// Clear all recorded metrics
    pub fn clearMetrics(self: *Self) void {
        self.metrics_buffer.clearRetainingCapacity();
    }
};

/// Collect current system resource metrics for a process
pub fn collectProcessMetrics(allocator: Allocator, pid: std.posix.pid_t) !ResourceMetrics {
    const builtin = @import("builtin");
    const now = std.time.milliTimestamp();

    const os_tag = builtin.os.tag;

    if (os_tag == .linux) {
        return collectLinuxMetrics(allocator, pid, now);
    } else if (os_tag == .macos) {
        return collectMacOSMetrics(allocator, pid, now);
    } else {
        // Unsupported platform - return zeros
        return ResourceMetrics{
            .peak_memory_bytes = 0,
            .avg_cpu_percent = 0.0,
            .total_io_ops = 0,
            .timestamp_ms = now,
        };
    }
}

/// Collect metrics on Linux using /proc filesystem
fn collectLinuxMetrics(allocator: Allocator, pid: std.posix.pid_t, now: i64) !ResourceMetrics {
    var peak_memory_bytes: u64 = 0;
    var total_io_ops: u64 = 0;

    // Try to read memory info from /proc/[pid]/status
    // Format: /proc/{pid}/status
    var pid_buf: [64]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{d}", .{pid});

    // Read /proc/[pid]/status for VmRSS (resident set size in KB)
    const status_path = try std.fs.path.join(allocator, &[_][]const u8{ "/proc", pid_str, "status" });
    defer allocator.free(status_path);

    if (std.fs.cwd().readFileAlloc(allocator, status_path, 64 * 1024)) |status_content| {
        defer allocator.free(status_content);
        // Try to get VmRSS (resident set size) - this is the current physical memory
        if (try extractStatusValue(status_content, "VmRSS:")) |vmrss_kb| {
            // Convert from KB to bytes
            peak_memory_bytes = vmrss_kb * 1024;
        }
    } else |_| {
        // Status file not available - return zeros gracefully
    }

    // Try to read I/O stats from /proc/[pid]/io
    const io_path = try std.fs.path.join(allocator, &[_][]const u8{ "/proc", pid_str, "io" });
    defer allocator.free(io_path);

    if (std.fs.cwd().readFileAlloc(allocator, io_path, 8 * 1024)) |io_content| {
        defer allocator.free(io_content);
        // Parse rchar (read chars) and wchar (write chars)
        if (try extractStatusValue(io_content, "rchar:")) |rchar| {
            if (try extractStatusValue(io_content, "wchar:")) |wchar| {
                total_io_ops = rchar + wchar;
            }
        }
    } else |_| {
        // I/O file not available - return zero gracefully
    }

    // TODO: CPU percentage calculation requires tracking previous measurements
    // For now, return 0.0 - would need a baseline measurement and elapsed time
    // to calculate CPU time delta and convert to percentage.
    const avg_cpu_percent = 0.0;

    return ResourceMetrics{
        .peak_memory_bytes = peak_memory_bytes,
        .avg_cpu_percent = avg_cpu_percent,
        .total_io_ops = total_io_ops,
        .timestamp_ms = now,
    };
}

/// Collect metrics on macOS using proc_pidinfo and task_info
fn collectMacOSMetrics(_: Allocator, pid: std.posix.pid_t, now: i64) !ResourceMetrics {
    // macOS uses libproc and mach APIs
    const c = @cImport({
        @cInclude("sys/proc_info.h");
        @cInclude("libproc.h");
        @cInclude("mach/mach.h");
        @cInclude("mach/task.h");
    });

    var peak_memory_bytes: u64 = 0;
    var total_io_ops: u64 = 0;

    // Get task port for the process
    var task: c.mach_port_t = undefined;
    const kr = c.task_for_pid(c.mach_task_self(), @intCast(pid), &task);

    if (kr == c.KERN_SUCCESS) {
        // Get task basic info (includes resident memory size)
        var info: c.mach_task_basic_info_data_t = undefined;
        var count: c.mach_msg_type_number_t = c.MACH_TASK_BASIC_INFO_COUNT;

        const info_kr = c.task_info(
            task,
            c.MACH_TASK_BASIC_INFO,
            @ptrCast(&info),
            &count,
        );

        if (info_kr == c.KERN_SUCCESS) {
            // resident_size is in bytes
            peak_memory_bytes = info.resident_size;
        }

        // Deallocate task port
        _ = c.mach_port_deallocate(c.mach_task_self(), task);
    }

    // Try to get I/O stats using proc_pidinfo with PROC_PIDTASKINFO
    var task_info: c.proc_taskinfo = undefined;
    const bytes_read = c.proc_pidinfo(
        pid,
        c.PROC_PIDTASKINFO,
        0,
        &task_info,
        @sizeOf(c.proc_taskinfo),
    );

    if (bytes_read == @sizeOf(c.proc_taskinfo)) {
        // task_info contains pti_total_user, pti_total_system (nanoseconds)
        // and pti_faults (page faults) - use faults as a proxy for I/O
        total_io_ops = task_info.pti_faults;
    }

    // TODO: CPU percentage calculation requires tracking previous measurements
    const avg_cpu_percent = 0.0;

    return ResourceMetrics{
        .peak_memory_bytes = peak_memory_bytes,
        .avg_cpu_percent = avg_cpu_percent,
        .total_io_ops = total_io_ops,
        .timestamp_ms = now,
    };
}

test "ResourceMonitor: init and deinit" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    try std.testing.expect(!monitor.is_monitoring);
    try std.testing.expectEqual(@as(usize, 10), monitor.max_buffer_size);
}

test "ResourceMonitor: start and stop monitoring" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    monitor.startMonitoring();
    try std.testing.expect(monitor.is_monitoring);

    monitor.stopMonitoring();
    try std.testing.expect(!monitor.is_monitoring);
}

test "ResourceMonitor: record metrics" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    monitor.startMonitoring();

    const metrics = ResourceMetrics{
        .peak_memory_bytes = 1024 * 1024,
        .avg_cpu_percent = 50.0,
        .total_io_ops = 100,
        .timestamp_ms = std.time.milliTimestamp(),
    };

    try monitor.recordMetrics(metrics);

    const latest = monitor.getLatestMetrics();
    try std.testing.expect(latest != null);
    try std.testing.expectEqual(metrics.peak_memory_bytes, latest.?.peak_memory_bytes);
    try std.testing.expectEqual(metrics.avg_cpu_percent, latest.?.avg_cpu_percent);
}

test "ResourceMonitor: circular buffer overflow" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 3);
    defer monitor.deinit();

    monitor.startMonitoring();

    // Add 5 metrics (buffer size is 3)
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const metrics = ResourceMetrics{
            .peak_memory_bytes = i * 1024,
            .avg_cpu_percent = @floatFromInt(i * 10),
            .total_io_ops = i,
            .timestamp_ms = std.time.milliTimestamp(),
        };
        try monitor.recordMetrics(metrics);
    }

    // Should only have last 3 metrics
    const all_metrics = monitor.getMetrics();
    try std.testing.expectEqual(@as(usize, 3), all_metrics.len);

    // First item should be index 2 (oldest items removed)
    try std.testing.expectEqual(@as(u64, 2 * 1024), all_metrics[0].peak_memory_bytes);
}

test "ResourceMonitor: average metrics calculation" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    monitor.startMonitoring();

    // Add 3 metrics
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = 1000,
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = 2000,
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 3000,
        .avg_cpu_percent = 30.0,
        .total_io_ops = 300,
        .timestamp_ms = 3000,
    });

    const avg = monitor.getAverageMetrics();
    try std.testing.expect(avg != null);

    // Average should be (1000+2000+3000)/3 = 2000
    try std.testing.expectEqual(@as(u64, 2000), avg.?.peak_memory_bytes);
    // Average should be (10+20+30)/3 = 20
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), avg.?.avg_cpu_percent, 0.01);
    // Average should be (100+200+300)/3 = 200
    try std.testing.expectEqual(@as(u64, 200), avg.?.total_io_ops);
}

test "ResourceMonitor: clear metrics" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    monitor.startMonitoring();

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = std.time.milliTimestamp(),
    });

    try std.testing.expectEqual(@as(usize, 1), monitor.getMetrics().len);

    monitor.clearMetrics();
    try std.testing.expectEqual(@as(usize, 0), monitor.getMetrics().len);
}

// ============================================================================
// Linux /proc memory stats parsing tests
// ============================================================================

/// Helper function to extract a numeric value from /proc/meminfo format
/// Returns the value in KB, or null if not found
fn extractMemInfoValue(content: []const u8, key: []const u8) !?u64 {
    var lines = std.mem.tokenizeSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            var parts = std.mem.tokenizeSequence(u8, line, ":");
            _ = parts.next(); // Skip the key
            if (parts.next()) |value_part| {
                const trimmed = std.mem.trim(u8, value_part, " \t");
                // Remove "kB" suffix if present
                const numeric = std.mem.trim(u8, trimmed, "kB \t");
                return try std.fmt.parseInt(u64, numeric, 10);
            }
        }
    }
    return null;
}

/// Helper function to extract a numeric value from /proc/[pid]/status format
/// Returns the value (usually in KB for memory fields)
fn extractStatusValue(content: []const u8, key: []const u8) !?u64 {
    var lines = std.mem.tokenizeSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            // Extract the value part after the key and colon
            if (std.mem.indexOfScalar(u8, line, ':')) |colon_pos| {
                const value_part = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
                // Remove "kB" suffix if present
                const numeric = std.mem.trim(u8, value_part, "kB \t");
                return try std.fmt.parseInt(u64, numeric, 10);
            }
        }
    }
    return null;
}

/// Helper function to parse /proc/[pid]/stat for CPU times
/// Returns (utime, stime) tuple in jiffies
fn extractStatValues(content: []const u8) !?struct { utime: u64, stime: u64 } {
    // /proc/[pid]/stat format: pid (comm) state ppid pgrp session tty_nr ...
    // Fields 14-15 (1-indexed, so indices 13-14) are utime and stime
    var fields = std.mem.tokenizeSequence(u8, content, " ");

    var field_count: usize = 0;
    var utime: u64 = 0;
    var stime: u64 = 0;

    while (fields.next()) |field| {
        if (field_count == 13) {
            utime = try std.fmt.parseInt(u64, field, 10);
        } else if (field_count == 14) {
            stime = try std.fmt.parseInt(u64, field, 10);
            break;
        }
        field_count += 1;
    }

    if (utime == 0 and stime == 0) return null;
    return .{ .utime = utime, .stime = stime };
}

test "parse /proc/meminfo: extract MemTotal" {
    const content =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
        \\MemAvailable:    12288000 kB
        \\Buffers:         1024000 kB
        \\Cached:          2048000 kB
    ;

    const value = try extractMemInfoValue(content, "MemTotal:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 16384000), value.?);
}

test "parse /proc/meminfo: extract MemFree" {
    const content =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
        \\MemAvailable:    12288000 kB
    ;

    const value = try extractMemInfoValue(content, "MemFree:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 8192000), value.?);
}

test "parse /proc/meminfo: extract MemAvailable" {
    const content =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
        \\MemAvailable:    12288000 kB
        \\Buffers:         1024000 kB
        \\Cached:          2048000 kB
        \\SwapTotal:       4096000 kB
        \\SwapFree:        2048000 kB
    ;

    const value = try extractMemInfoValue(content, "MemAvailable:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 12288000), value.?);
}

test "parse /proc/meminfo: extract SwapTotal" {
    const content =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
        \\SwapTotal:       4096000 kB
        \\SwapFree:        2048000 kB
    ;

    const value = try extractMemInfoValue(content, "SwapTotal:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 4096000), value.?);
}

test "parse /proc/meminfo: missing key returns null" {
    const content =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
    ;

    const value = try extractMemInfoValue(content, "SwapTotal:");
    try std.testing.expect(value == null);
}

test "parse /proc/meminfo: empty content returns null" {
    const content = "";

    const value = try extractMemInfoValue(content, "MemTotal:");
    try std.testing.expect(value == null);
}

test "parse /proc/[pid]/status: extract VmSize" {
    const content =
        \\Name:   bash
        \\State:  S (sleeping)
        \\Pid:    1234
        \\VmSize:        8192 kB
        \\VmRSS:         4096 kB
        \\VmPeak:        16384 kB
    ;

    const value = try extractStatusValue(content, "VmSize:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 8192), value.?);
}

test "parse /proc/[pid]/status: extract VmRSS" {
    const content =
        \\Name:   bash
        \\State:  S (sleeping)
        \\VmSize:        8192 kB
        \\VmRSS:         4096 kB
        \\VmPeak:        16384 kB
    ;

    const value = try extractStatusValue(content, "VmRSS:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 4096), value.?);
}

test "parse /proc/[pid]/status: extract VmPeak" {
    const content =
        \\Name:   bash
        \\VmSize:        8192 kB
        \\VmRSS:         4096 kB
        \\VmPeak:        16384 kB
    ;

    const value = try extractStatusValue(content, "VmPeak:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 16384), value.?);
}

test "parse /proc/[pid]/status: missing field returns null" {
    const content =
        \\Name:   bash
        \\VmSize:        8192 kB
        \\VmRSS:         4096 kB
    ;

    const value = try extractStatusValue(content, "VmPeak:");
    try std.testing.expect(value == null);
}

test "parse /proc/[pid]/stat: extract CPU times" {
    const content = "1234 (bash) S 1000 1234 1234 0 -1 4194304 2500 50 0 0 234 156 0 0 20 0 1 0 123456789 8388608 1024 18446744073709551615 4194304 4238788 140731488921296 140731488920256 140721632408421 0 0 0 65536 0 0 0 17 3 0 0 0 0 0";
    const result = try extractStatValues(content);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 234), result.?.utime);
    try std.testing.expectEqual(@as(u64, 156), result.?.stime);
}

test "parse /proc/[pid]/stat: malformed content returns null" {
    const content = "invalid stat data";

    const result = try extractStatValues(content);
    try std.testing.expect(result == null);
}

test "parse /proc/[pid]/stat: empty content returns null" {
    const content = "";

    const result = try extractStatValues(content);
    try std.testing.expect(result == null);
}

test "parse /proc/meminfo: extract Cached field" {
    const content =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
        \\Buffers:         1024000 kB
        \\Cached:          3072000 kB
    ;

    const value = try extractMemInfoValue(content, "Cached:");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u64, 3072000), value.?);
}

test "parse /proc/[pid]/status: handles tab separators correctly" {
    // Actual /proc/[pid]/status format uses tabs between label and value
    const content =
        \\Name:  bash
        \\Pid:   1234
        \\VmSize:        8192 kB
        \\VmRSS:         2048 kB
    ;

    const size = try extractStatusValue(content, "VmSize:");
    try std.testing.expect(size != null);
    try std.testing.expectEqual(@as(u64, 8192), size.?);

    const rss = try extractStatusValue(content, "VmRSS:");
    try std.testing.expect(rss != null);
    try std.testing.expectEqual(@as(u64, 2048), rss.?);
}
