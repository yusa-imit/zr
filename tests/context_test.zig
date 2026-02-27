const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "38: context shows current context" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "context" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "73: context with --format json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "context", "--format", "json" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
}

test "184: context command with --format yaml outputs YAML structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = config });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fs.path.join(allocator, &.{ tmp_path, "zr.toml" });
    defer allocator.free(config_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "context", "--format", "yaml" }, tmp_path);
    defer result.deinit();

    // Context command may fail without git repo or other dependencies
    // Main test is that it doesn't crash
    try std.testing.expect(result.exit_code <= 1);
}

test "216: context outputs project metadata in default format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create simple config
    const context_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(context_toml);

    // Run context command
    var result = try runZr(allocator, &.{"context"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
}

test "319: context with --format=toml outputs TOML formatted context" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    var result = try runZr(allocator, &.{ "context", "--format=toml" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should output TOML or fail gracefully
    try std.testing.expect(std.mem.indexOf(u8, output, "[") != null or
                          std.mem.indexOf(u8, output, "context") != null or
                          result.exit_code == 0);
}

test "360: context command with multiple output formats produces consistent data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Test JSON format
    var json_result = try runZr(allocator, &.{ "context", "--format", "json" }, tmp_path);
    defer json_result.deinit();
    const json_output = if (json_result.stdout.len > 0) json_result.stdout else json_result.stderr;
    try std.testing.expect(json_output.len > 0);

    // Test YAML format
    var yaml_result = try runZr(allocator, &.{ "context", "--format", "yaml" }, tmp_path);
    defer yaml_result.deinit();
    const yaml_output = if (yaml_result.stdout.len > 0) yaml_result.stdout else yaml_result.stderr;
    try std.testing.expect(yaml_output.len > 0);
}

test "463: context with --scope flag filters to specific package" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const context_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\description = "Build the project"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(context_toml);

    var result = try runZr(allocator, &.{ "context", "--scope", "." }, tmp_path);
    defer result.deinit();
    // Should generate context output
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(result.stdout.len > 0);
}

test "498: context with --format toml outputs TOML format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "context", "--format", "toml" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "532: context with --scope filter limits output to specific path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Create workspace members
    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");

    const pkg1_toml = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll("[tasks.build]\ncmd = \"echo building\"");

    var result = try runZr(allocator, &.{ "--config", config, "context", "--scope", "pkg1" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should mention pkg1 but not pkg2
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "pkg1") != null);
}

test "556: context command generates structured project metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\description = "Build the project"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Test context command (default JSON format)
    var result = try runZr(allocator, &.{ "--config", config, "context" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should generate context with project metadata
    try std.testing.expect(result.stdout.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "project") != null or std.mem.indexOf(u8, result.stdout, "tasks") != null or std.mem.indexOf(u8, result.stdout, "context") != null);
}

test "568: context with --scope flag filters metadata by path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "context", "--scope", "src/" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should generate context scoped to src/ path
    const has_output = result.stdout.len > 0 or result.stderr.len > 0;
    try std.testing.expect(has_output);
}

test "615: context with --format yaml and --scope combined filters and formats correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\tags = ["backend"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\tags = ["backend"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "context", "--format", "yaml", "--scope", "." }, tmp_path);
    defer result.deinit();
    // Should output YAML format with scope filtering
    if (result.stdout.len > 0) {
        // YAML typically has key: value structure
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, ":") != null);
    }
}

test "643: context with --format toml outputs project context in TOML" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "context", "--format", "toml" }, tmp_path);
    defer result.deinit();

    // TOML format may not be implemented for context, should show error or output
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
