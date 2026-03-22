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
    // Should show usage error
    try std.testing.expect(result.stderr.len > 0);
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
    // In CI or non-TTY environment, interactive mode should fail gracefully
    // Either succeeds (if TUI available) or fails with clear error message
    if (result.exit_code != 0) {
        // If it fails, should have an error message explaining why
        try std.testing.expect(result.stderr.len > 0);
    }
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
    // Alias 'i' should behave identically to 'interactive-run'
    // Either succeeds (if TUI available) or fails with clear error message
    if (result.exit_code != 0) {
        try std.testing.expect(result.stderr.len > 0);
    }
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
    // Should report missing config file
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr.toml") != null or
        std.mem.indexOf(u8, result.stderr, "config") != null);
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
    // Should mention the task name in the error
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "nonexistent") != null or
        std.mem.indexOf(u8, result.stderr, "not found") != null or
        std.mem.indexOf(u8, result.stderr, "unknown") != null);
}
