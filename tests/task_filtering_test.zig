const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 1: GLOB PATTERN MATCHING (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "task filtering: glob pattern single wildcard test:*" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."test:unit"]
        \\cmd = "echo test_unit"
        \\
        \\[tasks."test:integration"]
        \\cmd = "echo test_integration"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with glob pattern: test:*
    var result = try runZr(allocator, &.{ "--config", config, "run", "test:*" }, tmp_path);
    defer result.deinit();

    // Both test tasks should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test_unit") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test_integration") != null);
}

test "task filtering: glob pattern double wildcard test:**" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."test:unit:api"]
        \\cmd = "echo api_test"
        \\
        \\[tasks."test:unit:db"]
        \\cmd = "echo db_test"
        \\
        \\[tasks."test:integration:api"]
        \\cmd = "echo int_api_test"
        \\
        \\[tasks.lint]
        \\cmd = "echo linting"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with glob pattern: test:**
    var result = try runZr(allocator, &.{ "--config", config, "run", "test:**" }, tmp_path);
    defer result.deinit();

    // All test tasks should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "api_test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "db_test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "int_api_test") != null);
}

test "task filtering: glob pattern prefix match build*" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo build_main"
        \\
        \\[tasks."build-prod"]
        \\cmd = "echo build_prod"
        \\
        \\[tasks."build-dev"]
        \\cmd = "echo build_dev"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with glob pattern: build*
    var result = try runZr(allocator, &.{ "--config", config, "run", "build*" }, tmp_path);
    defer result.deinit();

    // All build tasks should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_main") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_dev") != null);
}

test "task filtering: glob pattern no matches returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with non-existent glob pattern
    var result = try runZr(allocator, &.{ "--config", config, "run", "nonexistent:*" }, tmp_path);
    defer result.deinit();

    // Should fail with no matching tasks
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(
        std.mem.indexOf(u8, result.stderr, "nonexistent") != null or
        std.mem.indexOf(u8, result.stderr, "no matching") != null or
        std.mem.indexOf(u8, result.stderr, "not found") != null
    );
}

test "task filtering: glob pattern invalid syntax shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with invalid glob (unmatched bracket)
    var result = try runZr(allocator, &.{ "--config", config, "run", "test:[" }, tmp_path);
    defer result.deinit();

    // Should fail with error message
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 2: TAG-BASED SELECTION (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "task filtering: single tag --tag=integration" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.unit_test]
        \\cmd = "echo unit"
        \\tags = ["unit"]
        \\
        \\[tasks.integration_test]
        \\cmd = "echo integration"
        \\tags = ["integration"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["build"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with single tag filter
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=integration", "*" }, tmp_path);
    defer result.deinit();

    // Only integration task should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "integration") != null);
}

test "task filtering: multiple tags AND logic --tag=critical --tag=backend" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.critical_backend]
        \\cmd = "echo critical_backend"
        \\tags = ["critical", "backend"]
        \\
        \\[tasks.critical_frontend]
        \\cmd = "echo critical_frontend"
        \\tags = ["critical", "frontend"]
        \\
        \\[tasks.backend_setup]
        \\cmd = "echo backend_setup"
        \\tags = ["backend"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with multiple tag filters (AND logic)
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=critical", "--tag=backend", "*" }, tmp_path);
    defer result.deinit();

    // Only task with BOTH tags should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "critical_backend") != null);
}

test "task filtering: tag exclusion --exclude-tag=slow" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.fast_test]
        \\cmd = "echo fast"
        \\tags = ["test"]
        \\
        \\[tasks.slow_test]
        \\cmd = "echo slow"
        \\tags = ["test", "slow"]
        \\
        \\[tasks.integration]
        \\cmd = "echo integration"
        \\tags = ["test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run excluding slow tasks
    var result = try runZr(allocator, &.{ "--config", config, "run", "--exclude-tag=slow", "*" }, tmp_path);
    defer result.deinit();

    // Slow task should not execute, others should
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fast") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "integration") != null);
}

test "task filtering: combined tag include and exclude --tag=test --exclude-tag=slow" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.fast_unit]
        \\cmd = "echo fast_unit"
        \\tags = ["test", "fast"]
        \\
        \\[tasks.slow_unit]
        \\cmd = "echo slow_unit"
        \\tags = ["test", "slow"]
        \\
        \\[tasks.slow_integration]
        \\cmd = "echo slow_integration"
        \\tags = ["integration", "slow"]
        \\
        \\[tasks.fast_integration]
        \\cmd = "echo fast_integration"
        \\tags = ["integration", "fast"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run test tasks but exclude slow ones
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=test", "--exclude-tag=slow", "*" }, tmp_path);
    defer result.deinit();

    // Only fast_unit should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fast_unit") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "slow_unit") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "integration") == null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 3: COMBINATION FILTERS (4 tests)
// ──────────────────────────────────────────────────────────────────────────

test "task filtering: glob pattern plus tag filter test:* --tag=critical" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."test:unit"]
        \\cmd = "echo test_unit"
        \\tags = ["unit"]
        \\
        \\[tasks."test:integration"]
        \\cmd = "echo test_integration"
        \\tags = ["critical"]
        \\
        \\[tasks."test:e2e"]
        \\cmd = "echo test_e2e"
        \\tags = ["e2e"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["critical"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run glob pattern test:* filtered by critical tag
    var result = try runZr(allocator, &.{ "--config", config, "run", "test:*", "--tag=critical" }, tmp_path);
    defer result.deinit();

    // Only test:integration (critical) should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test_integration") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test_unit") == null);
}

test "task filtering: glob pattern with tag exclusion build* --exclude-tag=dev" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo build_prod"
        \\tags = ["production"]
        \\
        \\[tasks."build-dev"]
        \\cmd = "echo build_dev"
        \\tags = ["dev"]
        \\
        \\[tasks."build-test"]
        \\cmd = "echo build_test"
        \\tags = ["test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run glob pattern excluding dev builds
    var result = try runZr(allocator, &.{ "--config", config, "run", "build*", "--exclude-tag=dev" }, tmp_path);
    defer result.deinit();

    // build_prod and build_test should execute, build_dev should not
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_dev") == null);
}

test "task filtering: all filters combined pattern + include + exclude" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."ci:fast:unit"]
        \\cmd = "echo fast_unit"
        \\tags = ["ci", "fast"]
        \\
        \\[tasks."ci:slow:unit"]
        \\cmd = "echo slow_unit"
        \\tags = ["ci", "slow"]
        \\
        \\[tasks."ci:fast:integration"]
        \\cmd = "echo fast_integration"
        \\tags = ["ci", "fast", "integration"]
        \\
        \\[tasks."deploy:fast"]
        \\cmd = "echo deploy_fast"
        \\tags = ["fast"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run pattern ci:* with tag=fast, exclude slow
    var result = try runZr(allocator, &.{ "--config", config, "run", "ci:*", "--tag=fast", "--exclude-tag=slow" }, tmp_path);
    defer result.deinit();

    // Should execute: fast_unit, fast_integration
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fast_unit") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fast_integration") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy_fast") == null);
}

test "task filtering: combination filters with dry-run preview" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."test:unit"]
        \\cmd = "echo unit_exec"
        \\tags = ["test"]
        \\
        \\[tasks."test:integration"]
        \\cmd = "echo integration_exec"
        \\tags = ["test", "slow"]
        \\
        \\[tasks.build]
        \\cmd = "echo build_exec"
        \\tags = ["build"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with dry-run to preview filtered tasks
    var result = try runZr(allocator, &.{ "--dry-run", "--config", config, "run", "test:*", "--exclude-tag=slow" }, tmp_path);
    defer result.deinit();

    // Should show preview without executing
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 4: MULTIPLE TASK EXECUTION (3 tests)
// ──────────────────────────────────────────────────────────────────────────

test "task filtering: multiple glob matches execute in dependency order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."build:core"]
        \\cmd = "echo build_core"
        \\
        \\[tasks."build:lib"]
        \\cmd = "echo build_lib"
        \\deps = ["build:core"]
        \\
        \\[tasks."build:app"]
        \\cmd = "echo build_app"
        \\deps = ["build:lib"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run all build:* tasks
    var result = try runZr(allocator, &.{ "--config", config, "run", "build:*" }, tmp_path);
    defer result.deinit();

    // All tasks should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_core") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_lib") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build_app") != null);
}

test "task filtering: tag selection runs multiple tasks in parallel if no deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.lint_go]
        \\cmd = "echo lint_go"
        \\tags = ["lint"]
        \\
        \\[tasks.lint_rust]
        \\cmd = "echo lint_rust"
        \\tags = ["lint"]
        \\
        \\[tasks.lint_ts]
        \\cmd = "echo lint_ts"
        \\tags = ["lint"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run all lint tasks (no dependencies, can run in parallel)
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=lint", "*" }, tmp_path);
    defer result.deinit();

    // All lint tasks should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint_go") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint_rust") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint_ts") != null);
}

test "task filtering: combination filters execute all matching tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."ci:unit"]
        \\cmd = "echo unit"
        \\tags = ["ci", "fast"]
        \\
        \\[tasks."ci:lint"]
        \\cmd = "echo lint"
        \\tags = ["ci", "fast"]
        \\
        \\[tasks."ci:build"]
        \\cmd = "echo build"
        \\tags = ["ci", "fast"]
        \\
        \\[tasks."deploy:prod"]
        \\cmd = "echo deploy"
        \\tags = ["fast"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run ci:* tasks with fast tag
    var result = try runZr(allocator, &.{ "--config", config, "run", "ci:*", "--tag=fast" }, tmp_path);
    defer result.deinit();

    // All ci:* tasks should execute (all have fast tag)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "unit") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") == null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 5: EDGE CASES (3 tests)
// ──────────────────────────────────────────────────────────────────────────

test "task filtering: empty result set from glob returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[tasks.world]
        \\cmd = "echo world"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to run tasks that don't exist
    var result = try runZr(allocator, &.{ "--config", config, "run", "phantom:*" }, tmp_path);
    defer result.deinit();

    // Should fail with appropriate error
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "task filtering: all tasks filtered out by exclusion returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.slow_task_1]
        \\cmd = "echo slow1"
        \\tags = ["slow"]
        \\
        \\[tasks.slow_task_2]
        \\cmd = "echo slow2"
        \\tags = ["slow"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to run with wildcard but exclude all
    var result = try runZr(allocator, &.{ "--config", config, "run", "--exclude-tag=slow", "*" }, tmp_path);
    defer result.deinit();

    // Should fail because all tasks are excluded
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "task filtering: single task match runs normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.unique_task]
        \\cmd = "echo unique_output"
        \\tags = ["special"]
        \\
        \\[tasks.other_task]
        \\cmd = "echo other_output"
        \\tags = ["normal"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with filter that matches only one task
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=special", "*" }, tmp_path);
    defer result.deinit();

    // Single task should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "unique_output") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "other_output") == null);
}

// ──────────────────────────────────────────────────────────────────────────
// ADDITIONAL EDGE CASES: COMPLEX SCENARIOS (3 tests)
// ──────────────────────────────────────────────────────────────────────────

test "task filtering: nested glob pattern with multiple levels test:*:**" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."test:unit"]
        \\cmd = "echo unit"
        \\
        \\[tasks."test:integration:db"]
        \\cmd = "echo integration_db"
        \\
        \\[tasks."test:integration:api:v1"]
        \\cmd = "echo integration_api_v1"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with nested glob pattern
    var result = try runZr(allocator, &.{ "--config", config, "run", "test:*:**" }, tmp_path);
    defer result.deinit();

    // All test tasks should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "unit") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "integration_db") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "integration_api_v1") != null);
}

test "task filtering: multiple tag include with different logical groups" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.critical_feature_complete]
        \\cmd = "echo critical_complete"
        \\tags = ["critical", "feature", "complete"]
        \\
        \\[tasks.critical_feature_draft]
        \\cmd = "echo critical_draft"
        \\tags = ["critical", "feature", "draft"]
        \\
        \\[tasks.normal_feature]
        \\cmd = "echo normal_feature"
        \\tags = ["feature"]
        \\
        \\[tasks.critical_infra]
        \\cmd = "echo critical_infra"
        \\tags = ["critical", "infra"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with critical + complete tags (AND logic)
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=critical", "--tag=complete", "*" }, tmp_path);
    defer result.deinit();

    // Only task with both tags should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "critical_complete") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "critical_draft") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "critical_infra") == null);
}

test "task filtering: glob with special characters in task names" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."lint-go"]
        \\cmd = "echo lint_go"
        \\
        \\[tasks."lint-rust"]
        \\cmd = "echo lint_rust"
        \\
        \\[tasks."lint_ts"]
        \\cmd = "echo lint_ts"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with pattern matching hyphens and underscores
    var result = try runZr(allocator, &.{ "--config", config, "run", "lint*" }, tmp_path);
    defer result.deinit();

    // All lint tasks should execute
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint_go") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint_rust") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint_ts") != null);
}
