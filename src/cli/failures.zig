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
pub fn cmdFailures(allocator: std.mem.Allocator, options: FailuresOptions) !u8 {
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
            std.debug.print("No failure reports found for task: {s}\n", .{t});
        } else {
            std.debug.print("No failure reports found.\n", .{});
        }
        return 0;
    }

    // Display each failure report
    for (failures_list.items, 0..) |*failure, i| {
        if (i > 0) {
            std.debug.print("\n", .{});
            if (options.use_color) {
                std.debug.print("\x1b[2m", .{}); // dim
            }
            std.debug.print("{s}\n\n", .{"─" ** 80});
            if (options.use_color) {
                std.debug.print("\x1b[0m", .{}); // reset
            }
        }

        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);
        const buf_writer = buf.writer(allocator);
        try failure.formatReport(buf_writer);
        std.debug.print("{s}", .{buf.items});
    }

    return 0;
}

/// Clear all captured failure reports.
pub fn cmdFailuresClear(allocator: std.mem.Allocator, options: FailuresOptions) !u8 {
    var mgr = try replay.ReplayManager.init(allocator, options.storage_dir);
    defer mgr.deinit();

    // Load failures from disk first
    try mgr.loadFromDisk();

    const count = mgr.failures.count();

    // Delete all JSON files from disk
    const dir = std.fs.cwd().openDir(options.storage_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No failure reports to clear.\n", .{});
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

    std.debug.print("Cleared {d} failure report(s).\n", .{count});
    return 0;
}
