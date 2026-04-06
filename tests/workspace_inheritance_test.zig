const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfigPath = helpers.writeTmpConfigPath;
const writeTmpConfig = helpers.writeTmpConfig;

// Test 6000-6014: Workspace-Level Task Inheritance (v1.63.0)

test "6000: basic shared task inheritance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create workspace root with shared tasks
    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.lint]
        \\cmd = "echo 'linting...'"
        \\description = "Lint code"
        \\
        \\[workspace.shared_tasks.test]
        \\cmd = "echo 'testing...'"
        \\description = "Run tests"
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    // Create member directory with zr.toml (empty)
    try tmp.dir.makeDir("member");
    const member_toml = "[tasks.build]\ncmd = \"echo build\"\n";
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll(member_toml);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // List tasks in member should show both inherited and local tasks
    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "(inherited)") != null);
}

test "6001: member overrides workspace task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Workspace root with shared task
    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.test]
        \\cmd = "echo 'workspace test'"
        \\description = "Workspace test"
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    // Member overrides the test task
    try tmp.dir.makeDir("member");
    const member_toml =
        \\[tasks.test]
        \\cmd = "echo 'member test override'"
        \\description = "Member test"
        \\
    ;
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll(member_toml);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    // Should NOT show (inherited) marker since member overrides
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "(inherited)") == null);
}

test "6002: shared task with dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.build]
        \\cmd = "echo build"
        \\
        \\[workspace.shared_tasks.test]
        \\cmd = "echo test"
        \\deps = ["build"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    // Run test task (should run build first due to dependency)
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const build_pos = std.mem.indexOf(u8, result.stdout, "build") orelse return error.TestFailed;
    const test_pos = std.mem.indexOf(u8, result.stdout, "test") orelse return error.TestFailed;
    // build should run before test
    try std.testing.expect(build_pos < test_pos);
}

test "6003: shared task with serial dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[workspace.shared_tasks.deploy]
        \\cmd = "echo deploy"
        \\deps_serial = ["setup"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "deploy" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

test "6004: shared task with optional dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.lint]
        \\cmd = "echo lint"
        \\deps_optional = ["format"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    // lint should run even though optional dep 'format' doesn't exist
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "lint" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
}

test "6005: shared task with environment variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.env-test]
        \\cmd = "echo $TEST_VAR"
        \\env = [["TEST_VAR", "workspace-value"]]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "env-test" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "workspace-value") != null);
}

test "6006: shared task with timeout" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.timeout-test]
        \\cmd = "sleep 10"
        \\timeout_ms = 100
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "timeout-test" }, member_path);
    defer result.deinit();

    // Should timeout and fail
    try std.testing.expect(result.exit_code != 0);
}

test "6007: shared task with allow_failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.fail-ok]
        \\cmd = "exit 1"
        \\allow_failure = true
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "fail-ok" }, member_path);
    defer result.deinit();

    // Should succeed despite task failure
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "6008: multiple members inherit same shared tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[workspace.shared_tasks.lint]
        \\cmd = "echo lint"
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("pkg1");
    const pkg1_file = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_file.close();
    try pkg1_file.writeAll("");

    try tmp.dir.makeDir("pkg2");
    const pkg2_file = try tmp.dir.createFile("pkg2/zr.toml", .{});
    defer pkg2_file.close();
    try pkg2_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Check pkg1
    const pkg1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "pkg1" });
    defer allocator.free(pkg1_path);
    var result1 = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, pkg1_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result1.stdout, "lint") != null);

    // Check pkg2
    const pkg2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "pkg2" });
    defer allocator.free(pkg2_path);
    var result2 = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, pkg2_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result2.stdout, "lint") != null);
}

test "6009: mixed inherited and local tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.lint]
        \\cmd = "echo workspace lint"
        \\
        \\[workspace.shared_tasks.test]
        \\cmd = "echo workspace test"
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_toml =
        \\[tasks.build]
        \\cmd = "echo member build"
        \\
        \\[tasks.deploy]
        \\cmd = "echo member deploy"
        \\
    ;
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll(member_toml);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show all 4 tasks (2 inherited, 2 local)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

test "6010: shared task cross-dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[workspace.shared_tasks.build]
        \\cmd = "echo build"
        \\deps = ["setup"]
        \\
        \\[workspace.shared_tasks.test]
        \\cmd = "echo test"
        \\deps = ["build"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All three tasks should run in correct order
    const setup_pos = std.mem.indexOf(u8, result.stdout, "setup") orelse return error.TestFailed;
    const build_pos = std.mem.indexOf(u8, result.stdout, "build") orelse return error.TestFailed;
    const test_pos = std.mem.indexOf(u8, result.stdout, "test") orelse return error.TestFailed;
    try std.testing.expect(setup_pos < build_pos);
    try std.testing.expect(build_pos < test_pos);
}

test "6011: empty workspace shared_tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_toml = "[tasks.build]\ncmd = \"echo build\"\n";
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll(member_toml);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    // No (inherited) marker since no shared tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "(inherited)") == null);
}

test "6012: inherited task can depend on local task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.test]
        \\cmd = "echo test"
        \\deps = ["build"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_toml =
        \\[tasks.build]
        \\cmd = "echo member build"
        \\
    ;
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll(member_toml);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "member build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "6013: validation - nonexistent shared task dependency" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.test]
        \\cmd = "echo test"
        \\deps = ["nonexistent"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "test" }, member_path);
    defer result.deinit();

    // Should fail with dependency error
    try std.testing.expect(result.exit_code != 0);
}

test "6014: list shows inherited marker for tag-grouped view" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["member"]
        \\
        \\[workspace.shared_tasks.lint]
        \\cmd = "echo lint"
        \\tags = ["quality"]
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(root_config);

    try tmp.dir.makeDir("member");
    const member_file = try tmp.dir.createFile("member/zr.toml", .{});
    defer member_file.close();
    try member_file.writeAll("");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const member_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "member" });
    defer allocator.free(member_path);

    var result = try runZr(allocator, &.{ "--config", "zr.toml", "list", "--tags" }, member_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "(inherited)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "quality") != null);
}
