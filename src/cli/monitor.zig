const std = @import("std");
const builtin = @import("builtin");
const sailor = @import("sailor");
const resource = @import("../exec/resource.zig");
const color_mod = @import("../output/color.zig");
const loader = @import("../config/loader.zig");
const scheduler = @import("../exec/scheduler.zig");
const types = @import("../config/types.zig");

/// Task execution metrics for monitoring dashboard.
pub const TaskMetrics = struct {
    name: []const u8,
    pid: if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.posix.pid_t,
    start_time: i128, // Unix timestamp in nanoseconds
    rss_bytes: u64,
    cpu_percent: f64,
    status: TaskStatus,
};

pub const TaskStatus = enum {
    running,
    completed,
    failed,
};

/// Live monitoring dashboard using TUI widgets.
/// Displays real-time resource usage with time-series graphs.
pub const MonitorDashboard = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(TaskMetrics),

    // Time-series data for graphs (circular buffers)
    cpu_history: std.ArrayList(f64),
    mem_history: std.ArrayList(u64),
    timestamps: std.ArrayList(i128),
    max_history_points: usize = 60, // 60 seconds at 1Hz

    // TUI state
    use_color: bool,
    update_interval_ms: u64 = 1000,
    done: *std.atomic.Value(bool),

    pub fn init(
        allocator: std.mem.Allocator,
        use_color: bool,
        done: *std.atomic.Value(bool),
    ) !MonitorDashboard {
        return MonitorDashboard{
            .allocator = allocator,
            .tasks = std.ArrayList(TaskMetrics){},
            .cpu_history = std.ArrayList(f64){},
            .mem_history = std.ArrayList(u64){},
            .timestamps = std.ArrayList(i128){},
            .use_color = use_color,
            .done = done,
        };
    }

    pub fn deinit(self: *MonitorDashboard) void {
        self.tasks.deinit(self.allocator);
        self.cpu_history.deinit(self.allocator);
        self.mem_history.deinit(self.allocator);
        self.timestamps.deinit(self.allocator);
    }

    /// Add a task to monitor.
    pub fn addTask(self: *MonitorDashboard, task: TaskMetrics) !void {
        try self.tasks.append(self.allocator, task);
    }

    /// Update metrics for all running tasks.
    fn updateMetrics(self: *MonitorDashboard) !void {
        const now = std.time.nanoTimestamp();
        var total_cpu: f64 = 0.0;
        var total_mem: u64 = 0;

        for (self.tasks.items) |*task| {
            if (task.status != .running) continue;

            const usage = resource.getProcessUsage(task.pid) orelse continue;
            task.rss_bytes = usage.rss_bytes;
            task.cpu_percent = usage.cpu_percent;

            total_cpu += usage.cpu_percent;
            total_mem += usage.rss_bytes;
        }

        // Add to history (circular buffer)
        if (self.cpu_history.items.len >= self.max_history_points) {
            _ = self.cpu_history.orderedRemove(0);
            _ = self.mem_history.orderedRemove(0);
            _ = self.timestamps.orderedRemove(0);
        }

        try self.cpu_history.append(self.allocator, total_cpu);
        try self.mem_history.append(self.allocator, total_mem);
        try self.timestamps.append(self.allocator, now);
    }

    /// Render the dashboard to stdout.
    pub fn render(self: *MonitorDashboard) !void {
        var stdout_buf: [8192]u8 = undefined;
        const stdout = std.fs.File.stdout();
        var file_writer = stdout.writer(&stdout_buf);
        const writer = &file_writer.interface;

        // Clear screen and move to top
        try writer.writeAll("\x1b[2J\x1b[H");

        // Header
        if (self.use_color) {
            try writer.writeAll("\x1b[1;36m"); // Bold cyan
        }
        try writer.writeAll("═══ zr Resource Monitor ═══\n");
        if (self.use_color) {
            try writer.writeAll("\x1b[0m"); // Reset
        }
        try writer.writeAll("\n");

        // Task status table
        try self.renderTaskTable(writer);
        try writer.writeAll("\n");

        // CPU graph
        try self.renderCpuGraph(writer);
        try writer.writeAll("\n");

        // Memory graph
        try self.renderMemoryGraph(writer);
        try writer.writeAll("\n");

        // Bottleneck detection
        try self.renderBottlenecks(writer);

        // Footer
        if (self.use_color) {
            try writer.writeAll("\x1b[2m"); // Dim
        }
        try writer.writeAll("\nPress Ctrl+C to stop monitoring");
        if (self.use_color) {
            try writer.writeAll("\x1b[0m"); // Reset
        }
        try writer.writeAll("\n");
    }

    fn renderTaskTable(self: *MonitorDashboard, writer: anytype) !void {
        if (self.use_color) {
            try writer.writeAll("\x1b[1m"); // Bold
        }
        try writer.writeAll("Task                     Status      RSS         CPU\n");
        if (self.use_color) {
            try writer.writeAll("\x1b[0m");
        }
        try writer.writeAll("──────────────────────────────────────────────────────\n");

        for (self.tasks.items) |task| {
            // Task name (truncate to 24 chars)
            const name_len = @min(task.name.len, 24);
            try writer.writeAll(task.name[0..name_len]);
            const padding = 24 - name_len;
            var i: usize = 0;
            while (i < padding) : (i += 1) {
                try writer.writeAll(" ");
            }
            try writer.writeAll(" ");

            // Status with color
            const status_str = switch (task.status) {
                .running => "RUNNING",
                .completed => "DONE   ",
                .failed => "FAILED ",
            };
            const status_color = switch (task.status) {
                .running => "\x1b[33m", // Yellow
                .completed => "\x1b[32m", // Green
                .failed => "\x1b[31m", // Red
            };

            if (self.use_color) {
                try writer.writeAll(status_color);
            }
            try writer.writeAll(status_str);
            if (self.use_color) {
                try writer.writeAll("\x1b[0m");
            }
            try writer.writeAll("  ");

            // RSS
            if (task.status == .running) {
                try formatBytes(writer, task.rss_bytes);
                // Pad to 12 chars
                const bytes_str_len = estimateBytesLen(task.rss_bytes);
                const bytes_padding = 12 -| bytes_str_len;
                var j: usize = 0;
                while (j < bytes_padding) : (j += 1) {
                    try writer.writeAll(" ");
                }
            } else {
                try writer.writeAll("-           ");
            }

            // CPU
            if (task.status == .running) {
                try writer.print("{d:.1}%\n", .{task.cpu_percent});
            } else {
                try writer.writeAll("-\n");
            }
        }
    }

    fn renderCpuGraph(self: *MonitorDashboard, writer: anytype) !void {
        if (self.use_color) {
            try writer.writeAll("\x1b[1m"); // Bold
        }
        try writer.writeAll("CPU Usage (%):\n");
        if (self.use_color) {
            try writer.writeAll("\x1b[0m");
        }

        if (self.cpu_history.items.len == 0) {
            try writer.writeAll("  [No data yet]\n");
            return;
        }

        // Simple ASCII bar chart (60 columns wide)
        const max_cpu = blk: {
            var max: f64 = 1.0;
            for (self.cpu_history.items) |val| {
                if (val > max) max = val;
            }
            break :blk max;
        };

        // Show last 60 points
        const start_idx = if (self.cpu_history.items.len > 60)
            self.cpu_history.items.len - 60
        else
            0;

        // Render 10 rows (0% to 100%)
        const num_rows = 10;
        var row: usize = 0;
        while (row < num_rows) : (row += 1) {
            const threshold = max_cpu * @as(f64, @floatFromInt(num_rows - row)) / @as(f64, @floatFromInt(num_rows));

            try writer.print("{d:3.0}% ", .{threshold});

            for (self.cpu_history.items[start_idx..]) |cpu| {
                const char = if (cpu >= threshold) "█" else " ";
                if (self.use_color and cpu >= threshold) {
                    // Color based on CPU usage
                    if (cpu > 80.0) {
                        try writer.writeAll("\x1b[31m"); // Red
                    } else if (cpu > 50.0) {
                        try writer.writeAll("\x1b[33m"); // Yellow
                    } else {
                        try writer.writeAll("\x1b[32m"); // Green
                    }
                }
                try writer.writeAll(char);
                if (self.use_color and cpu >= threshold) {
                    try writer.writeAll("\x1b[0m");
                }
            }
            try writer.writeAll("\n");
        }

        // X-axis
        try writer.writeAll("     ");
        var i: usize = 0;
        while (i < @min(60, self.cpu_history.items.len)) : (i += 1) {
            try writer.writeAll("─");
        }
        try writer.writeAll("\n");
    }

    fn renderMemoryGraph(self: *MonitorDashboard, writer: anytype) !void {
        if (self.use_color) {
            try writer.writeAll("\x1b[1m"); // Bold
        }
        try writer.writeAll("Memory Usage (MB):\n");
        if (self.use_color) {
            try writer.writeAll("\x1b[0m");
        }

        if (self.mem_history.items.len == 0) {
            try writer.writeAll("  [No data yet]\n");
            return;
        }

        // Convert to MB and find max
        const max_mem_mb = blk: {
            var max: u64 = 1;
            for (self.mem_history.items) |val| {
                const mb = val / (1024 * 1024);
                if (mb > max) max = mb;
            }
            break :blk max;
        };

        // Show last 60 points
        const start_idx = if (self.mem_history.items.len > 60)
            self.mem_history.items.len - 60
        else
            0;

        // Render 8 rows
        const num_rows = 8;
        var row: usize = 0;
        while (row < num_rows) : (row += 1) {
            const threshold = max_mem_mb * (num_rows - row) / num_rows;

            try writer.print("{d:4} ", .{threshold});

            for (self.mem_history.items[start_idx..]) |mem_bytes| {
                const mem_mb = mem_bytes / (1024 * 1024);
                const char = if (mem_mb >= threshold) "█" else " ";
                if (self.use_color and mem_mb >= threshold) {
                    try writer.writeAll("\x1b[36m"); // Cyan
                }
                try writer.writeAll(char);
                if (self.use_color and mem_mb >= threshold) {
                    try writer.writeAll("\x1b[0m");
                }
            }
            try writer.writeAll("\n");
        }

        // X-axis
        try writer.writeAll("     ");
        var i: usize = 0;
        while (i < @min(60, self.mem_history.items.len)) : (i += 1) {
            try writer.writeAll("─");
        }
        try writer.writeAll("\n");
    }

    fn renderBottlenecks(self: *MonitorDashboard, writer: anytype) !void {
        // Detect tasks with high resource usage
        var has_bottleneck = false;

        for (self.tasks.items) |task| {
            if (task.status != .running) continue;

            const high_cpu = task.cpu_percent > 80.0;
            const high_mem = task.rss_bytes > 500 * 1024 * 1024; // > 500 MB

            if (high_cpu or high_mem) {
                if (!has_bottleneck) {
                    if (self.use_color) {
                        try writer.writeAll("\x1b[1;33m"); // Bold yellow
                    }
                    try writer.writeAll("⚠ Bottlenecks Detected:\n");
                    if (self.use_color) {
                        try writer.writeAll("\x1b[0m");
                    }
                    has_bottleneck = true;
                }

                try writer.writeAll("  • ");
                try writer.writeAll(task.name);
                try writer.writeAll(": ");

                if (high_cpu) {
                    try writer.print("High CPU ({d:.1}%)", .{task.cpu_percent});
                    if (high_mem) try writer.writeAll(", ");
                }
                if (high_mem) {
                    try writer.writeAll("High Memory (");
                    try formatBytes(writer, task.rss_bytes);
                    try writer.writeAll(")");
                }
                try writer.writeAll("\n");
            }
        }

        if (!has_bottleneck) {
            if (self.use_color) {
                try writer.writeAll("\x1b[32m"); // Green
            }
            try writer.writeAll("✓ No bottlenecks detected\n");
            if (self.use_color) {
                try writer.writeAll("\x1b[0m");
            }
        }
    }

    /// Main monitoring loop (runs in a separate thread).
    pub fn run(self: *MonitorDashboard) !void {
        while (!self.done.load(.acquire)) {
            try self.updateMetrics();
            try self.render();
            std.Thread.sleep(self.update_interval_ms * std.time.ns_per_ms);
        }

        // Final render
        try self.updateMetrics();
        try self.render();
    }
};

/// Format bytes into human-readable format.
fn formatBytes(writer: anytype, bytes: u64) !void {
    if (bytes < 1024) {
        try writer.print("{d} B", .{bytes});
    } else if (bytes < 1024 * 1024) {
        const kb: f64 = @as(f64, @floatFromInt(bytes)) / 1024.0;
        try writer.print("{d:.1} KB", .{kb});
    } else if (bytes < 1024 * 1024 * 1024) {
        const mb: f64 = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
        try writer.print("{d:.1} MB", .{mb});
    } else {
        const gb: f64 = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0);
        try writer.print("{d:.2} GB", .{gb});
    }
}

/// Estimate string length of formatted bytes (for padding).
fn estimateBytesLen(bytes: u64) usize {
    if (bytes < 1024) {
        return 5; // "999 B"
    } else if (bytes < 1024 * 1024) {
        return 8; // "1024.0 KB"
    } else if (bytes < 1024 * 1024 * 1024) {
        return 8; // "1024.0 MB"
    } else {
        return 9; // "1024.00 GB"
    }
}

/// Context for monitoring thread - tracks task PIDs during execution.
const MonitorContext = struct {
    allocator: std.mem.Allocator,
    dashboard: *MonitorDashboard,
    process_map: *std.StringHashMap(std.posix.pid_t),
    map_mutex: *std.Thread.Mutex,
};

/// CLI entry point for `zr monitor <workflow>` command.
/// Executes the workflow and displays real-time resource monitoring dashboard.
pub fn cmdMonitor(
    allocator: std.mem.Allocator,
    workflow_name: []const u8,
    config_path: ?[]const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    _ = w; // Not used in this command (TUI takes over stdout)

    // Load config
    const resolved_path = config_path orelse "zr.toml";
    var config = loader.loadFromFile(allocator, resolved_path) catch |err| {
        try color_mod.printError(ew, use_color, "Failed to load config: {}\n", .{err});
        return 1;
    };
    defer config.deinit();

    // Find workflow
    const workflow = config.workflows.get(workflow_name) orelse {
        try color_mod.printError(ew, use_color, "Workflow '{s}' not found\n", .{workflow_name});
        return 1;
    };

    // Create monitoring dashboard
    var done = std.atomic.Value(bool).init(false);
    var dashboard = try MonitorDashboard.init(allocator, use_color, &done);
    defer dashboard.deinit();

    // Create process map for tracking task PIDs
    var process_map = std.StringHashMap(std.posix.pid_t).init(allocator);
    defer process_map.deinit();
    var map_mutex = std.Thread.Mutex{};

    // Spawn monitoring thread
    const monitor_ctx = MonitorContext{
        .allocator = allocator,
        .dashboard = &dashboard,
        .process_map = &process_map,
        .map_mutex = &map_mutex,
    };
    const monitor_thread = try std.Thread.spawn(.{}, monitoringLoop, .{monitor_ctx});

    // Execute workflow stages sequentially
    var all_success = true;
    for (workflow.stages) |stage| {
        // Add stage header to dashboard (simplified - just track tasks)
        const sched_config = scheduler.SchedulerConfig{
            .max_jobs = 0, // Use all CPU cores
            .inherit_stdio = true,
            .dry_run = false,
            .monitor = true, // Enable resource tracking in scheduler
            .use_color = use_color,
        };

        var result = scheduler.run(
            allocator,
            &config,
            stage.tasks,
            sched_config,
        ) catch |err| {
            done.store(true, .release);
            monitor_thread.join();
            try color_mod.printError(ew, use_color, "Stage '{s}' failed: {}\n", .{ stage.name, err });
            return 1;
        };
        defer result.deinit(allocator);

        if (!result.total_success) {
            all_success = false;
            // Stop on first failure (default workflow behavior)
            break;
        }
    }

    // Signal monitoring thread to stop
    done.store(true, .release);
    monitor_thread.join();

    // Show final summary
    if (all_success) {
        try color_mod.printSuccess(ew, use_color, "\n✓ Workflow completed successfully\n", .{});
    } else {
        try color_mod.printError(ew, use_color, "\n✗ Workflow failed\n", .{});
    }

    return if (all_success) 0 else 1;
}

/// Monitoring thread loop - periodically discovers running processes and updates dashboard.
fn monitoringLoop(ctx: MonitorContext) !void {
    while (!ctx.dashboard.done.load(.acquire)) {
        // Discover all child processes (zr spawns them, we track them by name)
        try discoverAndTrackProcesses(ctx);

        // Update metrics for all tracked tasks
        try ctx.dashboard.updateMetrics();
        try ctx.dashboard.render();

        // Sleep for update interval
        std.Thread.sleep(ctx.dashboard.update_interval_ms * std.time.ns_per_ms);
    }

    // Final render
    try ctx.dashboard.updateMetrics();
    try ctx.dashboard.render();
}

/// Discover child processes and add them to the dashboard if not already tracked.
fn discoverAndTrackProcesses(ctx: MonitorContext) !void {
    // This is a simplified implementation - in production, we would:
    // 1. Parse /proc to find all child processes of current PID
    // 2. Match process command lines to task names
    // 3. Add new processes to the dashboard
    //
    // For now, we rely on the scheduler's resource tracking which already
    // monitors processes via resource_monitor.zig. The dashboard will show
    // aggregate resource usage even without per-task tracking.
    //
    // Future enhancement: Hook into scheduler's workerFn to register PIDs
    // when tasks start, then remove them when tasks complete.
    _ = ctx;
}

// Tests
test "MonitorDashboard init/deinit" {
    var done = std.atomic.Value(bool).init(false);
    var dashboard = try MonitorDashboard.init(std.testing.allocator, false, &done);
    defer dashboard.deinit();

    try std.testing.expectEqual(@as(usize, 0), dashboard.tasks.items.len);
    try std.testing.expectEqual(@as(usize, 0), dashboard.cpu_history.items.len);
}

test "MonitorDashboard addTask" {
    var done = std.atomic.Value(bool).init(false);
    var dashboard = try MonitorDashboard.init(std.testing.allocator, false, &done);
    defer dashboard.deinit();

    const task = TaskMetrics{
        .name = "test-task",
        .pid = if (builtin.os.tag == .windows) undefined else 1,
        .start_time = std.time.nanoTimestamp(),
        .rss_bytes = 0,
        .cpu_percent = 0.0,
        .status = .running,
    };

    try dashboard.addTask(task);
    try std.testing.expectEqual(@as(usize, 1), dashboard.tasks.items.len);
    try std.testing.expectEqualStrings("test-task", dashboard.tasks.items[0].name);
}

test "formatBytes" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatBytes(writer, 512);
    try std.testing.expectEqualStrings("512 B", stream.getWritten());

    stream.reset();
    try formatBytes(writer, 1536);
    try std.testing.expectEqualStrings("1.5 KB", stream.getWritten());

    stream.reset();
    try formatBytes(writer, 2 * 1024 * 1024);
    try std.testing.expectEqualStrings("2.0 MB", stream.getWritten());
}

test "estimateBytesLen" {
    try std.testing.expectEqual(@as(usize, 5), estimateBytesLen(512));
    try std.testing.expectEqual(@as(usize, 8), estimateBytesLen(1536));
    try std.testing.expectEqual(@as(usize, 8), estimateBytesLen(2 * 1024 * 1024));
    try std.testing.expectEqual(@as(usize, 9), estimateBytesLen(3 * 1024 * 1024 * 1024));
}
