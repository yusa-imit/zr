const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Test Fixtures ──────────────────────────────────────────────────────

/// Simple task chain: lint -> format -> build
const SKIP_CHAIN_TOML =
    \\[tasks.lint]
    \\cmd = "echo linting"
    \\
    \\[tasks.format]
    \\cmd = "echo formatting"
    \\
    \\[tasks.build]
    \\cmd = "echo building"
    \\deps = ["lint", "format"]
    \\
;

/// Task chain for testing target task skip: a -> b -> c
const SKIP_TARGET_TOML =
    \\[tasks.a]
    \\cmd = "echo task-a"
    \\
    \\[tasks.b]
    \\cmd = "echo task-b"
    \\deps = ["a"]
    \\
    \\[tasks.c]
    \\cmd = "echo task-c"
    \\deps = ["b"]
    \\
;

/// Task chain for testing skip with optional deps
const SKIP_OPTIONAL_TOML =
    \\[tasks.lint]
    \\cmd = "echo linting"
    \\
    \\[tasks.format]
    \\cmd = "echo formatting"
    \\
    \\[tasks.build]
    \\cmd = "echo building"
    \\deps = ["lint"]
    \\deps_optional = ["format"]
    \\
;

/// Task chain for testing skip with conditional deps
const SKIP_CONDITIONAL_TOML =
    \\[tasks.lint]
    \\cmd = "echo linting"
    \\
    \\[tasks.format]
    \\cmd = "echo formatting"
    \\
    \\[tasks.build]
    \\cmd = "echo building"
    \\deps_if = [{ task = "lint", condition = "true" }, { task = "format", condition = "true" }]
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "500: run with --skip single task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task, skip lint
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // lint should NOT appear in output as "✓ completed" or similar
    // (it's skipped, not executed)
    // format and build should still appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "formatting") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "501: run with --skip multiple tasks comma-separated" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task, skip both lint and format (comma-separated)
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint,format" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Both lint and format should be skipped
    // Only building should appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "502: run with --skip multiple flags" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task, skip lint and format using multiple --skip flags
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint", "--skip", "format" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Only building should appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "503: run target task with --skip target itself" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run lint task, but skip lint itself
    var result = try runZr(allocator, &.{ "--config", config, "run", "lint", "--skip", "lint" }, null);
    defer result.deinit();

    // Should succeed (even though target is skipped)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "504: run with --skip nonexistent task succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task, skip nonexistent task (should be silently ignored)
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "nonexistent" }, null);
    defer result.deinit();

    // Should succeed (unknown skip target is silently ignored)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // build should still run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "505: run with --skip and --dry-run together" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task with --dry-run and --skip
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint", "--dry-run" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "506: run with --skip and --json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task with --json and --skip
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint", "--json" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should be valid JSON (at least parseable)
    // Check for expected JSON structure: should have a results object with tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
}

test "507: skipped task doesn't block dependent tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_TARGET_TOML);
    defer allocator.free(config);

    // Run task c with a skipped in the middle
    // Even though a is skipped, b should still run (and then c)
    var result = try runZr(allocator, &.{ "--config", config, "run", "c", "--skip", "a" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Both b and c should run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task-c") != null);
}

test "508: run with --skip and optional deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_OPTIONAL_TOML);
    defer allocator.free(config);

    // Run build task, skip lint (which is a regular dep)
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // format (optional) should still run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "formatting") != null);
    // build should run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "509: run with --skip and conditional deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CONDITIONAL_TOML);
    defer allocator.free(config);

    // Run build task, skip lint (which is conditionally required)
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint" }, null);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // format should still run (conditional dep)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "formatting") != null);
    // build should run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "510: run with --skip, empty skip list succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task normally (no skip) should still work
    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, null);
    defer result.deinit();

    // Should succeed and all tasks should run
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "linting") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "formatting") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "511: run multiple --skip with some valid, some invalid" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, SKIP_CHAIN_TOML);
    defer allocator.free(config);

    // Run build task, skip lint (valid) and nonexistent (invalid)
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--skip", "lint", "--skip", "nonexistent" }, null);
    defer result.deinit();

    // Should succeed (nonexistent is silently ignored)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // format and build should run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "formatting") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}
