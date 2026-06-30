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
