const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const types = @import("../config/types.zig");
const parser = @import("../config/parser.zig");

/// Interactive add command for creating tasks, workflows, and profiles.
/// Usage: zr add <task|workflow|profile> [name] [--interactive]
pub fn cmdAdd(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    if (args.len < 1) {
        try color.printError(ew, use_color, "add: missing type\n\n  Hint: zr add task | zr add workflow | zr add profile\n", .{});
        return 1;
    }

    // Check for --interactive flag
    var is_interactive = false;
    var name: ?[]const u8 = null;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--interactive")) {
            is_interactive = true;
        } else if (name == null) {
            name = arg;
        }
    }

    const add_type = args[0];

    // If interactive mode requested, check if TTY available
    if (is_interactive) {
        const add_interactive = @import("add_interactive.zig");
        if (!add_interactive.isTty()) {
            try color.printError(ew, use_color, "Interactive mode requires a TTY terminal.\n\n  Hint: Run without --interactive flag for prompt-based mode\n", .{});
            return 1;
        }

        if (std.mem.eql(u8, add_type, "task")) {
            return add_interactive.addTaskInteractive(allocator, name, config_path, w, ew, use_color);
        } else if (std.mem.eql(u8, add_type, "workflow")) {
            return add_interactive.addWorkflowInteractive(allocator, name, config_path, w, ew, use_color);
        } else {
            try color.printError(ew, use_color, "add: interactive mode not yet supported for '{s}'\n\n  Hint: Use 'task' or 'workflow'\n", .{add_type});
            return 1;
        }
    }

    if (std.mem.eql(u8, add_type, "task")) {
        return addTask(allocator, name, config_path, w, ew, use_color);
    } else if (std.mem.eql(u8, add_type, "workflow")) {
        return addWorkflow(allocator, name, config_path, w, ew, use_color);
    } else if (std.mem.eql(u8, add_type, "profile")) {
        return addProfile(allocator, name, config_path, w, ew, use_color);
    } else {
        try color.printError(ew, use_color, "add: unknown type '{s}'\n\n  Hint: zr add task | zr add workflow | zr add profile\n", .{add_type});
        return 1;
    }
}

/// Prompt user for input with a message.
fn prompt(allocator: std.mem.Allocator, w: anytype, ew: anytype, use_color: bool, message: []const u8) !?[]const u8 {
    try color.printBold(w, use_color, "{s}", .{message});
    try w.writeAll(": ");
    try w.flush(); // CRITICAL: flush before reading stdin on Windows

    const stdin = std.fs.File.stdin();

    // Read line from stdin byte by byte
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    var read_buf: [1]u8 = undefined;
    while (true) {
        const n = stdin.read(&read_buf) catch |err| {
            if (err == error.EndOfStream or err == error.NotOpenForReading) {
                try color.printError(ew, use_color, "\nCancelled by user\n", .{});
                return null;
            }
            return err;
        };
        if (n == 0) {
            // EOF
            try color.printError(ew, use_color, "\nCancelled by user\n", .{});
            return null;
        }
        const ch = read_buf[0];
        if (ch == '\n') break;
        if (ch != '\r') { // Skip carriage return
            try buffer.append(allocator, ch);
        }
    }

    const line = buffer.items;
    if (line.len == 0) {
        return null;
    }

    return try allocator.dupe(u8, line);
}

/// Prompt for yes/no question.
fn promptBool(allocator: std.mem.Allocator, w: anytype, ew: anytype, use_color: bool, message: []const u8) !bool {
    const response = try prompt(allocator, w, ew, use_color, message);
    defer if (response) |r| allocator.free(r);

    if (response) |r| {
        if (std.mem.eql(u8, r, "y") or std.mem.eql(u8, r, "Y") or std.mem.eql(u8, r, "yes") or std.mem.eql(u8, r, "Yes")) {
            return true;
        }
    }
    return false;
}

/// Interactive task creation.
fn addTask(
    allocator: std.mem.Allocator,
    name_arg: ?[]const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    try color.printBold(w, use_color, "\n=== Add New Task ===\n\n", .{});
    try w.flush(); // CRITICAL: flush header before prompts on Windows

    // Get task name
    const task_name = if (name_arg) |n| blk: {
        try color.printBold(w, use_color, "Task name: ", .{});
        try w.print("{s}\n", .{n});
        try w.flush(); // CRITICAL: flush after printing pre-filled value on Windows
        break :blk try allocator.dupe(u8, n);
    } else blk: {
        const name = try prompt(allocator, w, ew, use_color, "Task name");
        if (name == null) return 1;
        break :blk name.?;
    };
    defer allocator.free(task_name);

    // Get command
    const has_cmd = try promptBool(allocator, w, ew, use_color, "Add command? (y/n)");
    const cmd = if (has_cmd) blk: {
        const c = try prompt(allocator, w, ew, use_color, "Command");
        if (c == null) return 1;
        break :blk c.?;
    } else null;
    defer if (cmd) |c| allocator.free(c);

    // Get description
    const has_desc = try promptBool(allocator, w, ew, use_color, "Add description? (y/n)");
    const description = if (has_desc) blk: {
        const d = try prompt(allocator, w, ew, use_color, "Description");
        if (d == null) return 1;
        break :blk d.?;
    } else null;
    defer if (description) |d| allocator.free(d);

    // Get dependencies
    const has_deps = try promptBool(allocator, w, ew, use_color, "Add dependencies? (y/n)");
    const deps = if (has_deps) blk: {
        const d = try prompt(allocator, w, ew, use_color, "Dependencies (comma-separated)");
        if (d == null) return 1;
        break :blk d.?;
    } else null;
    defer if (deps) |d| allocator.free(d);

    // Build TOML entry
    var toml_entry = std.ArrayList(u8){};
    defer toml_entry.deinit(allocator);

    try toml_entry.writer(allocator).print("\n[tasks.{s}]\n", .{task_name});

    if (description) |d| {
        const escaped_desc = try escapeTomlString(allocator, d);
        defer if (escaped_desc.ptr != d.ptr) allocator.free(escaped_desc);
        try toml_entry.writer(allocator).print("description = \"{s}\"\n", .{escaped_desc});
    }

    if (cmd) |c| {
        const escaped_cmd = try escapeTomlString(allocator, c);
        defer if (escaped_cmd.ptr != c.ptr) allocator.free(escaped_cmd);
        try toml_entry.writer(allocator).print("cmd = \"{s}\"\n", .{escaped_cmd});
    }

    if (deps) |d| {
        try toml_entry.writer(allocator).writeAll("deps = [");
        var it = std.mem.splitSequence(u8, d, ",");
        var first = true;
        while (it.next()) |dep| {
            const trimmed = std.mem.trim(u8, dep, " \t\r\n");
            if (trimmed.len > 0) {
                if (!first) try toml_entry.writer(allocator).writeAll(", ");
                try toml_entry.writer(allocator).print("\"{s}\"", .{trimmed});
                first = false;
            }
        }
        try toml_entry.writer(allocator).writeAll("]\n");
    }

    // Append to config file
    const config_file = std.fs.cwd().openFile(config_path, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            try color.printError(ew, use_color, "add: config file not found: {s}\n\n  Hint: Run 'zr init' first\n", .{config_path});
            return 1;
        }
        return err;
    };
    defer config_file.close();

    // Seek to end and append
    try config_file.seekFromEnd(0);
    try config_file.writeAll(toml_entry.items);

    try color.printSuccess(w, use_color, "\n✓ Task '{s}' added to {s}\n", .{ task_name, config_path });

    return 0;
}

/// Interactive workflow creation.
fn addWorkflow(
    allocator: std.mem.Allocator,
    name_arg: ?[]const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    try color.printBold(w, use_color, "\n=== Add New Workflow ===\n\n", .{});
    try w.flush(); // CRITICAL: flush header before prompts on Windows

    // Get workflow name
    const workflow_name = if (name_arg) |n| blk: {
        try color.printBold(w, use_color, "Workflow name: ", .{});
        try w.print("{s}\n", .{n});
        try w.flush(); // CRITICAL: flush after printing pre-filled value on Windows
        break :blk try allocator.dupe(u8, n);
    } else blk: {
        const name = try prompt(allocator, w, ew, use_color, "Workflow name");
        if (name == null) return 1;
        break :blk name.?;
    };
    defer allocator.free(workflow_name);

    // Get description
    const has_desc = try promptBool(allocator, w, ew, use_color, "Add description? (y/n)");
    const description = if (has_desc) blk: {
        const d = try prompt(allocator, w, ew, use_color, "Description");
        if (d == null) return 1;
        break :blk d.?;
    } else null;
    defer if (description) |d| allocator.free(d);

    // Get stages
    try color.printBold(w, use_color, "Add stages (one per line, empty line to finish)\n", .{});
    try w.flush(); // CRITICAL: flush before prompts on Windows
    var stages = std.ArrayList([]const u8){};
    defer {
        for (stages.items) |stage| {
            allocator.free(stage);
        }
        stages.deinit(allocator);
    }

    var stage_index: usize = 1;
    while (true) {
        const stage_prompt = try std.fmt.allocPrint(allocator, "Stage {d} tasks (comma-separated, or empty to finish)", .{stage_index});
        defer allocator.free(stage_prompt);

        const stage_input = try prompt(allocator, w, ew, use_color, stage_prompt);
        if (stage_input == null or stage_input.?.len == 0) {
            if (stage_input) |s| allocator.free(s);
            break;
        }

        try stages.append(allocator, stage_input.?);
        stage_index += 1;
    }

    if (stages.items.len == 0) {
        try color.printError(ew, use_color, "add: workflow must have at least one stage\n", .{});
        return 1;
    }

    // Build TOML entry
    var toml_entry = std.ArrayList(u8){};
    defer toml_entry.deinit(allocator);

    try toml_entry.writer(allocator).print("\n[[workflows.{s}.stages]]\n", .{workflow_name});

    if (description) |d| {
        const escaped_desc = try escapeTomlString(allocator, d);
        defer if (escaped_desc.ptr != d.ptr) allocator.free(escaped_desc);
        try toml_entry.writer(allocator).print("description = \"{s}\"\n", .{escaped_desc});
    }

    for (stages.items) |stage_tasks| {
        try toml_entry.writer(allocator).writeAll("tasks = [");
        var it = std.mem.splitSequence(u8, stage_tasks, ",");
        var first = true;
        while (it.next()) |task| {
            const trimmed = std.mem.trim(u8, task, " \t\r\n");
            if (trimmed.len > 0) {
                if (!first) try toml_entry.writer(allocator).writeAll(", ");
                try toml_entry.writer(allocator).print("\"{s}\"", .{trimmed});
                first = false;
            }
        }
        try toml_entry.writer(allocator).writeAll("]\n");
    }

    // Append to config file
    const config_file = std.fs.cwd().openFile(config_path, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            try color.printError(ew, use_color, "add: config file not found: {s}\n\n  Hint: Run 'zr init' first\n", .{config_path});
            return 1;
        }
        return err;
    };
    defer config_file.close();

    // Seek to end and append
    try config_file.seekFromEnd(0);
    try config_file.writeAll(toml_entry.items);

    try color.printSuccess(w, use_color, "\n✓ Workflow '{s}' added to {s}\n", .{ workflow_name, config_path });

    return 0;
}

/// Interactive profile creation.
fn addProfile(
    allocator: std.mem.Allocator,
    name_arg: ?[]const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    try color.printBold(w, use_color, "\n=== Add New Profile ===\n\n", .{});
    try w.flush(); // CRITICAL: flush header before prompts on Windows

    // Get profile name
    const profile_name = if (name_arg) |n| blk: {
        try color.printBold(w, use_color, "Profile name: ", .{});
        try w.print("{s}\n", .{n});
        try w.flush(); // CRITICAL: flush after printing pre-filled value on Windows
        break :blk try allocator.dupe(u8, n);
    } else blk: {
        const name = try prompt(allocator, w, ew, use_color, "Profile name");
        if (name == null) return 1;
        break :blk name.?;
    };
    defer allocator.free(profile_name);

    // Get environment variables
    const has_env = try promptBool(allocator, w, ew, use_color, "Add environment variables? (y/n)");
    var env_vars = std.ArrayList(struct { key: []const u8, value: []const u8 }){};
    defer {
        for (env_vars.items) |item| {
            allocator.free(item.key);
            allocator.free(item.value);
        }
        env_vars.deinit(allocator);
    }

    if (has_env) {
        try color.printBold(w, use_color, "Add environment variables (one per line, format: KEY=VALUE, empty line to finish)\n", .{});
        try w.flush(); // CRITICAL: flush before prompts on Windows
        while (true) {
            const env_input = try prompt(allocator, w, ew, use_color, "Environment variable");
            if (env_input == null or env_input.?.len == 0) {
                if (env_input) |s| allocator.free(s);
                break;
            }

            // Parse KEY=VALUE
            var it = std.mem.splitSequence(u8, env_input.?, "=");
            const key = it.next() orelse {
                allocator.free(env_input.?);
                try color.printError(ew, use_color, "Invalid format. Use KEY=VALUE\n", .{});
                continue;
            };
            const value = it.rest();

            try env_vars.append(allocator, .{
                .key = try allocator.dupe(u8, std.mem.trim(u8, key, " \t")),
                .value = try allocator.dupe(u8, std.mem.trim(u8, value, " \t")),
            });

            allocator.free(env_input.?);
        }
    }

    // Build TOML entry
    var toml_entry = std.ArrayList(u8){};
    defer toml_entry.deinit(allocator);

    try toml_entry.writer(allocator).print("\n[profiles.{s}]\n", .{profile_name});

    if (env_vars.items.len > 0) {
        try toml_entry.writer(allocator).writeAll("env = {\n");
        for (env_vars.items) |item| {
            const escaped_value = try escapeTomlString(allocator, item.value);
            defer if (escaped_value.ptr != item.value.ptr) allocator.free(escaped_value);
            try toml_entry.writer(allocator).print("  {s} = \"{s}\",\n", .{ item.key, escaped_value });
        }
        try toml_entry.writer(allocator).writeAll("}\n");
    }

    // Append to config file
    const config_file = std.fs.cwd().openFile(config_path, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            try color.printError(ew, use_color, "add: config file not found: {s}\n\n  Hint: Run 'zr init' first\n", .{config_path});
            return 1;
        }
        return err;
    };
    defer config_file.close();

    // Seek to end and append
    try config_file.seekFromEnd(0);
    try config_file.writeAll(toml_entry.items);

    try color.printSuccess(w, use_color, "\n✓ Profile '{s}' added to {s}\n", .{ profile_name, config_path });

    return 0;
}

/// Escape special characters for TOML string values.
fn escapeTomlString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    // Check if escaping is needed
    var needs_escape = false;
    for (s) |c| {
        if (c == '"' or c == '\\' or c == '\n' or c == '\r' or c == '\t') {
            needs_escape = true;
            break;
        }
    }

    // If no escaping needed, return as-is
    if (!needs_escape) return s;

    // Build escaped string
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    for (s) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }

    return result.toOwnedSlice(allocator);
}

test "prompt basic functionality" {
    // This test would require mocking stdin, skip for now
}

test "escapeTomlString basic" {
    const allocator = std.testing.allocator;

    // No escaping needed
    const result1 = try escapeTomlString(allocator, "hello world");
    defer if (result1.ptr != "hello world".ptr) allocator.free(result1);
    try std.testing.expectEqualStrings("hello world", result1);

    // Quote escaping
    const result2 = try escapeTomlString(allocator, "say \"hello\"");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("say \\\"hello\\\"", result2);

    // Backslash escaping
    const result3 = try escapeTomlString(allocator, "path\\to\\file");
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("path\\\\to\\\\file", result3);

    // Newline escaping
    const result4 = try escapeTomlString(allocator, "line1\nline2");
    defer allocator.free(result4);
    try std.testing.expectEqualStrings("line1\\nline2", result4);
}
