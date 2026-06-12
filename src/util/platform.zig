const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

/// Cross-platform HOME directory lookup.
/// Returns "." on Windows (where POSIX getenv is unavailable).
pub fn getHome() []const u8 {
    if (comptime native_os == .windows) return ".";
    return std.posix.getenv("HOME") orelse ".";
}

/// Cross-platform process kill.
/// Sends SIGKILL on POSIX; uses TerminateProcess on Windows.
pub fn killProcess(pid: std.process.Child.Id) void {
    if (comptime native_os == .windows) {
        const windows = std.os.windows;
        const handle: windows.HANDLE = @ptrCast(pid);
        windows.TerminateProcess(handle, 1) catch {};
    } else {
        std.posix.kill(pid, std.posix.SIG.KILL) catch {};
    }
}

/// Cross-platform process pause.
/// Sends SIGSTOP on POSIX; no-op on Windows.
pub fn pauseProcess(pid: std.process.Child.Id) void {
    if (comptime native_os == .windows) return;
    std.posix.kill(pid, std.posix.SIG.STOP) catch {};
}

/// Cross-platform process resume.
/// Sends SIGCONT on POSIX; no-op on Windows.
pub fn resumeProcess(pid: std.process.Child.Id) void {
    if (comptime native_os == .windows) return;
    std.posix.kill(pid, std.posix.SIG.CONT) catch {};
}

/// Cross-platform getenv wrapper.
/// Returns null on Windows (where POSIX getenv is unavailable).
pub fn getenv(key: []const u8) ?[:0]const u8 {
    if (comptime native_os == .windows) return null;
    return std.posix.getenv(key);
}

// Tests
test "getHome returns valid path" {
    const home = getHome();
    try std.testing.expect(home.len > 0);
    if (comptime native_os != .windows) {
        // On POSIX, HOME should be set
        try std.testing.expect(!std.mem.eql(u8, home, ".") or std.posix.getenv("HOME") == null);
    } else {
        // On Windows, should return "."
        try std.testing.expectEqualStrings(".", home);
    }
}

test "killProcess handles invalid PID without panic" {
    // killProcess silently ignores errors (no-op on invalid PIDs).
    // The test verifies no panic/crash occurs for clearly invalid inputs.
    if (comptime native_os != .windows) {
        killProcess(999999); // ESRCH from kernel, caught internally
        killProcess(1); // permission denied for init, caught internally
    } else {
        killProcess(0); // invalid handle, TerminateProcess failure caught internally
    }
    // If we reach here, no panic occurred — that IS the assertion
}

test "getenv returns env vars on POSIX" {
    if (comptime native_os == .windows) {
        // Windows always returns null
        try std.testing.expectEqual(@as(?[:0]const u8, null), getenv("PATH"));
    } else {
        // PATH should exist on all POSIX systems
        const path = getenv("PATH");
        try std.testing.expect(path != null);
        if (path) |p| {
            try std.testing.expect(p.len > 0);
            // Verify PATH contains reasonable path separators
            const has_separator = std.mem.indexOfScalar(u8, p, ':') != null or
                std.mem.indexOfScalar(u8, p, '/') != null;
            try std.testing.expect(has_separator);
        }
    }
}
