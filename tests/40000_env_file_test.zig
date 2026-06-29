const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Environment File Tests ────────────────────────────────────────────────────
//
// Tests for `--env-file <path>` flag (v1.111.0):
//
// 40000: Basic env file loading — task prints env var from dotenv file
// 40001: Multiple env files — both files' variables are loaded
// 40002: Env file override by --env — --env takes priority over file
// 40003: Missing env file — warning printed but run continues (exit 0)
// 40004: Second env file overrides first — last file's value wins
// 40005: Env file with comments and blank lines — parsed correctly
//

// Test 40000: Basic env file loading from --env-file
test "env_file: basic env file loading" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.print-env]
        \\cmd = "echo $MY_VAR"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Write a dotenv file
    try tmp.dir.writeFile(.{ .sub_path = ".env.extra", .data = "MY_VAR=hello_from_env_file" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "print-env", "--env-file", ".env.extra" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Verify the env var from file was loaded
    try testing.expect(std.mem.indexOf(u8, combined, "hello_from_env_file") != null);
}

// Test 40001: Multiple env files — both variables are loaded
test "env_file: multiple env files load all variables" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.print-both]
        \\cmd = "sh -c 'echo \"A=$A B=$B\"'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Write two dotenv files
    try tmp.dir.writeFile(.{ .sub_path = ".env.a", .data = "A=from_a" });
    try tmp.dir.writeFile(.{ .sub_path = ".env.b", .data = "B=from_b" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "print-both", "--env-file", ".env.a", "--env-file", ".env.b" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Verify both env vars are loaded
    try testing.expect(std.mem.indexOf(u8, combined, "from_a") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "from_b") != null);
}

// Test 40002: Env file override by --env — --env takes priority
test "env_file: --env takes priority over env file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.print-var]
        \\cmd = "echo $MY_VAR"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Write a dotenv file with a value
    try tmp.dir.writeFile(.{ .sub_path = ".env.extra", .data = "MY_VAR=from_file" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run with both --env-file and --env; --env should win
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "print-var", "--env-file", ".env.extra", "--env", "MY_VAR=from_cli" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Verify --env takes priority
    try testing.expect(std.mem.indexOf(u8, combined, "from_cli") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "from_file") == null);
}

// Test 40003: Missing env file — warning printed but run continues
test "env_file: missing env file prints warning but continues" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.simple]
        \\cmd = "echo ok"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Specify a non-existent env file
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "simple", "--env-file", "nonexistent.env" }, tmp_path);
    defer result.deinit();

    // Should still succeed
    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Task should execute (output "ok")
    try testing.expect(std.mem.indexOf(u8, combined, "ok") != null);

    // Warning should be in stderr about missing file
    try testing.expect(std.mem.indexOf(u8, result.stderr, "nonexistent.env") != null or
        std.mem.indexOf(u8, result.stderr, "warning") != null or
        std.mem.indexOf(u8, result.stderr, "not found") != null or
        std.mem.indexOf(u8, result.stderr, "cannot") != null);
}

// Test 40004: Second env file overrides first — last file wins
test "env_file: second env file overrides first" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.print-key]
        \\cmd = "echo $KEY"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Both files define KEY; second should override first
    try tmp.dir.writeFile(.{ .sub_path = ".env.first", .data = "KEY=first_value" });
    try tmp.dir.writeFile(.{ .sub_path = ".env.second", .data = "KEY=second_value" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "print-key", "--env-file", ".env.first", "--env-file", ".env.second" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Second file value should appear (last wins)
    try testing.expect(std.mem.indexOf(u8, combined, "second_value") != null);
    // First value should not appear
    try testing.expect(std.mem.indexOf(u8, combined, "first_value") == null);
}

// Test 40005: Env file with comments and blank lines — parsed correctly
test "env_file: handles comments and blank lines correctly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.print-var]
        \\cmd = "echo $APP_NAME"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Write a dotenv file with comments and blank lines
    const dotenv_content =
        \\# This is a comment
        \\
        \\APP_NAME=MyApp
        \\# Another comment
        \\# APP_NAME=OtherValue
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env.config", .data = dotenv_content });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "print-var", "--env-file", ".env.config" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Should load the uncommented KEY=value, ignoring comments
    try testing.expect(std.mem.indexOf(u8, combined, "MyApp") != null);
    // Should not load the commented-out value
    try testing.expect(std.mem.indexOf(u8, combined, "OtherValue") == null);
}
