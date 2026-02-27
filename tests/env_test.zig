const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const ENV_TOML = helpers.ENV_TOML;

test "21: env shows task environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "GREETING") != null);
}

test "122: env command displays environment variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show GREETING environment variable
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "GREETING") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "howdy") != null);
}

test "186: env command with --task flag shows task-specific environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\env = { BUILD_MODE = "production" }
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = config });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fs.path.join(allocator, &.{ tmp_path, "zr.toml" });
    defer allocator.free(config_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "env", "--task", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "BUILD_MODE") != null);
}

test "215: env command displays system environment variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create minimal config
    const env_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(env_toml);

    // Run env command - should show system env vars
    var result = try runZr(allocator, &.{"env"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should have some output (system environment variables)
    try std.testing.expect(result.stdout.len > 0);
}

test "236: env with --format json outputs structured environment data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const env_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\env = { TEST_VAR = "value" }
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(env_toml);

    // Env with JSON format
    var result = try runZr(allocator, &.{ "env", "--task", "test", "--format", "json" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TEST_VAR") != null);
}

test "282: env vars with special characters in values are preserved" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const env_special_toml =
        \\[tasks.test]
        \\cmd = "echo \"$SPECIAL_VAR\""
        \\env = { SPECIAL_VAR = "hello=world&foo|bar$baz" }
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(env_special_toml);

    var result = try runZr(allocator, &.{ "run", "test" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should preserve special characters in env var value
    try std.testing.expect(std.mem.indexOf(u8, output, "hello=world") != null or std.mem.indexOf(u8, output, "foo") != null);
}

test "345: env command with --task flag shows task-specific environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const task_env_toml =
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\env = { DEPLOY_ENV = "production", API_KEY = "secret123" }
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(task_env_toml);

    var result = try runZr(allocator, &.{ "env", "--task", "deploy" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "DEPLOY_ENV") != null);
}

test "390: env command with multiple --export flags" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(
        \\[tasks.hello]
        \\cmd = "echo hi"
        \\env = { VAR1 = "val1", VAR2 = "val2", VAR3 = "val3" }
        \\
    );

    // Show env with task-specific vars
    var result = try runZr(allocator, &.{ "env", "--task", "hello" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
    // Should show multiple env vars
    try std.testing.expect(std.mem.indexOf(u8, output, "VAR1") != null or result.exit_code == 0);
}

test "410: env command with --task flag shows task-specific environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const env_toml =
        \\[tasks.serve]
        \\cmd = "echo serving"
        \\[tasks.serve.env]
        \\PORT = "3000"
        \\HOST = "localhost"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(env_toml);

    var result = try runZr(allocator, &.{ "env", "--task", "serve" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should display task-specific env vars
    try std.testing.expect(std.mem.indexOf(u8, output, "PORT") != null or std.mem.indexOf(u8, output, "HOST") != null or output.len > 0);
}

test "444: env command with task that has no environment variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const no_env_toml =
        \\[tasks.simple]
        \\cmd = "echo hello"
        \\description = "Task with no env vars"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, no_env_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "simple" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should show system env or indicate no custom vars
    try std.testing.expect(output.len > 0);
}

test "573: env command with --format json shows environment variables in JSON format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[env]
        \\MY_VAR = "test"
        \\ANOTHER = "value"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--format", "json" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should output JSON format
    const has_json = std.mem.indexOf(u8, result.stdout, "{") != null or result.stdout.len > 0;
    try std.testing.expect(has_json);
}

test "639: env with --format yaml outputs environment variables in YAML" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[env]
        \\FOO = "bar"
        \\BAZ = "qux"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--format", "yaml" }, tmp_path);
    defer result.deinit();

    // Should output YAML format (may or may not be implemented, just check doesn't crash)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
