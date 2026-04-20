const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "task aliases: run task by exact alias match" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alias_toml =
        \\[tasks.build]
        \\cmd = "echo 'Building project'"
        \\aliases = ["b", "compile"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, alias_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run via alias "b"
    var result = try runZr(allocator, &.{ "--config", config, "run", "b" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Building project") != null);
}

test "task aliases: list command shows aliases" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alias_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\description = "Build the project"
        \\aliases = ["b", "compile"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\aliases = ["t"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, alias_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that aliases are displayed
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "aliases:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "compile") != null);
}

test "task aliases: JSON output includes aliases field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alias_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\aliases = ["b", "compile"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, alias_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // JSON output should include aliases array
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"aliases\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"b\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"compile\"") != null);
}

test "task aliases: conflict with task name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const conflict_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\aliases = ["test"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, conflict_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Any command should fail due to alias conflict
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    // Should fail with AliasConflict error
    try std.testing.expect(result.exit_code != 0);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Alias") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "conflicts") != null);
}

test "task aliases: duplicate alias across tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const duplicate_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\aliases = ["b"]
        \\
        \\[tasks.benchmark]
        \\cmd = "echo benchmarking"
        \\aliases = ["b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, duplicate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Should fail due to duplicate alias
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Alias") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "conflicts") != null);
}

test "task aliases: prefix matching works with aliases" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const prefix_toml =
        \\[tasks.build]
        \\cmd = "echo 'Building with alias'"
        \\aliases = ["compile"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, prefix_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Use prefix "com" which should match alias "compile"
    var result = try runZr(allocator, &.{ "--config", config, "run", "com" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Building with alias") != null);
}

test "global --silent flag: suppresses successful task output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const normal_toml =
        \\[tasks.build]
        \\cmd = "echo 'This should be hidden'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, normal_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--silent", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should be suppressed
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "This should be hidden") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "This should be hidden") == null);
}

test "global --silent flag: shows failed task output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const fail_toml =
        \\[tasks.fail]
        \\cmd = "echo 'Error occurred' && false"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, fail_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--silent", "fail" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Failed task output should still be visible
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Error occurred") != null);
}

test "global --silent flag: short form -s works" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const normal_toml =
        \\[tasks.echo]
        \\cmd = "echo 'Hidden by -s'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, normal_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "-s", "echo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hidden by -s") == null);
}

test "global --silent flag: overrides task-level silent=false" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const explicit_verbose_toml =
        \\[tasks.loud]
        \\cmd = "echo 'Should be hidden by global --silent'"
        \\silent = false
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, explicit_verbose_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--silent", "loud" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Global --silent should override task-level silent=false
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Should be hidden by global --silent") == null);
}

test "global --silent with workflow: suppresses all tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workflow_toml =
        \\[tasks.step1]
        \\cmd = "echo 'Step 1 output'"
        \\
        \\[tasks.step2]
        \\cmd = "echo 'Step 2 output'"
        \\
        \\[workflows.deploy]
        \\stages = [
        \\  { name = "s1", tasks = ["step1", "step2"] }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "--silent", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Both tasks should be silent
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Step 1 output") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Step 2 output") == null);
}
