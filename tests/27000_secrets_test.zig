const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrEnv = helpers.runZrEnv;

// ── Task Secret Management Tests ───────────────────────────────────────────
//
// Tests for `secrets = ["KEY1", "KEY2"]` task field and secret management
// commands (v1.98.0 milestone):
//
// 1. Task with secrets runs successfully when all secrets are set in env
// 2. Task fails early when a required secret is missing
// 3. `zr secrets list` shows tasks with their secret status (set/missing)
// 4. `zr secrets check` validates all secrets and exits accordingly
// 5. Secret values are automatically masked in task output
// 6. `zr run --dry-run` shows "Secrets required: ..." for tasks with secrets
//

const SECRETS_TOML_SINGLE =
    \\[tasks.secure]
    \\cmd = "echo My secret is: $MY_API_KEY"
    \\secrets = ["MY_API_KEY"]
    \\
;

const SECRETS_TOML_MULTIPLE =
    \\[tasks.auth]
    \\cmd = "echo API_KEY=$API_KEY and TOKEN=$AUTH_TOKEN"
    \\secrets = ["API_KEY", "AUTH_TOKEN"]
    \\
    \\[tasks.public]
    \\cmd = "echo Hello World"
    \\
;

const SECRETS_TOML_PARTIAL =
    \\[tasks.deploy]
    \\cmd = "echo Deploying with $DB_PASS and $SSH_KEY"
    \\secrets = ["DB_PASS", "SSH_KEY"]
    \\
;

test "27000: zr run task with secrets succeeds when all secrets are set in env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with a task that has secrets
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SECRETS_TOML_SINGLE });

    // Set up environment with the secret
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("MY_API_KEY", "super-secret-123");

    // Run the task with the secret set
    var result = try runZrEnv(allocator, &.{ "run", "secure" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed (exit code 0)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Stdout should NOT contain the actual secret value (should be masked)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "super-secret-123") == null);
}

test "27001: zr run task fails when required secret is missing from env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with a task that requires a secret
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SECRETS_TOML_SINGLE });

    // Set up empty environment (no MY_API_KEY)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();

    // Run the task WITHOUT the secret set
    var result = try runZrEnv(allocator, &.{ "run", "secure" }, tmp_path, &env_map);
    defer result.deinit();

    // Should fail (exit code != 0)
    try std.testing.expect(result.exit_code != 0);

    // Stderr should mention the missing secret name
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "MY_API_KEY") != null);

    // Stdout should be empty or minimal — the task command should NOT have run
    // (check that we don't see the task's echo output)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "My secret is") == null);
}

test "27002: zr secrets list shows tasks with their secret names and status" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with two tasks: one with secrets, one without
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SECRETS_TOML_MULTIPLE });

    // Set up environment with one secret set, one missing
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("API_KEY", "key-value");
    // AUTH_TOKEN is NOT set

    // Run: zr secrets list
    var result = try runZrEnv(allocator, &.{ "secrets", "list" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed with exit code 0
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should mention the 'auth' task and its secrets
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "auth") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "API_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "AUTH_TOKEN") != null);

    // Output should indicate status: API_KEY is set, AUTH_TOKEN is missing
    // (exact format may vary, but should distinguish between set/missing)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "set") != null or
        std.mem.indexOf(u8, result.stdout, "missing") != null or
        std.mem.indexOf(u8, result.stdout, "[✓]") != null or
        std.mem.indexOf(u8, result.stdout, "[✗]") != null);

    // The 'public' task (no secrets) may or may not be listed, but if listed, should not have secrets
    // (we just verify the output is non-empty and well-formed)
    try std.testing.expect(result.stdout.len > 0);
}

test "27003: zr secrets check exits 0 when all secrets are set, 1 when any missing" {
    const allocator = std.testing.allocator;

    // Test A: All secrets set -> exit code 0
    {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);

        try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SECRETS_TOML_MULTIPLE });

        var env_map = std.process.EnvMap.init(allocator);
        defer env_map.deinit();
        try env_map.put("API_KEY", "key-value");
        try env_map.put("AUTH_TOKEN", "token-value");

        var result = try runZrEnv(allocator, &.{ "secrets", "check" }, tmp_path, &env_map);
        defer result.deinit();

        // Should succeed when all secrets are set
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // Test B: Some secrets missing -> exit code 1
    {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);

        try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SECRETS_TOML_MULTIPLE });

        var env_map = std.process.EnvMap.init(allocator);
        defer env_map.deinit();
        try env_map.put("API_KEY", "key-value");
        // AUTH_TOKEN NOT set

        var result = try runZrEnv(allocator, &.{ "secrets", "check" }, tmp_path, &env_map);
        defer result.deinit();

        // Should fail when secrets are missing
        try std.testing.expect(result.exit_code != 0);

        // Output (stdout or stderr) should mention the missing secret name
        const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
        defer allocator.free(combined);
        try std.testing.expect(std.mem.indexOf(u8, combined, "AUTH_TOKEN") != null);
    }
}

test "27004: Secret values are masked in task output with ***" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with a task that echoes the secret value
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SECRETS_TOML_SINGLE });

    // Set up environment with a known secret value
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("MY_API_KEY", "secret-api-key-12345");

    // Run the task
    var result = try runZrEnv(allocator, &.{ "run", "secure" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should contain the masked placeholder
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "***") != null);

    // Output should NOT contain the actual secret value
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "secret-api-key-12345") == null);
}

test "27005: zr run --dry-run shows 'Secrets required: ...' for tasks with secrets" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with a task that has multiple secrets
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SECRETS_TOML_MULTIPLE });

    // Set up environment (may or may not have secrets — dry-run doesn't require them)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();

    // Run: zr run --dry-run auth
    var result = try runZrEnv(allocator, &.{ "run", "--dry-run", "auth" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed with exit code 0 (dry-run doesn't validate secrets)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Dry-run output should mention the required secrets
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);

    // Should indicate that secrets are required
    try std.testing.expect(std.mem.indexOf(u8, combined, "Secrets") != null or
        std.mem.indexOf(u8, combined, "API_KEY") != null or
        std.mem.indexOf(u8, combined, "AUTH_TOKEN") != null);
}
