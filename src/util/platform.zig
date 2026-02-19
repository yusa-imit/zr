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
/// Sends SIGKILL on POSIX; no-op on Windows.
pub fn killProcess(pid: std.process.Child.Id) void {
    if (comptime native_os == .windows) return;
    std.posix.kill(pid, std.posix.SIG.KILL) catch {};
}

/// Cross-platform getenv wrapper.
/// Returns null on Windows (where POSIX getenv is unavailable).
pub fn getenv(key: []const u8) ?[:0]const u8 {
    if (comptime native_os == .windows) return null;
    return std.posix.getenv(key);
}
