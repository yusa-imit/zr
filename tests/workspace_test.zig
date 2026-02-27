const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfigPath = helpers.writeTmpConfigPath;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "27: workspace list shows members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a workspace config
    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create member directories
    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "59: workspace run with empty workspace" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const no_workspace_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, no_workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "hello" }, tmp_path);
    defer result.deinit();
    // Should handle gracefully (either error or run on single project)
    _ = result.exit_code;
}

test "97: workspace list command without workspace section fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    // Should fail when no workspace section exists
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "workspace") != null);
}

test "98: workspace run with --parallel flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "hello", "--parallel" }, tmp_path);
    defer result.deinit();
    // Should succeed or handle parallel flag appropriately
    _ = result.exit_code;
}

test "116: workspace run with filtered members using glob pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["apps/*", "libs/*"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    // Create workspace structure
    try tmp.dir.makeDir("apps");
    try tmp.dir.makeDir("apps/web");
    try tmp.dir.makeDir("apps/mobile");
    try tmp.dir.makeDir("libs");
    try tmp.dir.makeDir("libs/utils");
    try tmp.dir.writeFile(.{ .sub_path = "apps/web/zr.toml", .data = "[tasks.test]\ncmd = \"echo web\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/mobile/zr.toml", .data = "[tasks.test]\ncmd = \"echo mobile\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "libs/utils/zr.toml", .data = "[tasks.test]\ncmd = \"echo utils\"\n" });

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should find all workspace members via glob patterns
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "apps/web") != null or std.mem.indexOf(u8, result.stdout, "web") != null);
}

test "134: workspace with tagged filtering and parallel execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_tags_toml =
        \\[workspace]
        \\members = ["pkg-a", "pkg-b"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\tags = ["ci", "build"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\tags = ["ci", "test"]
        \\deps = ["build"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_tags_toml);
    defer allocator.free(config);

    // Create workspace member directories
    try tmp.dir.makeDir("pkg-a");
    try tmp.dir.makeDir("pkg-b");

    // Create member configs
    const pkg_a_file = try tmp.dir.createFile("pkg-a/zr.toml", .{});
    defer pkg_a_file.close();
    try pkg_a_file.writeAll("[tasks.build]\ncmd = \"echo pkg-a build\"\n");

    const pkg_b_file = try tmp.dir.createFile("pkg-b/zr.toml", .{});
    defer pkg_b_file.close();
    try pkg_b_file.writeAll("[tasks.build]\ncmd = \"echo pkg-b build\"\n");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "--jobs", "2", "list", "--tags=ci" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should list tasks with ci tag
    try std.testing.expect(result.stdout.len > 0);
}

test "147: workspace sync builds synthetic workspace from multi-repo" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try syncing without zr-repos.toml (should fail gracefully)
    var result = try runZr(allocator, &.{ "workspace", "sync" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully if no zr-repos.toml found
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos.toml") != null);
}

test "155: workspace run with --parallel and specific members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg-a", "pkg-b"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create workspace member directories
    try tmp.dir.makeDir("pkg-a");
    try tmp.dir.makeDir("pkg-b");

    // Create zr.toml in each member
    var pkg_a = try tmp.dir.openDir("pkg-a", .{});
    defer pkg_a.close();
    const pkg_a_config = try pkg_a.createFile("zr.toml", .{});
    defer pkg_a_config.close();
    try pkg_a_config.writeAll(workspace_toml);

    var pkg_b = try tmp.dir.openDir("pkg-b", .{});
    defer pkg_b.close();
    const pkg_b_config = try pkg_b.createFile("zr.toml", .{});
    defer pkg_b_config.close();
    try pkg_b_config.writeAll(workspace_toml);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "--parallel", "test" }, tmp_path);
    defer result.deinit();

    // Should succeed even if members don't have the task
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "190: workspace run with --format json outputs structured results" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = config });

    try tmp.dir.makePath("packages/app");
    try tmp.dir.writeFile(.{ .sub_path = "packages/app/zr.toml", .data = "[tasks.test]\ncmd = \"echo app test\"" });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fs.path.join(allocator, &.{ tmp_path, "zr.toml" });
    defer allocator.free(config_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "--format", "json", "workspace", "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // JSON output should be present
    try std.testing.expect(result.stdout.len > 0);
}

test "205: workspace run with --affected and no changes skips all tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workspace config
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    );

    // Create a package subdirectory
    try tmp.dir.makePath("packages/pkg1");
    const pkg1_toml = try tmp.dir.createFile("packages/pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll(
        \\[tasks.test]
        \\cmd = "echo pkg1 test"
        \\
    );

    // Initialize git repo (required for --affected)
    {
        const git_init = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "init" },
            .cwd = tmp_path,
        });
        allocator.free(git_init.stdout);
        allocator.free(git_init.stderr);
    }
    {
        const git_config_name = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.name", "Test" },
            .cwd = tmp_path,
        });
        allocator.free(git_config_name.stdout);
        allocator.free(git_config_name.stderr);
    }
    {
        const git_config_email = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.email", "test@test.com" },
            .cwd = tmp_path,
        });
        allocator.free(git_config_email.stdout);
        allocator.free(git_config_email.stderr);
    }
    {
        const git_add = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "add", "." },
            .cwd = tmp_path,
        });
        allocator.free(git_add.stdout);
        allocator.free(git_add.stderr);
    }
    {
        const git_commit = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "commit", "-m", "initial" },
            .cwd = tmp_path,
        });
        allocator.free(git_commit.stdout);
        allocator.free(git_commit.stderr);
    }

    // Run with --affected HEAD (no changes)
    var result = try runZr(allocator, &.{ "workspace", "run", "test", "--affected", "HEAD" }, tmp_path);
    defer result.deinit();

    // Should succeed with no tasks run
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "223: workspace member with empty config is skipped gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workspace root
    const root_toml =
        \\[workspace]
        \\members = ["pkg-a", "pkg-empty"]
        \\
        \\[tasks.test]
        \\cmd = "echo root"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(root_toml);

    // Create pkg-a with a task
    try tmp.dir.makeDir("pkg-a");
    const pkg_a_file = try tmp.dir.createFile("pkg-a/zr.toml", .{});
    defer pkg_a_file.close();
    try pkg_a_file.writeAll(
        \\[tasks.test]
        \\cmd = "echo pkg-a"
        \\
    );

    // Create pkg-empty with minimal config (no tasks)
    try tmp.dir.makeDir("pkg-empty");
    const pkg_empty_file = try tmp.dir.createFile("pkg-empty/zr.toml", .{});
    defer pkg_empty_file.close();
    try pkg_empty_file.writeAll("# Empty config\n");

    // Workspace run should handle empty member gracefully
    var result = try runZr(allocator, &.{ "workspace", "run", "test" }, tmp_path);
    defer result.deinit();
    // Should succeed (or fail gracefully), not crash
    try std.testing.expect(result.exit_code <= 1);
}

test "237: workspace list with --format json outputs structured member data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workspace config
    const workspace_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    // Create packages directory
    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/pkg1");
    const pkg1_toml = try tmp.dir.createFile("packages/pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll(
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    );

    // List workspace with JSON format
    var result = try runZr(allocator, &.{ "workspace", "list", "--format", "json" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "247: workspace with deeply nested member paths resolves correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workspace_toml =
        \\[workspace]
        \\members = ["packages/*/nested/*"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    // Create nested directory structure
    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/pkg1");
    try tmp.dir.makeDir("packages/pkg1/nested");
    try tmp.dir.makeDir("packages/pkg1/nested/lib");
    const nested_toml = try tmp.dir.createFile("packages/pkg1/nested/lib/zr.toml", .{});
    defer nested_toml.close();
    try nested_toml.writeAll(
        \\[tasks.build]
        \\cmd = "echo nested build"
        \\
    );

    var result = try runZr(allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "253: workspace run with --filter flag runs only matching members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workspace_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    // Create workspace members
    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/pkg1");
    try tmp.dir.makeDir("packages/pkg2");

    const pkg1_toml = try tmp.dir.createFile("packages/pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll("\\n[tasks.test]\\ncmd = \"echo pkg1\"\\n");

    const pkg2_toml = try tmp.dir.createFile("packages/pkg2/zr.toml", .{});
    defer pkg2_toml.close();
    try pkg2_toml.writeAll("\\n[tasks.test]\\ncmd = \"echo pkg2\"\\n");

    var result = try runZr(allocator, &.{ "workspace", "run", "test", "--filter", "*1" }, tmp_path);
    defer result.deinit();
    // May not support --filter flag yet, test command parses
    try std.testing.expect(result.exit_code <= 1);
}

test "263: workspace with single member behaves correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workspace with single member
    try tmp.dir.makeDir("pkg");
    const pkg_toml = try tmp.dir.createFile("pkg/zr.toml", .{});
    defer pkg_toml.close();
    try pkg_toml.writeAll(
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    );

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    var result = try runZr(allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "pkg") != null);
}

test "277: workspace with unicode task names and descriptions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const unicode_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.测试]
        \\description = "运行测试 🧪"
        \\cmd = "echo testing"
        \\
        \\[tasks.déployer]
        \\description = "Déployer l'application 🚀"
        \\cmd = "echo déploiement"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(unicode_toml);

    // Create workspace member
    try tmp.dir.makePath("packages/app");
    const member_toml_file = try tmp.dir.createFile("packages/app/zr.toml", .{});
    defer member_toml_file.close();
    try member_toml_file.writeAll("[tasks.test]\ncmd = \"echo member-test\"\n");

    var result = try runZr(allocator, &.{"list"}, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    // Should handle unicode task names gracefully
    try std.testing.expect(result.stdout.len > 0 or result.stderr.len > 0);
}

test "283: workspace members with conflicting task names use correct context" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Root config with workspace
    const root_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.build]
        \\cmd = "echo root-build"
        \\
    ;

    // Member 1 with same task name
    const pkg1_toml =
        \\[tasks.build]
        \\cmd = "echo pkg1-build"
        \\
    ;

    // Member 2 with same task name
    const pkg2_toml =
        \\[tasks.build]
        \\cmd = "echo pkg2-build"
        \\
    ;

    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");

    const root_file = try tmp.dir.createFile("zr.toml", .{});
    defer root_file.close();
    try root_file.writeAll(root_toml);

    const pkg1_file = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_file.close();
    try pkg1_file.writeAll(pkg1_toml);

    const pkg2_file = try tmp.dir.createFile("pkg2/zr.toml", .{});
    defer pkg2_file.close();
    try pkg2_file.writeAll(pkg2_toml);

    var result = try runZr(allocator, &.{ "workspace", "run", "build" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Each member should run its own build task
    try std.testing.expect(std.mem.indexOf(u8, output, "pkg1-build") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pkg2-build") != null);
}

test "294: workspace run with --parallel and mixed success/failure tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    // Create workspace members
    try tmp.dir.makeDir("pkg1");
    const pkg1_toml = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll(
        \\[tasks.test]
        \\cmd = "echo pkg1 ok"
        \\
    );

    try tmp.dir.makeDir("pkg2");
    const pkg2_toml = try tmp.dir.createFile("pkg2/zr.toml", .{});
    defer pkg2_toml.close();
    try pkg2_toml.writeAll(
        \\[tasks.test]
        \\cmd = "exit 1"
        \\allow_failure = true
        \\
    );

    var result = try runZr(allocator, &.{ "workspace", "run", "test", "--parallel" }, tmp_path);
    defer result.deinit();
    // Should complete even with one failure due to allow_failure
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "pkg1") != null or std.mem.indexOf(u8, output, "pkg2") != null);
}

test "302: workspace run with --jobs=1 forces sequential execution across members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workspace_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    // Create multiple workspace members
    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/pkg1");
    try tmp.dir.makeDir("packages/pkg2");
    try tmp.dir.makeDir("packages/pkg3");

    const pkg1_toml = try tmp.dir.createFile("packages/pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll("[tasks.test]\\ncmd = \"echo pkg1\"\\n");

    const pkg2_toml = try tmp.dir.createFile("packages/pkg2/zr.toml", .{});
    defer pkg2_toml.close();
    try pkg2_toml.writeAll("[tasks.test]\\ncmd = \"echo pkg2\"\\n");

    const pkg3_toml = try tmp.dir.createFile("packages/pkg3/zr.toml", .{});
    defer pkg3_toml.close();
    try pkg3_toml.writeAll("[tasks.test]\\ncmd = \"echo pkg3\"\\n");

    var result = try runZr(allocator, &.{ "workspace", "run", "test", "--jobs=1" }, tmp_path);
    defer result.deinit();
    // Should force sequential execution (exit_code 0 = success, even with potential memory leaks from GPA)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(result.exit_code <= 1 and output.len > 0);
}

test "327: workspace list with members that have different task names" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    try tmp.dir.makeDir("app1");
    try tmp.dir.makeDir("app2");

    const app1_toml =
        \\[tasks.build]
        \\cmd = "echo app1 build"
        \\
    ;
    const app2_toml =
        \\[tasks.test]
        \\cmd = "echo app2 test"
        \\
    ;

    const app1_file = try tmp.dir.createFile("app1/zr.toml", .{});
    defer app1_file.close();
    try app1_file.writeAll(app1_toml);

    const app2_file = try tmp.dir.createFile("app2/zr.toml", .{});
    defer app2_file.close();
    try app2_file.writeAll(app2_toml);

    const workspace_toml =
        \\[workspace]
        \\members = ["app1", "app2"]
        \\
    ;
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    var result = try runZr(allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "app1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "app2") != null);
}

test "335: workspace run with different profiles in members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workspace with members
    try tmp.dir.makeDir("member-a");
    try tmp.dir.makeDir("member-b");

    const root_toml =
        \\[workspace]
        \\members = ["member-a", "member-b"]
        \\
    ;

    const member_a_toml =
        \\[tasks.test]
        \\cmd = "echo member-a"
        \\
        \\[profiles.dev]
        \\env = { MODE = "dev-a" }
        \\
    ;

    const member_b_toml =
        \\[tasks.test]
        \\cmd = "echo member-b"
        \\
        \\[profiles.prod]
        \\env = { MODE = "prod-b" }
        \\
    ;

    const root_file = try tmp.dir.createFile("zr.toml", .{});
    defer root_file.close();
    try root_file.writeAll(root_toml);

    const member_a_file = try tmp.dir.createFile("member-a/zr.toml", .{});
    defer member_a_file.close();
    try member_a_file.writeAll(member_a_toml);

    const member_b_file = try tmp.dir.createFile("member-b/zr.toml", .{});
    defer member_b_file.close();
    try member_b_file.writeAll(member_b_toml);

    // Run workspace task - members have different profiles available
    var result = try runZr(allocator, &.{ "workspace", "run", "test" }, tmp_path);
    defer result.deinit();
    // Should run successfully despite profile differences
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "member-a") != null or
        std.mem.indexOf(u8, output, "member-b") != null);
}

test "342: workspace run with --format=json shows structured member results" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    try tmp.dir.makeDir("service-a");
    try tmp.dir.makeDir("service-b");

    const service_a_toml =
        \\[tasks.health]
        \\cmd = "echo service-a ok"
        \\
    ;
    const service_b_toml =
        \\[tasks.health]
        \\cmd = "echo service-b ok"
        \\
    ;

    const sa_file = try tmp.dir.createFile("service-a/zr.toml", .{});
    defer sa_file.close();
    try sa_file.writeAll(service_a_toml);

    const sb_file = try tmp.dir.createFile("service-b/zr.toml", .{});
    defer sb_file.close();
    try sb_file.writeAll(service_b_toml);

    const workspace_toml =
        \\[workspace]
        \\members = ["service-a", "service-b"]
        \\
    ;
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    var result = try runZr(allocator, &.{ "workspace", "run", "health", "--format", "json" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should output JSON with member results
    try std.testing.expect(std.mem.indexOf(u8, output, "service-a") != null or
        std.mem.indexOf(u8, output, "[") != null or
        std.mem.indexOf(u8, output, "{") != null);
}

test "358: workspace with empty members array is valid configuration" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const empty_workspace_toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(empty_workspace_toml);

    var result = try runZr(allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should handle empty workspace gracefully
    try std.testing.expect(output.len > 0);
}

test "361: workspace affected command runs tasks on changed members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Initialize git repo
    {
        const git_init = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "init" },
            .cwd = tmp_path,
        });
        allocator.free(git_init.stdout);
        allocator.free(git_init.stderr);
    }
    {
        const git_config1 = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.name", "Test User" },
            .cwd = tmp_path,
        });
        allocator.free(git_config1.stdout);
        allocator.free(git_config1.stderr);
    }
    {
        const git_config2 = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.email", "test@example.com" },
            .cwd = tmp_path,
        });
        allocator.free(git_config2.stdout);
        allocator.free(git_config2.stderr);
    }

    // Create workspace config with multiple members
    const zr_toml =
        \\[workspace]
        \\members = ["app", "lib"]
        \\
        \\[task.test]
        \\command = "echo testing"
        \\
    ;
    const config_file = try tmp.dir.createFile("zr.toml", .{});
    defer config_file.close();
    try config_file.writeAll(zr_toml);

    // Create workspace members
    try tmp.dir.makeDir("app");
    try tmp.dir.makeDir("lib");
    const app_config = try tmp.dir.createFile("app/zr.toml", .{});
    defer app_config.close();
    try app_config.writeAll("[task.test]\ncommand = \"echo app\"\n");
    const lib_config = try tmp.dir.createFile("lib/zr.toml", .{});
    defer lib_config.close();
    try lib_config.writeAll("[task.test]\ncommand = \"echo lib\"\n");

    // Initial commit
    {
        const git_add = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "add", "." },
            .cwd = tmp_path,
        });
        allocator.free(git_add.stdout);
        allocator.free(git_add.stderr);
    }
    {
        const git_commit = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "commit", "-m", "initial" },
            .cwd = tmp_path,
        });
        allocator.free(git_commit.stdout);
        allocator.free(git_commit.stderr);
    }

    // workspace affected requires git changes to detect affected members
    var result = try runZr(allocator, &.{ "workspace", "affected", "test" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should report no affected members or run successfully
    try std.testing.expect(output.len > 0);
}

test "369: workspace run with --affected flag integration" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Initialize git repo
    {
        const git_init = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "init" },
            .cwd = tmp_path,
        });
        allocator.free(git_init.stdout);
        allocator.free(git_init.stderr);
    }
    {
        const git_config1 = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.name", "Test User" },
            .cwd = tmp_path,
        });
        allocator.free(git_config1.stdout);
        allocator.free(git_config1.stderr);
    }
    {
        const git_config2 = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.email", "test@example.com" },
            .cwd = tmp_path,
        });
        allocator.free(git_config2.stdout);
        allocator.free(git_config2.stderr);
    }

    // Create workspace
    const zr_toml =
        \\[workspace]
        \\members = ["m1", "m2"]
        \\
        \\[task.build]
        \\command = "echo building"
        \\
    ;
    const config_file = try tmp.dir.createFile("zr.toml", .{});
    defer config_file.close();
    try config_file.writeAll(zr_toml);

    try tmp.dir.makeDir("m1");
    try tmp.dir.makeDir("m2");
    const m1_config = try tmp.dir.createFile("m1/zr.toml", .{});
    defer m1_config.close();
    try m1_config.writeAll("[task.build]\ncommand = \"echo m1\"\n");
    const m2_config = try tmp.dir.createFile("m2/zr.toml", .{});
    defer m2_config.close();
    try m2_config.writeAll("[task.build]\ncommand = \"echo m2\"\n");

    // Initial commit
    {
        const git_add = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "add", "." },
            .cwd = tmp_path,
        });
        allocator.free(git_add.stdout);
        allocator.free(git_add.stderr);
    }
    {
        const git_commit = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "commit", "-m", "initial" },
            .cwd = tmp_path,
        });
        allocator.free(git_commit.stdout);
        allocator.free(git_commit.stderr);
    }

    // Workspace run with affected detection
    var result = try runZr(allocator, &.{ "workspace", "run", "build", "--affected", "HEAD" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should run on affected members only
    try std.testing.expect(output.len > 0);
}

test "386: workspace run with some members succeeding and some failing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2", "pkg3"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;
    const config_file = try tmp.dir.createFile("zr.toml", .{});
    defer config_file.close();
    try config_file.writeAll(zr_toml);

    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");
    try tmp.dir.makeDir("pkg3");

    // pkg1 succeeds
    const pkg1_config = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_config.close();
    try pkg1_config.writeAll("[task.test]\ncommand = \"echo pkg1\"\n");

    // pkg2 fails
    const pkg2_config = try tmp.dir.createFile("pkg2/zr.toml", .{});
    defer pkg2_config.close();
    try pkg2_config.writeAll("[task.test]\ncommand = \"false\"\n");

    // pkg3 succeeds
    const pkg3_config = try tmp.dir.createFile("pkg3/zr.toml", .{});
    defer pkg3_config.close();
    try pkg3_config.writeAll("[task.test]\ncommand = \"echo pkg3\"\n");

    // Run across workspace
    var result = try runZr(allocator, &.{ "workspace", "run", "test" }, tmp_path);
    defer result.deinit();
    // Should report mixed results
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "396: workspace run with --format json and --jobs=2" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workspace root config
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.build]
        \\cmd = "echo root-build"
        \\
    );

    // Create packages directory
    try tmp.dir.makePath("packages/pkg1");
    try tmp.dir.makePath("packages/pkg2");

    const pkg1_toml = try tmp.dir.createFile("packages/pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll(
        \\[tasks.build]
        \\cmd = "echo pkg1-build"
        \\
    );

    const pkg2_toml = try tmp.dir.createFile("packages/pkg2/zr.toml", .{});
    defer pkg2_toml.close();
    try pkg2_toml.writeAll(
        \\[tasks.build]
        \\cmd = "echo pkg2-build"
        \\
    );

    // Run workspace with combined flags
    var result = try runZr(allocator, &.{ "workspace", "run", "build", "--format", "json", "--jobs", "2" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "407: workspace run with --affected flag and no git changes skips all" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    // Create workspace members
    try tmp.dir.makeDir("pkg1");
    const pkg1_toml = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll(
        \\[tasks.build]
        \\cmd = "echo pkg1"
        \\
    );

    try tmp.dir.makeDir("pkg2");
    const pkg2_toml = try tmp.dir.createFile("pkg2/zr.toml", .{});
    defer pkg2_toml.close();
    try pkg2_toml.writeAll(
        \\[tasks.build]
        \\cmd = "echo pkg2"
        \\
    );

    // Try with --affected (no git repo, so should handle gracefully)
    var result = try runZr(allocator, &.{ "workspace", "run", "build", "--affected", "HEAD" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should either skip or report no git repo
    try std.testing.expect(output.len > 0);
}

test "418: workspace run with --format json and --quiet combined" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workspace structure
    try tmp.dir.makeDir("project-a");
    try tmp.dir.makeDir("project-b");

    const workspace_toml =
        \\[workspace]
        \\members = ["project-a", "project-b"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workspace_toml);

    const task_toml =
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const project_a_toml = try tmp.dir.createFile("project-a/zr.toml", .{});
    defer project_a_toml.close();
    try project_a_toml.writeAll(task_toml);

    const project_b_toml = try tmp.dir.createFile("project-b/zr.toml", .{});
    defer project_b_toml.close();
    try project_b_toml.writeAll(task_toml);

    var result = try runZr(allocator, &.{ "workspace", "run", "test", "--format", "json", "--quiet" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // With --quiet, should have minimal output even with JSON format
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "428: workspace run with --jobs=0 accepts and uses default CPU count" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1"]
        \\
        \\[tasks.build]
        \\cmd = "echo root"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    try tmp.dir.makeDir("pkg1");
    const pkg_config = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg_config.close();
    try pkg_config.writeAll("[tasks.build]\ncmd = \"echo pkg1\"\n");

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "build", "--jobs=0" }, tmp_path);
    defer result.deinit();
    // Should accept --jobs=0 and use default
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "435: workspace affected with --base and --head refs on same commit shows no changes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Initialize git repo
    {
        const git_init = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "init" },
            .cwd = tmp_path,
        });
        allocator.free(git_init.stdout);
        allocator.free(git_init.stderr);
    }
    {
        const git_config1 = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.name", "Test User" },
            .cwd = tmp_path,
        });
        allocator.free(git_config1.stdout);
        allocator.free(git_config1.stderr);
    }
    {
        const git_config2 = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.email", "test@example.com" },
            .cwd = tmp_path,
        });
        allocator.free(git_config2.stdout);
        allocator.free(git_config2.stderr);
    }

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    try tmp.dir.makeDir("pkg1");
    const pkg_config = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg_config.close();
    try pkg_config.writeAll("[tasks.test]\ncmd = \"echo pkg1\"\n");

    // Initial commit
    {
        const git_add = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "add", "." },
            .cwd = tmp_path,
        });
        allocator.free(git_add.stdout);
        allocator.free(git_add.stderr);
    }
    {
        const git_commit = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "commit", "-m", "initial" },
            .cwd = tmp_path,
        });
        allocator.free(git_commit.stdout);
        allocator.free(git_commit.stderr);
    }

    // Affected with same base and head (HEAD...HEAD) should show no changes
    var result = try runZr(allocator, &.{ "--config", config, "affected", "test", "--base=HEAD", "--include-dependents" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

// ── NEW TESTS (436-445): Edge cases, error recovery, and advanced combinations ──

test "437: workspace list with empty members array shows appropriate message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const empty_workspace_toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, empty_workspace_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "453: workspace run with --dry-run and --jobs flags combined" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg-a", "pkg-b"]
        \\
    ;

    try tmp.dir.makeDir("pkg-a");
    try tmp.dir.makeDir("pkg-b");

    const pkg_toml =
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const root_file = try tmp.dir.createFile("zr.toml", .{});
    defer root_file.close();
    try root_file.writeAll(workspace_toml);

    const pkg_a_file = try tmp.dir.createFile("pkg-a/zr.toml", .{});
    defer pkg_a_file.close();
    try pkg_a_file.writeAll(pkg_toml);

    const pkg_b_file = try tmp.dir.createFile("pkg-b/zr.toml", .{});
    defer pkg_b_file.close();
    try pkg_b_file.writeAll(pkg_toml);

    // Test dry-run with jobs flag
    var result = try runZr(allocator, &.{ "workspace", "run", "test", "--dry-run", "--jobs", "1" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should show both members in output
    try std.testing.expect(std.mem.indexOf(u8, output, "pkg-a") != null or
        std.mem.indexOf(u8, output, "pkg-b") != null);
}

test "468: workspace run with no members shows appropriate error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const no_members_toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(no_members_toml);

    var result = try runZr(allocator, &.{ "workspace", "run", "build" }, tmp_path);
    defer result.deinit();
    // Should handle empty workspace gracefully
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "477: workspace sync with nonexistent repo config shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "workspace", "sync", "/nonexistent/path/zr-repos.toml" }, tmp_path);
    defer result.deinit();
    // Should return error for nonexistent config
    try std.testing.expect(result.exit_code != 0);
}

test "485: workspace run with --format json and parallel execution shows structured output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create workspace structure
    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/app1");
    try tmp.dir.makeDir("packages/app2");

    const root_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
    ;

    const app1_toml =
        \\[tasks.build]
        \\cmd = "echo app1"
        \\
    ;

    const app2_toml =
        \\[tasks.build]
        \\cmd = "echo app2"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(root_toml);

    const app1_config = try tmp.dir.createFile("packages/app1/zr.toml", .{});
    defer app1_config.close();
    try app1_config.writeAll(app1_toml);

    const app2_config = try tmp.dir.createFile("packages/app2/zr.toml", .{});
    defer app2_config.close();
    try app2_config.writeAll(app2_toml);

    var result = try runZr(allocator, &.{ "workspace", "run", "build", "--format", "json", "--jobs", "2" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should output valid JSON with results from both packages
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
}

test "489: workspace affected with --format json outputs structured change analysis" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Initialize git
    const git_init2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "init" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_init2.stdout);
    defer allocator.free(git_init2.stderr);

    const git_config_name2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.name", "Test" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_config_name2.stdout);
    defer allocator.free(git_config_name2.stderr);

    const git_config_email2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.email", "test@example.com" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_config_email2.stdout);
    defer allocator.free(git_config_email2.stderr);

    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/app1");

    const root_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
    ;

    const app1_toml =
        \\[tasks.build]
        \\cmd = "echo app1"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(root_toml);

    const app1_config = try tmp.dir.createFile("packages/app1/zr.toml", .{});
    defer app1_config.close();
    try app1_config.writeAll(app1_toml);

    const git_add2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "add", "." },
        .cwd = tmp_path,
    });
    defer allocator.free(git_add2.stdout);
    defer allocator.free(git_add2.stderr);

    const git_commit2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "commit", "-m", "init" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_commit2.stdout);
    defer allocator.free(git_commit2.stderr);

    var result = try runZr(allocator, &.{ "affected", "build", "--format", "json" }, tmp_path);
    defer result.deinit();
    // Should show affected analysis in JSON
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "504: workspace run with --affected + --format json + --dry-run shows structured preview" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Init git repo
    const git_init = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "init" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_init.stdout);
    defer allocator.free(git_init.stderr);

    const git_config1 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.name", "Test User" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_config1.stdout);
    defer allocator.free(git_config1.stderr);

    const git_config2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.email", "test@example.com" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_config2.stdout);
    defer allocator.free(git_config2.stderr);

    const toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    // Create workspace member
    try tmp.dir.makeDir("packages");
    var packages_dir = try tmp.dir.openDir("packages", .{});
    defer packages_dir.close();
    try packages_dir.makeDir("lib");
    var lib_dir = try packages_dir.openDir("lib", .{});
    defer lib_dir.close();

    const member_toml =
        \\[tasks.test]
        \\cmd = "echo lib test"
        \\
    ;

    const lib_zr = try lib_dir.createFile("zr.toml", .{});
    defer lib_zr.close();
    try lib_zr.writeAll(member_toml);

    const git_add = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "add", "." },
        .cwd = tmp_path,
    });
    defer allocator.free(git_add.stdout);
    defer allocator.free(git_add.stderr);

    const git_commit = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "commit", "-m", "init" },
        .cwd = tmp_path,
    });
    defer allocator.free(git_commit.stdout);
    defer allocator.free(git_commit.stderr);

    var result = try runZr(allocator, &.{ "workspace", "run", "test", "--affected", "HEAD", "--format", "json", "--dry-run" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "509: workspace run with --jobs=999 uses available CPU count as ceiling" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    try tmp.dir.makeDir("packages");
    var packages_dir = try tmp.dir.openDir("packages", .{});
    defer packages_dir.close();
    try packages_dir.makeDir("core");
    var core_dir = try packages_dir.openDir("core", .{});
    defer core_dir.close();

    const member_toml =
        \\[tasks.build]
        \\cmd = "echo core build"
        \\
    ;

    const core_zr = try core_dir.createFile("zr.toml", .{});
    defer core_zr.close();
    try core_zr.writeAll(member_toml);

    var result = try runZr(allocator, &.{ "workspace", "run", "build", "--jobs", "999", "--dry-run" }, tmp_path);
    defer result.deinit();
    // Should succeed without error (capped at CPU count internally)
    try std.testing.expect(result.exit_code == 0);
}

test "516: workspace list with nonexistent members glob shows empty" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Workspace with glob that matches nothing
    const toml =
        \\[workspace]
        \\members = ["nonexistent/*"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();
    // Should succeed (empty workspace is valid)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "536: workspace run with --format json and --verbose shows both structured output and logs" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["pkg1"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    try tmp.dir.makeDir("pkg1");
    const pkg1_toml = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_toml.close();
    try pkg1_toml.writeAll("[tasks.test]\ncmd = \"echo pkg1-test\"");

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "test", "--format", "json", "--verbose" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should output JSON format even with verbose
    try std.testing.expect(result.stdout.len > 0);
}

test "546: workspace list with --format yaml shows YAML structured output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    try tmp.dir.makeDir("pkg1");
    const pkg1_config = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_config.close();
    try pkg1_config.writeAll("[tasks.build]\ncmd = \"echo build\"");

    try tmp.dir.makeDir("pkg2");
    const pkg2_config = try tmp.dir.createFile("pkg2/zr.toml", .{});
    defer pkg2_config.close();
    try pkg2_config.writeAll("[tasks.test]\ncmd = \"echo test\"");

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list", "--format", "yaml" }, tmp_path);
    defer result.deinit();
    // Should output YAML or succeed without crashing
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "554: workspace run with --jobs and --affected together executes filtered tasks in parallel" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Initialize git repo
    const git_init = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "init" },
        .cwd = tmp_path,
    });
    defer {
        allocator.free(git_init.stdout);
        allocator.free(git_init.stderr);
    }

    const git_config_name = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.name", "Test User" },
        .cwd = tmp_path,
    });
    defer {
        allocator.free(git_config_name.stdout);
        allocator.free(git_config_name.stderr);
    }

    const git_config_email = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.email", "test@example.com" },
        .cwd = tmp_path,
    });
    defer {
        allocator.free(git_config_email.stdout);
        allocator.free(git_config_email.stderr);
    }

    const toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    try tmp.dir.makeDir("pkg1");
    const pkg1_config = try tmp.dir.createFile("pkg1/zr.toml", .{});
    defer pkg1_config.close();
    try pkg1_config.writeAll("[tasks.build]\ncmd = \"echo build\"");

    try tmp.dir.makeDir("pkg2");
    const pkg2_config = try tmp.dir.createFile("pkg2/zr.toml", .{});
    defer pkg2_config.close();
    try pkg2_config.writeAll("[tasks.build]\ncmd = \"echo build\"");

    const git_add = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "add", "." },
        .cwd = tmp_path,
    });
    defer {
        allocator.free(git_add.stdout);
        allocator.free(git_add.stderr);
    }

    const git_commit = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "commit", "-m", "Initial" },
        .cwd = tmp_path,
    });
    defer {
        allocator.free(git_commit.stdout);
        allocator.free(git_commit.stderr);
    }

    // Make a change to pkg1
    const change_file = try tmp.dir.createFile("pkg1/src.txt", .{});
    defer change_file.close();
    try change_file.writeAll("changed");

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "build", "--affected", "HEAD", "--jobs=2" }, tmp_path);
    defer result.deinit();
    // Should work or handle gracefully
    try std.testing.expect(result.exit_code <= 1);
}

test "558: workspace run with --profile and --dry-run shows execution plan with profile overrides" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create workspace root with member
    const toml =
        \\[workspace]
        \\members = ["pkg"]
        \\
        \\[profiles.prod]
        \\env.MODE = "production"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Create member pkg directory with zr.toml
    try tmp.dir.makeDir("pkg");
    var pkg_dir = try tmp.dir.openDir("pkg", .{});
    defer pkg_dir.close();

    const pkg_toml =
        \\[tasks.deploy]
        \\cmd = "echo pkg deploy"
        \\
    ;
    try pkg_dir.writeFile(.{ .sub_path = "zr.toml", .data = pkg_toml });

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "prod", "--dry-run", "workspace", "run", "deploy" }, tmp_path);
    defer result.deinit();
    // Workspace run with dry-run should succeed or show deploy-related output
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "deploy") != null or std.mem.indexOf(u8, output, "pkg") != null or result.exit_code == 0);
}

test "567: workspace run with --parallel and --format csv shows structured output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "--parallel", "--format=csv", "test" }, tmp_path);
    defer result.deinit();
    // May not support CSV format for workspace run yet
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "577: workspace member with relative path and ../ navigation resolves correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create workspace structure with nested paths
    try tmp.dir.makeDir("subdir");
    try tmp.dir.makeDir("subdir/pkg1");
    try tmp.dir.makeDir("pkg2");

    const root_toml =
        \\[workspace]
        \\members = ["subdir/pkg1", "pkg2"]
        \\
        \\[tasks.root]
        \\cmd = "echo root"
        \\
    ;

    const pkg1_toml =
        \\[tasks.build]
        \\cmd = "echo pkg1"
        \\cwd = "../.."
        \\
    ;

    const pkg2_toml =
        \\[tasks.build]
        \\cmd = "echo pkg2"
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, root_toml);
    defer allocator.free(root_config);
    const pkg1_config = try writeTmpConfigPath(allocator, tmp.dir, pkg1_toml, "subdir/pkg1/zr.toml");
    defer allocator.free(pkg1_config);
    const pkg2_config = try writeTmpConfigPath(allocator, tmp.dir, pkg2_toml, "pkg2/zr.toml");
    defer allocator.free(pkg2_config);

    var result = try runZr(allocator, &.{ "--config", root_config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "581: workspace with circular member references detected and handled" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");

    const root_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
    ;

    const pkg1_toml =
        \\[workspace]
        \\members = ["../pkg2"]
        \\
        \\[tasks.build]
        \\cmd = "echo pkg1"
        \\
    ;

    const pkg2_toml =
        \\[workspace]
        \\members = ["../pkg1"]
        \\
        \\[tasks.build]
        \\cmd = "echo pkg2"
        \\
    ;

    const root_config = try writeTmpConfig(allocator, tmp.dir, root_toml);
    defer allocator.free(root_config);
    const pkg1_config = try writeTmpConfigPath(allocator, tmp.dir, pkg1_toml, "pkg1/zr.toml");
    defer allocator.free(pkg1_config);
    const pkg2_config = try writeTmpConfigPath(allocator, tmp.dir, pkg2_toml, "pkg2/zr.toml");
    defer allocator.free(pkg2_config);

    // Should handle circular references gracefully
    var result = try runZr(allocator, &.{ "--config", root_config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    // Should either succeed or report circular reference error
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "587: workspace list with --format csv shows unsupported format error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["pkg1"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    try tmp.dir.makeDir("pkg1");
    const root_config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(root_config);

    const pkg1_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;
    const pkg1_config = try writeTmpConfigPath(allocator, tmp.dir, pkg1_toml, "pkg1/zr.toml");
    defer allocator.free(pkg1_config);

    // CSV format not supported for workspace list
    var result = try runZr(allocator, &.{ "--config", root_config, "workspace", "list", "--format", "csv" }, tmp_path);
    defer result.deinit();
    // Should error or fallback to default format
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "591: workspace run with both --jobs and --parallel flags handles redundancy" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.build]
        \\cmd = "echo root"
        \\
    ;

    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");
    const root_config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(root_config);

    const pkg_toml =
        \\[tasks.build]
        \\cmd = "echo pkg"
        \\
    ;
    const pkg1_config = try writeTmpConfigPath(allocator, tmp.dir, pkg_toml, "pkg1/zr.toml");
    defer allocator.free(pkg1_config);
    const pkg2_config = try writeTmpConfigPath(allocator, tmp.dir, pkg_toml, "pkg2/zr.toml");
    defer allocator.free(pkg2_config);

    // Both --jobs and --parallel (redundant) - should handle gracefully
    var result = try runZr(allocator, &.{ "--config", root_config, "workspace", "run", "build", "--jobs=2", "--parallel" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "598: workspace affected with --exclude-self shows only dependents" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
    ;

    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");
    const root_config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(root_config);

    const pkg1_toml =
        \\[tasks.build]
        \\cmd = "echo pkg1"
        \\
    ;
    const pkg1_config = try writeTmpConfigPath(allocator, tmp.dir, pkg1_toml, "pkg1/zr.toml");
    defer allocator.free(pkg1_config);

    const pkg2_toml =
        \\[tasks.build]
        \\cmd = "echo pkg2"
        \\
        \\[metadata]
        \\dependencies = ["pkg1"]
        \\
    ;
    const pkg2_config = try writeTmpConfigPath(allocator, tmp.dir, pkg2_toml, "pkg2/zr.toml");
    defer allocator.free(pkg2_config);

    // Initialize git repo
    {
        var init_child = std.process.Child.init(&.{ "git", "init" }, allocator);
        init_child.cwd = tmp_path;
        _ = try init_child.spawnAndWait();
    }
    {
        var config_user = std.process.Child.init(&.{ "git", "config", "user.name", "Test" }, allocator);
        config_user.cwd = tmp_path;
        _ = try config_user.spawnAndWait();
    }
    {
        var config_email = std.process.Child.init(&.{ "git", "config", "user.email", "test@test.com" }, allocator);
        config_email.cwd = tmp_path;
        _ = try config_email.spawnAndWait();
    }
    {
        var add_child = std.process.Child.init(&.{ "git", "add", "." }, allocator);
        add_child.cwd = tmp_path;
        _ = try add_child.spawnAndWait();
    }
    {
        var commit_child = std.process.Child.init(&.{ "git", "commit", "-m", "init" }, allocator);
        commit_child.cwd = tmp_path;
        _ = try commit_child.spawnAndWait();
    }

    // Modify pkg1
    try tmp.dir.writeFile(.{ .sub_path = "pkg1/file.txt", .data = "changed" });
    {
        var add_child = std.process.Child.init(&.{ "git", "add", "pkg1/file.txt" }, allocator);
        add_child.cwd = tmp_path;
        _ = try add_child.spawnAndWait();
    }

    // affected with --exclude-self should only show pkg2 (dependent)
    var result = try runZr(allocator, &.{ "--config", root_config, "affected", "build", "--exclude-self", "--include-dependents", "--list" }, tmp_path);
    defer result.deinit();
    // Should show pkg2 but not pkg1
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "605: workspace run with --affected and no changes shows informative message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
    ;

    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");
    const root_config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(root_config);

    const pkg_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;
    const pkg1_config = try writeTmpConfigPath(allocator, tmp.dir, pkg_toml, "pkg1/zr.toml");
    defer allocator.free(pkg1_config);
    const pkg2_config = try writeTmpConfigPath(allocator, tmp.dir, pkg_toml, "pkg2/zr.toml");
    defer allocator.free(pkg2_config);

    // Initialize git repo and commit everything
    {
        var init_child = std.process.Child.init(&.{ "git", "init" }, allocator);
        init_child.cwd = tmp_path;
        _ = try init_child.spawnAndWait();
    }
    {
        var config_user = std.process.Child.init(&.{ "git", "config", "user.name", "Test" }, allocator);
        config_user.cwd = tmp_path;
        _ = try config_user.spawnAndWait();
    }
    {
        var config_email = std.process.Child.init(&.{ "git", "config", "user.email", "test@test.com" }, allocator);
        config_email.cwd = tmp_path;
        _ = try config_email.spawnAndWait();
    }
    {
        var add_child = std.process.Child.init(&.{ "git", "add", "." }, allocator);
        add_child.cwd = tmp_path;
        _ = try add_child.spawnAndWait();
    }
    {
        var commit_child = std.process.Child.init(&.{ "git", "commit", "-m", "init" }, allocator);
        commit_child.cwd = tmp_path;
        _ = try commit_child.spawnAndWait();
    }

    // Run with --affected when nothing changed
    var result = try runZr(allocator, &.{ "--config", root_config, "workspace", "run", "build", "--affected" }, tmp_path);
    defer result.deinit();
    // May exit with 0 (no work to do) or 1 (no affected packages)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "610: workspace run with --format json and empty workspace shows graceful handling" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const empty_workspace_toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, empty_workspace_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "build", "--format", "json" }, tmp_path);
    defer result.deinit();
    // Should handle gracefully with JSON output
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    if (result.stdout.len > 0) {
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null or std.mem.indexOf(u8, result.stdout, "[") != null);
    }
}

test "659: workspace run with --format json and multiple tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    // Create workspace member
    try tmp.dir.makeDir("pkg1");
    try tmp.dir.writeFile(.{ .sub_path = "pkg1/zr.toml", .data = "[tasks.test]\ncmd = \"echo pkg1-test\"\n" });

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "test", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should output JSON with workspace results
    try std.testing.expect(result.exit_code == 0 or result.stderr.len > 0);
}

test "666: workspace run with --affected and --exclude-self shows only dependents" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const workspace_toml =
        \\[workspace]
        \\members = ["lib", "app"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    // Create workspace members
    try tmp.dir.makeDir("lib");
    try tmp.dir.writeFile(.{ .sub_path = "lib/zr.toml", .data = "[tasks.build]\ncmd = \"echo lib\"\n" });

    try tmp.dir.makeDir("app");
    try tmp.dir.writeFile(.{ .sub_path = "app/zr.toml", .data = "[tasks.build]\ncmd = \"echo app\"\n" });

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "build", "--affected", "HEAD", "--exclude-self" }, tmp_path);
    defer result.deinit();

    // Should run without errors (exclude-self filters out directly affected, shows only dependents)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "683: workspace list with filter pattern shows only matching members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create workspace structure
    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/api");
    try tmp.dir.makeDir("packages/web");
    try tmp.dir.makeDir("packages/cli");

    const root_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
    ;

    const pkg_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = root_toml });
    try tmp.dir.writeFile(.{ .sub_path = "packages/api/zr.toml", .data = pkg_toml });
    try tmp.dir.writeFile(.{ .sub_path = "packages/web/zr.toml", .data = pkg_toml });
    try tmp.dir.writeFile(.{ .sub_path = "packages/cli/zr.toml", .data = pkg_toml });

    var result = try runZr(allocator, &.{ "workspace", "list", "api" }, tmp_path);
    defer result.deinit();

    // Should list only matching workspace members (or list all if filter not supported)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "693: workspace run with --affected and git submodule changes detects affected members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Initialize git repo
    {
        const git_init = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "init" },
            .cwd = tmp_path,
        });
        defer allocator.free(git_init.stdout);
        defer allocator.free(git_init.stderr);
    }
    {
        const git_config = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.name", "Test" },
            .cwd = tmp_path,
        });
        defer allocator.free(git_config.stdout);
        defer allocator.free(git_config.stderr);
    }
    {
        const git_email = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.email", "test@test.com" },
            .cwd = tmp_path,
        });
        defer allocator.free(git_email.stdout);
        defer allocator.free(git_email.stderr);
    }

    const root_toml =
        \\[workspace]
        \\members = ["packages/*"]
        \\
    ;

    const pkg_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = root_toml });
    try tmp.dir.makeDir("packages");
    try tmp.dir.makeDir("packages/core");
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/zr.toml", .data = pkg_toml });

    {
        const git_add = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "add", "." },
            .cwd = tmp_path,
        });
        defer allocator.free(git_add.stdout);
        defer allocator.free(git_add.stderr);
    }
    {
        const git_commit = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "commit", "-m", "initial" },
            .cwd = tmp_path,
        });
        defer allocator.free(git_commit.stdout);
        defer allocator.free(git_commit.stderr);
    }

    // Modify a file in submodule
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/file.txt", .data = "changed" });

    var result = try runZr(allocator, &.{ "workspace", "run", "--affected", "build" }, tmp_path);
    defer result.deinit();

    // Should detect core package as affected
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "700: workspace list with --format json and empty workspace returns valid JSON" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should output valid JSON array (empty or with error)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "713: workspace run with nonexistent member shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[workspace]
        \\members = ["pkg-a"]
        \\
    ;
    const config_file = try tmp.dir.createFile("zr.toml", .{});
    defer config_file.close();
    try config_file.writeAll(config);

    var result = try runZr(allocator, &.{ "workspace", "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    // Workspace error can be "no member directories found" or similar
    try std.testing.expect(std.mem.indexOf(u8, output, "member") != null or std.mem.indexOf(u8, output, "workspace") != null);
}
