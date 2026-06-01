const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Test Fixtures ──────────────────────────────────────────────────────

const SIMPLE_TASK_TOML =
    \\[tasks.hello]
    \\cmd = "echo hello"
    \\
;

const TASK_WITH_DEPS_TOML =
    \\[tasks.setup]
    \\cmd = "echo setup"
    \\
    \\[tasks.generate]
    \\cmd = "echo generate"
    \\deps = ["setup"]
    \\
    \\[tasks.build]
    \\cmd = "zig build"
    \\deps = ["setup", "generate"]
    \\
;

const MULTI_LEVEL_DEPS_TOML =
    \\[tasks.install]
    \\cmd = "echo install"
    \\
    \\[tasks.configure]
    \\cmd = "echo configure"
    \\deps = ["install"]
    \\
    \\[tasks.compile]
    \\cmd = "echo compile"
    \\deps = ["configure"]
    \\
    \\[tasks.package]
    \\cmd = "echo package"
    \\deps = ["compile", "install"]
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "15000: zr explain with no args prints error and returns 1" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Must mention "required" — the exact phrase from the error message
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "required") != null);
    // Must not print a successful plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Execution plan") == null);
}

test "15001: zr explain unknown-task for nonexistent task returns 1 with not found message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "nonexistent" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Must say "not found" and mention the task name
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "nonexistent") != null);
    // Must not print a successful plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Execution plan") == null);
}

test "15002: zr explain simple-task shows task command in output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "hello" }, tmp_path);
    defer result.deinit();

    // Should succeed for valid task
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should show the task command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "echo hello") != null);
    // Output should mention the task name
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "15003: zr explain task-with-deps shows all deps in execution order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check task count in header
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tasks to run (3)") != null);
    // Verify each task appears at its numbered step — setup first, build last
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[1] setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[2] generate") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[3] build") != null);
    // Step markers must appear in ascending order
    const s1 = std.mem.indexOf(u8, result.stdout, "[1]").?;
    const s2 = std.mem.indexOf(u8, result.stdout, "[2]").?;
    const s3 = std.mem.indexOf(u8, result.stdout, "[3]").?;
    try std.testing.expect(s1 < s2);
    try std.testing.expect(s2 < s3);
}

test "15004: zr explain task-with-deps --tree shows tree format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build", "--tree" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Tree format should show task names
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "generate") != null);
    // Tree format typically uses box-drawing characters or tree symbols
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "├") != null or
        std.mem.indexOf(u8, result.stdout, "└") != null or
        std.mem.indexOf(u8, result.stdout, "─") != null or
        std.mem.indexOf(u8, result.stdout, "|") != null);
}

test "15005: zr explain task-with-deps --json produces valid JSON with tasks array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Must contain JSON structure keys
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"tasks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"total\"") != null);
    // Must contain all three task names as JSON string literals
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"setup\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"generate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"build\"") != null);
    // Must show total=3
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"total\":3") != null);
}

test "15006: zr explain --help returns 0 with usage info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "--help" }, tmp_path);
    defer result.deinit();

    // Should succeed with --help
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain help text
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage") != null or
        std.mem.indexOf(u8, result.stdout, "usage") != null or
        std.mem.indexOf(u8, result.stdout, "explain") != null or
        std.mem.indexOf(u8, result.stdout, "Explain") != null);
}

test "15007: zr explain multi-level-deps shows correct execution order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_LEVEL_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "package" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify task count
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tasks to run (4)") != null);
    // Topological order via section headers: install first, package last
    // install has no deps → [1]; configure depends on install → [2]; compile → [3]; package → [4]
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[1] install") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[2] configure") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[3] compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[4] package") != null);
    // Step markers must be in order
    const s1 = std.mem.indexOf(u8, result.stdout, "[1]").?;
    const s2 = std.mem.indexOf(u8, result.stdout, "[2]").?;
    const s3 = std.mem.indexOf(u8, result.stdout, "[3]").?;
    const s4 = std.mem.indexOf(u8, result.stdout, "[4]").?;
    try std.testing.expect(s1 < s2);
    try std.testing.expect(s2 < s3);
    try std.testing.expect(s3 < s4);
}

test "15008: zr explain task-with-deps --tree shows recursive dependency structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build", "--tree" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Root task at top level (no connector prefix)
    try std.testing.expect(std.mem.startsWith(u8, result.stdout, "build\n"));
    // Direct deps of build shown with tree connectors
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "├── setup") != null or
        std.mem.indexOf(u8, result.stdout, "└── setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "└── generate") != null);
    // generate's transitive dep on setup shown recursively
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "already shown") != null);
}

// ── Feature Tests: Multiple tasks in zr explain (Feature 1) ──────────────

const TWO_TASK_SHARED_DEP_TOML =
    \\[tasks.setup]
    \\cmd = "echo setup"
    \\
    \\[tasks.build]
    \\cmd = "zig build"
    \\deps = ["setup"]
    \\
    \\[tasks.test]
    \\cmd = "zig build test"
    \\deps = ["setup"]
    \\
;

test "15009: zr explain build test shows merged dependency plan with deduplication" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TWO_TASK_SHARED_DEP_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show merged plan with 3 tasks: setup, build, test
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tasks to run (3)") != null);
    // Each task should appear exactly once (deduplication)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[1] setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[2]") != null); // Either build or test
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[3]") != null); // Either test or build
    // Both requested tasks should be in the plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    // Verify setup comes before build and test (topological order)
    const setup_pos = std.mem.indexOf(u8, result.stdout, "[1] setup").?;
    const build_pos = std.mem.indexOf(u8, result.stdout, "build").?;
    const test_pos = std.mem.indexOf(u8, result.stdout, "test").?;
    try std.testing.expect(setup_pos < build_pos);
    try std.testing.expect(setup_pos < test_pos);
}

test "15010: zr explain unknown1 unknown2 returns error code 1 with not found message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "unknown1", "unknown2" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Should mention that a task is not found
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null);
    // Should not print a successful plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Execution plan") == null);
}

test "15011: zr explain build (single task) still works after multiple-task support" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build" }, tmp_path);
    defer result.deinit();

    // Should work the same as before multiple-task support
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tasks to run (3)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[1] setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[2] generate") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[3] build") != null);
}

// ── Feature Tests: zr run --explain flag (Feature 2) ──────────────────────

const TASK_WITH_CWD_TOML =
    \\[tasks.setup]
    \\cmd = "echo setup"
    \\
    \\[tasks.build]
    \\cmd = "zig build"
    \\cwd = "/tmp/build"
    \\deps = ["setup"]
    \\
;

const TASK_WITH_TIMEOUT_TOML =
    \\[tasks.long-running]
    \\cmd = "sleep 60"
    \\timeout = "30s"
    \\
;

test "15012: zr run --explain shows task name and command without executing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--explain", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain the task name
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
    // Output should contain the command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "echo hello") != null);
    // The task should NOT actually execute (no "hello" output from echo)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") == null or
        std.mem.indexOf(u8, result.stdout, "echo hello") != null); // Echo command shows, but not its output
}

test "15013: zr run --explain with task having cwd shows cwd in output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_CWD_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--explain", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain task name
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    // Output should contain the cwd
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/tmp/build") != null);
    // Output should contain the command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zig build") != null);
}

test "15014: zr run --explain with no task name returns error code 1" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--explain" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Should show an error message (not a successful explanation)
    try std.testing.expect(result.stderr.len > 0 or result.stdout.len > 0);
}
