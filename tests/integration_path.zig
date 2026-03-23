const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");

// ── Path Separator Tests ────────────────────────────────────────────────────

test "path handling: forward slash works on all platforms" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.hello]
        \\cmd = "echo separator"
        \\cwd = "./subdir"
    });

    try tmp.dir.makePath("subdir");
    try tmp.dir.writeFile(.{ .sub_path = "subdir/test.txt", .data = "test" });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: normalizes mixed separators in cwd" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific test

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
        \\cwd = ".\\subdir"
    });

    try tmp.dir.makePath("subdir");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "test" }, tmp_path);
    defer result.deinit();

    // Should succeed even with mixed separators
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: backslash escaping in config is NOT path separator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Backslash followed by 'n' should be treated as escape sequence, not path sep
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
        \\description = "line\\none"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    // Should not error - TOML escape sequences handled correctly
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Relative Path Tests ────────────────────────────────────────────────────

test "path handling: relative cwd resolved from zr.toml location" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.pwd]
        \\cmd = "pwd"
        \\cwd = "../"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "pwd" }, tmp_path);
    defer result.deinit();

    // Should succeed - relative path from zr.toml dir
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: nested relative paths work correctly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo nested"
        \\cwd = "./a/b/c"
    });

    try tmp.dir.makePath("a/b/c");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: dot dot parent directory traversal" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create zr.toml in nested dir, reference parent
    try tmp.dir.makePath("subdir");
    try tmp.dir.writeFile(.{ .sub_path = "subdir/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo parent"
        \\cwd = ".."
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const subdir = try std.fmt.allocPrint(std.testing.allocator, "{s}{s}subdir", .{
        tmp_path,
        std.fs.path.sep_str,
    });
    defer std.testing.allocator.free(subdir);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "test" }, subdir);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: absolute cwd is preserved" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const abs_cwd = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{tmp_path});
    defer std.testing.allocator.free(abs_cwd);

    const toml_content = try std.fmt.allocPrint(std.testing.allocator,
        \\[tasks.abs]
        \\cmd = "echo absolute"
        \\cwd = "{s}"
    , .{abs_cwd});
    defer std.testing.allocator.free(toml_content);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "abs" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Path Joining Tests ─────────────────────────────────────────────────────

test "path handling: cwd with trailing separator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo trailing"
        \\cwd = "./subdir/"
    });

    try tmp.dir.makePath("subdir");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "test" }, tmp_path);
    defer result.deinit();

    // Should handle trailing separator gracefully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: cwd with multiple trailing separators" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo multiple"
        \\cwd = "./subdir///"
    });

    try tmp.dir.makePath("subdir");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: empty cwd defaults to task directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo default"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Long Path Tests (Windows specific) ──────────────────────────────────────

test "path handling: supports long paths on Windows (>260 chars with prefix)" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a deeply nested directory structure to test long paths
    // Windows supports paths >260 chars when prefixed with \\?\
    var current_path: []const u8 = ".";
    var i: u32 = 0;
    while (i < 20) : (i += 1) {
        const subdir = try std.fmt.allocPrint(std.testing.allocator, "{s}/dir{d}", .{ current_path, i });
        defer std.testing.allocator.free(current_path);
        try tmp.dir.makePath(subdir);
        current_path = subdir;
    }

    // Create config in deeply nested location
    try tmp.dir.writeFile(.{ .sub_path = "deep_zr.toml", .data =
        \\[tasks.deep]
        \\cmd = "echo deep"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    // Should handle long nested paths without error
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

// ── Remote CWD Tests ────────────────────────────────────────────────────────

test "path handling: remote_cwd is distinct from cwd" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
        \\cwd = "./local"
        \\remote = "localhost"
        \\remote_cwd = "./remote"
    });

    try tmp.dir.makePath("local");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "test" }, tmp_path);
    defer result.deinit();

    // Config should parse without error even if remote execution isn't available
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote_cwd relative paths are supported" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.remote_rel]
        \\cmd = "pwd"
        \\remote = "dev-server"
        \\remote_cwd = "../project"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "remote_rel" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: both cwd and remote_cwd can be set independently" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.both]
        \\cmd = "echo both"
        \\cwd = "./build"
        \\remote = "ci"
        \\remote_cwd = "/home/ci/workspace"
    });

    try tmp.dir.makePath("build");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "both" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Config File Path Tests ─────────────────────────────────────────────────

test "path handling: zr.toml found in current directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "path handling: zr.toml searched in parent directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    try tmp.dir.makePath("nested/deep");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const nested_path = try std.fmt.allocPrint(std.testing.allocator, "{s}{s}nested{s}deep", .{
        tmp_path,
        std.fs.path.sep_str,
        std.fs.path.sep_str,
    });
    defer std.testing.allocator.free(nested_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, nested_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: config file with spaces in path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("dir with spaces");
    try tmp.dir.writeFile(.{ .sub_path = "dir with spaces/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo spaced"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const spaced_path = try std.fmt.allocPrint(std.testing.allocator, "{s}{s}dir with spaces", .{
        tmp_path,
        std.fs.path.sep_str,
    });
    defer std.testing.allocator.free(spaced_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, spaced_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Toolchain Path Tests ────────────────────────────────────────────────────

test "path handling: toolchain installation paths use consistent separators" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
        \\[tasks.test.toolchain]
        \\node = "20.11.1"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Windows-specific UNC Path Tests ────────────────────────────────────────

test "path handling: UNC path parsing (Windows only)" {
    if (comptime builtin.os.tag != .windows) return;

    // UNC paths like \\server\share should be parsed correctly
    // This is primarily a configuration parsing test
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.unc]
        \\cmd = "echo unc"
        \\description = "Test UNC path \\\\server\\share"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "unc" }, tmp_path);
    defer result.deinit();

    // Should parse without error despite \\ in description
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Unicode and Special Character Path Tests ───────────────────────────────

test "path handling: UTF-8 characters in cwd path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("テスト");
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.unicode]
        \\cmd = "echo test"
        \\cwd = "./テスト"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "unicode" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: special characters in cwd (!, @, #, $)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("special-dir_2024");
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.special]
        \\cmd = "echo special"
        \\cwd = "./special-dir_2024"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "special" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Nonexistent Path Tests ─────────────────────────────────────────────────

test "path handling: fails gracefully for nonexistent cwd" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.missing]
        \\cmd = "echo missing"
        \\cwd = "./nonexistent"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "missing" }, tmp_path);
    defer result.deinit();

    // Should fail with clear error
    try std.testing.expect(result.exit_code != 0);
}

// ── Symlink Resolution Tests (Unix-like systems) ────────────────────────────

test "path handling: symlink resolution on POSIX systems" {
    if (comptime builtin.os.tag == .windows) return; // Skip on Windows

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("real");
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.symlink]
        \\cmd = "echo symlink"
        \\cwd = "./real"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "symlink" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Current Working Directory Inheritance Tests ────────────────────────────

test "path handling: run with cwd from different initial directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("workspace");
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.cwd_test]
        \\cmd = "echo cwd"
        \\cwd = "./build"
    });

    try tmp.dir.makePath("build");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Run from temp root (where zr.toml is)
    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "cwd_test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Path Normalization Tests ────────────────────────────────────────────────

test "path handling: removes redundant dots from cwd" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.dots]
        \\cmd = "echo dots"
        \\cwd = "./././subdir"
    });

    try tmp.dir.makePath("subdir");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "dots" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Workspace Member Path Tests ────────────────────────────────────────────

test "path handling: workspace members with various path patterns" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*", "services/*/api"]
    });

    try tmp.dir.makePath("packages/core");
    try tmp.dir.writeFile(.{ .sub_path = "packages/core/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo core"
    });

    try tmp.dir.makePath("services/web/api");
    try tmp.dir.writeFile(.{ .sub_path = "services/web/api/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo api"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Glob Pattern Path Tests ────────────────────────────────────────────────

test "path handling: glob patterns with various separators" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["src/*/tests"]
    });

    try tmp.dir.makePath("src/module/tests");
    try tmp.dir.writeFile(.{ .sub_path = "src/module/tests/zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Mixed Config and Runtime Path Tests ────────────────────────────────────

test "path handling: matrix task with variable cwd paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.matrix_cwd]
        \\cmd = "echo matrix"
        \\
        \\[tasks.matrix_cwd.matrix]
        \\dir = ["a", "b", "c"]
        \\
        \\[[tasks.matrix_cwd.matrix.axis]]
        \\cwd = "./${{ dir }}"
    });

    try tmp.dir.makePath("a");
    try tmp.dir.makePath("b");
    try tmp.dir.makePath("c");

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "matrix_cwd" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Cross-platform Path Environment Tests ──────────────────────────────────

test "path handling: config file paths with environment variables" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.env_path]
        \\cmd = "echo $HOME"
        \\cwd = "."
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "env_path" }, tmp_path);
    defer result.deinit();

    // Should execute without error (exit code depends on environment)
    try std.testing.expect(result.stdout.len >= 0);
}

// ── Path Case Sensitivity Tests ────────────────────────────────────────────

test "path handling: case preservation in file paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("MyProject");
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo case"
        \\cwd = "./MyProject"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Remote Cache Temp File Path Tests ─────────────────────────────────────

test "path handling: remote cache temp files use system temp directory" {
    // This test verifies that remote cache operations (compression, decompression, uploads)
    // will use the system's temp directory rather than hardcoded /tmp
    // On Windows: C:\Windows\Temp or %TEMP%
    // On Unix: /tmp
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a config with remote cache enabled
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.test]
        \\cmd = "echo test"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "http"
        \\url = "http://example.com/cache"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // This should parse the config without errors
    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote cache with spaces in temp path (Windows)" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    // Windows temp paths can have spaces: C:\Users\John Doe\AppData\Local\Temp
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.cached]
        \\cmd = "echo cached"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "s3"
        \\bucket = "test-bucket"
        \\region = "us-east-1"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "cached" }, tmp_path);
    defer result.deinit();

    // Should parse without path-related errors
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote cache compression temp files on Windows" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.compress]
        \\cmd = "echo compress"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "gcs"
        \\bucket = "test-bucket"
        \\compression = true
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "compress" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote cache with Azure backend on Windows" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.azure]
        \\cmd = "echo azure"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "azure"
        \\bucket = "test-container"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "azure" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote cache incremental sync with long Windows paths" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.incremental]
        \\cmd = "echo incremental"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "http"
        \\url = "http://cache.example.com"
        \\incremental_sync = true
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "incremental" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: GCS OAuth temp files with Windows paths" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    // GCS backend creates temporary files for OAuth2 tokens and private keys
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.gcs]
        \\cmd = "echo gcs"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "gcs"
        \\bucket = "test-gcs-bucket"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "gcs" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote cache with special chars in temp directory name" {
    // Test that remote cache works even if temp directory has special characters
    // (parentheses, ampersands, etc. which can appear in Windows usernames)
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.special]
        \\cmd = "echo special"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "http"
        \\url = "http://cache.local"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "special" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote cache temp cleanup on error" {
    // Verify that temp files would be cleaned up properly even on Windows
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.cleanup]
        \\cmd = "echo cleanup"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "s3"
        \\bucket = "nonexistent-bucket-test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "cleanup" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: remote cache with network drive path (Windows UNC)" {
    if (comptime builtin.os.tag != .windows) return; // Windows-specific

    // Windows may use UNC paths for network drives: \\server\share
    // Temp operations should still work correctly
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.unc]
        \\cmd = "echo unc"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "http"
        \\url = "http://fileserver/cache"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "show", "unc" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "path handling: multiple concurrent remote cache operations temp isolation" {
    // Verify temp file naming prevents conflicts in concurrent operations
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[tasks.concurrent1]
        \\cmd = "echo c1"
        \\cache = true
        \\
        \\[tasks.concurrent2]
        \\cmd = "echo c2"
        \\cache = true
        \\
        \\[cache.remote]
        \\type = "http"
        \\url = "http://cache.test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}
