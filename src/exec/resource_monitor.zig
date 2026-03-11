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
    _ = allocator;
    _ = pid;

    // TODO: Platform-specific implementation
    // - Linux: read /proc/[pid]/status for memory, /proc/[pid]/stat for CPU
    // - macOS: use proc_pidinfo() system call
    // - Windows: use GetProcessMemoryInfo() and GetProcessTimes()

    const now = std.time.milliTimestamp();

    return ResourceMetrics{
        .peak_memory_bytes = 0,
        .avg_cpu_percent = 0.0,
        .total_io_ops = 0,
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
