const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Required Environment Variables ──────────────────────────────────────────
//
// These tests verify the Required Environment Variables feature:
// - required_env field in task config: required_env = ["VAR1", "VAR2", ...]
// - Array of variable names that MUST be set before task runs
// - Variables can come from system env, task env, or env_file
// - Task fails BEFORE running if any required var is missing
// - Error message lists all missing variables clearly
// - Empty required_env = [] has no effect (task runs normally)
//
// EXPECTED BEHAVIOR:
// - All required vars set → task runs normally (exit code 0)
// - Any required var missing → task fails (exit code != 0) BEFORE executing
// - Error message includes all missing var names
// - Vars from env_file count as "set"
// - Vars from task env count as "set"
// - Vars from system env count as "set"
// - Empty list → no validation performed
// - Works alongside other env features (env_file, task env)
//

test "required_env: task succeeds when all required vars are set" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create task with required_env and provide all vars via task env
    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to $DATABASE_URL with key $API_KEY"
        \\required_env = ["DATABASE_URL", "API_KEY"]
        \\env = { DATABASE_URL = "postgres://localhost", API_KEY = "secret123" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify it succeeds
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Deploying") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "postgres://localhost") != null);
}

test "required_env: task fails when required var is missing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create task with required_env but don't provide all required vars
    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo This should not run"
        \\required_env = ["DATABASE_URL", "API_KEY"]
        \\env = { API_KEY = "secret123" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify it fails
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code != 0)
    try std.testing.expect(result.exit_code != 0);
    // Error message should mention the missing var
    const error_msg = result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, error_msg, "DATABASE_URL") != null or
                          std.mem.indexOf(u8, error_msg, "missing") != null or
                          std.mem.indexOf(u8, error_msg, "required") != null);
}

test "required_env: error lists all missing variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create task requiring 3 variables but provide none
    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo This should not run"
        \\required_env = ["DATABASE_URL", "API_KEY", "SECRET_TOKEN"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify all missing vars are mentioned in error
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const error_msg = result.stderr;
    // All three missing variables should be listed
    try std.testing.expect(std.mem.indexOf(u8, error_msg, "DATABASE_URL") != null);
    try std.testing.expect(std.mem.indexOf(u8, error_msg, "API_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, error_msg, "SECRET_TOKEN") != null);
}

test "required_env: partially missing vars — only missing ones are reported" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create task requiring 3 variables but provide only 2
    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo This should not run"
        \\required_env = ["DATABASE_URL", "API_KEY", "SECRET_TOKEN"]
        \\env = { DATABASE_URL = "postgres://localhost", API_KEY = "secret123" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify only the missing var is reported
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const error_msg = result.stderr;
    // Missing var should be listed
    try std.testing.expect(std.mem.indexOf(u8, error_msg, "SECRET_TOKEN") != null);
    // Present vars should NOT appear in error (optional: they might be listed as "provided")
}

test "required_env: empty required_env list has no effect" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create task with empty required_env (should not prevent execution)
    const config_toml =
        \\[tasks.simple-task]
        \\cmd = "echo Task executed successfully"
        \\required_env = []
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify it succeeds despite empty required_env
    var result = try runZr(allocator, &.{ "--config", config, "run", "simple-task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task executed") != null);
}

test "required_env: vars from env_file satisfy required_env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file with required variables
    const env_content =
        \\DATABASE_URL=postgres://localhost
        \\API_KEY=secret123
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task with required_env and env_file
    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo Connecting to $DATABASE_URL"
        \\required_env = ["DATABASE_URL", "API_KEY"]
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify it succeeds because env_file provides required vars
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "postgres://localhost") != null);
}

test "required_env: var set in task env satisfies required_env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create task with required_env and all vars in task env
    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying with DB=$DATABASE_URL"
        \\required_env = ["DATABASE_URL"]
        \\env = { DATABASE_URL = "postgres://prod.example.com" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify it succeeds with task env vars
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "postgres://prod.example.com") != null);
}
