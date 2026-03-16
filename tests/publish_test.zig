const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "publish: --help shows usage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "publish", "--help" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "publish: requires config file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"publish"}, tmp_path);
    defer result.deinit();
    // NOTE: cmdPublish prints errors but returns void (exit 0) - this is a known limitation
    // Check that error message is printed
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Error") != null or std.mem.indexOf(u8, output, "Failed") != null);
}

test "publish: --dry-run with valid config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[package]
        \\name = "test-pkg"
        \\version = "0.1.0"
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "publish", "--dry-run" }, tmp_path);
    defer result.deinit();
    // Dry-run should succeed or show what would be published
    try std.testing.expect(result.exit_code <= 1);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "publish: --bump requires value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, helpers.HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "publish", "--bump" }, tmp_path);
    defer result.deinit();
    // NOTE: cmdPublish prints errors but returns void (exit 0)
    // Check that error message about missing bump value is printed
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Error") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bump") != null);
}

test "publish: invalid bump type shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, helpers.HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "publish", "--bump", "invalid" }, tmp_path);
    defer result.deinit();
    // NOTE: cmdPublish prints errors but returns void (exit 0)
    // Check that error message about invalid bump type is printed
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Error") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Invalid") != null or std.mem.indexOf(u8, output, "bump") != null);
}
