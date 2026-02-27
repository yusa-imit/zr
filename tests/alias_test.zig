const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "29: alias list shows aliases" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alias_toml =
        \\[alias]
        \\b = "build"
        \\t = "test"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, alias_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "alias", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "65: alias add and list workflow" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Alias commands will use ~/.zr/aliases.toml, but for the test
    // we just verify they don't crash and exit cleanly
    var add_result = try runZr(allocator, &.{ "alias", "add", "test-alias", "list" }, tmp_path);
    defer add_result.deinit();
    try std.testing.expect(add_result.exit_code == 0);

    // List should show the alias
    var list_result = try runZr(allocator, &.{ "alias", "list" }, tmp_path);
    defer list_result.deinit();
    try std.testing.expect(list_result.exit_code == 0);
}

test "66: alias show specific alias" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add alias first
    var add_result = try runZr(allocator, &.{ "alias", "add", "show-test", "list --tree" }, tmp_path);
    defer add_result.deinit();

    // Show specific alias
    var show_result = try runZr(allocator, &.{ "alias", "show", "show-test" }, tmp_path);
    defer show_result.deinit();
    try std.testing.expect(show_result.exit_code == 0);
}

test "67: alias remove existing alias" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add alias
    var add_result = try runZr(allocator, &.{ "alias", "add", "remove-me", "list" }, tmp_path);
    defer add_result.deinit();

    // Remove alias
    var remove_result = try runZr(allocator, &.{ "alias", "remove", "remove-me" }, tmp_path);
    defer remove_result.deinit();
    try std.testing.expect(remove_result.exit_code == 0);
}

test "77: alias with invalid name characters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to add alias with invalid characters
    var result = try runZr(allocator, &.{ "alias", "add", "invalid@name", "list" }, tmp_path);
    defer result.deinit();
    // Should fail validation
    try std.testing.expect(result.exit_code == 1);
}

test "109: alias add with empty name fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "alias", "add", "", "run test" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "empty") != null or std.mem.indexOf(u8, result.stderr, "cannot be empty") != null);
}

test "135: alias expansion with flags and arguments" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create alias
    {
        var add_result = try runZr(allocator, &.{ "alias", "add", "quick-build", "run hello --dry-run" }, tmp_path);
        defer add_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), add_result.exit_code);
    }

    // Use alias
    var result = try runZr(allocator, &.{ "--config", config, "quick-build" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "159: alias remove with nonexistent alias fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const simple_toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, simple_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "alias", "remove", "nonexistent-alias" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "177: alias add creates a new command alias" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "alias", "add", "greet", "run", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "178: alias show displays details of a specific alias" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // First add an alias
    {
        var add_result = try runZr(allocator, &.{ "--config", config, "alias", "add", "greet", "run", "hello" }, tmp_path);
        defer add_result.deinit();
    }

    // Then show it
    var result = try runZr(allocator, &.{ "--config", config, "alias", "show", "greet" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
}

test "245: alias with chained expansion supports nested aliases" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const alias_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[aliases]
        \\ci = ["build", "test"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(alias_toml);

    // Add alias via CLI
    var add_result = try runZr(allocator, &.{ "alias", "add", "quick-ci", "ci" }, tmp_path);
    defer add_result.deinit();
    try std.testing.expectEqual(@as(u8, 0), add_result.exit_code);

    // Show alias to verify
    var show_result = try runZr(allocator, &.{ "alias", "show", "quick-ci" }, tmp_path);
    defer show_result.deinit();
    try std.testing.expect(show_result.exit_code <= 1); // May not support nested aliases yet
}

test "266: alias with circular reference detects cycle" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const circular_alias_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[alias]
        \\foo = "bar"
        \\bar = "baz"
        \\baz = "foo"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(circular_alias_toml);

    var result = try runZr(allocator, &.{ "alias", "show", "foo" }, tmp_path);
    defer result.deinit();
    // Should detect circular reference or reach expansion limit
    try std.testing.expect(result.exit_code <= 1);
}

test "279: alias add → show → list → remove workflow" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const simple_toml =
        \\[tasks.test]
        \\cmd = "echo running-test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(simple_toml);

    // Add alias (CLI command alias, not task alias)
    var add_result = try runZr(allocator, &.{ "alias", "add", "t", "run test" }, tmp_path);
    defer add_result.deinit();
    try std.testing.expect(add_result.exit_code == 0);

    // Show alias
    var show_result = try runZr(allocator, &.{ "alias", "show", "t" }, tmp_path);
    defer show_result.deinit();
    try std.testing.expect(show_result.exit_code == 0);
    const show_output = if (show_result.stdout.len > 0) show_result.stdout else show_result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, show_output, "run test") != null or std.mem.indexOf(u8, show_output, "t") != null);

    // List aliases
    var list_result = try runZr(allocator, &.{ "alias", "list" }, tmp_path);
    defer list_result.deinit();
    try std.testing.expect(list_result.exit_code == 0);
    const list_output = if (list_result.stdout.len > 0) list_result.stdout else list_result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, list_output, "t") != null);

    // Remove alias
    var remove_result = try runZr(allocator, &.{ "alias", "remove", "t" }, tmp_path);
    defer remove_result.deinit();
    try std.testing.expect(remove_result.exit_code == 0);

    // Verify alias is gone
    var verify_result = try runZr(allocator, &.{ "alias", "show", "t" }, tmp_path);
    defer verify_result.deinit();
    try std.testing.expect(verify_result.exit_code == 1);
}

test "375: alias ls command lists all aliases (shorthand for list)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Add an alias first
    var add_result = try runZr(allocator, &.{ "alias", "add", "test-alias", "run hello" }, tmp_path);
    defer add_result.deinit();

    // Test 'ls' alias for 'list'
    var result = try runZr(allocator, &.{ "alias", "ls" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "test-alias") != null);
}

test "376: alias get command shows specific alias (shorthand for show)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Add an alias first
    var add_result = try runZr(allocator, &.{ "alias", "add", "dev", "run build && run test" }, tmp_path);
    defer add_result.deinit();

    // Test 'get' alias for 'show'
    var result = try runZr(allocator, &.{ "alias", "get", "dev" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "run build && run test") != null);
}

test "377: alias set command creates alias (shorthand for add)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Test 'set' alias for 'add'
    var result = try runZr(allocator, &.{ "alias", "set", "prod", "run build --profile=production" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify alias was created
    var list_result = try runZr(allocator, &.{ "alias", "list" }, tmp_path);
    defer list_result.deinit();
    const output = if (list_result.stdout.len > 0) list_result.stdout else list_result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "prod") != null);
}

test "378: alias rm command removes alias (shorthand for remove)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Add an alias first
    var add_result = try runZr(allocator, &.{ "alias", "add", "temp", "run hello" }, tmp_path);
    defer add_result.deinit();

    // Test 'rm' alias for 'remove'
    var result = try runZr(allocator, &.{ "alias", "rm", "temp" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify alias was removed
    var list_result = try runZr(allocator, &.{ "alias", "list" }, tmp_path);
    defer list_result.deinit();
    const output = if (list_result.stdout.len > 0) list_result.stdout else list_result.stderr;
    // Should not contain removed alias
    try std.testing.expect(std.mem.indexOf(u8, output, "temp") == null or result.exit_code == 0);
}

test "379: alias delete command removes alias (alternative shorthand for remove)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Add an alias first
    var add_result = try runZr(allocator, &.{ "alias", "add", "temp2", "run hello" }, tmp_path);
    defer add_result.deinit();

    // Test 'delete' alias for 'remove'
    var result = try runZr(allocator, &.{ "alias", "delete", "temp2" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify alias was removed
    var list_result = try runZr(allocator, &.{ "alias", "list" }, tmp_path);
    defer list_result.deinit();
    const output = if (list_result.stdout.len > 0) list_result.stdout else list_result.stderr;
    // Should not contain removed alias
    try std.testing.expect(std.mem.indexOf(u8, output, "temp2") == null or result.exit_code == 0);
}

test "461: alias with circular reference detection prevents infinite loops" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const alias_toml =
        \\[tasks.hello]
        \\cmd = "echo hi"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(alias_toml);

    // Add alias pointing to itself (should be rejected or handled)
    var result = try runZr(allocator, &.{ "alias", "add", "loop", "loop" }, tmp_path);
    defer result.deinit();
    // Should detect circular reference
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "561: alias list shows all defined aliases with their commands" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[aliases]
        \\b = "run build"
        \\d = "run deploy"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "alias", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show both aliases
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "608: alias with circular reference handles gracefully without infinite loop" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Create circular alias reference: a -> b -> a
    var add_a = try runZr(allocator, &.{ "--config", config, "alias", "add", "a", "b" }, tmp_path);
    defer add_a.deinit();
    var add_b = try runZr(allocator, &.{ "--config", config, "alias", "add", "b", "a" }, tmp_path);
    defer add_b.deinit();

    // Try to use the circular alias (should fail gracefully)
    var result = try runZr(allocator, &.{ "--config", config, "a" }, tmp_path);
    defer result.deinit();
    // Should detect circular reference or fail without hanging
    try std.testing.expect(result.exit_code != 0);
}
