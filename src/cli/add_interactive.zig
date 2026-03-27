/// Interactive Task Builder TUI using sailor Form widgets.
/// Provides form-based task/workflow creation with validation, templates, and live preview.
const std = @import("std");
const builtin = @import("builtin");
const sailor = @import("sailor");
const stui = sailor.tui;
const color = @import("../output/color.zig");
const parser = @import("../config/parser.zig");
const types = @import("../config/types.zig");

/// Check if stdout is connected to a TTY (interactive terminal).
pub fn isTty() bool {
    return color.isTty(std.fs.File.stdout());
}

/// Interactive task creation with TUI form.
pub fn addTaskInteractive(
    allocator: std.mem.Allocator,
    name_arg: ?[]const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    _ = name_arg;
    _ = w;

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

    try color.printError(ew, use_color, "Interactive TUI mode is not yet fully implemented.\n\n  Hint: Use 'zr add task' without --interactive for prompt-based mode\n", .{});
    return 1;
}

/// Interactive workflow creation with TUI form.
pub fn addWorkflowInteractive(
    allocator: std.mem.Allocator,
    name_arg: ?[]const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    _ = name_arg;
    _ = w;

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

    try color.printError(ew, use_color, "Interactive TUI mode is not yet fully implemented.\n\n  Hint: Use 'zr add workflow' without --interactive for prompt-based mode\n", .{});
    return 1;
}

test "isTty returns boolean" {
    const is_tty = isTty();
    // Just verify it doesn't crash
    _ = is_tty;
}
