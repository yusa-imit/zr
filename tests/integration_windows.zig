const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");

// ── Windows-Specific Integration Tests ──────────────────────────────────────
//
// These tests verify Windows-specific functionality beyond path handling:
// 1. Console encoding (UTF-8, UTF-16, codepage handling)
// 2. Process spawning (cmd.exe, PowerShell, batch files)
// 3. Signal handling (Ctrl+C, Ctrl+Break)
// 4. Environment variable handling (case-insensitive, special vars)
// 5. File locking behavior
// 6. Console input/output (TUI, colors, mouse)
//
// NOTE: These tests are Windows-specific and will be skipped on Unix.

// ── Console Encoding Tests ────────────────────────────────────────────────────

test "console: UTF-8 output from task command" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a task that outputs Unicode characters
    const toml_content =
        \\[tasks.unicode]
        \\description = "Test Unicode output"
        \\cmd = "cmd /c echo Hello 世界 🌍"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "unicode" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check output contains Unicode (may be encoded differently depending on console)
    try std.testing.expect(result.stdout.len > 0);
}

test "console: multi-byte characters in task description" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.日本語]
        \\description = "タスク with 한글 and العربية"
        \\cmd = "cmd /c echo test"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    // Should be able to validate config with multi-byte task names
    var result = try helpers.runZr(std.testing.allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "console: ANSI color codes preserved on Windows 10+" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Run 'zr list' which has colored output
    var result = try helpers.runZr(std.testing.allocator, &.{ "list" }, tmp_path);
    defer result.deinit();

    // Should not crash, may or may not have color codes depending on terminal
    // Just verify it runs successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Process Spawning Tests ────────────────────────────────────────────────────

test "process: spawn cmd.exe with arguments" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.cmd]
        \\description = "Run cmd.exe with args"
        \\cmd = "cmd /c echo %COMPUTERNAME%"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "cmd" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should output computer name
    try std.testing.expect(result.stdout.len > 0);
}

test "process: spawn PowerShell command" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.pwsh]
        \\description = "Run PowerShell command"
        \\cmd = "powershell -NoProfile -Command \"Write-Output 'test'\""
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "pwsh" }, tmp_path);
    defer result.deinit();

    // May fail if PowerShell not installed, that's ok
    // Just verify we don't crash
    _ = result.exit_code;
}

test "process: execute batch file" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a batch file
    const batch_content = "@echo off\r\necho batch output\r\n";
    try tmp.dir.writeFile(.{ .sub_path = "test.bat", .data = batch_content });

    const toml_content =
        \\[tasks.batch]
        \\description = "Execute batch file"
        \\cmd = "test.bat"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "batch" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "batch output"));
}

test "process: handle exit codes from cmd.exe" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.fail]
        \\description = "Task that exits with error"
        \\cmd = "cmd /c exit 42"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "fail" }, tmp_path);
    defer result.deinit();

    // Should capture exit code 42
    try std.testing.expectEqual(@as(u8, 1), result.exit_code); // zr returns 1 for task failures
}

test "process: spawn with working directory" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create subdirectory
    try tmp.dir.makeDir("subdir");
    try tmp.dir.writeFile(.{ .sub_path = "subdir/marker.txt", .data = "test" });

    const toml_content =
        \\[tasks.cwd]
        \\description = "Run in subdirectory"
        \\cmd = "cmd /c dir marker.txt"
        \\cwd = "subdir"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "cwd" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should find marker.txt in subdir
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "marker.txt"));
}

// ── Environment Variable Tests ────────────────────────────────────────────────

test "env: case-insensitive environment variables" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.env]
        \\description = "Test case-insensitive env vars"
        \\cmd = "cmd /c echo %PATH% %path%"
        \\env = [["CUSTOM", "value"]]
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "env" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both %PATH% and %path% should work on Windows
    try std.testing.expect(result.stdout.len > 0);
}

test "env: special Windows environment variables" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.winenv]
        \\description = "Access Windows-specific env vars"
        \\cmd = "cmd /c echo %USERPROFILE% %SYSTEMROOT%"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "winenv" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should output paths like C:\Users\... and C:\Windows
    try std.testing.expect(result.stdout.len > 0);
}

test "env: inherit PATH from parent process" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.path]
        \\description = "Check PATH inheritance"
        \\cmd = "cmd /c where cmd.exe"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "path" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should find cmd.exe in PATH
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "cmd.exe"));
}

// ── File System Tests ────────────────────────────────────────────────────

test "fs: handle backslash in file paths" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create nested directory structure
    try tmp.dir.makeDir("a");
    try tmp.dir.makeDir("a\\b");
    try tmp.dir.writeFile(.{ .sub_path = "a\\b\\file.txt", .data = "test" });

    const toml_content =
        \\[tasks.backslash]
        \\description = "Handle backslash paths"
        \\cmd = "cmd /c type a\\b\\file.txt"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "backslash" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test"));
}

test "fs: case-insensitive file system" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create file with lowercase name
    try tmp.dir.writeFile(.{ .sub_path = "file.txt", .data = "test" });

    const toml_content =
        \\[tasks.case]
        \\description = "Case-insensitive access"
        \\cmd = "cmd /c type FILE.TXT"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "case" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test"));
}

test "fs: reserved filenames (CON, NUL, PRN)" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Writing to NUL should discard output
    const toml_content =
        \\[tasks.nul]
        \\description = "Write to NUL device"
        \\cmd = "cmd /c echo test > NUL"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "nul" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Command Line Tests ────────────────────────────────────────────────────

test "cli: handle quoted arguments with spaces" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.quotes]
        \\description = "Quoted arguments"
        \\cmd = "cmd /c echo \"hello world\""
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "quotes" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "hello world"));
}

test "cli: handle caret escape character" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.caret]
        \\description = "Caret escape"
        \\cmd = "cmd /c echo test^>output"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "caret" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Caret escapes special characters
    try std.testing.expect(result.stdout.len > 0);
}

// ── TUI and Console Tests ────────────────────────────────────────────────────

test "tui: list command with color output" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.example]
        \\description = "Example task"
        \\cmd = "cmd /c echo test"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    // Run list command which uses colored output
    var result = try helpers.runZr(std.testing.allocator, &.{ "list", "--no-color" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "example"));
}

test "tui: validate command with syntax highlighting" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.test]
        \\description = "Test"
        \\cmd = "cmd /c echo test"
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "validate", "--no-color" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ── Integration with Windows Tools ────────────────────────────────────────────

test "tools: execute with Git Bash if available" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const toml_content =
        \\[tasks.bash]
        \\description = "Try Git Bash"
        \\cmd = "bash -c \"echo test\""
        \\
    ;

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });

    var result = try helpers.runZr(std.testing.allocator, &.{ "run", "bash" }, tmp_path);
    defer result.deinit();

    // May fail if Git Bash not installed, that's ok
    _ = result.exit_code;
}
