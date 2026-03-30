const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Tests for new task graph formats (v1.59.0 - Graph Format Enhancements milestone)
// These test the --type=tasks flag with ASCII, DOT, and JSON formats

test "3917: graph --type=tasks --format=ascii shows task tree" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "zig build"
        \\description = "Build the project"
        \\
        \\[tasks.test]
        \\cmd = "zig build test"
        \\description = "Run tests"
        \\deps = ["build"]
        \\
        \\[tasks.lint]
        \\cmd = "zig fmt --check ."
        \\description = "Check formatting"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=ascii" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain task names and descriptions
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task Dependency Graph") != null);
}

test "3918: graph --type=tasks --format=dot outputs Graphviz DOT" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\description = "Task A"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\description = "Task B"
        \\deps = ["a"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=dot" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain DOT format keywords
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "digraph tasks") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "rankdir=LR") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"a\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"b\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "->") != null);
}

test "3919: graph --type=tasks --format=json outputs JSON structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.clean]
        \\cmd = "rm -rf build"
        \\description = "Clean build artifacts"
        \\
        \\[tasks.compile]
        \\cmd = "gcc main.c"
        \\description = "Compile source"
        \\deps = ["clean"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain JSON structure with tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{\"tasks\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"name\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"cmd\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"deps\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "compile") != null);
}

test "3920: graph --type=tasks --format=ascii with serial dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.init]
        \\cmd = "echo init"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_serial = ["init"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=ascii" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "init") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "(serial)") != null);
}

test "3921: graph --type=tasks --format=dot with serial dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.stage1]
        \\cmd = "echo stage1"
        \\
        \\[tasks.stage2]
        \\cmd = "echo stage2"
        \\deps_serial = ["stage1"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=dot" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "style=bold") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "serial") != null);
}

test "3922: graph --type=tasks --format=json with conditional dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.main]
        \\cmd = "echo main"
        \\
        \\[[tasks.main.deps_if]]
        \\task = "optional"
        \\condition = "env.DEBUG == 'true'"
        \\
        \\[tasks.optional]
        \\cmd = "echo optional"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"deps_if\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"condition\"") != null);
}

test "3923: graph --type=tasks --format=ascii with optional dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps_optional = ["smoke-test"]
        \\
        \\[tasks.smoke-test]
        \\cmd = "echo smoke-test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=ascii" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "(optional)") != null);
}

test "3924: graph --type=tasks with no tasks shows empty message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml = "";

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=ascii" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "no tasks defined") != null);
}

test "3925: graph --type=tasks --format=html error message" {
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

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=html" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "HTML format is only for workspace graphs") != null);
}

test "3926: graph --type=tasks --format=tui error message" {
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

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=tui" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TUI format is only for workspace graphs") != null);
}
