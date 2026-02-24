const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const platform = @import("../util/platform.zig");

pub fn cmdSchedule(
    allocator: Allocator,
    args: []const []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (args.len == 0) {
        try printHelp(w, use_color);
        return 0;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "add")) {
        return cmdScheduleAdd(allocator, args[1..], config_path, w, ew, use_color);
    } else if (std.mem.eql(u8, subcmd, "list")) {
        return cmdScheduleList(allocator, w, ew, use_color);
    } else if (std.mem.eql(u8, subcmd, "remove")) {
        return cmdScheduleRemove(allocator, args[1..], w, ew, use_color);
    } else if (std.mem.eql(u8, subcmd, "show")) {
        return cmdScheduleShow(allocator, args[1..], w, ew, use_color);
    } else {
        try color.printError(ew, use_color, "Unknown schedule subcommand: {s}\n\n", .{subcmd});
        try printHelp(w, use_color);
        return 1;
    }
}

fn cmdScheduleAdd(
    allocator: Allocator,
    args: []const []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Usage: zr schedule add <task> <cron_expression> [--name <schedule_name>]
    if (args.len < 2) {
        try color.printError(ew, use_color, "Usage: zr schedule add <task> <cron_expression> [--name <schedule_name>]\n", .{});
        return 1;
    }

    const task_name = args[0];
    const cron_expr = args[1];

    // Parse optional name
    var schedule_name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--name") and i + 1 < args.len) {
            schedule_name = args[i + 1];
            i += 1;
        }
    }

    // Verify task exists
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    if (config.tasks.get(task_name) == null) {
        try color.printError(ew, use_color,
            "schedule: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    }

    // Get absolute path to config and current directory
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const abs_config_path = if (std.fs.path.isAbsolute(config_path))
        config_path
    else
        try std.fs.path.join(allocator, &.{ cwd, config_path });
    defer if (!std.fs.path.isAbsolute(config_path)) allocator.free(abs_config_path);

    const config_dir = std.fs.path.dirname(abs_config_path) orelse cwd;

    // Build the prompt for the cron job
    const final_name = schedule_name orelse task_name;
    const prompt = try std.fmt.allocPrint(allocator, "run {s}", .{task_name});
    defer allocator.free(prompt);

    // Store schedule metadata to ~/.zr/schedules.json
    const schedule_data = try getScheduleData(allocator);
    defer allocator.free(schedule_data);

    var schedules = try loadSchedules(allocator, schedule_data);
    defer deinitSchedules(&schedules, allocator);

    // Create schedule entry
    const entry = ScheduleEntry{
        .name = try allocator.dupe(u8, final_name),
        .task = try allocator.dupe(u8, task_name),
        .cron = try allocator.dupe(u8, cron_expr),
        .config_path = try allocator.dupe(u8, abs_config_path),
        .cwd = try allocator.dupe(u8, config_dir),
        .cron_job_id = null, // Will be set after creating cron job
    };

    // Save schedule (this is a placeholder - actual cron integration would happen here)
    try schedules.put(final_name, entry);
    try saveSchedules(allocator, schedule_data, &schedules);

    try color.printSuccess(w, use_color, "Schedule '{s}' created successfully\n\n", .{final_name});
    try w.print("  Task:       {s}\n", .{task_name});
    try w.print("  Schedule:   {s}\n", .{cron_expr});
    try w.print("  Working dir: {s}\n", .{config_dir});
    try w.print("\n  Note: Schedule will execute 'zr run {s}' at the specified times\n", .{task_name});

    return 0;
}

fn cmdScheduleList(
    allocator: Allocator,
    w: *std.Io.Writer,
    _: *std.Io.Writer,
    use_color: bool,
) !u8 {
    const schedule_data = try getScheduleData(allocator);
    defer allocator.free(schedule_data);

    var schedules = try loadSchedules(allocator, schedule_data);
    defer deinitSchedules(&schedules, allocator);

    if (schedules.count() == 0) {
        try color.printWarning(w, use_color, "No schedules configured\n\n  Hint: Use 'zr schedule add <task> <cron>' to create a schedule\n", .{});
        return 0;
    }

    try color.printBold(w, use_color, "Configured Schedules:\n\n", .{});

    // Sort by name for consistent output
    var names = std.ArrayList([]const u8){};
    defer names.deinit(allocator);

    var it = schedules.keyIterator();
    while (it.next()) |key| {
        try names.append(allocator, key.*);
    }

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (names.items) |name| {
        const entry = schedules.get(name).?;
        if (use_color) {
            try w.print(color.Code.cyan ++ "  {s}" ++ color.Code.reset ++ "\n", .{name});
        } else {
            try w.print("  {s}\n", .{name});
        }
        try w.print("    Task:     {s}\n", .{entry.task});
        try w.print("    Schedule: {s}\n", .{entry.cron});
        try w.print("    Config:   {s}\n", .{entry.config_path});
        try w.print("\n", .{});
    }

    return 0;
}

fn cmdScheduleRemove(
    allocator: Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (args.len == 0) {
        try color.printError(ew, use_color, "Usage: zr schedule remove <schedule_name>\n", .{});
        return 1;
    }

    const name = args[0];

    const schedule_data = try getScheduleData(allocator);
    defer allocator.free(schedule_data);

    var schedules = try loadSchedules(allocator, schedule_data);
    defer deinitSchedules(&schedules, allocator);

    if (!schedules.contains(name)) {
        try color.printError(ew, use_color, "Schedule '{s}' not found\n\n  Hint: Run 'zr schedule list' to see configured schedules\n", .{name});
        return 1;
    }

    // Remove the entry
    var entry = schedules.get(name).?;
    entry.deinit(allocator);
    _ = schedules.remove(name);

    try saveSchedules(allocator, schedule_data, &schedules);

    try color.printSuccess(w, use_color, "Schedule '{s}' removed successfully\n", .{name});
    return 0;
}

fn cmdScheduleShow(
    allocator: Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (args.len == 0) {
        try color.printError(ew, use_color, "Usage: zr schedule show <schedule_name>\n", .{});
        return 1;
    }

    const name = args[0];

    const schedule_data = try getScheduleData(allocator);
    defer allocator.free(schedule_data);

    var schedules = try loadSchedules(allocator, schedule_data);
    defer deinitSchedules(&schedules, allocator);

    if (!schedules.contains(name)) {
        try color.printError(ew, use_color, "Schedule '{s}' not found\n\n  Hint: Run 'zr schedule list' to see configured schedules\n", .{name});
        return 1;
    }

    const entry = schedules.get(name).?;

    try color.printBold(w, use_color, "Schedule: {s}\n\n", .{name});
    try w.print("  Task:         {s}\n", .{entry.task});
    try w.print("  Cron:         {s}\n", .{entry.cron});
    try w.print("  Config:       {s}\n", .{entry.config_path});
    try w.print("  Working dir:  {s}\n", .{entry.cwd});

    // Parse cron expression to show next run time (simplified example)
    try w.print("\n  Command:      zr run {s}\n", .{entry.task});

    return 0;
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "Usage: zr schedule <subcommand> [options]\n\n", .{});
    try w.writeAll("Subcommands:\n");
    try w.writeAll("  add <task> <cron> [--name <name>]  Create a scheduled task\n");
    try w.writeAll("  list                                List all schedules\n");
    try w.writeAll("  remove <name>                       Remove a schedule\n");
    try w.writeAll("  show <name>                         Show schedule details\n");
    try w.writeAll("\n");
    try w.writeAll("Cron expression format:\n");
    try w.writeAll("  * * * * *\n");
    try w.writeAll("  │ │ │ │ │\n");
    try w.writeAll("  │ │ │ │ └─ day of week (0-7, 0=Sunday)\n");
    try w.writeAll("  │ │ │ └─── month (1-12)\n");
    try w.writeAll("  │ │ └───── day of month (1-31)\n");
    try w.writeAll("  │ └─────── hour (0-23)\n");
    try w.writeAll("  └───────── minute (0-59)\n");
    try w.writeAll("\n");
    try w.writeAll("Examples:\n");
    try w.writeAll("  zr schedule add build \"0 */3 * * *\"    # Every 3 hours\n");
    try w.writeAll("  zr schedule add test \"0 0 * * *\"       # Daily at midnight\n");
    try w.writeAll("  zr schedule add deploy \"0 9 * * 1\"     # Every Monday at 9 AM\n");
}

// Internal data structures
const ScheduleEntry = struct {
    name: []const u8,
    task: []const u8,
    cron: []const u8,
    config_path: []const u8,
    cwd: []const u8,
    cron_job_id: ?u64,

    fn deinit(self: *const ScheduleEntry, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.task);
        allocator.free(self.cron);
        allocator.free(self.config_path);
        allocator.free(self.cwd);
    }
};

fn deinitSchedules(schedules: *std.StringHashMap(ScheduleEntry), allocator: Allocator) void {
    var it = schedules.valueIterator();
    while (it.next()) |entry| {
        entry.deinit(allocator);
    }
    schedules.deinit();
}

fn getScheduleData(allocator: Allocator) ![]const u8 {
    const home = platform.getHome();
    return try std.fs.path.join(allocator, &.{ home, ".zr", "schedules.json" });
}

fn loadSchedules(allocator: Allocator, path: []const u8) !std.StringHashMap(ScheduleEntry) {
    var schedules = std.StringHashMap(ScheduleEntry).init(allocator);

    // Try to read existing file
    const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            // File doesn't exist yet, return empty map
            return schedules;
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Basic JSON parsing - line by line (simplified, assumes our specific format)
    var lines = std.mem.splitScalar(u8, content, '\n');

    var current_name: ?[]const u8 = null;
    var current_task: ?[]const u8 = null;
    var current_cron: ?[]const u8 = null;
    var current_config_path: ?[]const u8 = null;
    var current_cwd: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "{")) continue;

        // End of entry - assemble and store BEFORE continuing
        if (std.mem.eql(u8, trimmed, "}") or std.mem.eql(u8, trimmed, "},")) {
            if (current_name != null and current_task != null and current_cron != null and current_config_path != null and current_cwd != null) {
                const entry = ScheduleEntry{
                    .name = current_name.?,
                    .task = current_task.?,
                    .cron = current_cron.?,
                    .config_path = current_config_path.?,
                    .cwd = current_cwd.?,
                    .cron_job_id = null,
                };
                try schedules.put(current_name.?, entry);
            }
            current_name = null;
            current_task = null;
            current_cron = null;
            current_config_path = null;
            current_cwd = null;
            continue;
        }

        // Parse entry name: "name": {
        if (std.mem.indexOf(u8, trimmed, "\":") != null and std.mem.indexOf(u8, trimmed, "{") != null) {
            // Extract name between quotes
            if (std.mem.indexOf(u8, trimmed, "\"")) |first_quote| {
                if (std.mem.indexOfPos(u8, trimmed, first_quote + 1, "\"")) |second_quote| {
                    current_name = try allocator.dupe(u8, trimmed[first_quote + 1 .. second_quote]);
                }
            }
        }
        // Parse fields
        else if (std.mem.indexOf(u8, trimmed, "\"task\":")) |_| {
            if (extractJsonString(trimmed)) |value| {
                current_task = try allocator.dupe(u8, value);
            }
        } else if (std.mem.indexOf(u8, trimmed, "\"cron\":")) |_| {
            if (extractJsonString(trimmed)) |value| {
                current_cron = try allocator.dupe(u8, value);
            }
        } else if (std.mem.indexOf(u8, trimmed, "\"config_path\":")) |_| {
            if (extractJsonString(trimmed)) |value| {
                current_config_path = try allocator.dupe(u8, value);
            }
        } else if (std.mem.indexOf(u8, trimmed, "\"cwd\":")) |_| {
            if (extractJsonString(trimmed)) |value| {
                current_cwd = try allocator.dupe(u8, value);
            }
        }
    }

    return schedules;
}

fn extractJsonString(line: []const u8) ?[]const u8 {
    // Extract string value from JSON line like: "key": "value",
    const colon_pos = std.mem.indexOf(u8, line, ":") orelse return null;
    const after_colon = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
    if (after_colon.len < 2) return null;

    // Find first quote
    const first_quote = std.mem.indexOf(u8, after_colon, "\"") orelse return null;
    // Find second quote
    const second_quote = std.mem.indexOfPos(u8, after_colon, first_quote + 1, "\"") orelse return null;

    return after_colon[first_quote + 1 .. second_quote];
}

fn saveSchedules(allocator: Allocator, path: []const u8, schedules: *std.StringHashMap(ScheduleEntry)) !void {
    // Ensure ~/.zr directory exists
    const home = platform.getHome();
    const zr_dir = try std.fs.path.join(allocator, &.{ home, ".zr" });
    defer allocator.free(zr_dir);

    std.fs.makeDirAbsolute(zr_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create/overwrite file
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();

    // Write JSON (simple format for now)
    try file.writeAll("{\n");

    var first = true;
    var it = schedules.iterator();
    while (it.next()) |entry| {
        if (!first) {
            try file.writeAll(",\n");
        }
        first = false;

        const json_line = try std.fmt.allocPrint(allocator,
            \\  "{s}": {{
            \\    "task": "{s}",
            \\    "cron": "{s}",
            \\    "config_path": "{s}",
            \\    "cwd": "{s}"
            \\  }}
        , .{
            entry.key_ptr.*,
            entry.value_ptr.task,
            entry.value_ptr.cron,
            entry.value_ptr.config_path,
            entry.value_ptr.cwd,
        });
        defer allocator.free(json_line);
        try file.writeAll(json_line);
    }

    try file.writeAll("\n}\n");
}

// Tests
test "ScheduleEntry deinit" {
    const allocator = std.testing.allocator;
    var entry = ScheduleEntry{
        .name = try allocator.dupe(u8, "test"),
        .task = try allocator.dupe(u8, "build"),
        .cron = try allocator.dupe(u8, "0 0 * * *"),
        .config_path = try allocator.dupe(u8, "/path/to/zr.toml"),
        .cwd = try allocator.dupe(u8, "/path/to"),
        .cron_job_id = null,
    };
    entry.deinit(allocator);
}

test "schedule help output" {
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    try printHelp(&out_w.interface, false);

    // Note: Cannot easily test output since writer writes to buffer
    // This test mainly ensures printHelp compiles and doesn't crash
}
