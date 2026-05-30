const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Run with --only Flag ───────────────────────────────────────────────────────
//
// These tests verify the --only flag behavior:
// - --only <task> runs ONLY the specified task WITHOUT executing its dependencies
// - Useful for iterating on specific tasks when deps are already done
// - Task isolation for debugging and testing
//
// EXPECTED BEHAVIOR:
// - zr run --only build → runs build even if it has deps = ["setup"]
// - setup task is NOT executed, no error about missing dependencies
// - If task doesn't exist, show "task not found" error (exit code != 0)
// - --only can combine with --dry-run, --format json, etc.
// - --only applies to all tasks on command line
// - Task output contains only the specified task's output
// - Normal run (without --only) still executes all dependencies
//

test "run --only: task with deps runs without executing deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with task that depends on another
    const config_toml =
        \\[tasks.setup]
        \\cmd = "echo setup completed"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\deps = ["setup"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run build with --only flag
    var result = try runZr(allocator, &.{ "--config", config, "run", "--only", "build" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // build task output should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);

    // setup task output should NOT be present (deps not executed)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup completed") == null);
}

test "run --only: task with multiple deps skips all deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with task that has multiple dependencies
    const config_toml =
        \\[tasks.lint]
        \\cmd = "echo linting"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\deps = ["lint", "test"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run deploy with --only flag
    var result = try runZr(allocator, &.{ "--config", config, "run", "--only", "deploy" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // deploy task output should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploying") != null);

    // dep task outputs should NOT be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "linting") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") == null);
}

test "run --only: nonexistent task produces error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal config
    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run with --only for nonexistent task
    var result = try runZr(allocator, &.{ "--config", config, "run", "--only", "nonexistent" }, tmp_path);
    defer result.deinit();

    // Should fail
    try std.testing.expect(result.exit_code != 0);

    // Error message should mention task not found
    const error_output = result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, error_output, "nonexistent") != null or
                          std.mem.indexOf(u8, error_output, "not found") != null or
                          std.mem.indexOf(u8, error_output, "No such task") != null);
}

test "run --only with --dry-run: shows dry-run output without executing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with deps
    const config_toml =
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps = ["setup"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run with both --only and --dry-run
    var result = try runZr(allocator, &.{ "--config", config, "run", "--only", "build", "--dry-run" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output indicates dry-run and only shows build task (not setup)
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
    // setup should NOT appear — --only skips deps, --dry-run should not plan them either
    try std.testing.expect(std.mem.indexOf(u8, output, "setup") == null);
}

test "run: normal run without --only executes dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with deps
    const config_toml =
        \\[tasks.setup]
        \\cmd = "echo setup done"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\deps = ["setup"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run build WITHOUT --only flag
    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // BOTH setup and build output should be present (deps ARE executed)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup done") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "run --only: task with no deps works normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with independent task
    const config_toml =
        \\[tasks.lint]
        \\cmd = "echo linting complete"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run with --only on task with no deps
    var result = try runZr(allocator, &.{ "--config", config, "run", "--only", "lint" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Task output should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "linting complete") != null);
}

test "run --only: with serial dependencies also skips them" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with serial deps
    const config_toml =
        \\[tasks.step1]
        \\cmd = "echo step1"
        \\
        \\[tasks.step2]
        \\cmd = "echo step2"
        \\
        \\[tasks.final]
        \\cmd = "echo final"
        \\deps_serial = ["step1", "step2"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run with --only
    var result = try runZr(allocator, &.{ "--config", config, "run", "--only", "final" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Only final output should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "final") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step1") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step2") == null);
}

test "run --only: with --format json includes only specified task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with deps
    const config_toml =
        \\[tasks.dep]
        \\cmd = "echo dep"
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\deps = ["dep"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run with --only and --format json
    var result = try runZr(allocator, &.{ "--config", config, "run", "--only", "main", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should succeed — --only skips the "dep" dependency and runs only "main"
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // JSON output lists only the tasks that ran; dep was skipped so it won't appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"name\":\"main\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"name\":\"dep\"") == null);
}
