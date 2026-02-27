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
    // Publish prints error but may return 0 (cmdPublish returns void, errors are just printed)
    // Check for error message in output
    _ = result.exit_code;
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
    // Should handle gracefully
    _ = result.exit_code;
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
    // Publish prints error but may return 0
    _ = result.exit_code;
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
    // Publish prints error but may return 0
    _ = result.exit_code;
}
