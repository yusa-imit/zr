const std = @import("std");
const helpers = @import("helpers.zig");

const runZr = helpers.runZr;
const runZrWithStdin = helpers.runZrWithStdin;
const writeTmpConfig = helpers.writeTmpConfig;

test "907: edit with no arguments shows usage error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const result = try runZr(allocator, &[_][]const u8{"edit"}, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Usage: zr edit") != null);
}

test "908: edit with invalid type shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "edit", "invalid" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid entity type") != null or
        std.mem.indexOf(u8, result.stderr, "Valid types") != null);
}

test "909: edit task with closed stdin shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    // Run with empty stdin (simulates EOF)
    const result = try runZrWithStdin(allocator, tmp.dir, &[_][]const u8{ "edit", "task" }, "");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Should show cancellation message
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Cancelled") != null or
        std.mem.indexOf(u8, result.stderr, "EOF") != null or
        std.mem.indexOf(u8, result.stderr, "stdin") != null);
}

test "910: edit workflow with closed stdin shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    // Run with empty stdin (simulates EOF)
    const result = try runZrWithStdin(allocator, tmp.dir, &[_][]const u8{ "edit", "workflow" }, "");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Cancelled") != null or
        std.mem.indexOf(u8, result.stderr, "EOF") != null or
        std.mem.indexOf(u8, result.stderr, "stdin") != null);
}

test "911: edit profile with closed stdin shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    // Run with empty stdin (simulates EOF)
    const result = try runZrWithStdin(allocator, tmp.dir, &[_][]const u8{ "edit", "profile" }, "");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Cancelled") != null or
        std.mem.indexOf(u8, result.stderr, "EOF") != null or
        std.mem.indexOf(u8, result.stderr, "stdin") != null);
}
