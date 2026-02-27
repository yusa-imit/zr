const std = @import("std");
const helpers = @import("helpers.zig");

test "lint: show help" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "lint", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "lint") != null or
        std.mem.indexOf(u8, result.stderr, "constraint") != null);
}

test "lint: no constraints in config shows info message" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a minimal zr.toml without constraints
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = helpers.HELLO_TOML });

    var result = try helpers.runZr(std.testing.allocator, &.{"lint"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "No architecture constraints") != null);
}

test "lint: missing config file returns error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{"lint"}, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Failed to load config") != null);
}

test "lint: --config requires argument" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "lint", "--config" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "--config") != null and
        std.mem.indexOf(u8, result.stderr, "missing") != null);
}

test "lint: with constraints validates successfully" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a zr.toml with constraints
    const config =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[[constraints]]
        \\rule = "no-circular"
        \\scope = "all"
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = config });

    var result = try helpers.runZr(std.testing.allocator, &.{"lint"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "passed") != null or
        std.mem.indexOf(u8, result.stderr, "constraint") != null);
}

test "lint: --verbose shows detailed output" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a zr.toml with constraints
    const config =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[[constraints]]
        \\rule = "no-circular"
        \\scope = "all"
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = config });

    var result = try helpers.runZr(std.testing.allocator, &.{ "lint", "--verbose" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verbose mode should show at least the result (passed or violations)
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "passed") != null or
        std.mem.indexOf(u8, result.stderr, "constraint") != null or
        std.mem.indexOf(u8, result.stderr, "verbose") != null);
}
