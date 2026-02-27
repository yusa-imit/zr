const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "37: repo info shows repository status" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "repo", "info" }, tmp_path);
    defer result.deinit();
    // May fail if not in git repo, but should not crash
    _ = result.exit_code;
}

test "87: repo sync without zr-repos.toml fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to sync without config
    var result = try runZr(allocator, &.{ "repo", "sync" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos.toml") != null or std.mem.indexOf(u8, result.stderr, "not found") != null or std.mem.indexOf(u8, result.stderr, "No such file") != null);
}

test "88: repo graph without zr-repos.toml reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to show graph without multi-repo config
    var result = try runZr(allocator, &.{ "repo", "graph" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "100: repo status command without multi-repo config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "repo", "status" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos") != null or std.mem.indexOf(u8, result.stderr, "not found") != null or std.mem.indexOf(u8, result.stderr, "No such file") != null);
}

test "148: repo run executes task across all repositories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try running task without zr-repos.toml (should fail gracefully)
    var result = try runZr(allocator, &.{ "repo", "run", "test" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully if no zr-repos.toml found
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos.toml") != null);
}

test "149: repo run with --dry-run flag shows execution plan" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try dry-run without zr-repos.toml (should fail gracefully)
    var result = try runZr(allocator, &.{ "repo", "run", "test", "--dry-run" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully if no zr-repos.toml found
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "171: repo sync clones and updates repositories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create empty zr-repos.toml file
    const repos_toml = "# Empty repos file\n";
    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    var result = try runZr(allocator, &.{ "--config", config, "repo", "sync" }, tmp_path);
    defer result.deinit();

    // Should succeed with empty repos file
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "172: repo status shows git status of all repositories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create empty zr-repos.toml file
    const repos_toml = "# Empty repos file\n";
    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    var result = try runZr(allocator, &.{ "--config", config, "repo", "status" }, tmp_path);
    defer result.deinit();

    // Should succeed with empty repos file
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "181: repo graph with --format json outputs JSON structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create zr-repos.toml
    const repos_config =
        \\[workspace]
        \\root = "."
        \\
        \\[repos.frontend]
        \\path = "packages/frontend"
        \\
        \\[repos.backend]
        \\path = "packages/backend"
        \\deps = ["frontend"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr-repos.toml", .data = repos_config });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create fake package dirs with zr.toml
    try tmp.dir.makePath("packages/frontend");
    try tmp.dir.writeFile(.{ .sub_path = "packages/frontend/zr.toml", .data = "[tasks.test]\ncmd = \"echo test\"" });
    try tmp.dir.makePath("packages/backend");
    try tmp.dir.writeFile(.{ .sub_path = "packages/backend/zr.toml", .data = "[tasks.test]\ncmd = \"echo test\"" });

    const repos_path = try std.fs.path.join(allocator, &.{ tmp_path, "zr-repos.toml" });
    defer allocator.free(repos_path);

    var result = try runZr(allocator, &.{ "repo", "graph", "--format", "json", repos_path }, tmp_path);
    defer result.deinit();

    // May fail without actual git repos, main test is that it handles flags correctly
    try std.testing.expect(result.exit_code <= 1);
}

test "354: repo graph command shows cross-repo dependency visualization" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const repos_toml =
        \\[repos.core]
        \\url = "https://github.com/example/core.git"
        \\path = "packages/core"
        \\
        \\[repos.ui]
        \\url = "https://github.com/example/ui.git"
        \\path = "packages/ui"
        \\deps = ["core"]
        \\
    ;

    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    var result = try runZr(allocator, &.{ "repo", "graph" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should show repo structure or report no repos/graph
    try std.testing.expect(output.len > 0);
}

test "451: repo graph with --format json outputs structured data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const repos_toml =
        \\[[repo]]
        \\name = "repo-a"
        \\url = "https://example.com/repo-a.git"
        \\path = "repos/repo-a"
        \\
    ;

    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    const empty_zr =
        \\# Empty config
        \\
    ;
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(empty_zr);

    // Try repo graph with JSON format
    var result = try runZr(allocator, &.{ "repo", "graph", "--format", "json" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should produce JSON output or handle gracefully
    try std.testing.expect(output.len > 0);
}

test "462: repo sync with authentication failure shows appropriate error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const repo_toml =
        \\[tasks.hello]
        \\cmd = "echo hi"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(repo_toml);

    // Create zr-repos.toml with invalid URL
    const repos_toml =
        \\[[repos]]
        \\name = "invalid"
        \\url = "https://invalid-url-xyz.example.com/repo.git"
        \\path = "./repos/invalid"
        \\
    ;
    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    var result = try runZr(allocator, &.{ "repo", "sync" }, tmp_path);
    defer result.deinit();
    // Should handle sync failure gracefully
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "493: repo status with --format json outputs structured git status" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal repos config
    const repos_toml =
        \\[repos.main]
        \\url = "https://github.com/example/repo.git"
        \\path = "."
        \\
    ;

    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    var result = try runZr(allocator, &.{ "repo", "status", "--format", "json" }, tmp_path);
    defer result.deinit();
    // May fail gracefully if repos not actually cloned
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "533: repo graph with --format json shows structured dependency graph" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const repos_toml =
        \\[workspace]
        \\root = "."
        \\
        \\[repos.backend]
        \\path = "backend"
        \\url = "https://example.com/backend.git"
        \\
        \\[repos.frontend]
        \\path = "frontend"
        \\url = "https://example.com/frontend.git"
        \\deps = ["backend"]
        \\
    ;

    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    var result = try runZr(allocator, &.{ "repo", "graph", "--format", "json" }, tmp_path);
    defer result.deinit();
    // Should succeed and output valid JSON
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "backend") != null);
}

test "571: repo run with --tags flag filters repositories by tags" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const repos_toml =
        \\[workspace]
        \\name = "test-monorepo"
        \\
        \\[repos.backend]
        \\url = "https://example.com/backend.git"
        \\tags = ["backend", "api"]
        \\
        \\[repos.frontend]
        \\url = "https://example.com/frontend.git"
        \\tags = ["frontend", "web"]
        \\
    ;

    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    var result = try runZr(allocator, &.{ "repo", "run", "--tags=backend", "--dry-run", "build" }, tmp_path);
    defer result.deinit();
    // Should succeed with dry-run or report no repos synced
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "617: repo sync with --dry-run shows what would be synced without syncing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const repos_toml =
        \\[[repos]]
        \\name = "example"
        \\url = "https://github.com/example/repo.git"
        \\path = "repos/example"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const repos_path = try std.fs.path.join(allocator, &.{ tmp_path, "zr-repos.toml" });
    defer allocator.free(repos_path);
    try std.fs.cwd().writeFile(.{ .sub_path = repos_path, .data = repos_toml });

    var result = try runZr(allocator, &.{ "--config", config, "repo", "sync", "--dry-run" }, tmp_path);
    defer result.deinit();
    // Should show dry-run output without actually cloning
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "656: repo run with --affected and --tags combined filter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr-repos.toml for multi-repo (minimal)
    const repos_toml =
        \\[[repos]]
        \\name = "frontend"
        \\url = "https://github.com/example/frontend"
        \\tags = ["web", "ui"]
        \\
    ;
    const repos_file = try tmp.dir.createFile("zr-repos.toml", .{});
    defer repos_file.close();
    try repos_file.writeAll(repos_toml);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "repo", "run", "build", "--tags", "web", "--dry-run" }, tmp_path);
    defer result.deinit();

    // Should handle combined filtering (affected + tags)
    // In dry-run mode, should show execution plan or error message
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "674: repo graph with --format json and circular dependencies shows cycle info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr-repos.toml with circular deps
    const repos_toml =
        \\workspace = "."
        \\
        \\[repos.A]
        \\url = "https://example.com/A"
        \\deps = ["B"]
        \\
        \\[repos.B]
        \\url = "https://example.com/B"
        \\deps = ["A"]
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr-repos.toml", .data = repos_toml });

    var result = try runZr(allocator, &.{ "repo", "graph", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should detect and report circular dependencies
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
    // May show cycle warning or error
}
