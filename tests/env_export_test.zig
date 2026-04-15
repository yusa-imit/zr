const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

const TEST_CONFIG =
    \\[tasks.build]
    \\cmd = "echo build"
    \\env = [["NODE_ENV", "production"], ["DEBUG", "true"]]
    \\
    \\[tasks.test]
    \\cmd = "echo test"
    \\env = [["NODE_ENV", "test"], ["CI", "1"]]
    \\
;

test "env --export generates bash export statements" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "build", "--export", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export NODE_ENV=\"production\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export DEBUG=\"true\"") != null);
}

test "env --export generates zsh export statements" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "test", "--export", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export NODE_ENV=\"test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export CI=\"1\"") != null);
}

test "env --export generates fish set statements" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "build", "--export", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "set -x NODE_ENV \"production\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "set -x DEBUG \"true\"") != null);
}

test "env --export auto-detects shell from SHELL env var" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    // Auto-detect should work (defaults to bash if detection fails)
    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "build", "--export" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain either bash or fish format
    const has_export = std.mem.indexOf(u8, result.stdout, "export") != null or std.mem.indexOf(u8, result.stdout, "set -x") != null;
    try std.testing.expect(has_export);
}

test "env --export escapes special characters in bash" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const special_config =
        \\[tasks.special]
        \\cmd = "echo test"
        \\env = [["PATH", "/bin:/usr/bin:$HOME/bin"], ["MSG", "hello \"world\""]]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, special_config);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "special", "--export", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should escape $ and "
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\\$") != null or std.mem.indexOf(u8, result.stdout, "\\\"") != null);
}

test "env --export with nonexistent task returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "nonexistent", "--export" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "task 'nonexistent' not found") != null);
}

test "env --functions generates bash functions for all tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--functions", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr_build() { zr run build \"$@\"; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr_test() { zr run test \"$@\"; }") != null);
}

test "env --functions generates fish functions for all tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--functions", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "function zr_build; zr run build $argv; end") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "function zr_test; zr run test $argv; end") != null);
}

test "env --functions auto-detects shell" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--functions" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should generate functions in some format
    const has_functions = std.mem.indexOf(u8, result.stdout, "zr_build") != null and std.mem.indexOf(u8, result.stdout, "zr_test") != null;
    try std.testing.expect(has_functions);
}

test "env --export with invalid shell type returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TEST_CONFIG);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "build", "--export", "powershell" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown shell type") != null);
}
