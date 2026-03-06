const std = @import("std");
const helpers = @import("helpers.zig");

test "863: failures shows no reports initially" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal zr.toml
    const toml = "[tasks.build]\ncmd = \"echo 'test'\"";
    const config_path = try helpers.writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config_path);

    // Run failures command
    var result = try helpers.runZr(allocator, &.{"failures"}, tmp_path);
    defer result.deinit();

    // Should indicate no failures found (in stderr since std.debug.print is used)
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "No failure reports found") != null);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "864: failures clear with no failures" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml = "[tasks.test]\ncmd = \"echo 'test'\"";
    const config_path = try helpers.writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config_path);

    var result = try helpers.runZr(allocator, &.{ "failures", "clear" }, tmp_path);
    defer result.deinit();

    // Should indicate no failures to clear (in stderr since std.debug.print is used)
    try std.testing.expect(
        std.mem.indexOf(u8, result.stderr, "No failure reports to clear") != null or
            std.mem.indexOf(u8, result.stderr, "Cleared 0 failure report") != null,
    );
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "865: help text includes failures command" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try helpers.runZr(allocator, &.{"--help"}, tmp_path);
    defer result.deinit();

    // Should mention failures command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "failures") != null);
}
