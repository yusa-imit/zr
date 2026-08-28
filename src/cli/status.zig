const std = @import("std");
const common = @import("common.zig");

pub const StatusOptions = struct {
    config_path: ?[]const u8 = null,
    json_output: bool = false,
    use_color: bool = true,
};

pub fn cmdStatus(allocator: std.mem.Allocator, options: StatusOptions, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    const config_path = options.config_path orelse "zr.toml";

    // Check if config exists
    const config_exists = blk: {
        std.fs.cwd().access(config_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!config_exists) {
        if (options.use_color) {
            try ew.print("\x1b[31m✗\x1b[0m No zr.toml found\n\n", .{});
        } else {
            try ew.print("✗ No zr.toml found\n\n", .{});
        }
        try ew.print("  Hint: run \x1b[1mzr init\x1b[0m to create a config file\n", .{});
        return 1;
    }

    // Load config to count tasks
    const loader = @import("../config/loader.zig");
    var config = loader.loadFromFile(allocator, config_path) catch |err| {
        try ew.print("✗ Failed to load {s}: {}\n", .{ config_path, err });
        return 1;
    };
    defer config.deinit();

    const task_count = config.tasks.count();
    const project_root = std.fs.path.dirname(config_path) orelse ".";

    // Read .zr/last-failures.txt
    const failures_path = try std.fmt.allocPrint(allocator, "{s}/.zr/last-failures.txt", .{project_root});
    defer allocator.free(failures_path);

    var failed_tasks = std.ArrayList([]const u8){};
    defer {
        for (failed_tasks.items) |t| allocator.free(t);
        failed_tasks.deinit(allocator);
    }

    var has_run_history = false;

    if (std.fs.cwd().openFile(failures_path, .{})) |file| {
        defer file.close();
        has_run_history = true;
        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch "";
        defer allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len > 0) {
                try failed_tasks.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
    } else |_| {}

    if (options.json_output) {
        return printStatusJson(w, config_path, task_count, failed_tasks.items, has_run_history);
    }

    return printStatusText(w, config_path, task_count, failed_tasks.items, has_run_history, options.use_color);
}

fn printStatusText(w: *std.Io.Writer, config_path: []const u8, task_count: usize, failed_tasks: []const []const u8, has_run_history: bool, use_color: bool) !u8 {
    _ = use_color;

    try w.print("zr.toml  {s}\n", .{config_path});
    try w.print("Tasks    {d}\n\n", .{task_count});

    if (!has_run_history) {
        try w.print("No run history\n", .{});
    } else if (failed_tasks.len == 0) {
        try w.print("All tasks succeeded\n", .{});
    } else {
        try w.print("Last run failures ({d}):\n", .{failed_tasks.len});
        for (failed_tasks) |task| {
            try w.print("  ✗ {s}\n", .{task});
        }
        try w.print("\n  Hint: run \x1b[1mzr run --retry-failed\x1b[0m to retry\n", .{});
    }

    return 0;
}

fn printStatusJson(w: *std.Io.Writer, config_path: []const u8, task_count: usize, failed_tasks: []const []const u8, has_run_history: bool) !u8 {
    try w.print("{{\n", .{});
    try w.print("  \"config\": \"{s}\",\n", .{config_path});
    try w.print("  \"task_count\": {d},\n", .{task_count});
    try w.print("  \"has_run_history\": {s},\n", .{if (has_run_history) "true" else "false"});
    try w.print("  \"last_failures\": [", .{});
    for (failed_tasks, 0..) |task, i| {
        if (i > 0) try w.print(", ", .{});
        try w.print("\"{s}\"", .{task});
    }
    try w.print("]\n}}\n", .{});
    return 0;
}

test "cmdStatus: text output with no run history" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\
        \\[tasks.test]
        \\cmd = "test"
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

    const options = StatusOptions{ .config_path = config_path, .json_output = false, .use_color = false };
    const code = try cmdStatus(allocator, options, &out_w, &err_w);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "Tasks    2") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "No run history") != null);
}

test "cmdStatus: text output with run history and failures" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\
        \\[tasks.test]
        \\cmd = "test"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    // Create .zr directory and last-failures.txt
    try tmp.dir.makePath(".zr");
    const failures_content = "build\ntest\n";
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = failures_content });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const options = StatusOptions{ .config_path = config_path, .json_output = false, .use_color = false };
    const code = try cmdStatus(allocator, options, &out_w, &err_w);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "Last run failures (2)") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "test") != null);
}

test "cmdStatus: text output with run history but all succeeded" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    // Create .zr directory with empty last-failures.txt (all succeeded)
    try tmp.dir.makePath(".zr");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = "" });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const options = StatusOptions{ .config_path = config_path, .json_output = false, .use_color = false };
    const code = try cmdStatus(allocator, options, &out_w, &err_w);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "All tasks succeeded") != null);
}

test "cmdStatus: json output format" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\
        \\[tasks.test]
        \\cmd = "test"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    // Create failures file
    try tmp.dir.makePath(".zr");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = "build\n" });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const options = StatusOptions{ .config_path = config_path, .json_output = true, .use_color = false };
    const code = try cmdStatus(allocator, options, &out_w, &err_w);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "\"config\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"task_count\": 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"has_run_history\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"last_failures\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"build\"") != null);
}

test "cmdStatus: missing config file returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const options = StatusOptions{ .config_path = "/nonexistent/path/zr.toml", .json_output = false, .use_color = false };
    const code = try cmdStatus(allocator, options, &out_w, &err_w);
    try std.testing.expectEqual(@as(u8, 1), code);

    const written_err = err_buf[0..err_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written_err, "No zr.toml found") != null);
}
