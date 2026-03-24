const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");

// ── Windows-Specific Path Tests ──────────────────────────────────────────
//
// These tests verify Windows-specific path handling:
// 1. UNC paths (\\server\share)
// 2. Long paths (>260 characters)
// 3. Symlink resolution
//
// EXPECTED BEHAVIOR:
// - UNC paths work as cwd for task execution
// - Long paths (>260 chars) are handled correctly
// - Symlinks resolve correctly (requires Windows Dev Mode or admin)
//
// NOTE: These tests are Windows-specific and will be skipped on Unix.

// ── UNC Path Tests ────────────────────────────────────────────────────────

test "cwd: UNC path accepted in task configuration" {
    // Tests that a UNC path like \\server\share can be used as cwd
    // Skip on non-Windows
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // UNC paths are only testable if we have network shares available
    // For CI, we'll create a config with UNC path and verify it doesn't crash
    const toml_content =
        \\[tasks.test]
        \\description = "Test with UNC path"
        \\cmd = "echo hello"
        \\cwd = "\\\\localhost\\share"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    // Validate config (should not crash on UNC path)
    var result = try helpers.runZr(std.testing.allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    // Validation should succeed (UNC path is syntactically valid)
    // Execution might fail if share doesn't exist, but that's ok
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "remote_cwd: UNC path accepted in remote task configuration" {
    // Tests that remote_cwd can use UNC paths
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.test]
        \\description = "Remote test with UNC path"
        \\cmd = "echo hello"
        \\remote = "ssh://example.com"
        \\remote_cwd = "\\\\server\\share\\project"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "workspace: UNC path in member directory" {
    // Tests that workspace members can reside on UNC paths
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[workspace]
        \\members = ["\\\\localhost\\share\\project"]
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    // Should not crash on UNC path in workspace members
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Long Path Tests (>260 characters) ─────────────────────────────────────

test "cwd: long path (>260 chars) handled correctly" {
    // Tests that paths exceeding Windows MAX_PATH (260) are handled
    // This requires Windows 10 1607+ with long path support enabled
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a deeply nested directory structure (>260 chars total)
    const deep_path = "a" ** 50 ++ std.fs.path.sep_str ++ "b" ** 50 ++ std.fs.path.sep_str ++ "c" ** 50 ++ std.fs.path.sep_str ++ "d" ** 50;
    tmp.dir.makePath(deep_path) catch |err| {
        // If we can't create the path, skip the test (long paths not enabled)
        if (err == error.NameTooLong or err == error.PathAlreadyExists) return error.SkipZigTest;
        return err;
    };

    const full_deep_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, deep_path });
    defer std.testing.allocator.free(full_deep_path);

    // Create config with long path as cwd
    const toml_content = try std.fmt.allocPrint(std.testing.allocator,
        \\[tasks.test]
        \\cmd = "echo hello"
        \\cwd = "{s}"
        \\
    , .{full_deep_path});
    defer std.testing.allocator.free(toml_content);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    // Should handle long path without crashing
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "workspace: long member path (>260 chars) handled correctly" {
    // Tests that workspace members with long paths work
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a deeply nested directory
    const deep_path = "pkg" ++ std.fs.path.sep_str ++ "a" ** 50 ++ std.fs.path.sep_str ++ "b" ** 50 ++ std.fs.path.sep_str ++ "c" ** 50;
    tmp.dir.makePath(deep_path) catch |err| {
        if (err == error.NameTooLong or err == error.PathAlreadyExists) return error.SkipZigTest;
        return err;
    };

    const member_toml = try std.fs.path.join(std.testing.allocator, &.{ deep_path, "zr.toml" });
    defer std.testing.allocator.free(member_toml);

    try tmp.dir.writeFile(.{ .sub_path = member_toml, .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    const toml_content = try std.fmt.allocPrint(std.testing.allocator,
        \\[workspace]
        \\members = ["{s}"]
        \\
    , .{deep_path});
    defer std.testing.allocator.free(toml_content);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Should list the member even with long path
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Symlink Tests ─────────────────────────────────────────────────────────

test "cwd: symlink to directory resolves correctly" {
    // Tests that cwd can be a symlink to a directory
    // On Windows, this requires Developer Mode or admin privileges
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create real directory
    try tmp.dir.makeDir("real_dir");
    const real_dir_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "real_dir" });
    defer std.testing.allocator.free(real_dir_path);

    // Create symlink (skip if permission denied)
    const symlink_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "link_dir" });
    defer std.testing.allocator.free(symlink_path);

    tmp.dir.symLink(real_dir_path, "link_dir", .{ .is_directory = true }) catch |err| {
        // Skip if symlinks not supported (requires Dev Mode or admin)
        if (err == error.AccessDenied or err == error.Unexpected) return error.SkipZigTest;
        return err;
    };

    // Create config using symlink as cwd
    const toml_content = try std.fmt.allocPrint(std.testing.allocator,
        \\[tasks.test]
        \\cmd = "echo hello"
        \\cwd = "{s}"
        \\
    , .{symlink_path});
    defer std.testing.allocator.free(toml_content);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    // Should resolve symlink correctly
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "workspace: symlink to member directory resolves correctly" {
    // Tests that workspace members can be symlinks
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create real project directory
    try tmp.dir.makeDir("real_project");
    try tmp.dir.writeFile(.{ .sub_path = "real_project/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    const real_project_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "real_project" });
    defer std.testing.allocator.free(real_project_path);

    // Create symlink
    const link_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "linked_project" });
    defer std.testing.allocator.free(link_path);

    tmp.dir.symLink(real_project_path, "linked_project", .{ .is_directory = true }) catch |err| {
        if (err == error.AccessDenied or err == error.Unexpected) return error.SkipZigTest;
        return err;
    };

    const toml_content =
        \\[workspace]
        \\members = ["linked_project"]
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Should find and list the linked member
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "linked_project") != null);
}

// ── Mixed Path Format Tests ───────────────────────────────────────────────

test "cwd: mixed forward and backward slashes normalized" {
    // Tests that Windows paths with mixed separators are handled
    // Windows accepts both / and \, but should normalize internally
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makeDir("subdir");

    // Use mixed separators (Windows allows this, but it's messy)
    const mixed_path = try std.fmt.allocPrint(std.testing.allocator, "{s}\\subdir/nested", .{tmp_path});
    defer std.testing.allocator.free(mixed_path);

    const toml_content = try std.fmt.allocPrint(std.testing.allocator,
        \\[tasks.test]
        \\cmd = "echo hello"
        \\cwd = "{s}"
        \\
    , .{mixed_path});
    defer std.testing.allocator.free(toml_content);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    // Should handle mixed separators gracefully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "workspace: glob pattern with backslash separator on Windows" {
    // Tests that glob patterns use Windows backslash separator
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("packages\\core");
    try tmp.dir.writeFile(.{ .sub_path = "packages\\core\\zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    // Use Windows-style glob pattern
    const toml_content =
        \\[workspace]
        \\members = ["packages\\*"]
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Should find member using backslash glob
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "core") != null);
}
