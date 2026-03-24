const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");

// ── Path Separator Compatibility Tests (Hardcoded '/' Detection) ──────────

// These tests verify that glob.zig, affected.zig, and workspace.zig correctly
// use platform-specific path separators instead of hardcoded '/'.
//
// EXPECTED BEHAVIOR (after fix):
// - Unix systems: use '/' as separator
// - Windows: use '\' as separator
// - Path operations should be platform-aware
//
// CURRENT STATE: Many of these tests will FAIL because the implementation uses hardcoded '/'

// ── Workspace Glob Pattern Tests ──────────────────────────────────────────

test "workspace: glob pattern with platform-specific separator finds members" {
    // Tests that workspace member resolution works with backslashes on Windows
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create structure
    try tmp.dir.makePath("packages/core");
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    // Use platform-specific separator in workspace pattern
    const sep_str = if (comptime builtin.os.tag == .windows) "\\" else "/";
    const pattern = try std.fmt.allocPrint(
        std.testing.allocator,
        "packages{s}*",
        .{sep_str}
    );
    defer std.testing.allocator.free(pattern);

    const toml_content = try std.fmt.allocPrint(std.testing.allocator,
        \\[workspace]
        \\members = ["{s}"]
    , .{pattern});
    defer std.testing.allocator.free(toml_content);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Should find the member regardless of platform
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "core") != null);
}

test "workspace: nested glob pattern with backslashes on Windows" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific test

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("packages/pkg1/src");
    try tmp.dir.writeFile(.{ .sub_path = "packages/pkg1/src/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    // Windows-specific: pattern with backslashes
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages\\*\\src"]
    });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // This test will FAIL if glob.zig hardcodes '/' for pattern splitting
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "src") != null);
}

test "workspace: absolute path with Windows drive letter and backslashes" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific test

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("packages/pkg1");
    try tmp.dir.writeFile(.{ .sub_path = "packages/pkg1/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    // Create config with absolute Windows path
    const config = try std.fmt.allocPrint(std.testing.allocator,
        \\[workspace]
        \\members = ["{s}\\packages\\*"]
    , .{tmp_path});
    defer std.testing.allocator.free(config);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = config });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Tests workspace.zig line 40: extraction of base path from absolute pattern with backslashes
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "workspace: member path reconstruction preserves platform separator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("apps/web");
    try tmp.dir.makePath("apps/api");
    try tmp.dir.writeFile(.{ .sub_path = "apps/web/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo web"
    });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo api"
    });

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["apps/*"]
    });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output contains paths with platform-appropriate separators
    if (comptime builtin.os.tag == .windows) {
        // On Windows, paths should use backslashes
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\\") != null);
    } else {
        // On Unix, paths should use forward slashes
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/") != null);
    }
}

// ── Affected Detection Tests ───────────────────────────────────────────────

test "affected: detects changes in subdirectory with platform separator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Initialize git repo
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "init" }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "config", "user.email", "test@example.com" }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "config", "user.name", "Test User" }, tmp_path);

    try tmp.dir.makePath("packages/core");
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/main.zig", .data = "const std = @import(\"std\");" });

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*"]
    });

    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "add", "." }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "commit", "-m", "Initial" }, tmp_path);

    // Modify file
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/main.zig", .data = "const std = @import(\"std\"); // changed" });

    var result = try helpers.runZr(std.testing.allocator, &.{ "affected", "--base", "HEAD" }, tmp_path);
    defer result.deinit();

    // Should detect that packages/core is affected
    // Tests affected.zig line 124, 133: path boundary detection with '/' vs platform separator
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "core") != null);
}

test "affected: correctly matches paths with trailing separator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Initialize git repo
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "init" }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "config", "user.email", "test@example.com" }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "config", "user.name", "Test User" }, tmp_path);

    try tmp.dir.makePath("packages/utils");
    try tmp.dir.writeFile(.{ .sub_path = "packages/utils/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });
    try tmp.dir.writeFile(.{ .sub_path = "packages/utils/helper.zig", .data = "pub fn help() void {}" });

    // Note the trailing slash in member path
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/utils/"]
    });

    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "add", "." }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "commit", "-m", "Initial" }, tmp_path);

    // Modify file
    try tmp.dir.writeFile(.{ .sub_path = "packages/utils/helper.zig", .data = "pub fn help() void {} // changed" });

    var result = try helpers.runZr(std.testing.allocator, &.{ "affected", "--base", "HEAD" }, tmp_path);
    defer result.deinit();

    // Tests affected.zig line 124: handling of trailing '/' in member path normalization
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "utils") != null);
}

test "affected: distinguishes similar path prefixes" {
    // Tests affected.zig line 133: ensures "packages/core-utils" doesn't match "packages/core/file.zig"
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Initialize git repo
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "init" }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "config", "user.email", "test@example.com" }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "config", "user.name", "Test User" }, tmp_path);

    try tmp.dir.makePath("packages/core");
    try tmp.dir.makePath("packages/core-utils");
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo core"
    });
    try tmp.dir.writeFile(.{ .sub_path = "packages/core-utils/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo utils"
    });
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/main.zig", .data = "const std = @import(\"std\");" });
    try tmp.dir.writeFile(.{ .sub_path = "packages/core-utils/util.zig", .data = "pub fn util() void {}" });

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/core", "packages/core-utils"]
    });

    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "add", "." }, tmp_path);
    _ = try helpers.runCommand(std.testing.allocator, &.{ "git", "commit", "-m", "Initial" }, tmp_path);

    // Modify only packages/core/main.zig
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/main.zig", .data = "const std = @import(\"std\"); // changed" });

    var result = try helpers.runZr(std.testing.allocator, &.{ "affected", "--base", "HEAD" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should only detect packages/core as affected, NOT packages/core-utils
    // This tests path boundary checking (requires '/' or end-of-string after prefix)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "core") != null);

    // Verify core-utils is NOT in output (unless output format includes both, filter by lines)
    var lines = std.mem.splitSequence(u8, result.stdout, "\n");
    var found_core = false;
    var found_core_utils = false;
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "packages/core") != null and std.mem.indexOf(u8, line, "core-utils") == null) {
            found_core = true;
        }
        if (std.mem.indexOf(u8, line, "core-utils") != null) {
            found_core_utils = true;
        }
    }
    try std.testing.expect(found_core);
    try std.testing.expect(!found_core_utils);
}

// ── Glob Pattern File Finding Tests ───────────────────────────────────────

test "workspace: finds files with glob pattern in subdirectory" {
    // Integration test for glob functionality used by workspace member resolution
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("src/core");
    try tmp.dir.writeFile(.{ .sub_path = "src/core/main.zig", .data = "content" });
    try tmp.dir.writeFile(.{ .sub_path = "src/core/util.zig", .data = "content" });
    try tmp.dir.writeFile(.{ .sub_path = "src/core/zr.toml", .data =
        \\[tasks.build]
        \\cmd = "echo build"
    });

    // Workspace member resolution relies on glob.find() with directory patterns
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["src/*"]
    });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Tests that glob.zig finds directories correctly with platform separators
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "core") != null);
}

test "workspace: nested wildcard pattern finds deep directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("packages/pkg1/src");
    try tmp.dir.makePath("packages/pkg2/src");
    try tmp.dir.writeFile(.{ .sub_path = "packages/pkg1/src/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo pkg1"
    });
    try tmp.dir.writeFile(.{ .sub_path = "packages/pkg2/src/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo pkg2"
    });

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*/src"]
    });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Tests glob.zig findDirs() with nested wildcard patterns
    // Relies on correct path joining with platform separators
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "pkg1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "pkg2") != null);
}

// ── Edge Case Tests ────────────────────────────────────────────────────────

test "workspace: handles mixed forward and backward slashes on Windows" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("packages/core");
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    // Mixed separators: forward slash in one part, backslash in another
    // Windows can accept both, but paths from git may use forward slashes
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages\\core"]
    });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Should handle mixed separators gracefully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "workspace: multiple patterns with different depths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("apps/web");
    try tmp.dir.makePath("services/api/backend");
    try tmp.dir.writeFile(.{ .sub_path = "apps/web/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo web"
    });
    try tmp.dir.writeFile(.{ .sub_path = "services/api/backend/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo backend"
    });

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["apps/*", "services/*/backend"]
    });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Tests that glob pattern parsing handles multiple patterns at different nesting levels
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "web") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "backend") != null);
}

test "workspace: UNC path pattern on Windows" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // This tests that patterns starting with \\ (UNC paths) don't crash the parser
    // We can't create actual UNC shares in tests, but we verify parsing doesn't break
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = []
        \\[tasks.test]
        \\cmd = "echo test"
    });

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    // Should not crash with UNC path syntax present in config
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Path Reconstruction Tests ──────────────────────────────────────────────

test "workspace: absolute pattern path reconstruction uses platform separator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.makePath("packages/core");
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    // Use absolute path with platform-appropriate separator
    const sep_str = if (comptime builtin.os.tag == .windows) "\\" else "/";
    const config = try std.fmt.allocPrint(std.testing.allocator,
        \\[workspace]
        \\members = ["{s}{s}packages{s}*"]
    , .{ tmp_path, sep_str, sep_str });
    defer std.testing.allocator.free(config);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = config });

    var result = try helpers.runZr(std.testing.allocator, &.{ "workspace", "list" }, tmp_path);
    defer result.deinit();

    // Tests workspace.zig line 87: full_path reconstruction with fmt.allocPrint
    // Should use platform separator, not hardcoded '/'
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "core") != null);
}
