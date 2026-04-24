const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrEnv = helpers.runZrEnv;
const writeTmpConfig = helpers.writeTmpConfig;

// ══════════════════════════════════════════════════════════════════════════════
// Integration Tests: Conditional Dependencies in --dry-run Mode
// ══════════════════════════════════════════════════════════════════════════════
//
// These tests verify that --dry-run correctly previews which tasks will run
// based on conditional dependency evaluation (deps_if).
//
// Conditional deps use the expression engine (params.X, has_tag(), env vars)
// to decide at planning time whether a dependency should be included.
//
// Key behaviors tested:
// - Conditional deps that evaluate to TRUE → dependency task appears in plan
// - Conditional deps that evaluate to FALSE → dependency task NOT in plan
// - Multiple conditional deps with mixed results
// - Nested dependencies with conditions
// - Combination with regular deps in the execution plan
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 1: Basic Conditional Dependency Dry-Run (4 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps_dryrun: condition met shows both tasks in plan" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'deploy' conditionally depends on 'setup' when env.TARGET == 'production'
    const toml =
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps_if = [{ task = "setup", condition = "env.TARGET == 'production'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Set TARGET to 'production' → condition is met
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("TARGET", "production");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both tasks should appear in the dry-run plan (dependency included)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
    // Should indicate this is a dry-run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Dry run") != null or std.mem.indexOf(u8, result.stdout, "dry") != null);
}

test "conditional_deps_dryrun: condition not met shows only target task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'deploy' conditionally depends on 'setup' when env.TARGET == 'production'
    const toml =
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps_if = [{ task = "setup", condition = "env.TARGET == 'production'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Set TARGET to 'dev' (not 'production') → condition is NOT met
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("TARGET", "dev");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only deploy should appear (conditional dependency skipped)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") == null);
}

test "conditional_deps_dryrun: has_tag condition met includes dependency" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' has 'docker' tag
    // Conditionally depends on 'docker_setup' if has_tag('docker')
    const toml =
        \\[tasks.docker_setup]
        \\cmd = "echo docker_setup"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["docker", "production"]
        \\deps_if = [{ task = "docker_setup", condition = "has_tag('docker')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--dry-run" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both tasks should appear (condition met because task has 'docker' tag)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "docker_setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "conditional_deps_dryrun: has_tag condition not met excludes dependency" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' does NOT have 'docker' tag
    // Conditionally depends on 'docker_setup' if has_tag('docker')
    const toml =
        \\[tasks.docker_setup]
        \\cmd = "echo docker_setup"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["python", "lint"]
        \\deps_if = [{ task = "docker_setup", condition = "has_tag('docker')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--dry-run" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only build should appear (no 'docker' tag → condition not met)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "docker_setup") == null);
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 2: Multiple Conditional Dependencies (3 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps_dryrun: multiple deps_if with some met some not" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' has two conditional deps
    // - 'lint' runs if SKIP_LINT != 'true'
    // - 'test' runs if SKIP_TEST != 'true'
    const toml =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = [
        \\  { task = "lint", condition = "env.SKIP_LINT != 'true'" },
        \\  { task = "test", condition = "env.SKIP_TEST != 'true'" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // SKIP_LINT=true (condition NOT met), SKIP_TEST=false (condition met)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_LINT", "true");
    try env_map.put("SKIP_TEST", "false");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only test and build should appear (lint skipped due to SKIP_LINT=true)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") == null);
}

test "conditional_deps_dryrun: all conditional deps met shows all tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = [
        \\  { task = "lint", condition = "env.SKIP_LINT != 'true'" },
        \\  { task = "test", condition = "env.SKIP_TEST != 'true'" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Both conditions met (neither SKIP var is 'true')
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_LINT", "false");
    try env_map.put("SKIP_TEST", "false");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All three tasks should appear in plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "conditional_deps_dryrun: all conditional deps not met shows only target" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = [
        \\  { task = "lint", condition = "env.SKIP_LINT != 'true'" },
        \\  { task = "test", condition = "env.SKIP_TEST != 'true'" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Both conditions NOT met (both SKIP vars are 'true')
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_LINT", "true");
    try env_map.put("SKIP_TEST", "true");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only build should appear (all conditional deps skipped)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") == null);
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 3: Nested Dependencies with Conditions (3 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps_dryrun: nested chain A->B->C with condition met" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A conditionally depends on B (if ENV_MODE == 'production')
    // B unconditionally depends on C
    const toml =
        \\[tasks.c]
        \\cmd = "echo c"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["c"]
        \\
        \\[tasks.a]
        \\cmd = "echo a"
        \\deps_if = [{ task = "b", condition = "env.ENV_MODE == 'production'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Condition met → A depends on B, B depends on C
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ENV_MODE", "production");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "a", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All three tasks should appear in dependency order: C -> B -> A
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "c") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
}

test "conditional_deps_dryrun: nested chain A->B->C with condition not met" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A conditionally depends on B (if ENV_MODE == 'production')
    // B unconditionally depends on C
    const toml =
        \\[tasks.c]
        \\cmd = "echo c"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["c"]
        \\
        \\[tasks.a]
        \\cmd = "echo a"
        \\deps_if = [{ task = "b", condition = "env.ENV_MODE == 'production'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Condition NOT met → A does not depend on B (or C)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ENV_MODE", "dev");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "a", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only A should appear (conditional dep on B not included, so C also excluded)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "c") == null);
}

test "conditional_deps_dryrun: diamond dependency with conditional middle branch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Diamond shape:
    //   D depends on B and C
    //   B depends on A (unconditional)
    //   C depends on A (conditional: if env.USE_C == 'true')
    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\deps_if = [{ task = "a", condition = "env.USE_C == 'true'" }]
        \\
        \\[tasks.d]
        \\cmd = "echo d"
        \\deps = ["b", "c"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // USE_C is 'false' → C's conditional dep on A is NOT met
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("USE_C", "false");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "d", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show: A (via B), B, C (but C won't depend on A), D
    // A appears because B->A is unconditional
    // C appears because D->C is unconditional, but C->A conditional dep is not met
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "c") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "d") != null);
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 4: Mixed Regular + Conditional Dependencies (3 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps_dryrun: mix of deps and deps_if shows correct plan" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'deploy' has:
    // - Regular dep: 'build' (always runs)
    // - Conditional dep: 'test' (runs if SKIP_TEST != 'true')
    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps = ["build"]
        \\deps_if = [{ task = "test", condition = "env.SKIP_TEST != 'true'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Condition met → test should be included
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_TEST", "false");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All three tasks should appear (regular + conditional deps both included)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

test "conditional_deps_dryrun: mix with conditional dep skipped shows regular deps only" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'deploy' has:
    // - Regular dep: 'build' (always runs)
    // - Conditional dep: 'test' (runs if SKIP_TEST != 'true')
    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps = ["build"]
        \\deps_if = [{ task = "test", condition = "env.SKIP_TEST != 'true'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Condition NOT met → test should be skipped
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_TEST", "true");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only build and deploy should appear (conditional test dep skipped)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") == null);
}

test "conditional_deps_dryrun: complex mix with multiple regular and conditional deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'package' has:
    // - Regular deps: 'compile', 'lint'
    // - Conditional deps: 'test' (if RUN_TESTS != 'false'), 'docs' (if GEN_DOCS == 'true')
    const toml =
        \\[tasks.compile]
        \\cmd = "echo compile"
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.docs]
        \\cmd = "echo docs"
        \\
        \\[tasks.package]
        \\cmd = "echo package"
        \\deps = ["compile", "lint"]
        \\deps_if = [
        \\  { task = "test", condition = "env.RUN_TESTS != 'false'" },
        \\  { task = "docs", condition = "env.GEN_DOCS == 'true'" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // RUN_TESTS != 'false' (true), GEN_DOCS != 'true' (false)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("RUN_TESTS", "true");
    try env_map.put("GEN_DOCS", "false");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "package", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show: compile, lint, test, package (docs excluded)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "package") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "docs") == null);
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 5: Edge Cases (3 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps_dryrun: empty deps_if array shows only target" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task with empty deps_if array (no conditional deps)
    const toml =
        \\[tasks.simple]
        \\cmd = "echo simple"
        \\deps_if = []
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "simple", "--dry-run" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only the target task should appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "simple") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Dry run") != null);
}

test "conditional_deps_dryrun: complex boolean expression in condition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Condition: (ENV_TYPE == 'prod' AND has 'docker') OR !has_tag('skip')
    const toml =
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["docker", "production"]
        \\deps_if = [{ task = "setup", condition = "(env.ENV_TYPE == 'prod' && has_tag('docker')) || !has_tag('skip')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // ENV_TYPE == 'prod' AND has_tag('docker') is TRUE
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ENV_TYPE", "prod");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy", "--dry-run" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Condition is met (first part of OR is true)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

test "conditional_deps_dryrun: negation operator in condition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Condition uses negation: !has_tag('skip')
    const toml =
        \\[tasks.prep]
        \\cmd = "echo prep"
        \\
        \\[tasks.run]
        \\cmd = "echo run"
        \\tags = ["fast", "ci"]
        \\deps_if = [{ task = "prep", condition = "!has_tag('skip')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "run", "--dry-run" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Task does NOT have 'skip' tag, so !has_tag('skip') is TRUE
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prep") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "run") != null);
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 6: Dry-Run Format Verification (2 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps_dryrun: output shows execution plan header" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.simple]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "simple", "--dry-run" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain dry-run indicator
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Dry run") != null or std.mem.indexOf(u8, result.stdout, "dry") != null);
    // Should contain execution plan or similar wording
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "plan") != null or std.mem.indexOf(u8, result.stdout, "execution") != null);
}

test "conditional_deps_dryrun: parallel level formatting in output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Two tasks that can run in parallel (no dependencies between them)
    const toml =
        \\[tasks.task_a]
        \\cmd = "echo a"
        \\
        \\[tasks.task_b]
        \\cmd = "echo b"
        \\
        \\[tasks.final]
        \\cmd = "echo final"
        \\deps = ["task_a", "task_b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "final", "--dry-run" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show all three tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task_a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task_b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "final") != null);
    // May contain level indicators (Level 0, Level 1, etc) or parallel indicators
    const has_level_info = std.mem.indexOf(u8, result.stdout, "Level") != null or
        std.mem.indexOf(u8, result.stdout, "parallel") != null;
    try std.testing.expect(has_level_info);
}
