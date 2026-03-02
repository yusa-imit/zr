const std = @import("std");
const helpers = @import("helpers.zig");

test "upgrade: show help" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "upgrade", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Help goes to stderr
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "upgrade") != null or
        std.mem.indexOf(u8, result.stderr, "Upgrade") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "--check") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "--version") != null);
}

test "upgrade: unknown option returns error" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "upgrade", "--invalid-option" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unknown option") != null);
}

test "upgrade: --version without value returns error" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "upgrade", "--version" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "--version requires") != null);
}

test "upgrade: --check completes without crashing" {
    // This test verifies the command doesn't crash and handles network errors gracefully
    // It may report "already on latest" if GitHub API is unreachable, which is acceptable
    var result = try helpers.runZr(std.testing.allocator, &.{ "upgrade", "--check" }, null);
    defer result.deinit();

    // Exit code should be 0 regardless of network availability
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should show "Checking for updates" message
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Checking for updates") != null);

    // Should either show "latest version" or "Update available" (if network works)
    const has_latest = std.mem.indexOf(u8, result.stdout, "latest version") != null;
    const has_update = std.mem.indexOf(u8, result.stdout, "Update available") != null;
    try std.testing.expect(has_latest or has_update);
}

// Note: Full --check flag tests would require network access and are handled by the basic test above
