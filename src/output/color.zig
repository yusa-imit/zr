/// ANSI color/style codes for terminal output.
/// Automatically disabled when stdout is not a TTY (e.g., pipes, CI).
const std = @import("std");
const builtin = @import("builtin");

/// ANSI escape codes
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
        // Not a console or failed to get mode
        return false;
    }

    // ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

    // Enable Virtual Terminal Processing
    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if (windows.kernel32.SetConsoleMode(handle, mode) == 0) {
        // Failed to set mode
        return false;
    }

    return true;
}

/// Returns true if the given file descriptor appears to be a TTY
/// and supports ANSI color codes.
/// On Windows, this also enables Virtual Terminal Processing.
pub fn isTty(file: std.fs.File) bool {
    if (!file.isTty()) {
        return false;
    }

    // On Windows, check if we can enable ANSI support
    if (comptime builtin.os.tag == .windows) {
        return enableWindowsAnsiSupport(file);
    }

    return true;
}

/// Semantic print helpers. Pass `use_color = isTty(stdout)` from caller.

pub fn printSuccess(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try w.print(Code.bright_green ++ "✓" ++ Code.reset ++ " " ++ fmt, args);
    } else {
        try w.print("✓ " ++ fmt, args);
    }
}

pub fn printError(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try w.print(Code.bright_red ++ "✗" ++ Code.reset ++ " " ++ fmt, args);
    } else {
        try w.print("✗ " ++ fmt, args);
    }
}

pub fn printInfo(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try w.print(Code.bright_cyan ++ "→" ++ Code.reset ++ " " ++ fmt, args);
    } else {
        try w.print("→ " ++ fmt, args);
    }
}

pub fn printWarning(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try w.print(Code.bright_yellow ++ "⚠" ++ Code.reset ++ " " ++ fmt, args);
    } else {
        try w.print("⚠ " ++ fmt, args);
    }
}

pub fn printBold(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try w.print(Code.bold ++ fmt ++ Code.reset, args);
    } else {
        try w.print(fmt, args);
    }
}

pub fn printDim(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try w.print(Code.dim ++ fmt ++ Code.reset, args);
    } else {
        try w.print(fmt, args);
    }
}

pub fn printHeader(w: *std.Io.Writer, use_color: bool, comptime fmt: []const u8, args: anytype) !void {
    if (use_color) {
        try w.print(Code.bold ++ Code.bright_white ++ fmt ++ Code.reset ++ "\n", args);
    } else {
        try w.print(fmt ++ "\n", args);
    }
}

pub fn taskLabel(w: *std.Io.Writer, use_color: bool, name: []const u8) !void {
    if (use_color) {
        try w.print(Code.bold ++ Code.blue ++ "[{s}]" ++ Code.reset ++ " ", .{name});
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
