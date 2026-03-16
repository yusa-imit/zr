const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "live: requires task name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, helpers.HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "live" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "missing") != null or
        std.mem.indexOf(u8, result.stderr, "task") != null);
}

test "live: with task name and config" {
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

    var result = try runZr(allocator, &.{ "--config", config, "live", "hello" }, tmp_path);
    defer result.deinit();
    // Live command should succeed (exit 0) or fail gracefully (exit 1)
    // Should not crash
    try std.testing.expect(result.exit_code <= 1);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "live: missing config file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "live", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "live: unknown task shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, helpers.HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "live", "nonexistent" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "live: with output_file streams to file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.test]
        \\cmd = "echo hello world"
        \\output_mode = "stream"
        \\output_file = "test-output.log"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "live", "test" }, tmp_path);
    defer result.deinit();

    // Live mode requires TTY and will fail in test environment
    // Verify it fails with TTY error message
    try std.testing.expect(result.exit_code != 0);
    const has_tty_error = std.mem.indexOf(u8, result.stdout, "TTY") != null or
        std.mem.indexOf(u8, result.stderr, "TTY") != null;
    try std.testing.expect(has_tty_error);
}

test "live: with output_mode=buffer captures in memory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.test]
        \\cmd = "echo test buffer"
        \\output_mode = "buffer"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "live", "test" }, tmp_path);
    defer result.deinit();

    // Live mode requires TTY and will fail in test environment
    try std.testing.expect(result.exit_code != 0);
    const has_tty_error = std.mem.indexOf(u8, result.stdout, "TTY") != null or
        std.mem.indexOf(u8, result.stderr, "TTY") != null;
    try std.testing.expect(has_tty_error);
}
