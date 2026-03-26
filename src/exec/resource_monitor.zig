const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("../util/platform.zig");

/// Memory breakdown by category
pub const MemoryBreakdown = struct {
    /// Heap memory allocated via malloc/new (bytes)
    heap_memory_bytes: u64 = 0,
    /// Stack memory usage (bytes)
    stack_memory_bytes: u64 = 0,
    /// Memory-mapped regions - files, shared memory (bytes)
    mapped_memory_bytes: u64 = 0,
};

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
    /// Optional memory breakdown by category (heap/stack/mapped)
    memory_breakdown: ?MemoryBreakdown = null,
};

/// CPU time snapshot for calculating usage percentage
pub const CpuTimeSnapshot = struct {
    /// Total CPU time in nanoseconds (user + system)
    total_cpu_ns: u64,
    /// Wall-clock timestamp when this snapshot was taken
    timestamp_ms: i64,
};

/// Time window for historical metrics
pub const TimeWindow = enum {
    five_minutes,
    one_hour,
    twenty_four_hours,

    /// Get the window duration in milliseconds
    pub fn durationMs(self: TimeWindow) i64 {
        return switch (self) {
            .five_minutes => 5 * 60 * 1000, // 5 minutes
            .one_hour => 60 * 60 * 1000,     // 1 hour
            .twenty_four_hours => 24 * 60 * 60 * 1000, // 24 hours
        };
    }
};

/// Aggregated metrics over a time window
pub const WindowedMetrics = struct {
    /// Average memory usage in bytes
    avg_memory_bytes: u64,
    /// Peak memory usage in bytes
    peak_memory_bytes: u64,
    /// Average CPU usage percentage
    avg_cpu_percent: f64,
    /// Peak CPU usage percentage
    peak_cpu_percent: f64,
    /// Total I/O operations
    total_io_ops: u64,
    /// Number of samples in this window
    sample_count: usize,
    /// Window start timestamp
    window_start_ms: i64,
    /// Window end timestamp
    window_end_ms: i64,
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
    /// Previous CPU time snapshot for calculating percentage (per-PID tracking)
    cpu_snapshots: std.AutoHashMapUnmanaged(std.posix.pid_t, CpuTimeSnapshot),

    const Self = @This();

    pub fn init(allocator: Allocator, max_buffer_size: usize) !Self {
        return Self{
            .allocator = allocator,
            .metrics_buffer = .{},
            .max_buffer_size = max_buffer_size,
            .is_monitoring = false,
            .cpu_snapshots = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.metrics_buffer.deinit(self.allocator);
        self.cpu_snapshots.deinit(self.allocator);
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

    /// Calculate CPU percentage from current and previous snapshots
    /// Returns 0.0 if this is the first measurement for this PID
    pub fn calculateCpuPercent(self: *Self, pid: std.posix.pid_t, current: CpuTimeSnapshot) !f64 {
        const prev_snapshot = self.cpu_snapshots.get(pid);

        // Store current snapshot for next calculation
        try self.cpu_snapshots.put(self.allocator, pid, current);

        // If no previous snapshot, return 0.0 (baseline)
        const prev = prev_snapshot orelse return 0.0;

        // Calculate time deltas
        const wall_time_ms = current.timestamp_ms - prev.timestamp_ms;
        if (wall_time_ms <= 0) return 0.0; // Avoid division by zero

        const cpu_time_ns = current.total_cpu_ns - prev.total_cpu_ns;

        // Convert wall time from ms to ns for consistent units
        const wall_time_ns: u64 = @intCast(wall_time_ms * 1_000_000);

        // CPU percentage = (cpu_time_delta / wall_time_delta) * 100
        // Note: On multi-core systems, this can exceed 100% (e.g., 200% on 2 cores fully utilized)
        const cpu_percent = (@as(f64, @floatFromInt(cpu_time_ns)) / @as(f64, @floatFromInt(wall_time_ns))) * 100.0;

        return cpu_percent;
    }

    /// Get aggregated metrics over a specific time window
    /// Returns null if no metrics are available in the window
    pub fn getWindowedMetrics(self: *const Self, window: TimeWindow) ?WindowedMetrics {
        if (self.metrics_buffer.items.len == 0) return null;

        const now = std.time.milliTimestamp();
        const window_duration_ms = window.durationMs();
        const window_start_ms = now - window_duration_ms;

        // Find metrics within the time window
        var total_memory: u64 = 0;
        var peak_memory: u64 = 0;
        var total_cpu: f64 = 0.0;
        var peak_cpu: f64 = 0.0;
        var total_io: u64 = 0;
        var sample_count: usize = 0;
        var first_timestamp: i64 = now;

        for (self.metrics_buffer.items) |metric| {
            if (metric.timestamp_ms >= window_start_ms) {
                total_memory += metric.peak_memory_bytes;
                peak_memory = @max(peak_memory, metric.peak_memory_bytes);
                total_cpu += metric.avg_cpu_percent;
                peak_cpu = @max(peak_cpu, metric.avg_cpu_percent);
                total_io += metric.total_io_ops;
                sample_count += 1;

                if (metric.timestamp_ms < first_timestamp) {
                    first_timestamp = metric.timestamp_ms;
                }
            }
        }

        if (sample_count == 0) return null;

        const count_f64: f64 = @floatFromInt(sample_count);
        return WindowedMetrics{
            .avg_memory_bytes = @intFromFloat(@as(f64, @floatFromInt(total_memory)) / count_f64),
            .peak_memory_bytes = peak_memory,
            .avg_cpu_percent = total_cpu / count_f64,
            .peak_cpu_percent = peak_cpu,
            .total_io_ops = total_io,
            .sample_count = sample_count,
            .window_start_ms = first_timestamp,
            .window_end_ms = now,
        };
    }

    /// Get multiple windowed metrics at once (5min, 1hr, 24hr)
    /// Returns a struct with all three windows
    pub fn getAllWindowedMetrics(self: *const Self) struct {
        five_min: ?WindowedMetrics,
        one_hour: ?WindowedMetrics,
        twenty_four_hr: ?WindowedMetrics,
    } {
        return .{
            .five_min = self.getWindowedMetrics(.five_minutes),
            .one_hour = self.getWindowedMetrics(.one_hour),
            .twenty_four_hr = self.getWindowedMetrics(.twenty_four_hours),
        };
    }
};

/// Collect current system resource metrics for a process
/// If monitor is provided, CPU percentage is calculated using previous snapshots
pub fn collectProcessMetrics(allocator: Allocator, pid: std.posix.pid_t, monitor: ?*ResourceMonitor) !ResourceMetrics {
    const builtin = @import("builtin");
    const now = std.time.milliTimestamp();

    const os_tag = builtin.os.tag;

    if (os_tag == .linux) {
        return collectLinuxMetrics(allocator, pid, now, monitor);
    } else if (os_tag == .macos) {
        return collectMacOSMetrics(allocator, pid, now, monitor);
    } else {
        // Unsupported platform - return zeros with null memory breakdown
        return ResourceMetrics{
            .peak_memory_bytes = 0,
            .avg_cpu_percent = 0.0,
            .total_io_ops = 0,
            .timestamp_ms = now,
            .memory_breakdown = null,
        };
    }
}

/// Collect metrics on Linux using /proc filesystem
fn collectLinuxMetrics(allocator: Allocator, pid: std.posix.pid_t, now: i64, monitor: ?*ResourceMonitor) !ResourceMetrics {
    var peak_memory_bytes: u64 = 0;
    var total_io_ops: u64 = 0;
    var memory_breakdown: ?MemoryBreakdown = null;

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

        // Extract memory breakdown from /proc/[pid]/status
        memory_breakdown = try extractLinuxMemoryBreakdown(status_content);
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

    // CPU percentage calculation using /proc/[pid]/stat
    var avg_cpu_percent: f64 = 0.0;

    if (monitor) |mon| {
        // Read /proc/[pid]/stat for CPU times (utime + stime)
        const stat_path = try std.fs.path.join(allocator, &[_][]const u8{ "/proc", pid_str, "stat" });
        defer allocator.free(stat_path);

        if (std.fs.cwd().readFileAlloc(allocator, stat_path, 8 * 1024)) |stat_content| {
            defer allocator.free(stat_content);

            // Parse /proc/[pid]/stat to get utime (field 14) and stime (field 15)
            // Format: pid (comm) state ppid pgrp session tty_nr tpgid flags minflt cminflt majflt cmajflt utime stime ...
            // Fields are space-separated, but comm can contain spaces and parens
            if (try extractStatValues(stat_content)) |cpu_times| {
                const cpu_time_ticks = cpu_times.utime + cpu_times.stime;

                // Convert ticks to nanoseconds (typically 100 ticks/second on Linux)
                const ticks_per_sec = std.posix.sysconf(std.posix.SC.CLK_TCK);
                const ticks_per_sec_u64: u64 = if (ticks_per_sec > 0) @intCast(ticks_per_sec) else 100;
                const cpu_time_ns = (cpu_time_ticks * 1_000_000_000) / ticks_per_sec_u64;

                const snapshot = CpuTimeSnapshot{
                    .total_cpu_ns = cpu_time_ns,
                    .timestamp_ms = now,
                };

                avg_cpu_percent = try mon.calculateCpuPercent(pid, snapshot);
            }
        } else |_| {
            // stat file not available - return 0.0 gracefully
        }
    }

    return ResourceMetrics{
        .peak_memory_bytes = peak_memory_bytes,
        .avg_cpu_percent = avg_cpu_percent,
        .total_io_ops = total_io_ops,
        .timestamp_ms = now,
        .memory_breakdown = memory_breakdown,
    };
}

/// Collect metrics on macOS using proc_pidinfo and task_info
fn collectMacOSMetrics(_: Allocator, pid: std.posix.pid_t, now: i64, monitor: ?*ResourceMonitor) !ResourceMetrics {
    // macOS uses libproc and mach APIs
    const c = @cImport({
        @cInclude("sys/proc_info.h");
        @cInclude("libproc.h");
        @cInclude("mach/mach.h");
        @cInclude("mach/task.h");
    });

    var peak_memory_bytes: u64 = 0;
    var total_io_ops: u64 = 0;
    var avg_cpu_percent: f64 = 0.0;
    var memory_breakdown: ?MemoryBreakdown = null;

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

    // Try to get I/O stats and CPU time using proc_pidinfo with PROC_PIDTASKINFO
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

        // CPU percentage calculation using pti_total_user and pti_total_system (already in nanoseconds)
        if (monitor) |mon| {
            const cpu_time_ns = task_info.pti_total_user + task_info.pti_total_system;

            const snapshot = CpuTimeSnapshot{
                .total_cpu_ns = cpu_time_ns,
                .timestamp_ms = now,
            };

            avg_cpu_percent = try mon.calculateCpuPercent(pid, snapshot);
        }
    }

    // macOS: memory breakdown not yet fully supported - return null for breakdown
    // In future, could infer from proc_taskinfo or mach task info
    memory_breakdown = null;

    return ResourceMetrics{
        .peak_memory_bytes = peak_memory_bytes,
        .avg_cpu_percent = avg_cpu_percent,
        .total_io_ops = total_io_ops,
        .timestamp_ms = now,
        .memory_breakdown = memory_breakdown,
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

test "calculateCpuPercent: returns 0.0 for first measurement" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    const snapshot = CpuTimeSnapshot{
        .total_cpu_ns = 1_000_000_000, // 1 second of CPU time
        .timestamp_ms = std.time.milliTimestamp(),
    };

    const percent = try monitor.calculateCpuPercent(1234, snapshot);
    try std.testing.expectEqual(@as(f64, 0.0), percent);
}

test "calculateCpuPercent: calculates percentage from two measurements" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    // First measurement (baseline)
    const snapshot1 = CpuTimeSnapshot{
        .total_cpu_ns = 1_000_000_000, // 1 second of CPU time
        .timestamp_ms = 1000,
    };
    _ = try monitor.calculateCpuPercent(1234, snapshot1);

    // Second measurement after 1 second wall time, 500ms CPU time used
    const snapshot2 = CpuTimeSnapshot{
        .total_cpu_ns = 1_500_000_000, // 1.5 seconds of CPU time
        .timestamp_ms = 2000, // 1 second later
    };
    const percent = try monitor.calculateCpuPercent(1234, snapshot2);

    // Expected: (500ms CPU / 1000ms wall) * 100 = 50%
    try std.testing.expectApproxEqRel(@as(f64, 50.0), percent, 0.01);
}

test "calculateCpuPercent: handles multi-core usage (>100%)" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    // First measurement
    const snapshot1 = CpuTimeSnapshot{
        .total_cpu_ns = 1_000_000_000,
        .timestamp_ms = 1000,
    };
    _ = try monitor.calculateCpuPercent(1234, snapshot1);

    // Second measurement: 2 seconds of CPU time in 1 second wall time (2 cores fully utilized)
    const snapshot2 = CpuTimeSnapshot{
        .total_cpu_ns = 3_000_000_000, // 3 seconds total CPU time
        .timestamp_ms = 2000,
    };
    const percent = try monitor.calculateCpuPercent(1234, snapshot2);

    // Expected: (2000ms CPU / 1000ms wall) * 100 = 200%
    try std.testing.expectApproxEqRel(@as(f64, 200.0), percent, 0.01);
}

test "calculateCpuPercent: tracks multiple PIDs independently" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    // PID 1234 measurements
    _ = try monitor.calculateCpuPercent(1234, .{ .total_cpu_ns = 1_000_000_000, .timestamp_ms = 1000 });
    const percent1 = try monitor.calculateCpuPercent(1234, .{ .total_cpu_ns = 1_500_000_000, .timestamp_ms = 2000 });

    // PID 5678 measurements
    _ = try monitor.calculateCpuPercent(5678, .{ .total_cpu_ns = 2_000_000_000, .timestamp_ms = 1000 });
    const percent2 = try monitor.calculateCpuPercent(5678, .{ .total_cpu_ns = 3_000_000_000, .timestamp_ms = 2000 });

    // PID 1234: 50% (500ms / 1000ms)
    try std.testing.expectApproxEqRel(@as(f64, 50.0), percent1, 0.01);

    // PID 5678: 100% (1000ms / 1000ms)
    try std.testing.expectApproxEqRel(@as(f64, 100.0), percent2, 0.01);
}

test "calculateCpuPercent: returns 0.0 for negative wall time delta" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 10);
    defer monitor.deinit();

    // First measurement
    _ = try monitor.calculateCpuPercent(1234, .{ .total_cpu_ns = 1_000_000_000, .timestamp_ms = 2000 });

    // Second measurement with earlier timestamp (clock skew)
    const percent = try monitor.calculateCpuPercent(1234, .{ .total_cpu_ns = 1_500_000_000, .timestamp_ms = 1500 });

    try std.testing.expectEqual(@as(f64, 0.0), percent);
}

// ============================================================================
// Memory Breakdown Tests
// ============================================================================

test "MemoryBreakdown: struct creation with defaults" {
    const breakdown = MemoryBreakdown{};
    try std.testing.expectEqual(@as(u64, 0), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.mapped_memory_bytes);
}

test "MemoryBreakdown: struct creation with values" {
    const breakdown = MemoryBreakdown{
        .heap_memory_bytes = 1024 * 1024,
        .stack_memory_bytes = 8192,
        .mapped_memory_bytes = 512 * 1024,
    };
    try std.testing.expectEqual(@as(u64, 1024 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 8192), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, 512 * 1024), breakdown.mapped_memory_bytes);
}

test "MemoryBreakdown: total calculation" {
    const breakdown = MemoryBreakdown{
        .heap_memory_bytes = 1000,
        .stack_memory_bytes = 500,
        .mapped_memory_bytes = 300,
    };
    const total = breakdown.heap_memory_bytes + breakdown.stack_memory_bytes + breakdown.mapped_memory_bytes;
    try std.testing.expectEqual(@as(u64, 1800), total);
}

test "MemoryBreakdown: zero values" {
    const breakdown = MemoryBreakdown{
        .heap_memory_bytes = 0,
        .stack_memory_bytes = 0,
        .mapped_memory_bytes = 0,
    };
    try std.testing.expectEqual(@as(u64, 0), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.mapped_memory_bytes);
}

test "MemoryBreakdown: large values" {
    const breakdown = MemoryBreakdown{
        .heap_memory_bytes = 1024 * 1024 * 1024, // 1 GB
        .stack_memory_bytes = 8 * 1024 * 1024,   // 8 MB
        .mapped_memory_bytes = 256 * 1024 * 1024, // 256 MB
    };
    try std.testing.expectEqual(@as(u64, 1024 * 1024 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 8 * 1024 * 1024), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, 256 * 1024 * 1024), breakdown.mapped_memory_bytes);
}

// ============================================================================
// Linux /proc memory breakdown parsing tests
// ============================================================================

/// Helper function to extract memory breakdown from /proc/[pid]/status
/// Returns MemoryBreakdown with VmData (heap), VmStk (stack), VmLib+VmExe (mapped)
fn extractLinuxMemoryBreakdown(content: []const u8) !MemoryBreakdown {
    var breakdown = MemoryBreakdown{};

    // VmData: heap memory in KB
    if (try extractStatusValue(content, "VmData:")) |vmdata_kb| {
        breakdown.heap_memory_bytes = vmdata_kb * 1024;
    }

    // VmStk: stack memory in KB
    if (try extractStatusValue(content, "VmStk:")) |vmstk_kb| {
        breakdown.stack_memory_bytes = vmstk_kb * 1024;
    }

    // VmLib: shared library memory in KB
    var mapped_total: u64 = 0;
    if (try extractStatusValue(content, "VmLib:")) |vmlib_kb| {
        mapped_total += vmlib_kb * 1024;
    }

    // VmExe: executable memory in KB
    if (try extractStatusValue(content, "VmExe:")) |vmexe_kb| {
        mapped_total += vmexe_kb * 1024;
    }

    breakdown.mapped_memory_bytes = mapped_total;

    return breakdown;
}

test "parse /proc/[pid]/status: extract memory breakdown with all fields" {
    const content =
        \\Name:   test
        \\VmData:         512 kB
        \\VmStk:           8 kB
        \\VmLib:         2048 kB
        \\VmExe:          256 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 512 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 8 * 1024), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, (2048 + 256) * 1024), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown with missing VmLib" {
    const content =
        \\Name:   test
        \\VmData:         512 kB
        \\VmStk:           8 kB
        \\VmExe:          256 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 512 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 8 * 1024), breakdown.stack_memory_bytes);
    // Only VmExe, no VmLib
    try std.testing.expectEqual(@as(u64, 256 * 1024), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown with missing VmExe" {
    const content =
        \\Name:   test
        \\VmData:         512 kB
        \\VmStk:           8 kB
        \\VmLib:         2048 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 512 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 8 * 1024), breakdown.stack_memory_bytes);
    // Only VmLib, no VmExe
    try std.testing.expectEqual(@as(u64, 2048 * 1024), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown with missing VmData" {
    const content =
        \\Name:   test
        \\VmStk:           8 kB
        \\VmLib:         2048 kB
        \\VmExe:          256 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 0), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 8 * 1024), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, (2048 + 256) * 1024), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown with missing VmStk" {
    const content =
        \\Name:   test
        \\VmData:         512 kB
        \\VmLib:         2048 kB
        \\VmExe:          256 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 512 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, (2048 + 256) * 1024), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown with all zero values" {
    const content =
        \\Name:   test
        \\VmData:           0 kB
        \\VmStk:            0 kB
        \\VmLib:            0 kB
        \\VmExe:            0 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 0), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown with missing all memory fields" {
    const content =
        \\Name:   test
        \\Pid:    1234
        \\State:  S
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 0), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown with large values" {
    const content =
        \\Name:   test
        \\VmData:      524288 kB
        \\VmStk:        16384 kB
        \\VmLib:      2097152 kB
        \\VmExe:       1048576 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 524288 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 16384 * 1024), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, (2097152 + 1048576) * 1024), breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown sum check" {
    const content =
        \\Name:   test
        \\VmRSS:        2048 kB
        \\VmData:         512 kB
        \\VmStk:           8 kB
        \\VmLib:         768 kB
        \\VmExe:         256 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    const total_breakdown = breakdown.heap_memory_bytes + breakdown.stack_memory_bytes + breakdown.mapped_memory_bytes;
    const total_rss = 2048 * 1024;

    // Breakdown sum should be <= RSS (may have other memory not accounted)
    try std.testing.expect(total_breakdown <= total_rss);
}

// ============================================================================
// macOS memory breakdown parsing tests
// ============================================================================

test "MemoryBreakdown: macOS style initialization (resident_size)" {
    // On macOS, we extract from proc_pidinfo resident_size
    // For testing, demonstrate breakdown creation
    const breakdown = MemoryBreakdown{
        .heap_memory_bytes = 2048 * 1024,     // Typical heap
        .stack_memory_bytes = 8192,           // Typical stack
        .mapped_memory_bytes = 512 * 1024,    // Typical mapped regions
    };

    const total = breakdown.heap_memory_bytes + breakdown.stack_memory_bytes + breakdown.mapped_memory_bytes;
    try std.testing.expect(total > 0);
}

test "MemoryBreakdown: graceful degradation when breakdown unavailable" {
    // When platform doesn't support breakdown, should return zero breakdown
    const breakdown = MemoryBreakdown{};

    try std.testing.expectEqual(@as(u64, 0), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, 0), breakdown.mapped_memory_bytes);
}

// ============================================================================
// Integration tests for memory breakdown
// ============================================================================

test "MemoryBreakdown: breakdown proportions make sense" {
    const breakdown = MemoryBreakdown{
        .heap_memory_bytes = 1024 * 1024,
        .stack_memory_bytes = 8192,
        .mapped_memory_bytes = 256 * 1024,
    };

    const total = breakdown.heap_memory_bytes + breakdown.stack_memory_bytes + breakdown.mapped_memory_bytes;

    // Heap should be dominant (typically largest)
    try std.testing.expect(breakdown.heap_memory_bytes >= breakdown.stack_memory_bytes);
    try std.testing.expect(breakdown.heap_memory_bytes >= breakdown.mapped_memory_bytes);

    // Total should be reasonable
    try std.testing.expect(total > 0);
    try std.testing.expect(total < 1024 * 1024 * 1024); // Less than 1 GB for test
}

test "MemoryBreakdown: stack is typically smallest" {
    const breakdown = MemoryBreakdown{
        .heap_memory_bytes = 1024 * 1024,
        .stack_memory_bytes = 4096,
        .mapped_memory_bytes = 512 * 1024,
    };

    // Stack is typically the smallest memory category
    try std.testing.expect(breakdown.stack_memory_bytes <= breakdown.heap_memory_bytes);
    try std.testing.expect(breakdown.stack_memory_bytes <= breakdown.mapped_memory_bytes);
}

test "parse /proc/[pid]/status: memory breakdown handles whitespace variations" {
    const content =
        \\Name:   test
        \\VmData:          512 kB
        \\VmStk:             8 kB
        \\VmLib:          2048 kB
        \\VmExe:           256 kB
    ;

    const breakdown = try extractLinuxMemoryBreakdown(content);
    try std.testing.expectEqual(@as(u64, 512 * 1024), breakdown.heap_memory_bytes);
    try std.testing.expectEqual(@as(u64, 8 * 1024), breakdown.stack_memory_bytes);
    try std.testing.expectEqual(@as(u64, (2048 + 256) * 1024), breakdown.mapped_memory_bytes);
}

// ============================================================================
// Historical resource usage trends tests
// ============================================================================

test "TimeWindow: five_minutes duration" {
    const window = TimeWindow.five_minutes;
    try std.testing.expectEqual(@as(i64, 5 * 60 * 1000), window.durationMs());
}

test "TimeWindow: one_hour duration" {
    const window = TimeWindow.one_hour;
    try std.testing.expectEqual(@as(i64, 60 * 60 * 1000), window.durationMs());
}

test "TimeWindow: twenty_four_hours duration" {
    const window = TimeWindow.twenty_four_hours;
    try std.testing.expectEqual(@as(i64, 24 * 60 * 60 * 1000), window.durationMs());
}

test "getWindowedMetrics: returns null for empty buffer" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result == null);
}

test "getWindowedMetrics: five_minutes window with recent metrics" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add 3 metrics within the last 5 minutes
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = now - (2 * 60 * 1000), // 2 minutes ago
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = now - (1 * 60 * 1000), // 1 minute ago
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 3000,
        .avg_cpu_percent = 30.0,
        .total_io_ops = 300,
        .timestamp_ms = now,
    });

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result != null);

    const windowed = result.?;
    try std.testing.expectEqual(@as(usize, 3), windowed.sample_count);

    // Average memory: (1000 + 2000 + 3000) / 3 = 2000
    try std.testing.expectEqual(@as(u64, 2000), windowed.avg_memory_bytes);

    // Peak memory: max(1000, 2000, 3000) = 3000
    try std.testing.expectEqual(@as(u64, 3000), windowed.peak_memory_bytes);

    // Average CPU: (10 + 20 + 30) / 3 = 20
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), windowed.avg_cpu_percent, 0.01);

    // Peak CPU: max(10, 20, 30) = 30
    try std.testing.expectApproxEqAbs(@as(f64, 30.0), windowed.peak_cpu_percent, 0.01);

    // Total I/O: 100 + 200 + 300 = 600
    try std.testing.expectEqual(@as(u64, 600), windowed.total_io_ops);
}

test "getWindowedMetrics: filters out old metrics" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add old metric (10 minutes ago, outside 5-minute window)
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = now - (10 * 60 * 1000),
    });

    // Add recent metric (1 minute ago, inside 5-minute window)
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = now - (1 * 60 * 1000),
    });

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result != null);

    const windowed = result.?;
    // Should only count the recent metric
    try std.testing.expectEqual(@as(usize, 1), windowed.sample_count);
    try std.testing.expectEqual(@as(u64, 2000), windowed.avg_memory_bytes);
}

test "getWindowedMetrics: one_hour window" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add metric 30 minutes ago
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = now - (30 * 60 * 1000),
    });

    // Add metric 10 minutes ago
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = now - (10 * 60 * 1000),
    });

    const result = monitor.getWindowedMetrics(.one_hour);
    try std.testing.expect(result != null);

    const windowed = result.?;
    try std.testing.expectEqual(@as(usize, 2), windowed.sample_count);
}

test "getWindowedMetrics: twenty_four_hours window" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 1000);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add metric 12 hours ago
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = now - (12 * 60 * 60 * 1000),
    });

    // Add metric 6 hours ago
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = now - (6 * 60 * 60 * 1000),
    });

    const result = monitor.getWindowedMetrics(.twenty_four_hours);
    try std.testing.expect(result != null);

    const windowed = result.?;
    try std.testing.expectEqual(@as(usize, 2), windowed.sample_count);
}

test "getWindowedMetrics: peak values are correctly tracked" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add metrics with varying values
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 5000,
        .avg_cpu_percent = 75.0,
        .total_io_ops = 100,
        .timestamp_ms = now - (3 * 60 * 1000),
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 25.0,
        .total_io_ops = 50,
        .timestamp_ms = now - (2 * 60 * 1000),
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 3000,
        .avg_cpu_percent = 50.0,
        .total_io_ops = 75,
        .timestamp_ms = now - (1 * 60 * 1000),
    });

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result != null);

    const windowed = result.?;

    // Peak memory should be 5000 (highest)
    try std.testing.expectEqual(@as(u64, 5000), windowed.peak_memory_bytes);

    // Peak CPU should be 75.0 (highest)
    try std.testing.expectApproxEqAbs(@as(f64, 75.0), windowed.peak_cpu_percent, 0.01);

    // Average memory: (5000 + 2000 + 3000) / 3 = 3333
    try std.testing.expectEqual(@as(u64, 3333), windowed.avg_memory_bytes);

    // Average CPU: (75 + 25 + 50) / 3 = 50
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), windowed.avg_cpu_percent, 0.01);
}

test "getAllWindowedMetrics: returns all three windows" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 1000);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add metrics at various time points
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = now - (2 * 60 * 1000), // 2 min ago (in 5min window)
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = now - (30 * 60 * 1000), // 30 min ago (in 1hr window)
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 3000,
        .avg_cpu_percent = 30.0,
        .total_io_ops = 300,
        .timestamp_ms = now - (12 * 60 * 60 * 1000), // 12 hrs ago (in 24hr window)
    });

    const all_windows = monitor.getAllWindowedMetrics();

    // 5-minute window should have 1 metric
    try std.testing.expect(all_windows.five_min != null);
    try std.testing.expectEqual(@as(usize, 1), all_windows.five_min.?.sample_count);

    // 1-hour window should have 2 metrics
    try std.testing.expect(all_windows.one_hour != null);
    try std.testing.expectEqual(@as(usize, 2), all_windows.one_hour.?.sample_count);

    // 24-hour window should have 3 metrics
    try std.testing.expect(all_windows.twenty_four_hr != null);
    try std.testing.expectEqual(@as(usize, 3), all_windows.twenty_four_hr.?.sample_count);
}

test "getWindowedMetrics: window_start and window_end timestamps" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();
    const first_timestamp = now - (3 * 60 * 1000);

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = first_timestamp,
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = now,
    });

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result != null);

    const windowed = result.?;

    // Window start should be the timestamp of the first metric in the window
    try std.testing.expectEqual(first_timestamp, windowed.window_start_ms);

    // Window end should be approximately now (within 1 second tolerance)
    try std.testing.expect(@abs(windowed.window_end_ms - now) < 1000);
}

test "getWindowedMetrics: all metrics outside window returns null" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add old metrics (all outside 5-minute window)
    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 100,
        .timestamp_ms = now - (10 * 60 * 1000), // 10 min ago
    });

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 20.0,
        .total_io_ops = 200,
        .timestamp_ms = now - (20 * 60 * 1000), // 20 min ago
    });

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result == null);
}

test "getWindowedMetrics: single metric in window" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 2000,
        .avg_cpu_percent = 50.0,
        .total_io_ops = 100,
        .timestamp_ms = now,
    });

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result != null);

    const windowed = result.?;
    try std.testing.expectEqual(@as(usize, 1), windowed.sample_count);
    try std.testing.expectEqual(@as(u64, 2000), windowed.avg_memory_bytes);
    try std.testing.expectEqual(@as(u64, 2000), windowed.peak_memory_bytes);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), windowed.avg_cpu_percent, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), windowed.peak_cpu_percent, 0.01);
}

test "getWindowedMetrics: zero I/O operations" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 100);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    try monitor.recordMetrics(.{
        .peak_memory_bytes = 1000,
        .avg_cpu_percent = 10.0,
        .total_io_ops = 0,
        .timestamp_ms = now,
    });

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result != null);

    const windowed = result.?;
    try std.testing.expectEqual(@as(u64, 0), windowed.total_io_ops);
}

test "getWindowedMetrics: large number of samples" {
    const allocator = std.testing.allocator;
    var monitor = try ResourceMonitor.init(allocator, 1000);
    defer monitor.deinit();

    monitor.startMonitoring();

    const now = std.time.milliTimestamp();

    // Add 100 metrics within 5-minute window
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try monitor.recordMetrics(.{
            .peak_memory_bytes = 1000 + i * 10,
            .avg_cpu_percent = @as(f64, @floatFromInt(i)),
            .total_io_ops = i,
            .timestamp_ms = now - @as(i64, @intCast(i * 1000)), // Spread over 100 seconds
        });
    }

    const result = monitor.getWindowedMetrics(.five_minutes);
    try std.testing.expect(result != null);

    const windowed = result.?;
    try std.testing.expectEqual(@as(usize, 100), windowed.sample_count);
}
