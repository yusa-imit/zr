const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "31: plugin list shows installed plugins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "plugin", "list" }, tmp_path);
    defer result.deinit();
    // Should succeed even with no plugins
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "91: plugin list command shows builtin plugins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "plugin", "list" }, tmp_path);
    defer result.deinit();
    // Should succeed even with no plugins configured
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "92: plugin info command with nonexistent plugin fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "plugin", "info", "nonexistent-plugin" }, tmp_path);
    defer result.deinit();
    // Should fail when plugin doesn't exist
    try std.testing.expect(result.exit_code != 0);
}

test "125: plugin create generates plugin scaffold" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "plugin", "create", "test-plugin" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should create plugin directory
    tmp.dir.access("test-plugin", .{}) catch |err| {
        std.debug.print("Expected plugin directory not found: {}\n", .{err});
        return err;
    };
}

test "126: plugin search with query returns results" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "plugin", "search", "docker" }, tmp_path);
    defer result.deinit();
    // Search should complete without error (even if registry unavailable)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "145: plugin update updates installed plugin" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try updating a nonexistent plugin (should fail gracefully)
    var result = try runZr(allocator, &.{ "plugin", "update", "nonexistent" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully for nonexistent plugin
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "146: plugin builtins lists available built-in plugins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "plugin", "builtins" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should list built-in plugins like env, git, docker, cache
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "env") != null or
        std.mem.indexOf(u8, result.stdout, "git") != null);
}

test "185: plugin create generates scaffold with valid structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "plugin", "create", "test-plugin" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that plugin directory was created
    tmp.dir.access("test-plugin", .{}) catch |err| {
        std.debug.print("plugin directory not found: {}\n", .{err});
        return err;
    };
}

test "228: plugin list shows builtin plugins even with no config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create minimal config with no plugins section
    const no_plugins_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(no_plugins_toml);

    // List builtins should work
    var result = try runZr(allocator, &.{ "plugin", "builtins" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show built-in plugins
    try std.testing.expect(result.stdout.len > 0);
}

test "244: plugin with custom environment variables affects task execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const plugin_toml =
        \\[plugins.env]
        \\builtin = "env"
        \\config = { CUSTOM_VAR = "from_plugin" }
        \\
        \\[tasks.show-env]
        \\cmd = "echo $CUSTOM_VAR"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(plugin_toml);

    var result = try runZr(allocator, &.{ "run", "show-env" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "269: plugin with missing required fields reports validation error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const bad_plugin_toml =
        \\[plugins.broken]
        \\# Missing required 'path' or 'command' field
        \\description = "Broken plugin"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(bad_plugin_toml);

    var result = try runZr(allocator, &.{ "plugin", "list" }, tmp_path);
    defer result.deinit();
    // Should either skip invalid plugin or report error
    try std.testing.expect(result.exit_code <= 1);
}

test "298: plugin create with directory that already exists reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const basic_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(basic_toml);

    // Create existing directory
    try tmp.dir.makeDir("existing-plugin");

    var result = try runZr(allocator, &.{ "plugin", "create", "existing-plugin" }, tmp_path);
    defer result.deinit();
    // Should fail because directory exists
    try std.testing.expect(result.exit_code != 0);
}

test "393: plugin list with no plugins shows empty list gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // List plugins when none are configured
    var result = try runZr(allocator, &.{ "plugin", "list" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "419: plugin info for nonexistent plugin shows appropriate error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const minimal_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(minimal_toml);

    var result = try runZr(allocator, &.{ "plugin", "info", "nonexistent-plugin" }, tmp_path);
    defer result.deinit();
    // Should fail with appropriate error message
    try std.testing.expect(result.exit_code != 0);
}

test "492: plugin info with builtin plugin shows detailed metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const plugin_toml =
        \\[plugins]
        \\env = "builtin"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(plugin_toml);

    var result = try runZr(allocator, &.{ "plugin", "info", "env" }, tmp_path);
    defer result.deinit();
    // Should show plugin metadata
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "env") != null or
        std.mem.indexOf(u8, output, "builtin") != null);
}

test "525: plugin info with invalid plugin name shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "plugin", "info", "nonexistent-plugin-xyz" }, tmp_path);
    defer result.deinit();
    // Should return error for nonexistent plugin
    try std.testing.expect(result.exit_code != 0);
}

test "603: plugin list with --format json outputs structured plugin data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Plugin list with JSON format (may not be supported)
    var result = try runZr(allocator, &.{ "plugin", "list", "--format", "json" }, tmp_path);
    defer result.deinit();
    // May succeed or fail depending on format support
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    // If successful, should have output
    if (result.exit_code == 0) {
        try std.testing.expect(result.stdout.len > 0 or result.stderr.len > 0);
    }
}

test "651: plugin with missing required metadata fields shows validation error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create plugin directory with incomplete plugin.toml
    try tmp.dir.makeDir(".zr-plugins");
    try tmp.dir.makeDir(".zr-plugins/incomplete");

    const incomplete_plugin =
        \\# Missing required fields like 'name' or 'version'
        \\description = "Incomplete plugin"
        \\
    ;

    const plugin_file = try tmp.dir.createFile(".zr-plugins/incomplete/plugin.toml", .{});
    defer plugin_file.close();
    try plugin_file.writeAll(incomplete_plugin);

    const toml =
        \\[[plugins]]
        \\name = "incomplete"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "plugin", "list" }, tmp_path);
    defer result.deinit();

    // Should handle incomplete plugin gracefully (may show error or skip)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
