/// Error code system for standardized error messages across zr.
/// Each error has a unique code (E001, E002, etc.) for documentation lookup.
const std = @import("std");

/// Error code enum with all known error categories.
pub const ErrorCode = enum(u16) {
    // Config errors (E001-E099)
    config_parse_error = 1,
    config_not_found = 2,
    config_syntax_error = 3,
    config_invalid_field = 4,
    config_missing_required = 5,
    config_circular_dependency = 6,
    config_duplicate_task = 7,
    config_invalid_expression = 8,
    config_import_failed = 9,
    config_invalid_task_name = 10,

    // Task errors (E100-E199)
    task_not_found = 100,
    task_failed = 101,
    task_timeout = 102,
    task_missing_dependency = 103,
    task_invalid_command = 104,
    task_execution_error = 105,

    // Workflow errors (E200-E299)
    workflow_not_found = 200,
    workflow_invalid_stage = 201,
    workflow_matrix_error = 202,

    // Plugin errors (E300-E399)
    plugin_not_found = 300,
    plugin_load_failed = 301,
    plugin_invalid_config = 302,

    // Toolchain errors (E400-E499)
    toolchain_not_found = 400,
    toolchain_download_failed = 401,
    toolchain_invalid_version = 402,

    // System errors (E500-E599)
    system_io_error = 500,
    system_permission_denied = 501,
    system_out_of_memory = 502,

    pub fn format(code: ErrorCode, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("E{d:0>3}", .{@intFromEnum(code)});
    }
};

/// Error detail with code, message, hint, and optional context.
pub const ErrorDetail = struct {
    code: ErrorCode,
    message: []const u8,
    hint: ?[]const u8 = null,
    context: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    line: ?usize = null,
    column: ?usize = null,

    /// Format the error detail with colors and structure.
    pub fn print(
        self: ErrorDetail,
        writer: anytype,
        use_color: bool,
    ) !void {
        const color = @import("../output/color.zig");

        // Error symbol and code (build manually to avoid writer type issues)
        if (use_color) {
            try writer.writeAll("\x1b[91m"); // bright red
            try writer.writeAll("✗");
            try writer.writeAll("\x1b[0m"); // reset
            try writer.writeAll(" ");
        } else {
            try writer.writeAll("✗ ");
        }
        // Format error code manually to avoid Zig 0.15 format ambiguity
        try writer.print("[E{d:0>3}]: {s}\n", .{ @intFromEnum(self.code), self.message });

        // Location info if available
        if (self.file_path) |path| {
            try writer.writeAll("\n  ");
            if (use_color) {
                try writer.writeAll(color.Code.dim);
            }
            try writer.print("at {s}", .{path});
            if (self.line) |line| {
                try writer.print(":{d}", .{line});
                if (self.column) |col| {
                    try writer.print(":{d}", .{col});
                }
            }
            if (use_color) {
                try writer.writeAll(color.Code.reset);
            }
            try writer.writeAll("\n");
        }

        // Context snippet if available
        if (self.context) |ctx| {
            try writer.writeAll("\n  ");
            if (use_color) {
                try writer.writeAll(color.Code.dim);
            }
            try writer.print("{s}", .{ctx});
            if (use_color) {
                try writer.writeAll(color.Code.reset);
            }
            try writer.writeAll("\n");
        }

        // Hint for resolution
        if (self.hint) |hint| {
            try writer.writeAll("\n  ");
            if (use_color) {
                try writer.writeAll(color.Code.cyan);
            }
            try writer.print("Hint: {s}", .{hint});
            if (use_color) {
                try writer.writeAll(color.Code.reset);
            }
            try writer.writeAll("\n");
        }

        try writer.writeAll("\n");
    }
};

/// Common error factory functions for frequently used errors.
pub const errors = struct {
    pub fn taskNotFound(task_name: []const u8, suggestions: ?[]const []const u8) ErrorDetail {
        var hint_buf: [512]u8 = undefined;
        const hint = if (suggestions) |sugg| blk: {
            if (sugg.len > 0) {
                var stream = std.io.fixedBufferStream(&hint_buf);
                const writer = stream.writer();
                writer.print("Did you mean one of these tasks?\n", .{}) catch break :blk null;
                for (sugg) |s| {
                    writer.print("    - {s}\n", .{s}) catch break :blk null;
                }
                break :blk stream.getWritten();
            }
            break :blk "Run 'zr list' to see all available tasks";
        } else "Run 'zr list' to see all available tasks";

        return .{
            .code = .task_not_found,
            .message = task_name,
            .hint = hint,
        };
    }

    pub fn configNotFound(path: []const u8) ErrorDetail {
        return .{
            .code = .config_not_found,
            .message = path,
            .hint = "Run 'zr init' to create a new configuration file",
        };
    }

    pub fn circularDependency(cycle: []const u8) ErrorDetail {
        return .{
            .code = .config_circular_dependency,
            .message = "Circular dependency detected",
            .context = cycle,
            .hint = "Remove one of the dependencies to break the cycle",
        };
    }

    pub fn invalidExpression(expr: []const u8, reason: []const u8) ErrorDetail {
        return .{
            .code = .config_invalid_expression,
            .message = reason,
            .context = expr,
            .hint = "Check the expression syntax. Valid operators: ==, !=, <, >, <=, >=, &&, ||",
        };
    }
};

// Tests
const testing = std.testing;

test "ErrorCode format" {
    var buf: [256]u8 = undefined;
    // Format using the manual approach to match the actual usage
    const result = try std.fmt.bufPrint(&buf, "E{d:0>3}", .{@intFromEnum(ErrorCode.task_not_found)});
    try testing.expectEqualStrings("E100", result);

    const result2 = try std.fmt.bufPrint(&buf, "E{d:0>3}", .{@intFromEnum(ErrorCode.config_parse_error)});
    try testing.expectEqualStrings("E001", result2);
}

test "ErrorDetail print without colors" {
    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    const err = ErrorDetail{
        .code = .task_not_found,
        .message = "build",
        .hint = "Run 'zr list' to see all tasks",
    };

    try err.print(&writer, false);
    const output = stream.getWritten();

    try testing.expect(std.mem.indexOf(u8, output, "E100") != null);
    try testing.expect(std.mem.indexOf(u8, output, "build") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Hint:") != null);
}

test "ErrorDetail print with location" {
    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    const err = ErrorDetail{
        .code = .config_syntax_error,
        .message = "Expected '=' after key",
        .file_path = "zr.toml",
        .line = 42,
        .column = 10,
        .context = "tasks.build",
        .hint = "Add '=' between the key and value",
    };

    try err.print(&writer, false);
    const output = stream.getWritten();

    try testing.expect(std.mem.indexOf(u8, output, "zr.toml:42:10") != null);
    try testing.expect(std.mem.indexOf(u8, output, "tasks.build") != null);
}

test "errors.taskNotFound without suggestions" {
    const err = errors.taskNotFound("missing-task", null);
    try testing.expectEqual(ErrorCode.task_not_found, err.code);
    try testing.expectEqualStrings("missing-task", err.message);
}

test "errors.configNotFound" {
    const err = errors.configNotFound("/path/to/zr.toml");
    try testing.expectEqual(ErrorCode.config_not_found, err.code);
    try testing.expect(std.mem.indexOf(u8, err.hint.?, "zr init") != null);
}

test "errors.circularDependency" {
    const err = errors.circularDependency("A -> B -> C -> A");
    try testing.expectEqual(ErrorCode.config_circular_dependency, err.code);
    try testing.expectEqualStrings("A -> B -> C -> A", err.context.?);
}

test "errors.invalidExpression" {
    const err = errors.invalidExpression("${foo bar}", "Unexpected token 'bar'");
    try testing.expectEqual(ErrorCode.config_invalid_expression, err.code);
    try testing.expectEqualStrings("${foo bar}", err.context.?);
}
