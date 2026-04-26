const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");

pub fn cmdWhich(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, null, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    // Check if task exists
    const task = config.tasks.get(task_name) orelse {
        try color.printError(err_writer, use_color,
            "which: task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    };

    // Find which file defined this task
    // For now, we only track the main config file
    // Future: track imports and show imported file + line number
    const abs_config_path = try std.fs.realpathAlloc(allocator, config_path);
    defer allocator.free(abs_config_path);

    try color.printInfo(w, use_color, "{s}", .{task_name});
    try w.print(" is defined in:\n", .{});
    try color.printDim(w, use_color, "  {s}\n\n", .{abs_config_path});

    // Show task details
    try color.printBold(w, use_color, "Command:\n", .{});
    try w.print("  {s}\n\n", .{task.cmd});

    if (task.description) |desc| {
        try color.printBold(w, use_color, "Description:\n", .{});
        try w.print("  {s}\n", .{desc.getShort()});
        if (desc.getLong()) |long| {
            try w.print("\n  {s}\n", .{long});
        }
        try w.print("\n", .{});
    }

    if (task.deps.len > 0) {
        try color.printBold(w, use_color, "Dependencies:\n", .{});
        for (task.deps) |dep| {
            try w.print("  - {s}\n", .{dep});
        }
        try w.print("\n", .{});
    }

    if (task.tags.len > 0) {
        try color.printBold(w, use_color, "Tags:\n", .{});
        for (task.tags) |tag| {
            try w.print("  - {s}\n", .{tag});
        }
        try w.print("\n", .{});
    }

    return 0;
}

// --- Tests ---

test "cmdWhich: shows task location and details" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\description = "Build the project"
        \\tags = ["build", "dev"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdWhich(allocator, "build", config_path, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "make") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "Build the project") != null);
}

test "cmdWhich: nonexistent task returns error" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdWhich(allocator, "nonexistent", config_path, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 1), code);

    const err_written = err_buf[0..err_w.end];
    try std.testing.expect(std.mem.indexOf(u8, err_written, "not found") != null);
}
