const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrEnv = helpers.runZrEnv;
const writeTmpConfig = helpers.writeTmpConfig;

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 1: Environment-Based Conditional Dependencies (5 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps: env.TARGET == 'production' when condition met" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'deploy' depends on 'setup' only when TARGET env var == 'production'
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP_RAN"
        \\
        \\[tasks.deploy]
        \\cmd = "echo DEPLOY_RAN"
        \\deps_if = [{ task = "setup", condition = "env.TARGET == 'production'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Create environment with TARGET set to 'production'
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("TARGET", "production");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both setup and deploy should have run
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP_RAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "DEPLOY_RAN"));
}

test "conditional_deps: env.TARGET == 'production' when condition not met" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'deploy' depends on 'setup' only when TARGET env var == 'production'
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP_RAN"
        \\
        \\[tasks.deploy]
        \\cmd = "echo DEPLOY_RAN"
        \\deps_if = [{ task = "setup", condition = "env.TARGET == 'production'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Create environment with TARGET set to 'dev' (not 'production')
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("TARGET", "dev");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only deploy should have run (setup skipped)
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP_RAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "DEPLOY_RAN"));
}

test "conditional_deps: env.SKIP_TESTS != 'true'" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' depends on 'test' unless SKIP_TESTS == 'true'
    const toml =
        \\[tasks.test]
        \\cmd = "echo TEST_RAN"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD_RAN"
        \\deps_if = [{ task = "test", condition = "env.SKIP_TESTS != 'true'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Condition is true when SKIP_TESTS is NOT 'true' (e.g., 'false' or missing)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_TESTS", "false");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Test should run because SKIP_TESTS != 'true'
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "TEST_RAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD_RAN"));
}

test "conditional_deps: env.USE_CACHE truthy check" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' depends on 'setup_cache' only if USE_CACHE env var is truthy (non-empty)
    const toml =
        \\[tasks.setup_cache]
        \\cmd = "echo CACHE_SETUP"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD_DONE"
        \\deps_if = [{ task = "setup_cache", condition = "env.USE_CACHE" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // USE_CACHE is set to a truthy value
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("USE_CACHE", "yes");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both should run because USE_CACHE is truthy
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "CACHE_SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD_DONE"));
}

test "conditional_deps: env in nested dependencies A->B->C" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A depends on B if ENV_MODE == 'production'
    // B depends on C unconditionally
    const toml =
        \\[tasks.c]
        \\cmd = "echo C_RAN"
        \\
        \\[tasks.b]
        \\cmd = "echo B_RAN"
        \\deps = ["c"]
        \\
        \\[tasks.a]
        \\cmd = "echo A_RAN"
        \\deps_if = [{ task = "b", condition = "env.ENV_MODE == 'production'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ENV_MODE", "production");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "a" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All three should run in dependency order: C -> B -> A
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "C_RAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "B_RAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "A_RAN"));
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 2: Tag-Based Conditional Dependencies (4 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps: has_tag('docker') when task has tag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' has 'docker' tag
    // Task 'deploy' depends on 'docker_setup' only if task has 'docker' tag
    const toml =
        \\[tasks.docker_setup]
        \\cmd = "echo DOCKER_SETUP"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD"
        \\tags = ["docker", "production"]
        \\deps_if = [{ task = "docker_setup", condition = "has_tag('docker')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // docker_setup should run because build has 'docker' tag
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "DOCKER_SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD"));
}

test "conditional_deps: has_tag('docker') when task lacks tag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' does NOT have 'docker' tag
    // Task 'deploy' depends on 'docker_setup' only if task has 'docker' tag
    const toml =
        \\[tasks.docker_setup]
        \\cmd = "echo DOCKER_SETUP"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD"
        \\tags = ["python", "lint"]
        \\deps_if = [{ task = "docker_setup", condition = "has_tag('docker')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // docker_setup should NOT run because build lacks 'docker' tag
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "DOCKER_SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD"));
}

test "conditional_deps: has_tag with multiple conditions using &&" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' has both 'docker' and 'linux' tags
    // Task depends on 'setup' only if has both tags
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD"
        \\tags = ["docker", "linux", "ci"]
        \\deps_if = [{ task = "setup", condition = "has_tag('docker') && has_tag('linux')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // setup should run because task has both 'docker' and 'linux'
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD"));
}

test "conditional_deps: has_tag with OR condition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task depends on 'setup' if has 'slow' OR 'benchmark' tag
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP"
        \\
        \\[tasks.benchmark]
        \\cmd = "echo BENCHMARK"
        \\tags = ["benchmark", "ci"]
        \\deps_if = [{ task = "setup", condition = "has_tag('slow') || has_tag('benchmark')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "benchmark" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // setup should run because task has 'benchmark' tag (second condition)
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BENCHMARK"));
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 3: Combined Conditions (3 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps: env && tags combined" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task depends on 'setup' if DEPLOY_MODE env == 'production' AND has 'deploy' tag
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP"
        \\
        \\[tasks.release]
        \\cmd = "echo RELEASE"
        \\tags = ["deploy", "production"]
        \\deps_if = [{ task = "setup", condition = "env.DEPLOY_MODE == 'production' && has_tag('deploy')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("DEPLOY_MODE", "production");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "release" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both conditions met, so setup should run
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "RELEASE"));
}

test "conditional_deps: multiple env vars combined" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task depends on 'setup' if BUILD_TARGET == 'linux' AND ENABLE_LINUX == 'true'
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD"
        \\deps_if = [{ task = "setup", condition = "env.BUILD_TARGET == 'linux' && env.ENABLE_LINUX == 'true'" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("BUILD_TARGET", "linux");
    try env_map.put("ENABLE_LINUX", "true");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both conditions met
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD"));
}

test "conditional_deps: complex condition with grouping" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Complex condition: (ENV_TYPE == 'prod' AND has 'docker') OR !has_tag('skip')
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP"
        \\
        \\[tasks.deploy]
        \\cmd = "echo DEPLOY"
        \\tags = ["docker", "production"]
        \\deps_if = [{ task = "setup", condition = "(env.ENV_TYPE == 'prod' && has_tag('docker')) || !has_tag('skip')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ENV_TYPE", "prod");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "deploy" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // First part of OR is true: env.ENV_TYPE == 'prod' && has_tag('docker')
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "DEPLOY"));
}

// ══════════════════════════════════════════════════════════════════════════════
// Test Category 4: Edge Cases (3 tests)
// ══════════════════════════════════════════════════════════════════════════════

test "conditional_deps: missing env var evaluates as falsy" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task depends on 'setup' only if OPTIONAL_VAR env var is set (truthy)
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD"
        \\deps_if = [{ task = "setup", condition = "env.OPTIONAL_VAR" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Don't set OPTIONAL_VAR — it will be empty/falsy
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // setup should NOT run because OPTIONAL_VAR is missing (falsy)
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD"));
}

test "conditional_deps: task with no tags + has_tag condition evaluates false" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task has NO tags defined
    // Condition requires 'docker' tag
    const toml =
        \\[tasks.setup]
        \\cmd = "echo SETUP"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD"
        \\deps_if = [{ task = "setup", condition = "has_tag('docker')" }]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // setup should NOT run because task has no tags
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "SETUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD"));
}

test "conditional_deps: multiple deps_if conditions on same task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task 'build' has multiple deps_if
    // lint runs if condition1, test runs if condition2
    const toml =
        \\[tasks.lint]
        \\cmd = "echo LINT"
        \\
        \\[tasks.test]
        \\cmd = "echo TEST"
        \\
        \\[tasks.build]
        \\cmd = "echo BUILD"
        \\deps_if = [
        \\  { task = "lint", condition = "env.SKIP_LINT != 'true'" },
        \\  { task = "test", condition = "env.SKIP_TEST != 'true'" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_LINT", "true");
    try env_map.put("SKIP_TEST", "false");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "build" }, null, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Only test should run (SKIP_LINT is true, so lint skipped)
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "LINT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "TEST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "BUILD"));
}
