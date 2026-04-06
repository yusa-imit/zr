const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "7000: enhanced discovery: exclude-tags filter" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\tags = ["ci"]
        \\
        \\[tasks.slow]
        \\cmd = "slow"
        \\tags = ["slow"]
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--exclude-tags=slow" }, tmp_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "slow") == null);
}

test "7001: enhanced discovery: --tags with ALL (AND) logic" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\tags = ["ci", "build"]
        \\
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\tags = ["ci", "prod"]
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--tags=ci,prod" }, tmp_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "build") == null);
}

test "7002: enhanced discovery: --search includes command text" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "docker build"
        \\
        \\[tasks.test]
        \\cmd = "pytest"
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--search=docker" }, tmp_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "test") == null);
}

test "7003: enhanced discovery: combined filters" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\tags = ["ci", "build"]
        \\
        \\[tasks.slow_test]
        \\cmd = "pytest --slow"
        \\tags = ["ci", "test", "slow"]
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--tags=ci", "--exclude-tags=slow" }, tmp_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "slow_test") == null);
}

test "7004: enhanced discovery: JSON output with filters" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\tags = ["ci"]
        \\
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\tags = ["prod"]
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--format", "json", "--config", config, "list", "--tags=ci" }, tmp_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"tasks\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"build\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"deploy\"") == null);
}

test "7005: enhanced discovery: empty results with strict filters" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\tags = ["ci"]
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--tags=ci,prod" }, tmp_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "build") == null);
}
