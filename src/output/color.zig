/// ANSI color/style codes for terminal output.
/// Automatically disabled when stdout is not a TTY (e.g., pipes, CI).
///
/// Backend: sailor.color (https://github.com/yusa-imit/sailor)
/// This module wraps sailor.color to maintain the existing public API.
const std = @import("std");
const builtin = @import("builtin");
const sailor = @import("sailor");
const sailor_color = sailor.color;

/// ANSI escape codes — kept as compile-time string constants for
/// backward compatibility with inline concatenation patterns used
/// throughout the codebase. These match the codes sailor.color would emit.
pub const Code = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";

    // Foreground colors
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const bright_red = "\x1b[91m";
    pub const bright_green = "\x1b[92m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_blue = "\x1b[94m";
    pub const bright_cyan = "\x1b[96m";
    pub const bright_white = "\x1b[97m";
};

// Sailor-based style definitions for semantic print helpers.
const styles = struct {
    const success = sailor_color.Style{
        .fg = .{ .basic = .bright_green },
    };
    const err = sailor_color.Style{
        .fg = .{ .basic = .bright_red },
    };
    const info = sailor_color.Style{
        .fg = .{ .basic = .bright_cyan },
    };
    const warn = sailor_color.Style{
        .fg = .{ .basic = .bright_yellow },
    };
    const bold_style = sailor_color.Style{
        .attrs = .{ .bold = true },
    };
    const dim_style = sailor_color.Style{
        .attrs = .{ .dim = true },
    };
    const header = sailor_color.Style{
        .fg = .{ .basic = .bright_white },
        .attrs = .{ .bold = true },
    };
    const task = sailor_color.Style{
        .fg = .{ .basic = .blue },
        .attrs = .{ .bold = true },
    };
};

/// Enables Windows Virtual Terminal Processing for ANSI color support.
/// On Windows, this must be called before using ANSI codes.
/// Returns true if ANSI codes are supported (always true on non-Windows).
fn enableWindowsAnsiSupport(file: std.fs.File) bool {
    if (comptime builtin.os.tag != .windows) {
        return true;
    }

    // Windows-specific code to enable Virtual Terminal Processing
    const windows = std.os.windows;
    const handle = file.handle;

    // Get current console mode
    var mode: windows.DWORD = 0;
    if (windows.kernel32.GetConsoleMode(handle, &mode) == 0) {
        return false;
    }

    const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if (windows.kernel32.SetConsoleMode(handle, mode) == 0) {
        return false;
    }

    return true;
}

/// Returns true if the given file descriptor appears to be a TTY
/// and supports ANSI color codes.
/// On Windows, this also enables Virtual Terminal Processing.
pub fn isTty(file: std.fs.File) bool {
    // Cross-platform TTY detection (workaround for sailor#3)
    const is_tty = switch (builtin.os.tag) {
        .linux, .macos => blk: {
            const posix = std.posix;
            break :blk posix.isatty(file.handle);
        },
        .windows => blk: {
            const windows = std.os.windows;
            // On Windows, file.handle is HANDLE (*anyopaque)
            // Check if it's a console by calling GetConsoleMode
            var mode: windows.DWORD = 0;
            break :blk windows.kernel32.GetConsoleMode(file.handle, &mode) != 0;
        },
        else => false,
    };

    if (!is_tty) {
        return false;
    }

    // On Windows, enable VT processing for ANSI support
    if (comptime builtin.os.tag == .windows) {
        return enableWindowsAnsiSupport(file);
    }

    return true;
}

/// Semantic print helpers. Pass `use_color = isTty(stdout)` from caller.

pub fn printSuccess(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.success, "\xe2\x9c\x93", .{});
        try w.print(" " ++ fmt, args);
    } else {
        try w.print("\xe2\x9c\x93 " ++ fmt, args);
    }
}

pub fn printError(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.err, "\xe2\x9c\x97", .{});
        try w.print(" " ++ fmt, args);
    } else {
        try w.print("\xe2\x9c\x97 " ++ fmt, args);
    }
}

pub fn printInfo(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.info, "\xe2\x86\x92", .{});
        try w.print(" " ++ fmt, args);
    } else {
        try w.print("\xe2\x86\x92 " ++ fmt, args);
    }
}

pub fn printWarning(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.warn, "\xe2\x9a\xa0", .{});
        try w.print(" " ++ fmt, args);
    } else {
        try w.print("\xe2\x9a\xa0 " ++ fmt, args);
    }
}

pub fn printBold(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.bold_style, fmt, args);
    } else {
        try w.print(fmt, args);
    }
}

pub fn printDim(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.dim_style, fmt, args);
    } else {
        try w.print(fmt, args);
    }
}

pub fn printHeader(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.header, fmt, args);
        try w.writeAll("\n");
    } else {
        try w.print(fmt ++ "\n", args);
    }
}

pub fn taskLabel(w: *std.Io.Writer, use_color: bool, name: []const u8) !void {
    if (use_color) {
        try sailor_color.printStyled(w, styles.task, "[{s}]", .{name});
        try w.writeAll(" ");
    } else {
        try w.print("[{s}] ", .{name});
    }
}

test "color codes are non-empty" {
    try std.testing.expect(Code.reset.len > 0);
    try std.testing.expect(Code.green.len > 0);
    try std.testing.expect(Code.red.len > 0);
}

test "color functions compile and exist" {
    // Smoke test: compile-time check that the functions exist with correct signatures
    _ = &printSuccess;
    _ = &printError;
    _ = &printInfo;
    _ = &printBold;
    _ = &printDim;
    _ = &printHeader;
    _ = &taskLabel;
}

test "sailor style definitions are valid" {
    // Verify sailor-based styles have expected properties
    try std.testing.expect(styles.success.fg == .basic);
    try std.testing.expect(styles.err.fg == .basic);
    try std.testing.expect(styles.info.fg == .basic);
    try std.testing.expect(styles.warn.fg == .basic);
    try std.testing.expect(styles.bold_style.attrs.bold);
    try std.testing.expect(styles.dim_style.attrs.dim);
    try std.testing.expect(styles.header.attrs.bold);
    try std.testing.expect(styles.task.attrs.bold);
}
