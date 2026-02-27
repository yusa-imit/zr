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

// Note: --check flag tests would require network access and are skipped for integration tests
// as they depend on external GitHub API availability
