const std = @import("std");
const builtin = @import("builtin");
const resource = @import("../exec/resource.zig");
const color = @import("color.zig");

/// Context for the monitor display thread.
pub const MonitorContext = struct {
    pid: if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.posix.pid_t,
    task_name: []const u8,
    done: *std.atomic.Value(bool),
    use_color: bool,
    allocator: std.mem.Allocator,

    /// Peak resource usage recorded during execution.
    peak_rss_bytes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    peak_cpu_percent: std.atomic.Value(u64) = std.atomic.Value(u64).init(0), // Stored as u64 (percent * 10)
};

/// Display live resource usage for a running process.
/// This function runs in a separate thread and updates the display every 500ms.
pub fn monitorDisplay(ctx: *MonitorContext) void {
    const update_interval_ms: u64 = 500;
    var last_cpu_time_ns: u64 = 0;
    var last_update_ns = std.time.nanoTimestamp();

    // Get stderr for live updates
    const stderr = std.fs.File.stderr();
    var buf: [4096]u8 = undefined;
    var file_writer = stderr.writer(&buf);
    const writer = &file_writer.interface;

    while (!ctx.done.load(.acquire)) {
        std.Thread.sleep(update_interval_ms * std.time.ns_per_ms);
        if (ctx.done.load(.acquire)) break;

        // Get current resource usage
        const usage = resource.getProcessUsage(ctx.pid) orelse continue;

        // Update peak values
        const current_rss = ctx.peak_rss_bytes.load(.acquire);
        if (usage.rss_bytes > current_rss) {
            _ = ctx.peak_rss_bytes.cmpxchgWeak(current_rss, usage.rss_bytes, .release, .acquire);
        }

        // Calculate instantaneous CPU usage
        const now_ns = std.time.nanoTimestamp();
        const elapsed_ns = @as(u64, @intCast(now_ns - last_update_ns));
        const cpu_delta_ns = if (usage.cpu_time_ns > last_cpu_time_ns)
            usage.cpu_time_ns - last_cpu_time_ns
        else
            0;

        const cpu_percent = if (elapsed_ns > 0)
            @as(f64, @floatFromInt(cpu_delta_ns)) / @as(f64, @floatFromInt(elapsed_ns)) * 100.0
        else
            0.0;

        // Update peak CPU (stored as percent * 10 for atomic storage)
        const cpu_percent_x10: u64 = @intFromFloat(cpu_percent * 10.0);
        const current_peak_cpu = ctx.peak_cpu_percent.load(.acquire);
        if (cpu_percent_x10 > current_peak_cpu) {
            _ = ctx.peak_cpu_percent.cmpxchgWeak(current_peak_cpu, cpu_percent_x10, .release, .acquire);
        }

        last_cpu_time_ns = usage.cpu_time_ns;
        last_update_ns = now_ns;

        // Display live stats (overwrite previous line)
        // Use carriage return to update in place
        writer.print("\r", .{}) catch continue;

        if (ctx.use_color) {
            writer.print("\x1b[36m", .{}) catch continue; // Cyan
        }
        writer.print("  [{s}] RSS: ", .{ctx.task_name}) catch continue;
        if (ctx.use_color) {
            writer.print("\x1b[1m", .{}) catch continue; // Bold
        }
        formatBytes(writer, usage.rss_bytes) catch continue;
        if (ctx.use_color) {
            writer.print("\x1b[0m\x1b[36m", .{}) catch continue; // Reset bold, keep cyan
        }
        writer.print(" | CPU: ", .{}) catch continue;
        if (ctx.use_color) {
            writer.print("\x1b[1m", .{}) catch continue; // Bold
        }
        writer.print("{d:.1}%", .{cpu_percent}) catch continue;
        if (ctx.use_color) {
            writer.print("\x1b[0m", .{}) catch continue; // Reset
        }
        writer.print("  ", .{}) catch continue; // Extra spaces to clear previous content

        // No flush needed - direct write to stderr
    }

    // Clear the monitor line and print final peak stats
    writer.print("\r", .{}) catch return;
    writer.print("                                                                  \r", .{}) catch return;

    const peak_rss = ctx.peak_rss_bytes.load(.acquire);
    const peak_cpu_x10 = ctx.peak_cpu_percent.load(.acquire);
    const peak_cpu: f64 = @as(f64, @floatFromInt(peak_cpu_x10)) / 10.0;

    if (peak_rss > 0 or peak_cpu > 0.0) {
        if (ctx.use_color) {
            writer.print("\x1b[2m", .{}) catch return; // Dim
        }
        writer.print("  [{s}] Peak RSS: ", .{ctx.task_name}) catch return;
        formatBytes(writer, peak_rss) catch return;
        writer.print(" | Peak CPU: {d:.1}%\n", .{peak_cpu}) catch return;
        if (ctx.use_color) {
            writer.print("\x1b[0m", .{}) catch return; // Reset
        }
    }

    // No flush needed - direct write to stderr
}

/// Format bytes into human-readable format (KB, MB, GB).
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

// Tests
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

    stream.reset();
    try formatBytes(writer, 3 * 1024 * 1024 * 1024);
    try std.testing.expectEqualStrings("3.00 GB", stream.getWritten());
}

test "MonitorContext initialization" {
    var done = std.atomic.Value(bool).init(false);
    var ctx = MonitorContext{
        .pid = if (builtin.os.tag == .windows) undefined else 1,
        .task_name = "test",
        .done = &done,
        .use_color = false,
        .allocator = std.testing.allocator,
    };

    try std.testing.expectEqual(@as(u64, 0), ctx.peak_rss_bytes.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), ctx.peak_cpu_percent.load(.acquire));
}
