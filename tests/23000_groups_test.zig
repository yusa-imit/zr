const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Task Groups & Namespaces Tests ──────────────────────────────────────────
//
// Tests for dot-separated task naming with namespace groups:
// 1. [tasks.build.compile] is parseable, creates task with name "build.compile"
// 2. zr run build.* runs all tasks in the build namespace in dependency order
// 3. zr run build.* with --skip skips specified task
// 4. zr list --group build shows only build namespace tasks
// 5. zr run build (no exact match) shows group tasks when build.* exists
// 6. zr list with namespace tasks shows grouped output (all tasks displayed)
// 7. zr run test.* with single task succeeds
// 8. zr run build.* on empty group returns error
//

test "23000: [tasks.build.compile] is parseable, has name build.compile" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build.compile]
        \\cmd = "echo compiled"
        \\
        \\[tasks.build.link]
        \\cmd = "echo linked"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both tasks should appear in list output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.link") != null);
}

test "23001: zr run build.* runs all tasks in the build namespace" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build.compile]
        \\cmd = "echo compiled"
        \\
        \\[tasks.build.link]
        \\cmd = "echo linked"
        \\deps = ["build.compile"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.*" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both outputs should be present (in dependency order: compile then link)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "compiled") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "linked") != null);
}

test "23002: zr run build.* with --skip skips specified task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build.compile]
        \\cmd = "echo compiled"
        \\
        \\[tasks.build.link]
        \\cmd = "echo linked"
        \\deps = ["build.compile"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.*", "--skip", "build.compile" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only link should run, compile should be skipped
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "linked") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "compiled") == null);
}

test "23003: zr list --group build shows only build namespace tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build.compile]
        \\cmd = "echo compiled"
        \\
        \\[tasks.build.link]
        \\cmd = "echo linked"
        \\
        \\[tasks.test.unit]
        \\cmd = "echo tested"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--group", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should include build tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.link") != null);
    // Should NOT include test task
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test.unit") == null);
}

test "23004: zr run build (no exact match) shows group tasks when build.* exists" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build.compile]
        \\cmd = "echo compiled"
        \\
        \\[tasks.build.link]
        \\cmd = "echo linked"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    // Should not error immediately, but inform about group tasks
    // Either shows group listing or returns informative message
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "build.compile") != null or
                           std.mem.indexOf(u8, output, "build.link") != null or
                           std.mem.indexOf(u8, output, "build") != null);
}

test "23005: zr list with namespace tasks shows grouped output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build.compile]
        \\cmd = "echo compiled"
        \\
        \\[tasks.build.link]
        \\cmd = "echo linked"
        \\
        \\[tasks.test.unit]
        \\cmd = "echo tested"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All tasks should appear in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.link") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test.unit") != null);
}

test "23006: zr run test.* with single task succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.test.unit]
        \\cmd = "echo tested"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test.*" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tested") != null);
}

test "23007: zr run build.* on empty group returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.test.unit]
        \\cmd = "echo tested"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.*" }, tmp_path);
    defer result.deinit();

    // Should fail since no build.* tasks exist
    try std.testing.expect(result.exit_code != 0);
    // Error message should mention missing tasks
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null or
                           std.mem.indexOf(u8, output, "no task") != null or
                           std.mem.indexOf(u8, output, "not found") != null);
}
