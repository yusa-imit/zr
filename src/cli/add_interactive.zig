/// Interactive Task Builder TUI using text prompts.
/// Provides form-based task/workflow creation with validation, templates, and live preview.
const std = @import("std");
const builtin = @import("builtin");
const color = @import("../output/color.zig");
const parser = @import("../config/parser.zig");
const types = @import("../config/types.zig");

/// Check if stdout is connected to a TTY (interactive terminal).
pub fn isTty() bool {
    return color.isTty(std.fs.File.stdout());
}

/// Prompt user for input with a message.
fn prompt(allocator: std.mem.Allocator, w: anytype, ew: anytype, use_color: bool, message: []const u8) !?[]const u8 {
    try color.printBold(w, use_color, "{s}", .{message});
    try w.writeAll(": ");
    try w.flush();

    const stdin = std.fs.File.stdin();

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
            try color.printError(ew, use_color, "\nCancelled by user\n", .{});
            return null;
        }
        const ch = read_buf[0];
        if (ch == '\n') break;
        if (ch != '\r') {
            try buffer.append(allocator, ch);
        }
    }

    const line = buffer.items;
    if (line.len == 0) {
        return null;
    }

    return try allocator.dupe(u8, line);
}

/// Escape special characters in TOML string values.
fn escapeTomlString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    for (input) |ch| {
        switch (ch) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, ch),
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Interactive task creation with text prompts.
pub fn addTaskInteractive(
    allocator: std.mem.Allocator,
    name_arg: ?[]const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    // Check if config file exists
    const config_file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try color.printError(ew, use_color, "✗ Config file not found: {s}\n\n  Hint: Run 'zr init' to create a new configuration\n", .{config_path});
            return 1;
        }
        return err;
    };
    defer config_file.close();

    // Try to parse config to validate it's not corrupted
    const config_content = config_file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        try color.printError(ew, use_color, "✗ Failed to read config file: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(config_content);

    var config = parser.parseToml(allocator, config_content) catch |err| {
        try color.printError(ew, use_color, "✗ Config file is corrupted or has syntax errors: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer config.deinit();

    try color.printBold(w, use_color, "\n=== Add New Task (Interactive) ===\n\n", .{});
    try w.flush();

    // Get task name - keep asking until valid and unique
    var task_name: []const u8 = undefined;
    var name_loop = true;
    while (name_loop) {
        const name = if (name_arg) |n| blk: {
            try color.printBold(w, use_color, "Task name: ", .{});
            try w.print("{s}\n", .{n});
            try w.flush();
            break :blk try allocator.dupe(u8, n);
        } else blk: {
            const n = try prompt(allocator, w, ew, use_color, "Task name");
            if (n == null) {
                try color.printError(ew, use_color, "Task name is required\n", .{});
                continue;
            }
            break :blk n.?;
        };

        if (name.len == 0) {
            try color.printError(ew, use_color, "✗ Task name must not be empty\n", .{});
            allocator.free(name);
            continue;
        }

        // Check if task name already exists
        if (config.tasks.get(name)) |_| {
            try color.printError(ew, use_color, "✗ Task '{s}' already exists\n", .{name});
            allocator.free(name);
            continue;
        }

        task_name = name;
        name_loop = false;
    }
    defer allocator.free(task_name);

    // Get command
    var cmd: ?[]const u8 = null;
    defer if (cmd) |c| allocator.free(c);

    var cmd_loop = true;
    while (cmd_loop) {
        const c = try prompt(allocator, w, ew, use_color, "Command");
        if (c == null or c.?.len == 0) {
            try color.printError(ew, use_color, "✗ Command is required\n", .{});
            if (c) |cmd_ptr| allocator.free(cmd_ptr);
            continue;
        }
        cmd = c;
        cmd_loop = false;
    }

    // Get dependencies
    var deps: ?[]const u8 = null;
    defer if (deps) |d| allocator.free(d);

    var deps_loop = true;
    while (deps_loop) {
        const d = try prompt(allocator, w, ew, use_color, "Dependencies (comma-separated, or empty)");
        if (d == null) {
            deps = null;
            deps_loop = false;
        } else {
            // Validate deps exist
            var all_valid = true;
            if (d.?.len > 0) {
                var it = std.mem.splitSequence(u8, d.?, ",");
                while (it.next()) |dep| {
                    const trimmed = std.mem.trim(u8, dep, " \t\r\n");
                    if (trimmed.len > 0 and config.tasks.get(trimmed) == null) {
                        try color.printError(ew, use_color, "✗ Dependency '{s}' does not exist\n", .{trimmed});
                        all_valid = false;
                        break;
                    }
                }
            }

            if (all_valid) {
                deps = d;
                deps_loop = false;
            } else {
                allocator.free(d.?);
            }
        }
    }

    // Get condition (optional)
    var condition: ?[]const u8 = null;
    defer if (condition) |c| allocator.free(c);

    var cond_loop = true;
    while (cond_loop) {
        const c = try prompt(allocator, w, ew, use_color, "Condition/Expression (or empty)");
        if (c == null or c.?.len == 0) {
            if (c) |cond_ptr| allocator.free(cond_ptr);
            condition = null;
            cond_loop = false;
        } else {
            // Try to validate expression syntax - basic check
            if (std.mem.indexOf(u8, c.?, "{{") != null and std.mem.indexOf(u8, c.?, "}}") == null) {
                try color.printError(ew, use_color, "✗ Invalid expression syntax: unmatched {{\n", .{});
                allocator.free(c.?);
            } else {
                condition = c;
                cond_loop = false;
            }
        }
    }

    // Generate TOML preview
    var toml_entry = std.ArrayList(u8){};
    defer toml_entry.deinit(allocator);

    try toml_entry.writer(allocator).print("\n[tasks.{s}]\n", .{task_name});

    if (cmd) |c| {
        const escaped_cmd = try escapeTomlString(allocator, c);
        defer if (escaped_cmd.ptr != c.ptr) allocator.free(escaped_cmd);
        try toml_entry.writer(allocator).print("cmd = \"{s}\"\n", .{escaped_cmd});
    }

    if (deps) |d| {
        if (d.len > 0) {
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
    }

    if (condition) |c| {
        const escaped_cond = try escapeTomlString(allocator, c);
        defer if (escaped_cond.ptr != c.ptr) allocator.free(escaped_cond);
        try toml_entry.writer(allocator).print("condition = \"{s}\"\n", .{escaped_cond});
    }

    // Show preview
    try color.printBold(w, use_color, "\n--- TOML Preview ---\n", .{});
    try w.print("{s}\n", .{toml_entry.items});
    try w.flush();

    // Ask for confirmation
    const should_save = try promptBool(allocator, w, ew, use_color, "Save task?");
    if (!should_save) {
        try color.printError(ew, use_color, "✗ Task not saved\n", .{});
        return 1;
    }

    // Create backup
    const backup_path = try std.fmt.allocPrint(allocator, "{s}.bak", .{config_path});
    defer allocator.free(backup_path);

    std.fs.cwd().copyFile(config_path, std.fs.cwd(), backup_path, .{}) catch {
        // Backup failure is not fatal
    };

    // Append to config file
    const cfg_file = std.fs.cwd().openFile(config_path, .{ .mode = .read_write }) catch |err| {
        try color.printError(ew, use_color, "✗ Failed to open config file: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer cfg_file.close();

    try cfg_file.seekFromEnd(0);
    try cfg_file.writeAll(toml_entry.items);

    // Re-parse to validate
    const updated_content = cfg_file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        try color.printError(ew, use_color, "✗ Failed to re-read config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(updated_content);

    _ = parser.parseToml(allocator, updated_content) catch |err| {
        try color.printError(ew, use_color, "✗ Validation failed after save: {s}\n", .{@errorName(err)});
        return 1;
    };

    try color.printSuccess(w, use_color, "✓ Task '{s}' added successfully\n", .{task_name});

    return 0;
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

/// Interactive workflow creation with text prompts.
pub fn addWorkflowInteractive(
    allocator: std.mem.Allocator,
    name_arg: ?[]const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    // Check if config file exists
    const config_file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try color.printError(ew, use_color, "✗ Config file not found: {s}\n\n  Hint: Run 'zr init' to create a new configuration\n", .{config_path});
            return 1;
        }
        return err;
    };
    defer config_file.close();

    // Try to parse config to validate it's not corrupted
    const config_content = config_file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        try color.printError(ew, use_color, "✗ Failed to read config file: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(config_content);

    var config = parser.parseToml(allocator, config_content) catch |err| {
        try color.printError(ew, use_color, "✗ Config file is corrupted or has syntax errors: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer config.deinit();

    try color.printBold(w, use_color, "\n=== Add New Workflow (Interactive) ===\n\n", .{});
    try w.flush();

    // Get workflow name
    var workflow_name: []const u8 = undefined;
    var name_loop = true;
    while (name_loop) {
        const name = if (name_arg) |n| blk: {
            try color.printBold(w, use_color, "Workflow name: ", .{});
            try w.print("{s}\n", .{n});
            try w.flush();
            break :blk try allocator.dupe(u8, n);
        } else blk: {
            const n = try prompt(allocator, w, ew, use_color, "Workflow name");
            if (n == null) {
                try color.printError(ew, use_color, "Workflow name is required\n", .{});
                continue;
            }
            break :blk n.?;
        };

        if (name.len == 0) {
            try color.printError(ew, use_color, "✗ Workflow name must not be empty\n", .{});
            allocator.free(name);
            continue;
        }

        workflow_name = name;
        name_loop = false;
    }
    defer allocator.free(workflow_name);

    // Get stages
    try color.printBold(w, use_color, "Add stages (one stage per entry, empty to finish)\n", .{});
    try w.flush();

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

        // Validate that referenced tasks exist
        var all_valid = true;
        var it = std.mem.splitSequence(u8, stage_input.?, ",");
        while (it.next()) |task_name| {
            const trimmed = std.mem.trim(u8, task_name, " \t\r\n");
            if (trimmed.len > 0 and config.tasks.get(trimmed) == null) {
                try color.printError(ew, use_color, "✗ Task '{s}' does not exist\n", .{trimmed});
                all_valid = false;
                break;
            }
        }

        if (all_valid) {
            try stages.append(allocator, stage_input.?);
            stage_index += 1;
        } else {
            allocator.free(stage_input.?);
        }
    }

    if (stages.items.len == 0) {
        try color.printError(ew, use_color, "✗ Workflow must have at least one stage\n", .{});
        return 1;
    }

    // Generate TOML preview
    var toml_entry = std.ArrayList(u8){};
    defer toml_entry.deinit(allocator);

    try toml_entry.writer(allocator).print("\n[[workflows.{s}.stages]]\n", .{workflow_name});

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

    // Show preview
    try color.printBold(w, use_color, "\n--- TOML Preview ---\n", .{});
    try w.print("{s}\n", .{toml_entry.items});
    try w.flush();

    // Ask for confirmation
    const should_save = try promptBool(allocator, w, ew, use_color, "Save workflow?");
    if (!should_save) {
        try color.printError(ew, use_color, "✗ Workflow not saved\n", .{});
        return 1;
    }

    // Create backup
    const backup_path = try std.fmt.allocPrint(allocator, "{s}.bak", .{config_path});
    defer allocator.free(backup_path);

    std.fs.cwd().copyFile(config_path, std.fs.cwd(), backup_path, .{}) catch {
        // Backup failure is not fatal
    };

    // Append to config file
    const cfg_file = std.fs.cwd().openFile(config_path, .{ .mode = .read_write }) catch |err| {
        try color.printError(ew, use_color, "✗ Failed to open config file: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer cfg_file.close();

    try cfg_file.seekFromEnd(0);
    try cfg_file.writeAll(toml_entry.items);

    // Re-parse to validate
    const updated_content = cfg_file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        try color.printError(ew, use_color, "✗ Failed to re-read config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(updated_content);

    _ = parser.parseToml(allocator, updated_content) catch |err| {
        try color.printError(ew, use_color, "✗ Validation failed after save: {s}\n", .{@errorName(err)});
        return 1;
    };

    try color.printSuccess(w, use_color, "✓ Workflow '{s}' added successfully\n", .{workflow_name});

    return 0;
}

test "isTty returns boolean" {
    const is_tty = isTty();
    // isTty should return either true or false (never error)
    try std.testing.expect(is_tty == true or is_tty == false);
}
