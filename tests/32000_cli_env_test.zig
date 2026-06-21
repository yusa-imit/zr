const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── CLI Environment Variables Tests ────────────────────────────────────────
//
// Tests for `--env KEY=VALUE` CLI flag feature (v1.102.0+):
//
// 32000: Basic --env KEY=VALUE — set an env var and verify task can use it via $KEY
// 32001: Multiple --env flags — --env A=foo --env B=bar, both available in task
// 32002: --env overrides task-level env field — task has env={X="original"}, --env X=override should win
// 32003: --env satisfies required_env — task has required_env=["REQUIRED_KEY"], run with --env REQUIRED_KEY=yes should succeed
// 32004: --dry-run shows CLI env overrides — with --env KEY=value, dry-run output contains "CLI env" or "KEY=value"
// 32005: --env value available in task cmd template substitution — define [vars] X="original", override with --env X=cli_val, verify CLI wins
//

const BASIC_ENV_TOML =
    \\[tasks.show_env]
    \\cmd = "echo X=$X"
    \\
;

const MULTI_ENV_TOML =
    \\[tasks.show_multi]
    \\cmd = "echo A=$A B=$B"
    \\
;

const OVERRIDE_ENV_TOML =
    \\[tasks.override_test]
    \\cmd = "echo X=$X"
    \\env = { X = "original" }
    \\
;

const REQUIRED_ENV_TOML =
    \\[tasks.requires_env]
    \\cmd = "echo REQUIRED_KEY=$REQUIRED_KEY"
    \\required_env = ["REQUIRED_KEY"]
    \\
;

const DRY_RUN_ENV_TOML =
    \\[tasks.simple]
    \\cmd = "echo hello"
    \\
;

const VAR_OVERRIDE_TOML =
    \\[vars]
    \\X = "original"
    \\
    \\[tasks.show_var]
    \\cmd = "echo X=$X"
    \\env = { X = "{{X}}" }
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "32000: basic --env KEY=VALUE — set an env var and verify task can use it via $KEY" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, BASIC_ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show_env", "--env", "X=hello" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain the env var value "hello" (not empty or unset)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "X=hello") != null);
}

test "32001: multiple --env flags — --env A=foo --env B=bar, both available in task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show_multi", "--env", "A=foo", "--env", "B=bar" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain both values
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "A=foo") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "B=bar") != null);
}

test "32002: --env overrides task-level env field — task has env={X=original}, --env X=override should win" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, OVERRIDE_ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "override_test", "--env", "X=override" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should show the CLI override value, not the task-level original
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "X=override") != null);
    // Verify the original value is NOT present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "X=original") == null);
}

test "32003: --env satisfies required_env — task has required_env=[REQUIRED_KEY], run with --env REQUIRED_KEY=yes should succeed" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, REQUIRED_ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "requires_env", "--env", "REQUIRED_KEY=yes" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully with exit code 0
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain the required env var
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "REQUIRED_KEY=yes") != null);
}

test "32004: --dry-run shows CLI env overrides — with --env KEY=value, dry-run output contains CLI env section" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, DRY_RUN_ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "--dry-run", "run", "simple", "--env", "MYKEY=myvalue" }, tmp_path);
    defer result.deinit();

    // Dry-run should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should indicate CLI env overrides (check for presence of env info)
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(
        std.mem.indexOf(u8, combined, "CLI env") != null or
            std.mem.indexOf(u8, combined, "MYKEY") != null or
            std.mem.indexOf(u8, combined, "myvalue") != null
    );
}

test "32005: --env value available in task cmd template substitution — [vars] X=original, --env X=cli_val, verify CLI wins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, VAR_OVERRIDE_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show_var", "--env", "X=cli_val" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should show the CLI override value "cli_val", not the vars value "original"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "X=cli_val") != null);
    // Verify the original var value is NOT present in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "X=original") == null);
}
