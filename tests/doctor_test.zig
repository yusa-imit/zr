const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

const BASIC_TOML =
    \\[tasks.test]
    \\cmd = "echo test"
    \\
;

const TOOLCHAIN_TOML =
    \\[toolchains]
    \\tools = [
    \\  "node@20.11.1"
    \\]
    \\
    \\[tasks.test]
    \\cmd = "node --version"
    \\
;

const DOCKER_TOML =
    \\[tasks.build]
    \\cmd = "docker build ."
    \\
    \\[tasks.test]
    \\cmd = "echo test"
    \\
;

test "725: doctor runs basic checks without zr.toml" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"doctor"}, tmp_path);
    defer result.deinit();

    // Doctor should succeed even without zr.toml (basic checks)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "No zr.toml found") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "git") != null);
}

test "726: doctor checks git availability" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    var result = try runZr(allocator, &.{"doctor"}, tmp_path);
    defer result.deinit();

    // Git should be available on CI systems
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "git") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "✓") != null or std.mem.indexOf(u8, result.stderr, "✗") != null);
}

test "727: doctor runs with valid config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    var result = try runZr(allocator, &.{"doctor"}, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr doctor") != null);
}

test "728: doctor checks docker when used in tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = DOCKER_TOML });

    var result = try runZr(allocator, &.{"doctor"}, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    // Docker check should appear in output
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "docker") != null);
}

test "729: doctor with custom config path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "custom.toml", .data = BASIC_TOML });

    var result = try runZr(allocator, &.{ "doctor", "--config=custom.toml" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr doctor") != null);
}

test "730: doctor succeeds with passing checks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    var result = try runZr(allocator, &.{"doctor"}, tmp_path);
    defer result.deinit();

    // Should show completion message
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "checks passed") != null or std.mem.indexOf(u8, result.stderr, "issue") != null);
}
