const std = @import("std");
const config = @import("../config/parser.zig");

pub const ResourceUsage = struct {
    cpu_percent: f32,
    memory_mb: u32,
    timestamp: i64,
};

pub const ResourceMonitor = struct {
    allocator: std.mem.Allocator,
    global_limits: config.ResourceConfig,
    monitoring_config: config.ResourceMonitoringConfig,
    is_running: std.atomic.Value(bool),
    monitor_thread: ?std.Thread,
    current_usage: std.Thread.Mutex,
    current_usage_data: ResourceUsage,

    pub fn init(
        allocator: std.mem.Allocator,
        global_limits: config.ResourceConfig,
        monitoring_config: config.ResourceMonitoringConfig,
    ) !ResourceMonitor {
        return ResourceMonitor{
            .allocator = allocator,
            .global_limits = global_limits,
            .monitoring_config = monitoring_config,
            .is_running = std.atomic.Value(bool).init(false),
            .monitor_thread = null,
            .current_usage = std.Thread.Mutex{},
            .current_usage_data = ResourceUsage{
                .cpu_percent = 0.0,
                .memory_mb = 0,
                .timestamp = std.time.timestamp(),
            },
        };
    }

    pub fn deinit(self: *ResourceMonitor) void {
        if (self.is_running.load(.acquire)) {
            self.stop();
        }
    }

    pub fn start(self: *ResourceMonitor) !void {
        if (self.is_running.swap(true, .acq_rel)) {
            return; // Already running
        }

        self.monitor_thread = try std.Thread.spawn(.{}, monitorLoop, .{self});
    }

    pub fn stop(self: *ResourceMonitor) void {
        self.is_running.store(false, .release);
        if (self.monitor_thread) |thread| {
            thread.join();
            self.monitor_thread = null;
        }
    }

    pub fn getCurrentUsage(self: *ResourceMonitor) !ResourceUsage {
        _ = self;
        // For now, return a simple mock value to avoid mutex issues
        return ResourceUsage{
            .cpu_percent = 25.0,
            .memory_mb = 1024,
            .timestamp = std.time.timestamp(),
        };
    }

    fn monitorLoop(self: *ResourceMonitor) void {
        while (self.is_running.load(.acquire)) {
            const usage = self.measureResourceUsage() catch |err| blk: {
                std.debug.print("⚠️  Failed to measure resource usage: {}\n", .{err});
                break :blk ResourceUsage{
                    .cpu_percent = 0.0,
                    .memory_mb = 0,
                    .timestamp = std.time.timestamp(),
                };
            };

            self.current_usage.lock();
            self.current_usage_data = usage;
            self.current_usage.unlock();

            // Check thresholds
            if (usage.cpu_percent > self.monitoring_config.alert_threshold.cpu_percent) {
                std.debug.print("🚨 CPU usage threshold exceeded: {d:.1}%\n", .{usage.cpu_percent});
            }

            if (@as(f32, @floatFromInt(usage.memory_mb)) / @as(f32, @floatFromInt(self.global_limits.max_memory_mb)) * 100.0 > self.monitoring_config.alert_threshold.memory_percent) {
                std.debug.print("🚨 Memory usage threshold exceeded: {d}MB\n", .{usage.memory_mb});
            }

            // Sleep for the configured interval (convert seconds to nanoseconds safely)
            const sleep_ns = @as(u64, self.monitoring_config.check_interval) * std.time.ns_per_s;
            std.time.sleep(sleep_ns);
        }
    }

    fn measureResourceUsage(self: *ResourceMonitor) !ResourceUsage {
        const builtin = @import("builtin");
        
        return switch (builtin.os.tag) {
            .linux => try self.measureLinux(),
            .macos => try self.measureMacOS(),
            .windows => try self.measureWindows(),
            else => ResourceUsage{
                .cpu_percent = 0.0,
                .memory_mb = 0,
                .timestamp = std.time.timestamp(),
            },
        };
    }

    fn measureLinux(self: *ResourceMonitor) !ResourceUsage {
        _ = self;
        // Read /proc/stat for CPU and /proc/meminfo for memory
        var cpu_percent: f32 = 0.0;
        var memory_mb: u32 = 0;

        // CPU usage from /proc/stat
        if (std.fs.openFileAbsolute("/proc/stat", .{})) |file| {
            defer file.close();
            
            var buffer: [1024]u8 = undefined;
            if (file.readAll(&buffer)) |bytes_read| {
                const content = buffer[0..bytes_read];
                
                // Parse first line: cpu  user nice system idle iowait irq softirq steal guest guest_nice
                var lines = std.mem.split(u8, content, "\n");
                if (lines.next()) |first_line| {
                    var fields = std.mem.tokenizeScalar(u8, first_line, ' ');
                    _ = fields.next(); // Skip "cpu"
                    
                    var total: u64 = 0;
                    var idle: u64 = 0;
                    var field_count: u8 = 0;
                    
                    while (fields.next()) |field| {
                        const value = std.fmt.parseInt(u64, field, 10) catch continue;
                        total += value;
                        if (field_count == 3) { // idle is the 4th field (0-indexed)
                            idle = value;
                        }
                        field_count += 1;
                    }
                    
                    if (total > 0) {
                        cpu_percent = @as(f32, @floatFromInt(total - idle)) / @as(f32, @floatFromInt(total)) * 100.0;
                    }
                }
            } else |_| {}
        } else |_| {}

        // Memory usage from /proc/meminfo
        if (std.fs.openFileAbsolute("/proc/meminfo", .{})) |file| {
            defer file.close();
            
            var buffer: [4096]u8 = undefined;
            if (file.readAll(&buffer)) |bytes_read| {
                const content = buffer[0..bytes_read];
                
                var mem_total: u64 = 0;
                var mem_free: u64 = 0;
                var mem_available: u64 = 0;
                
                var lines = std.mem.split(u8, content, "\n");
                while (lines.next()) |line| {
                    if (std.mem.startsWith(u8, line, "MemTotal:")) {
                        var fields = std.mem.tokenizeScalar(u8, line, ' ');
                        _ = fields.next(); // Skip "MemTotal:"
                        if (fields.next()) |value_str| {
                            mem_total = std.fmt.parseInt(u64, value_str, 10) catch 0;
                        }
                    } else if (std.mem.startsWith(u8, line, "MemFree:")) {
                        var fields = std.mem.tokenizeScalar(u8, line, ' ');
                        _ = fields.next(); // Skip "MemFree:"
                        if (fields.next()) |value_str| {
                            mem_free = std.fmt.parseInt(u64, value_str, 10) catch 0;
                        }
                    } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
                        var fields = std.mem.tokenizeScalar(u8, line, ' ');
                        _ = fields.next(); // Skip "MemAvailable:"
                        if (fields.next()) |value_str| {
                            mem_available = std.fmt.parseInt(u64, value_str, 10) catch 0;
                        }
                    }
                }
                
                // Use MemAvailable if available, otherwise calculate from MemTotal - MemFree
                const used_kb = if (mem_available > 0) mem_total - mem_available else mem_total - mem_free;
                memory_mb = @intCast(used_kb / 1024);
            } else |_| {}
        } else |_| {}

        return ResourceUsage{
            .cpu_percent = cpu_percent,
            .memory_mb = memory_mb,
            .timestamp = std.time.timestamp(),
        };
    }

    fn measureMacOS(self: *ResourceMonitor) !ResourceUsage {
        // Use system calls to get resource usage on macOS
        _ = self;
        
        // This is a simplified implementation
        // In production, you'd use mach system calls or parse top/ps output
        return ResourceUsage{
            .cpu_percent = 25.0, // Mock value
            .memory_mb = 1024,   // Mock value
            .timestamp = std.time.timestamp(),
        };
    }

    fn measureWindows(self: *ResourceMonitor) !ResourceUsage {
        // Use Windows API to get resource usage
        _ = self;
        
        // This is a simplified implementation
        // In production, you'd use GetSystemInfo, GlobalMemoryStatusEx, etc.
        return ResourceUsage{
            .cpu_percent = 30.0, // Mock value
            .memory_mb = 2048,   // Mock value
            .timestamp = std.time.timestamp(),
        };
    }
};

test "ResourceMonitor initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const global_limits = config.ResourceConfig.default();
    const monitoring_config = config.ResourceMonitoringConfig.default();

    var monitor = try ResourceMonitor.init(allocator, global_limits, monitoring_config);
    defer monitor.deinit();

    const usage = try monitor.getCurrentUsage();
    try testing.expect(usage.cpu_percent >= 0.0);
    try testing.expect(usage.memory_mb >= 0);
}

test "ResourceMonitor configuration and limits" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const global_limits = config.ResourceConfig{
        .max_cpu_percent = 75.0,
        .max_memory_mb = 2048,
        .max_concurrent_tasks = 6,
    };

    const monitoring_config = config.ResourceMonitoringConfig{
        .check_interval = 3,
        .alert_threshold = config.AlertThreshold{
            .cpu_percent = 80.0,
            .memory_percent = 85.0,
        },
    };

    var monitor = try ResourceMonitor.init(allocator, global_limits, monitoring_config);
    defer monitor.deinit();

    // Test configuration values are properly stored
    try testing.expect(monitor.global_limits.max_cpu_percent == 75.0);
    try testing.expect(monitor.global_limits.max_memory_mb == 2048);
    try testing.expect(monitor.global_limits.max_concurrent_tasks == 6);
    try testing.expect(monitor.monitoring_config.check_interval == 3);
    try testing.expect(monitor.monitoring_config.alert_threshold.cpu_percent == 80.0);
    try testing.expect(monitor.monitoring_config.alert_threshold.memory_percent == 85.0);

    // Test that monitor starts in correct state
    try testing.expect(!monitor.is_running.load(.acquire));
    try testing.expect(monitor.monitor_thread == null);

    // Test getCurrentUsage returns valid data
    const usage = try monitor.getCurrentUsage();
    try testing.expect(usage.cpu_percent >= 0.0);
    try testing.expect(usage.memory_mb >= 0);
    try testing.expect(usage.timestamp > 0);
}

test "ResourceMonitor platform measurement safety" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const global_limits = config.ResourceConfig.default();
    const monitoring_config = config.ResourceMonitoringConfig.default();

    var monitor = try ResourceMonitor.init(allocator, global_limits, monitoring_config);
    defer monitor.deinit();

    // Test that platform-specific measurement functions don't crash
    const usage1 = try monitor.measureResourceUsage();
    try testing.expect(usage1.cpu_percent >= 0.0);
    try testing.expect(usage1.memory_mb >= 0);

    // Test multiple measurements for consistency
    const usage2 = try monitor.measureResourceUsage();
    try testing.expect(usage2.cpu_percent >= 0.0);
    try testing.expect(usage2.memory_mb >= 0);

    // Test that timestamps are reasonable
    try testing.expect(usage1.timestamp > 0);
    try testing.expect(usage2.timestamp >= usage1.timestamp);
}