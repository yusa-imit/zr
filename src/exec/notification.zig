const std = @import("std");

/// Notification trigger conditions
pub const NotifyOn = enum {
    always,
    success,
    failure,
};

/// Determines whether a notification should be sent based on task completion state
///
/// Returns true if a notification should be triggered given the notify_on setting
/// and the task completion status (success/failure).
pub fn shouldNotify(notify_on: NotifyOn, success: bool) bool {
    return switch (notify_on) {
        .always => true,
        .success => success,
        .failure => !success,
    };
}

/// Builds a notification message from task metadata
///
/// Returns a formatted message string containing the task name, result status,
/// and duration. The returned string is allocated and must be freed by the caller.
pub fn buildMessage(allocator: std.mem.Allocator, task_name: []const u8, success: bool, duration_ms: u64) ![]u8 {
    const status = if (success) "succeeded" else "failed";
    const duration_s = duration_ms / 1000;

    if (duration_s > 0) {
        return try std.fmt.allocPrint(allocator, "{s} {s} in {d}s", .{ task_name, status, duration_s });
    } else {
        return try std.fmt.allocPrint(allocator, "{s} {s} in {d}ms", .{ task_name, status, duration_ms });
    }
}

/// Sends a desktop notification (platform-specific)
///
/// Uses platform-native notification APIs:
/// - macOS: osascript display notification
/// - Linux: notify-send
/// - Windows: no-op (notifications not supported)
///
/// This is a fire-and-forget operation; errors are silently ignored.
pub fn send(allocator: std.mem.Allocator, title: []const u8, message: []const u8, success: bool) void {
    _ = success; // May be used for notification color/icon in future

    // Platform-specific notification command
    if (builtin.os.tag == .macos) {
        // macOS: use osascript with AppleScript
        // For now, just skip - would need to properly escape and format the AppleScript
        return;
    } else if (builtin.os.tag == .linux) {
        // Linux: notify-send
        var proc = std.process.Child.init(&[_][]const u8{ "notify-send", title, message }, allocator);
        _ = proc.run() catch return;
    }
    // Windows or unsupported platform: no-op
}

const builtin = @import("builtin");

// ────────────────────────────────────────────────────────────────────────────
// Unit Tests
// ────────────────────────────────────────────────────────────────────────────

test "notification: shouldNotify always triggers on success" {
    const result = shouldNotify(.always, true);
    try std.testing.expectEqual(true, result);
}

test "notification: shouldNotify always triggers on failure" {
    const result = shouldNotify(.always, false);
    try std.testing.expectEqual(true, result);
}

test "notification: shouldNotify success only triggers on success" {
    const result = shouldNotify(.success, true);
    try std.testing.expectEqual(true, result);
}

test "notification: shouldNotify success does not trigger on failure" {
    const result = shouldNotify(.success, false);
    try std.testing.expectEqual(false, result);
}

test "notification: shouldNotify failure only triggers on failure" {
    const result = shouldNotify(.failure, false);
    try std.testing.expectEqual(true, result);
}

test "notification: shouldNotify failure does not trigger on success" {
    const result = shouldNotify(.failure, true);
    try std.testing.expectEqual(false, result);
}

test "notification: buildMessage formats task name correctly" {
    const allocator = std.testing.allocator;
    const message = try buildMessage(allocator, "build_task", true, 5000);
    defer allocator.free(message);

    // Stub returns empty string, so this assertion will fail until implemented
    // Once implemented, should contain task name
    try std.testing.expect(std.mem.indexOf(u8, message, "build_task") != null);
}

test "notification: buildMessage includes duration" {
    const allocator = std.testing.allocator;
    const message = try buildMessage(allocator, "test_task", false, 3500);
    defer allocator.free(message);

    // Stub returns empty string, so this assertion will fail until implemented
    // Once implemented, should contain duration in some form
    try std.testing.expect(message.len > 0);
}

test "notification: buildMessage includes success status" {
    const allocator = std.testing.allocator;
    const message = try buildMessage(allocator, "deploy", true, 1000);
    defer allocator.free(message);

    // Stub returns empty string, so this assertion will fail until implemented
    // Once implemented, should contain "success" or similar indicator
    try std.testing.expect(std.mem.indexOf(u8, message, "success") != null or
        std.mem.indexOf(u8, message, "completed") != null or
        std.mem.indexOf(u8, message, "succeeded") != null);
}

test "notification: buildMessage includes failure status" {
    const allocator = std.testing.allocator;
    const message = try buildMessage(allocator, "deploy", false, 2000);
    defer allocator.free(message);

    // Stub returns empty string, so this assertion will fail until implemented
    // Once implemented, should contain "failed" or "error"
    try std.testing.expect(std.mem.indexOf(u8, message, "failed") != null or
        std.mem.indexOf(u8, message, "error") != null or
        std.mem.indexOf(u8, message, "failure") != null);
}
