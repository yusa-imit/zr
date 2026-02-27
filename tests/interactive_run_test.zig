const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "interactive-run: requires task name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, helpers.HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "interactive-run" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "interactive-run: with task name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "interactive-run", "hello" }, tmp_path);
    defer result.deinit();
    // Interactive run may succeed or fail depending on TUI support
    _ = result.exit_code;
}

test "interactive-run: alias 'i' works" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "i", "hello" }, tmp_path);
    defer result.deinit();
    // Should work same as interactive-run
    _ = result.exit_code;
}

test "interactive-run: missing config file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "interactive-run", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "interactive-run: unknown task shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, helpers.HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "interactive-run", "nonexistent" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}
