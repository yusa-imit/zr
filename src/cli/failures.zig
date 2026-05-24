const std = @import("std");
const replay = @import("../exec/replay.zig");
const timeline = @import("../exec/timeline.zig");
const sailor_color = @import("../output/color.zig");

pub const FailuresOptions = struct {
    /// Show only failures for specific task (optional filter).
    task: ?[]const u8 = null,
    /// Storage directory for failure contexts (default: .zr/failures).
    storage_dir: []const u8 = ".zr/failures",
    /// Whether to use colored output.
    use_color: bool = true,
};

/// Execute the failures command to view captured failure reports.
pub fn cmdFailures(allocator: std.mem.Allocator, options: FailuresOptions, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    _ = ew; // Not needed for failures command, but accept for consistency
    var mgr = try replay.ReplayManager.init(allocator, options.storage_dir);
    defer mgr.deinit();

    // Load failures from disk
    try mgr.loadFromDisk();

    // Get all failures (or filtered by task)
    var failures_list = std.ArrayList(replay.FailureContext){};
    defer failures_list.deinit(allocator);

    var it = mgr.failures.iterator();
    while (it.next()) |entry| {
        const failure = entry.value_ptr.*;

        // Apply task filter if specified
        if (options.task) |filter_task| {
            if (!std.mem.eql(u8, failure.task_name, filter_task)) {
                continue;
            }
        }

        try failures_list.append(allocator, failure);
    }

    if (failures_list.items.len == 0) {
        if (options.task) |t| {
            try w.print("No failure reports found for task: {s}\n", .{t});
        } else {
            try w.print("No failure reports found.\n", .{});
        }
        return 0;
    }

    // Display each failure report
    for (failures_list.items, 0..) |*failure, i| {
        if (i > 0) {
            try w.print("\n", .{});
            if (options.use_color) {
                try w.print("\x1b[2m", .{}); // dim
            }
            try w.print("{s}\n\n", .{"─" ** 80});
            if (options.use_color) {
                try w.print("\x1b[0m", .{}); // reset
            }
        }

        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);
        const buf_writer = buf.writer(allocator);
        try failure.formatReport(buf_writer);
        try w.print("{s}", .{buf.items});
    }

    return 0;
}

/// Clear all captured failure reports.
pub fn cmdFailuresClear(allocator: std.mem.Allocator, options: FailuresOptions, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    _ = ew; // Not needed for clear command, but accept for consistency
    var mgr = try replay.ReplayManager.init(allocator, options.storage_dir);
    defer mgr.deinit();

    // Load failures from disk first
    try mgr.loadFromDisk();

    const count = mgr.failures.count();

    // Delete all JSON files from disk
    const dir = std.fs.cwd().openDir(options.storage_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            try w.print("No failure reports to clear.\n", .{});
            return 0;
        }
        return err;
    };
    var dir_copy = dir;
    defer dir_copy.close();

    var it = dir_copy.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

        // Delete the file
        try dir_copy.deleteFile(entry.name);
    }

    // Clear in-memory failures
    var failures_it = mgr.failures.iterator();
    while (failures_it.next()) |entry| {
        var ctx = entry.value_ptr.*;
        ctx.deinit(allocator);
    }
    mgr.failures.clearRetainingCapacity();

    try w.print("Cleared {d} failure report(s).\n", .{count});
    return 0;
}

// Unit tests
const testing = std.testing;

test "FailuresOptions: default values" {
    const opts = FailuresOptions{};
    try testing.expect(opts.task == null);
    try testing.expectEqualStrings(".zr/failures", opts.storage_dir);
    try testing.expect(opts.use_color == true);
}

test "FailuresOptions: custom task filter" {
    const opts = FailuresOptions{ .task = "build" };
    try testing.expect(opts.task != null);
    try testing.expectEqualStrings("build", opts.task.?);
}

test "FailuresOptions: custom storage dir" {
    const opts = FailuresOptions{ .storage_dir = "/tmp/failures" };
    try testing.expectEqualStrings("/tmp/failures", opts.storage_dir);
}

test "FailuresOptions: disable color" {
    const opts = FailuresOptions{ .use_color = false };
    try testing.expect(opts.use_color == false);
}

test "FailuresOptions: all custom values" {
    const opts = FailuresOptions{
        .task = "test",
        .storage_dir = "/custom/path",
        .use_color = false,
    };
    try testing.expectEqualStrings("test", opts.task.?);
    try testing.expectEqualStrings("/custom/path", opts.storage_dir);
    try testing.expect(opts.use_color == false);
}

test "cmdFailures writes to writer when no failures found" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const opts = FailuresOptions{
        .storage_dir = "/nonexistent/failures",
    };

    // This should FAIL until cmdFailures is refactored to accept writers
    const code = try cmdFailures(allocator, opts, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdFailuresClear writes to writer when clearing" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const opts = FailuresOptions{
        .storage_dir = "/nonexistent/failures",
    };

    // This should FAIL until cmdFailuresClear is refactored to accept writers
    const code = try cmdFailuresClear(allocator, opts, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), code);
}
