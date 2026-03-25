const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const writeTmpConfigPath = helpers.writeTmpConfigPath;

// ── Multi-File Configuration Import Tests ────────────────────────────────
//
// These tests verify the [imports] feature which allows zr.toml to import
// task definitions, workflows, and profiles from other TOML files.
//
// EXPECTED BEHAVIOR (after implementation):
// - [imports.files] section references other TOML files
// - Imported tasks/workflows/profiles merged into main config
// - Main config takes precedence over imported definitions
// - Circular imports detected and reported as error
// - Transitive imports supported (imported file can have imports too)
// - Missing imported files cause error
// - Relative paths resolved relative to importing file's directory
//

test "imports: basic import from one external file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported task file
    const common_toml =
        \\[tasks.common-task]
        \\description = "Common task"
        \\cmd = "echo common"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, common_toml, "common.toml");

    // Create main config that imports common.toml
    const main_toml =
        \\[imports]
        \\files = ["common.toml"]
        \\
        \\[tasks.main-task]
        \\description = "Main task"
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // List tasks - should include both main-task and common-task
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both tasks should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "main-task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "common-task") != null);
}

test "imports: multiple files imported in order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create first imported file
    const tasks1_toml =
        \\[tasks.task1]
        \\description = "Task 1"
        \\cmd = "echo task1"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, tasks1_toml, "tasks1.toml");

    // Create second imported file
    const tasks2_toml =
        \\[tasks.task2]
        \\description = "Task 2"
        \\cmd = "echo task2"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, tasks2_toml, "tasks2.toml");

    // Create main config that imports both files
    const main_toml =
        \\[imports]
        \\files = ["tasks1.toml", "tasks2.toml"]
        \\
        \\[tasks.main]
        \\description = "Main"
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All three tasks should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2") != null);
}

test "imports: main config tasks override imported tasks with same name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported file with 'build' task
    const common_toml =
        \\[tasks.build]
        \\description = "Build from common"
        \\cmd = "echo building-common"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, common_toml, "common.toml");

    // Create main config with same 'build' task (should override)
    const main_toml =
        \\[imports]
        \\files = ["common.toml"]
        \\
        \\[tasks.build]
        \\description = "Build from main"
        \\cmd = "echo building-main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show the main config's version
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Build from main") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building-main") != null);
}

test "imports: circular imports detected and reported as error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create file A that imports file B
    const file_a =
        \\[imports]
        \\files = ["file_b.toml"]
        \\
        \\[tasks.task-a]
        \\cmd = "echo a"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, file_a, "file_a.toml");

    // Create file B that imports file A (creates cycle)
    const file_b =
        \\[imports]
        \\files = ["file_a.toml"]
        \\
        \\[tasks.task-b]
        \\cmd = "echo b"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, file_b, "file_b.toml");

    // Main config imports file A
    const main_toml =
        \\[imports]
        \\files = ["file_a.toml"]
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // Should fail with circular import error
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Error message should mention circular import or cycle
    try std.testing.expect(
        std.mem.indexOf(u8, result.stderr, "circular") != null or
        std.mem.indexOf(u8, result.stderr, "cycle") != null or
        std.mem.indexOf(u8, result.stderr, "import") != null
    );
}

test "imports: missing imported file causes error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create main config that imports non-existent file
    const main_toml =
        \\[imports]
        \\files = ["nonexistent.toml"]
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // Should fail with file not found error
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Error should mention file not found or import
    try std.testing.expect(
        std.mem.indexOf(u8, result.stderr, "not found") != null or
        std.mem.indexOf(u8, result.stderr, "nonexistent") != null or
        std.mem.indexOf(u8, result.stderr, "import") != null
    );
}

test "imports: relative paths resolve correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create subdirectory structure
    try tmp.dir.makePath("tasks");
    try tmp.dir.makeDir("shared");

    // Create common task in shared directory
    const shared_common =
        \\[tasks.shared-common]
        \\cmd = "echo shared"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, shared_common, "shared/common.toml");

    // Create config in tasks directory that imports from shared
    const tasks_config =
        \\[imports]
        \\files = ["../shared/common.toml"]
        \\
        \\[tasks.local-task]
        \\cmd = "echo local"
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "tasks/zr.toml", .data = tasks_config });

    const tmp_path_dup = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path_dup);

    const tasks_config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/tasks/zr.toml",
        .{tmp_path_dup},
    );
    defer allocator.free(tasks_config_path);

    // Should find imported file using relative path
    var result = try runZr(allocator, &.{ "--config", tasks_config_path, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "shared-common") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "local-task") != null);
}

test "imports: transitive imports (imported file can have imports)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create base common tasks
    const base_toml =
        \\[tasks.base-task]
        \\cmd = "echo base"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, base_toml, "base.toml");

    // Create middle layer that imports base
    const middle_toml =
        \\[imports]
        \\files = ["base.toml"]
        \\
        \\[tasks.middle-task]
        \\cmd = "echo middle"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, middle_toml, "middle.toml");

    // Create main config that imports middle
    const main_toml =
        \\[imports]
        \\files = ["middle.toml"]
        \\
        \\[tasks.main-task]
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // Should transitively load all three tasks
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "main-task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "middle-task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "base-task") != null);
}

test "imports: empty imports section works" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create main config with empty imports section
    const main_toml =
        \\[imports]
        \\files = []
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "main") != null);
}

test "imports: config without imports section works as before" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config without imports section at all
    const main_toml =
        \\[tasks.task1]
        \\cmd = "echo task1"
        \\
        \\[tasks.task2]
        \\cmd = "echo task2"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2") != null);
}

test "imports: workflows can be imported" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported file with workflow
    const common_toml =
        \\[tasks.lint]
        \\cmd = "echo linting"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[workflows.ci]
        \\name = "CI Pipeline"
        \\tasks = ["lint", "test"]
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, common_toml, "common.toml");

    // Create main config that imports the workflow
    const main_toml =
        \\[imports]
        \\files = ["common.toml"]
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // List should show the imported workflow
    var result = try runZr(allocator, &.{ "--config", config, "list", "workflows" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ci") != null);
}

test "imports: profiles can be imported" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported file with profile
    const common_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[[profiles]]
        \\name = "dev"
        \\description = "Development profile"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, common_toml, "common.toml");

    // Create main config that imports the profile
    const main_toml =
        \\[imports]
        \\files = ["common.toml"]
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // List should show the imported profile
    var result = try runZr(allocator, &.{ "--config", config, "list", "profiles" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dev") != null);
}

test "imports: main config preserves its own tasks/workflows/profiles" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported file
    const common_toml =
        \\[tasks.common-task]
        \\cmd = "echo common"
        \\
        \\[workflows.common-workflow]
        \\name = "Common"
        \\tasks = ["common-task"]
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, common_toml, "common.toml");

    // Create main config with its own definitions
    const main_toml =
        \\[imports]
        \\files = ["common.toml"]
        \\
        \\[tasks.main-task]
        \\cmd = "echo main"
        \\
        \\[tasks.another-task]
        \\cmd = "echo another"
        \\
        \\[workflows.main-workflow]
        \\name = "Main"
        \\tasks = ["main-task"]
        \\
        \\[[profiles]]
        \\name = "prod"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All main tasks should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "main-task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "another-task") != null);
    // Imported tasks should be present too
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "common-task") != null);
}

test "imports: dependencies work across imported tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported file with setup task
    const setup_toml =
        \\[tasks.setup]
        \\cmd = "echo setting up"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, setup_toml, "setup.toml");

    // Create main config with build task that depends on setup
    const main_toml =
        \\[imports]
        \\files = ["setup.toml"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\deps = ["setup"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // Show build task - should list setup as dependency
    var result = try runZr(allocator, &.{ "--config", config, "show", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
}

test "imports: imported task environment variables accessible" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported file with environment variable
    const common_toml =
        \\[tasks.print-var]
        \\cmd = "echo $MY_VAR"
        \\env = { MY_VAR = "imported-value" }
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, common_toml, "common.toml");

    // Create main config
    const main_toml =
        \\[imports]
        \\files = ["common.toml"]
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    // Show should display the imported task with its env var
    var result = try runZr(allocator, &.{ "--config", config, "show", "print-var" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "imported-value") != null);
}

test "imports: config with both [imports] and direct tasks section" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create imported file
    const utils_toml =
        \\[tasks.lint]
        \\cmd = "echo linting"
        \\
        \\[tasks.format]
        \\cmd = "echo formatting"
        \\
    ;
    _ = try writeTmpConfigPath(allocator, tmp.dir, utils_toml, "utils.toml");

    // Create main config with both imports and direct task definitions
    const main_toml =
        \\[imports]
        \\files = ["utils.toml"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, main_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All tasks should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "format") != null);
}
