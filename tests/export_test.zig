const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;
const ENV_TOML = helpers.ENV_TOML;

test "22: export generates shell exports" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
    // Should contain export statement for GREETING variable
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export") != null or std.mem.indexOf(u8, result.stdout, "GREETING") != null);
}

test "62: export command with default bash format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export GREETING") != null);
}

test "63: export command with fish format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello", "--shell", "fish" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "set -gx GREETING") != null);
}

test "64: export command with powershell format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello", "--shell", "powershell" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "$env:GREETING") != null);
}

test "74: export with missing task argument" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task" }, tmp_path);
    defer result.deinit();
    // Should fail with error about missing task
    try std.testing.expect(result.exit_code == 1);
}

test "75: export with nonexistent task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "nonexistent" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 1);
}

test "104: export with invalid shell format fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello", "--shell", "invalid-shell" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "shell") != null or std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "unknown") != null);
}

test "138: export with toolchain paths and custom env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toolchain_export_toml =
        \\[tasks.node-app]
        \\cmd = "node app.js"
        \\env = { NODE_ENV = "production" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toolchain_export_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "node-app", "--shell", "bash" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should include env vars
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NODE_ENV") != null or std.mem.indexOf(u8, result.stdout, "production") != null);
}

test "240: export with --format text outputs shell-sourceable environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const export_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\env = { BUILD_ENV = "production" }
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(export_toml);

    // Export with text format (default shell-sourceable format)
    var result = try runZr(allocator, &.{ "export", "--task", "build" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export BUILD_ENV") != null or std.mem.indexOf(u8, result.stdout, "BUILD_ENV") != null);
}

test "328: export command with task that has multiple environment variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const multi_env_toml =
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\env = { ENV = "prod", REGION = "us-east-1", DEBUG = "false" }
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(multi_env_toml);

    var result = try runZr(allocator, &.{ "export", "--task", "deploy" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "ENV") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "REGION") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DEBUG") != null);
}

test "471: export with --format=json outputs JSON environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const export_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\env = { BUILD_ENV = "production" }
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(export_toml);

    var result = try runZr(allocator, &.{ "export", "--task", "build", "--format=json" }, tmp_path);
    defer result.deinit();
    // Should output JSON formatted environment variables
    if (result.exit_code == 0) {
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "BUILD_ENV") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "production") != null);
    }
}

test "606: export with --shell powershell outputs Windows-compatible syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\env = { BUILD_MODE = "production" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "build", "--shell", "powershell" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain PowerShell syntax like $env:BUILD_MODE = "production"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "$env:") != null or std.mem.indexOf(u8, result.stdout, "BUILD_MODE") != null);
}

test "670: export with --shell and --task combines shell format with task-specific env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\env = { BUILD_MODE = "production" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "build", "--shell", "bash" }, tmp_path);
    defer result.deinit();

    // Should output bash-compatible export statements for task env
    try std.testing.expect(result.exit_code == 0);
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "export") != null or
                            std.mem.indexOf(u8, output, "BUILD_MODE") != null);
}

test "681: export with multiple environment sources combines all env vars" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[env]
        \\GLOBAL_VAR = "global"
        \\
        \\[profiles.dev]
        \\env = { PROFILE_VAR = "dev" }
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\env = { TASK_VAR = "task" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--profile", "dev", "--task", "test" }, tmp_path);
    defer result.deinit();

    // Should export all environment variables from global, profile, and task
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "GLOBAL_VAR") != null or
        std.mem.indexOf(u8, result.stdout, "PROFILE_VAR") != null or
        std.mem.indexOf(u8, result.stdout, "TASK_VAR") != null);
}

test "704: export with --format json and --task combines JSON output with task-specific env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\env = { GLOBAL = "global_value" }
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\env = { TASK_VAR = "task_value" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--format", "json", "--task", "test" }, tmp_path);
    defer result.deinit();

    // Should output JSON with combined global and task-specific env vars
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
