const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrEnv = helpers.runZrEnv;
const writeTmpConfig = helpers.writeTmpConfig;

// Helper to run git commands
fn runGitCommand(allocator: std.mem.Allocator, args: []const []const u8, cwd: []const u8) !void {
    var child = std.process.Child.init(args, allocator);
    child.cwd = cwd;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    _ = try child.wait();
}

// Test skip_if with constant boolean
test "882: skip_if with true constant skips task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\[tasks.skipped]
        \\cmd = "touch {s}/should_not_exist"
        \\skip_if = "true"
        \\
        \\[tasks.executed]
        \\cmd = "touch {s}/should_exist"
        \\
        ,
        .{ tmp_path, tmp_path },
    );
    defer allocator.free(config_content);

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "skipped" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // File should NOT exist (task was skipped)
    const file_exists = blk: {
        tmp.dir.access("should_not_exist", .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk false;
            }
            return err;
        };
        break :blk true;
    };
    try std.testing.expect(!file_exists);

    // Now run the non-skipped task
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "executed" }, null);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);

    // This file SHOULD exist
    try tmp.dir.access("should_exist", .{});
}

// Test skip_if with false constant
test "883: skip_if with false constant executes task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\[tasks.hello]
        \\cmd = "touch {s}/marker"
        \\skip_if = "false"
        \\
        ,
        .{tmp_path},
    );
    defer allocator.free(config_content);

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // File SHOULD exist (task was executed)
    try tmp.dir.access("marker", .{});
}

// Test skip_if with environment variable
test "884: skip_if with env variable condition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\[tasks.conditional]
        \\cmd = "touch {s}/marker"
        \\skip_if = "env.SKIP_TASK == 'yes'"
        \\
        ,
        .{tmp_path},
    );
    defer allocator.free(config_content);

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    // Test with SKIP_TASK=yes (should skip)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("SKIP_TASK", "yes");

    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "conditional" }, null, &env_map);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // File should NOT exist (task was skipped)
    tmp.dir.access("marker", .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Expected - test passes
        } else {
            return err;
        }
    };
}

// Test git.dirty predicate
test "885: git.dirty predicate detects uncommitted changes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Initialize git repo with main as default branch
    try runGitCommand(allocator, &.{"git", "init", "-b", "main"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "config", "user.name", "Test User"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "config", "user.email", "test@example.com"}, tmp_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\[tasks.only_if_clean]
        \\cmd = "touch {s}/marker"
        \\skip_if = "git.dirty"
        \\
        ,
        .{tmp_path},
    );
    defer allocator.free(config_content);

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    // Create a file without staging it (makes repo dirty)
    try tmp.dir.writeFile(.{ .sub_path = "test.txt", .data = "hello" });

    var result = try runZr(allocator, &.{ "--config", config, "run", "only_if_clean" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // File should NOT exist (task was skipped because repo is dirty)
    tmp.dir.access("marker", .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Expected - test passes
        } else {
            return err;
        }
    };
}

// Test git.branch predicate
test "886: git.branch predicate matches current branch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Initialize git repo with main as default branch
    try runGitCommand(allocator, &.{"git", "init", "-b", "main"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "config", "user.name", "Test User"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "config", "user.email", "test@example.com"}, tmp_path);

    // Create initial commit
    try tmp.dir.writeFile(.{ .sub_path = "README.md", .data = "# Test\n" });
    try runGitCommand(allocator, &.{"git", "add", "README.md"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "commit", "-m", "initial"}, tmp_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\[tasks.only_on_main]
        \\cmd = "touch {s}/marker"
        \\skip_if = "git.branch != 'main'"
        \\
        ,
        .{tmp_path},
    );
    defer allocator.free(config_content);

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "only_on_main" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // File SHOULD exist (we're on main branch)
    try tmp.dir.access("marker", .{});
}

// Test git.tag predicate
test "887: git.tag predicate matches current tag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Initialize git repo with main as default branch
    try runGitCommand(allocator, &.{"git", "init", "-b", "main"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "config", "user.name", "Test User"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "config", "user.email", "test@example.com"}, tmp_path);

    // Create initial commit
    try tmp.dir.writeFile(.{ .sub_path = "README.md", .data = "# Test\n" });
    try runGitCommand(allocator, &.{"git", "add", "README.md"}, tmp_path);
    try runGitCommand(allocator, &.{"git", "commit", "-m", "initial"}, tmp_path);

    // Create a tag
    try runGitCommand(allocator, &.{"git", "tag", "v1.0.0"}, tmp_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\[tasks.only_on_release]
        \\cmd = "touch {s}/marker"
        \\skip_if = "git.tag != 'v*'"
        \\
        ,
        .{tmp_path},
    );
    defer allocator.free(config_content);

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "only_on_release" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // File SHOULD exist (we're on a v* tag)
    try tmp.dir.access("marker", .{});
}

// Test output_if field
test "888: output_if controls task output visibility" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_content =
        \\[tasks.verbose]
        \\cmd = "echo 'This should not appear'"
        \\output_if = "false"
        \\
        \\[tasks.quiet]
        \\cmd = "echo 'This should appear'"
        \\output_if = "true"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    // Run verbose task (output hidden)
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "verbose" }, null);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result1.stdout, "This should not appear") == null);

    // Run quiet task (output shown)
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "quiet" }, null);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result2.stdout, "This should appear") != null);
}

// Test output_if with env variable
test "889: output_if with env.DEBUG condition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_content =
        \\[tasks.debug]
        \\cmd = "echo 'Debug output'"
        \\output_if = "env.DEBUG == 'true'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    // Test without DEBUG env var (output hidden)
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "debug" }, null);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result1.stdout, "Debug output") == null);

    // Test with DEBUG=true (output shown)
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("DEBUG", "true");

    var result2 = try runZrEnv(allocator, &.{ "--config", config, "run", "debug" }, null, &env_map);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result2.stdout, "Debug output") != null);
}

// Test combined skip_if and output_if
test "890: combined skip_if and output_if behavior" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\[tasks.conditional]
        \\cmd = "echo 'Running task' && touch {s}/marker"
        \\skip_if = "env.SKIP == 'yes'"
        \\output_if = "env.VERBOSE == 'yes'"
        \\
        ,
        .{tmp_path},
    );
    defer allocator.free(config_content);

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    // Test 1: not skipped, no output
    {
        var result = try runZr(allocator, &.{ "--config", config, "run", "conditional" }, null);
        defer result.deinit();
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
        try tmp.dir.access("marker", .{});
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Running task") == null);
    }

    // Clean up marker
    try tmp.dir.deleteFile("marker");

    // Test 2: skipped, output doesn't matter
    {
        var env_map = std.process.EnvMap.init(allocator);
        defer env_map.deinit();
        try env_map.put("SKIP", "yes");

        var result = try runZrEnv(allocator, &.{ "--config", config, "run", "conditional" }, null, &env_map);
        defer result.deinit();
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);

        // File should NOT exist (task was skipped)
        tmp.dir.access("marker", .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Expected - test passes
            } else {
                return err;
            }
        };
    }
}
