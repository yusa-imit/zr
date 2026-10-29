//! Live resource monitor: a thread body that redraws one stderr line with a child process's RSS
//! and CPU every 500 ms and records the peaks.
//!
//! Contract: `monitorDisplay` runs until `ctx.done` is set, then clears the line and prints the
//! peak RSS and CPU. Peaks are atomics read by the owner after the thread joins; CPU is stored
//! as percent times ten. The stderr writer is buffered (4096 bytes); every redraw and the final
//! summary flush it so updates appear immediately. Write errors are ignored. The wall clock and
//! sleep are read directly, not injected.

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

        // Display live stats (overwrite previous line).
        renderLive(writer, ctx, usage.rss_bytes, cpu_percent) catch continue;
    }

    // Clear the monitor line and print final peak stats.
    const peak_cpu_x10 = ctx.peak_cpu_percent.load(.acquire);
    const peak_cpu: f64 = @as(f64, @floatFromInt(peak_cpu_x10)) / 10.0;
    renderSummary(writer, ctx, ctx.peak_rss_bytes.load(.acquire), peak_cpu) catch return;
}

/// Redraw the live line in place with a carriage return, then flush so it reaches the terminal.
fn renderLive(
    writer: *std.Io.Writer,
    ctx: *const MonitorContext,
    rss_bytes: u64,
    cpu_percent: f64,
) std.Io.Writer.Error!void {
    try writer.print("\r", .{});
    if (ctx.use_color) try writer.print("\x1b[36m", .{}); // Cyan
    try writer.print("  [{s}] RSS: ", .{ctx.task_name});
    if (ctx.use_color) try writer.print("\x1b[1m", .{}); // Bold
    try formatBytes(writer, rss_bytes);
    if (ctx.use_color) try writer.print("\x1b[0m\x1b[36m", .{}); // Reset bold, keep cyan
    try writer.print(" | CPU: ", .{});
    if (ctx.use_color) try writer.print("\x1b[1m", .{}); // Bold
    try writer.print("{d:.1}%", .{cpu_percent});
    if (ctx.use_color) try writer.print("\x1b[0m", .{}); // Reset
    try writer.print("  ", .{}); // Extra spaces to clear previous content
    try writer.flush();
}

/// Clear the live line, print the peak line when anything was measured, then flush.
fn renderSummary(
    writer: *std.Io.Writer,
    ctx: *const MonitorContext,
    peak_rss: u64,
    peak_cpu: f64,
) std.Io.Writer.Error!void {
    try writer.print("\r", .{});
    try writer.print("                                                                  \r", .{});
    if (peak_rss > 0 or peak_cpu > 0.0) {
        if (ctx.use_color) try writer.print("\x1b[2m", .{}); // Dim
        try writer.print("  [{s}] Peak RSS: ", .{ctx.task_name});
        try formatBytes(writer, peak_rss);
        try writer.print(" | Peak CPU: {d:.1}%\n", .{peak_cpu});
        if (ctx.use_color) try writer.print("\x1b[0m", .{}); // Reset
    }
    try writer.flush();
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

/// Test sink that records every byte the buffered writer drains.
const DrainSink = struct {
    interface: std.Io.Writer,
    drained: [512]u8 = undefined,
    drained_len: usize = 0,

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const sink: *DrainSink = @fieldParentPtr("interface", w);
        // Buffered bytes come first; a drain that leaves `end` set makes `flush` spin forever.
        @memcpy(sink.drained[sink.drained_len..][0..w.end], w.buffer[0..w.end]);
        sink.drained_len += w.end;
        w.end = 0;
        var consumed: usize = 0;
        for (data[0 .. data.len - 1]) |chunk| {
            @memcpy(sink.drained[sink.drained_len..][0..chunk.len], chunk);
            sink.drained_len += chunk.len;
            consumed += chunk.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| {
            @memcpy(sink.drained[sink.drained_len..][0..last.len], last);
            sink.drained_len += last.len;
            consumed += last.len;
        }
        return consumed;
    }
};

fn test_sink(buf: []u8) DrainSink {
    return .{ .interface = .{ .vtable = &.{ .drain = DrainSink.drain }, .buffer = buf } };
}

fn test_context(done: *std.atomic.Value(bool), use_color: bool) MonitorContext {
    return .{
        .pid = if (builtin.os.tag == .windows) undefined else 1,
        .task_name = "build",
        .done = done,
        .use_color = use_color,
        .allocator = std.testing.allocator,
    };
}

test "renderLive flushes the line to the sink" {
    var done = std.atomic.Value(bool).init(false);
    const ctx = test_context(&done, false);
    var buf: [256]u8 = undefined;
    var sink = test_sink(&buf);

    try renderLive(&sink.interface, &ctx, 2 * 1024 * 1024, 12.5);

    const expected = "\r  [build] RSS: 2.0 MB | CPU: 12.5%  ";
    try std.testing.expectEqualStrings(expected, sink.drained[0..sink.drained_len]);
    try std.testing.expectEqual(@as(usize, 0), sink.interface.end);
}

test "renderSummary flushes the peak line and colors it" {
    var done = std.atomic.Value(bool).init(false);
    const ctx = test_context(&done, true);
    var buf: [256]u8 = undefined;
    var sink = test_sink(&buf);

    try renderSummary(&sink.interface, &ctx, 512, 3.5);

    const out = sink.drained[0..sink.drained_len];
    const tail = "\x1b[2m  [build] Peak RSS: 512 B | Peak CPU: 3.5%\n\x1b[0m";
    try std.testing.expect(std.mem.endsWith(u8, out, tail));
    try std.testing.expect(std.mem.startsWith(u8, out, "\r" ++ " " ** 66 ++ "\r"));
    try std.testing.expectEqual(@as(usize, 0), sink.interface.end);
}

test "renderSummary with no samples only clears the line" {
    var done = std.atomic.Value(bool).init(false);
    const ctx = test_context(&done, false);
    var buf: [256]u8 = undefined;
    var sink = test_sink(&buf);

    try renderSummary(&sink.interface, &ctx, 0, 0.0);

    const cleared = "\r" ++ " " ** 66 ++ "\r";
    try std.testing.expectEqualStrings(cleared, sink.drained[0..sink.drained_len]);
}
