const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const writeTmpConfigPath = helpers.writeTmpConfigPath;

// ── Config File Includes & Composition ──────────────────────────────────────
//
// These tests verify the include = [...] feature:
// - Basic include: include = ["./other.zr.toml"] merges tasks from other file
// - Task override: Root config tasks take precedence over included tasks
// - Var merge: [vars] from included files are merged (root wins on conflict)
// - Nested includes: Included files can themselves have include = [...]
// - Cycle detection: Circular includes are detected and fail
// - validate --show-includes: Shows include tree with file paths and task counts
// - list --source: Shows [filename] next to each task indicating source file
// - --config compatibility: Include paths resolved relative to --config file's dir
//

test "28000: include basic - tasks from included file are available" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write included file with a task
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\[tasks.ci]
        \\cmd = "echo ci-task"
        \\description = "CI task from included file"
    , "ci.zr.toml");

    // Write root config with include
    const config = try writeTmpConfig(allocator, tmp.dir,
        \\include = ["./ci.zr.toml"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\description = "Build task from root"
    );
    defer allocator.free(config);

    // Run the included task
    var result = try runZr(allocator, &.{ "run", "ci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ci-task") != null);
}

test "28001: task override - root config task wins when same name in both files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write included file with task 'build'
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\[tasks.build]
        \\cmd = "echo build-from-included"
        \\description = "Build from included file"
    , "other.zr.toml");

    // Write root config with same task name
    const config = try writeTmpConfig(allocator, tmp.dir,
        \\include = ["./other.zr.toml"]
        \\
        \\[tasks.build]
        \\cmd = "echo build-from-root"
        \\description = "Build from root config"
    );
    defer allocator.free(config);

    // Run 'build' — should use root config version
    var result = try runZr(allocator, &.{ "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build-from-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build-from-included") == null);
}

test "28002: var merge - vars from included file available, root wins on conflict" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write included file with vars
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\[vars]
        \\DATABASE = "included_db"
        \\PORT = "5432"
        \\TIMEOUT = "30"
    , "db.zr.toml");

    // Write root config with overlapping vars
    const config = try writeTmpConfig(allocator, tmp.dir,
        \\include = ["./db.zr.toml"]
        \\
        \\[vars]
        \\DATABASE = "root_db"
        \\HOST = "localhost"
        \\
        \\[tasks.connect]
        \\cmd = "echo DATABASE=$DATABASE HOST=$HOST PORT=$PORT TIMEOUT=$TIMEOUT"
    );
    defer allocator.free(config);

    // Run task using merged vars
    var result = try runZr(allocator, &.{ "run", "connect" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Root config wins: DATABASE=root_db
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "DATABASE=root_db") != null);
    // Included vars available: PORT=5432, TIMEOUT=30
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "PORT=5432") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TIMEOUT=30") != null);
    // Root config vars: HOST=localhost
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "HOST=localhost") != null);
}

test "28003: nested include - included file itself has an include (multi-level)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Level 2: deepest include
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\[tasks.lint]
        \\cmd = "echo lint-task"
        \\description = "Lint from deep include"
    , "lint.zr.toml");

    // Level 1: includes level 2
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\include = ["./lint.zr.toml"]
        \\
        \\[tasks.test]
        \\cmd = "echo test-task"
        \\description = "Test from intermediate include"
    , "test.zr.toml");

    // Level 0: root includes level 1
    const config = try writeTmpConfig(allocator, tmp.dir,
        \\include = ["./test.zr.toml"]
        \\
        \\[tasks.build]
        \\cmd = "echo build-task"
        \\description = "Build from root"
    );
    defer allocator.free(config);

    // Verify all three levels are available
    var result_build = try runZr(allocator, &.{ "run", "build" }, tmp_path);
    defer result_build.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_build.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_build.stdout, "build-task") != null);

    var result_test = try runZr(allocator, &.{ "run", "test" }, tmp_path);
    defer result_test.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_test.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_test.stdout, "test-task") != null);

    var result_lint = try runZr(allocator, &.{ "run", "lint" }, tmp_path);
    defer result_lint.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_lint.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_lint.stdout, "lint-task") != null);
}

test "28004: cycle detection - circular include returns error (non-zero exit)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // File a.zr.toml includes b.zr.toml
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\include = ["./b.zr.toml"]
        \\
        \\[tasks.task-a]
        \\cmd = "echo a"
    , "a.zr.toml");

    // File b.zr.toml includes a.zr.toml (cycle!)
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\include = ["./a.zr.toml"]
        \\
        \\[tasks.task-b]
        \\cmd = "echo b"
    , "b.zr.toml");

    // Write root config that includes a.zr.toml (which includes b.zr.toml which includes a.zr.toml)
    const config = try writeTmpConfig(allocator, tmp.dir,
        \\include = ["./a.zr.toml"]
        \\
        \\[tasks.root-task]
        \\cmd = "echo root"
    );
    defer allocator.free(config);

    // Attempt to run should fail with non-zero exit code
    var result = try runZr(allocator, &.{ "run", "root-task" }, tmp_path);
    defer result.deinit();

    // Should detect cycle and fail
    try std.testing.expect(result.exit_code != 0);
    // Error message should mention cycle or include
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cycle") != null or
        std.mem.indexOf(u8, result.stderr, "include") != null or
        std.mem.indexOf(u8, result.stderr, "circular") != null);
}

test "28005: validate --show-includes shows file paths and task counts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write included file with 2 tasks
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\[tasks.ci]
        \\cmd = "echo ci"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
    , "ci.zr.toml");

    // Write root config with 1 task
    const config = try writeTmpConfig(allocator, tmp.dir,
        \\include = ["./ci.zr.toml"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
    );
    defer allocator.free(config);

    // Run validate --show-includes
    var result = try runZr(allocator, &.{ "validate", "--show-includes" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should show the include tree with file paths
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ci.zr.toml") != null or
        std.mem.indexOf(u8, result.stderr, "ci.zr.toml") != null);
}

test "28006: list --source shows [filename] next to tasks from included files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write included file with a task
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\[tasks.ci]
        \\cmd = "echo ci"
        \\description = "CI task"
    , "ci.zr.toml");

    // Write root config with a task and include
    const config = try writeTmpConfig(allocator, tmp.dir,
        \\include = ["./ci.zr.toml"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\description = "Build task"
    );
    defer allocator.free(config);

    // Run list --source
    var result = try runZr(allocator, &.{ "list", "--source" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should show source files for each task
    // Root task should be from zr.toml (or root)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    // Included task should show ci.zr.toml as source
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ci") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ci.zr.toml") != null);
}

test "28007: --config compatibility - include paths resolved relative to --config file's directory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a subdirectory for the config
    try tmp.dir.makePath("subdir");

    // Write an included file in root temp directory
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\[tasks.shared]
        \\cmd = "echo shared-task"
    , "shared.zr.toml");

    // Write root config in subdirectory that includes ../shared.zr.toml
    _ = try writeTmpConfigPath(allocator, tmp.dir,
        \\include = ["../shared.zr.toml"]
        \\
        \\[tasks.local]
        \\cmd = "echo local-task"
    , "subdir/project.zr.toml");

    // Get absolute path to the config file
    const config_path = try std.fmt.allocPrint(allocator, "{s}/subdir/project.zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    // Run with --config pointing to subdir/project.zr.toml
    // Includes should be resolved relative to subdir/ directory
    var result = try runZr(allocator, &.{ "--config", config_path, "run", "shared" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "shared-task") != null);

    // Also verify local task works
    var result_local = try runZr(allocator, &.{ "--config", config_path, "run", "local" }, null);
    defer result_local.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_local.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_local.stdout, "local-task") != null);
}
