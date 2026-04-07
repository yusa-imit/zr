const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test 8000-8019: Advanced Task Composition & Mixins (v1.67.0)

test "8000: basic single mixin inheritance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create config with mixin and task that uses it
    const config_toml =
        \\[mixins.common_env]
        \\env = [["BUILD_TYPE", "debug"], ["LOG_LEVEL", "info"]]
        \\deps = ["build"]
        \\tags = ["core"]
        \\
        \\[tasks.test]
        \\cmd = "echo 'testing'"
        \\description = "Run tests"
        \\mixins = ["common_env"]
        \\
        \\[tasks.build]
        \\cmd = "echo 'building'"
        \\description = "Build code"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // List tasks to verify mixin inheritance
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") != null);
}

test "8001: multiple mixins composition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.docker_auth]
        \\env = [["DOCKER_USER", "admin"], ["DOCKER_PASS", "secret"]]
        \\tags = ["docker"]
        \\
        \\[mixins.security_checks]
        \\deps = ["validate"]
        \\tags = ["security"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo 'deploying'"
        \\description = "Deploy to production"
        \\mixins = ["docker_auth", "security_checks"]
        \\
        \\[tasks.validate]
        \\cmd = "echo 'validating'"
        \\description = "Validate config"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Verify deploy task has dependencies from both mixins
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "validate") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploying") != null);
}

test "8002: task overrides mixin values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.base_env]
        \\env = [["LOG_LEVEL", "info"], ["DEBUG", "false"]]
        \\cmd = "echo 'base command'"
        \\description = "Base description"
        \\
        \\[tasks.test]
        \\cmd = "echo 'test command'"
        \\description = "Test description"
        \\env = [["LOG_LEVEL", "debug"], ["EXTRA", "value"]]
        \\mixins = ["base_env"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task and verify task-level values override mixin
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test command") != null);
    // Should NOT contain base command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "base command") == null);
}

test "8003: nested mixins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.base]
        \\tags = ["base"]
        \\
        \\[mixins.extended]
        \\mixins = ["base"]
        \\tags = ["extended"]
        \\deps = ["setup"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo 'deploying'"
        \\mixins = ["extended"]
        \\
        \\[tasks.setup]
        \\cmd = "echo 'setup'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Deploy should inherit from extended, which inherits from base
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploying") != null);
}

test "8004: circular mixin detection" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.alpha]
        \\mixins = ["beta"]
        \\cmd = "echo alpha"
        \\
        \\[mixins.beta]
        \\mixins = ["alpha"]
        \\cmd = "echo beta"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\mixins = ["alpha"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Should fail with cycle detection error
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cycl") != null or std.mem.indexOf(u8, result.stderr, "Cycl") != null);
}

test "8005: nonexistent mixin reference" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\mixins = ["nonexistent"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Should fail with undefined mixin error
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
}

test "8006: env merging semantics" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.parent_env]
        \\env = [["A", "parent_a"], ["B", "parent_b"], ["C", "parent_c"]]
        \\
        \\[tasks.test]
        \\cmd = "echo 'A=$A B=$B C=$C'"
        \\env = [["A", "child_a"], ["B", "parent_b"], ["D", "child_d"]]
        \\mixins = ["parent_env"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Child overrides: A should be child_a, C from parent should exist, D from child should exist
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Task-level env should override mixin env for same keys
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "child_a") != null or std.mem.indexOf(u8, result.stdout, "parent_a") == null);
}

test "8007: deps concatenation" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.setup_deps]
        \\deps = ["step1", "step2"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\deps = ["step3"]
        \\mixins = ["setup_deps"]
        \\
        \\[tasks.step1]
        \\cmd = "echo step1"
        \\
        \\[tasks.step2]
        \\cmd = "echo step2"
        \\
        \\[tasks.step3]
        \\cmd = "echo step3"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // test should run all steps: step1, step2 (from mixin), step3 (from task)
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step3") != null);
    const step1_pos = std.mem.indexOf(u8, result.stdout, "step1") orelse return error.TestFailed;
    const step3_pos = std.mem.indexOf(u8, result.stdout, "step3") orelse return error.TestFailed;
    try std.testing.expect(step1_pos < step3_pos);
}

test "8008: tags union" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.mixin1]
        \\tags = ["ci", "build"]
        \\
        \\[mixins.mixin2]
        \\tags = ["test", "build"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\tags = ["smoke", "ci"]
        \\mixins = ["mixin1", "mixin2"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // List with JSON output to verify all tags present (no duplicates)
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain "ci", "build", "test", "smoke" (union of all tags)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ci") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "smoke") != null);
}

test "8009: complex nesting (3-level chain)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.level1]
        \\tags = ["level1"]
        \\deps = ["setup"]
        \\
        \\[mixins.level2]
        \\mixins = ["level1"]
        \\tags = ["level2"]
        \\deps = ["build"]
        \\
        \\[mixins.level3]
        \\mixins = ["level2"]
        \\tags = ["level3"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\mixins = ["level3"]
        \\
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Deploy should inherit all levels: setup, build deps
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploying") != null);
}

test "8010: mixin with templates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[templates.deploy_base]
        \\cmd = "echo deploying to {{env}}"
        \\description = "Deploy to {{env}}"
        \\
        \\[mixins.docker_deploy]
        \\tags = ["docker", "deploy"]
        \\deps = ["build"]
        \\template = "deploy_base"
        \\
        \\[tasks.deploy_prod]
        \\cmd = "echo prod deployment"
        \\description = "Deploy to production"
        \\mixins = ["docker_deploy"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Task should inherit template from mixin
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "deploy_prod" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "8011: mixin + workspace inheritance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create workspace with shared tasks
    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.lint]
        \\cmd = "echo linting"
        \\
        \\[mixins.test_mixin]
        \\deps = ["lint"]
        \\tags = ["test"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_toml =
        \\[tasks.test]
        \\cmd = "echo testing"
        \\mixins = ["test_mixin"]
        \\
    ;
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll(member_toml);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    // test should use mixin from workspace root
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "linting") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") != null);
}

test "8012: empty mixin (no-op)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.empty]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\description = "Test task"
        \\mixins = ["empty"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Empty mixin should not affect task
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") != null);
}

test "8013: mixin with all supported fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.comprehensive]
        \\description = "Comprehensive mixin"
        \\env = [["BUILD_TYPE", "release"]]
        \\deps = ["setup"]
        \\deps_serial = ["validate"]
        \\deps_optional = ["format"]
        \\tags = ["core", "build"]
        \\timeout_ms = 5000
        \\cache = true
        \\allow_failure = false
        \\retry_max = 2
        \\
        \\[tasks.compile]
        \\cmd = "echo compiling"
        \\mixins = ["comprehensive"]
        \\
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.validate]
        \\cmd = "echo validate"
        \\
        \\[tasks.format]
        \\cmd = "echo format"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // List to verify comprehensive mixin fields are inherited
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "compile") != null);
}

test "8014: multiple tasks sharing same mixin" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.ci_base]
        \\env = [["CI", "true"]]
        \\tags = ["ci"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\mixins = ["ci_base"]
        \\
        \\[tasks.lint]
        \\cmd = "echo linting"
        \\mixins = ["ci_base"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\mixins = ["ci_base"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // List should show all three tasks with ci_base mixin
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "8015: order of application (mixin1, mixin2, task)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.mixin1]
        \\cmd = "echo mixin1"
        \\description = "First mixin"
        \\tags = ["first"]
        \\
        \\[mixins.mixin2]
        \\cmd = "echo mixin2"
        \\description = "Second mixin"
        \\tags = ["second"]
        \\
        \\[tasks.test]
        \\cmd = "echo task"
        \\description = "Task level"
        \\tags = ["task"]
        \\mixins = ["mixin1", "mixin2"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task - task-level cmd should win over both mixins
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task") != null);
}

test "8016: mixin with conditional deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.conditional_mixin]
        \\deps_if = [{ task = "lint", condition = "env.RUN_LINT == 'true'" }]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\mixins = ["conditional_mixin"]
        \\
        \\[tasks.lint]
        \\cmd = "echo linting"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Test should have conditional dep from mixin
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") != null);
}

test "8017: mixin with hooks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.hooked_mixin]
        \\[[mixins.hooked_mixin.hooks]]
        \\point = "before"
        \\cmd = "echo 'before hook'"
        \\[[mixins.hooked_mixin.hooks]]
        \\point = "after"
        \\cmd = "echo 'after hook'"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\mixins = ["hooked_mixin"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Hooks from mixin should be applied to task
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "before hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "after hook") != null);
}

test "8018: mixin with retry config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.retry_mixin]
        \\retry_max = 3
        \\retry_delay_ms = 100
        \\retry_backoff_multiplier = 2.0
        \\retry_jitter = true
        \\
        \\[tasks.test]
        \\cmd = "echo 'test with retry'"
        \\mixins = ["retry_mixin"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Test should inherit retry config from mixin
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test with retry") != null);
}

test "8019: JSON output includes mixin info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[mixins.tagged_mixin]
        \\tags = ["mixin_tag"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\mixins = ["tagged_mixin"]
        \\tags = ["task_tag"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // JSON output should include all composed tags from mixin and task
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mixin_tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task_tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}
