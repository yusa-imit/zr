const std = @import("std");
const helpers = @import("helpers.zig");

test "shell-hook: requires shell argument" {
    var result = try helpers.runZr(std.testing.allocator, &.{"shell-hook"}, null);
    defer result.deinit();

    // Should fail when no shell specified
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "shell type required") != null or
        std.mem.indexOf(u8, result.stderr, "required") != null);
}

test "shell-hook: bash generates valid bash hook code" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify bash-specific content
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "PROMPT_COMMAND") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "_zr_load_hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr.toml") != null);
}

test "shell-hook: zsh generates valid zsh hook code" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify zsh-specific content
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "add-zsh-hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "chpwd") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "_zr_load_hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr.toml") != null);
}

test "shell-hook: fish generates valid fish hook code" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify fish-specific content
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "function") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fish_postexec") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "_zr_load_hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr.toml") != null);
}

test "shell-hook: unknown shell returns error" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "powershell" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown shell") != null or
        std.mem.indexOf(u8, result.stderr, "powershell") != null);
}

test "shell-hook: case-sensitive shell names" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "BASH" }, null);
    defer result.deinit();

    // Shell names are case-sensitive, should reject uppercase
    try std.testing.expect(result.exit_code != 0);
}

test "shell-hook: all shells produce non-trivial output" {
    const shells = [_][]const u8{ "bash", "zsh", "fish" };
    for (shells) |shell| {
        var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", shell }, null);
        defer result.deinit();

        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
        // Each shell should produce significant output (at least 200 bytes)
        try std.testing.expect(result.stdout.len > 200);
    }
}

test "shell-hook: bash hook references ZR_HOOK_CACHE_DIR" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ZR_HOOK_CACHE_DIR") != null);
}

test "shell-hook: zsh hook references ZR_HOOK_CACHE_DIR" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ZR_HOOK_CACHE_DIR") != null);
}

test "shell-hook: fish hook references ZR_HOOK_CACHE_DIR" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ZR_HOOK_CACHE_DIR") != null);
}

test "shell-hook: bash hook provides fallback cache directory" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should have fallback like .zr_hooks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, ".zr_hooks") != null);
}

test "shell-hook: bash hook uses source for loading files" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "source") != null);
}

test "shell-hook: zsh hook uses source for loading files" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "source") != null);
}

test "shell-hook: fish hook uses source for loading files" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "source") != null);
}

test "shell-hook: bash hook handles root directory (/)" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Loop should terminate at root
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "!= \"/\"") != null or
        std.mem.indexOf(u8, result.stdout, "!= '/'") != null);
}

test "shell-hook: zsh hook handles root directory (/)" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Loop should terminate at root
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "!= \"/\"") != null or
        std.mem.indexOf(u8, result.stdout, "!= '/'") != null);
}

test "shell-hook: fish hook handles root directory (/)" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Loop should terminate at root
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "!= \"/\"") != null or
        std.mem.indexOf(u8, result.stdout, "!= '/'") != null);
}

test "shell-hook: bash hook computes directory hash" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should compute a hash of the directory path
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "md5sum") != null);
}

test "shell-hook: zsh hook computes directory hash" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should compute a hash of the directory path
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "md5sum") != null);
}

test "shell-hook: fish hook computes directory hash" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should compute a hash of the directory path
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "md5sum") != null);
}

test "shell-hook: bash hook has no syntax errors (basic check)" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const code = result.stdout;
    // Basic sanity: should not have unmatched brackets
    var open_brackets: i32 = 0;
    for (code) |c| {
        if (c == '{') open_brackets += 1;
        if (c == '}') open_brackets -= 1;
    }
    try std.testing.expectEqual(@as(i32, 0), open_brackets);
}

test "shell-hook: zsh hook has no syntax errors (basic check)" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const code = result.stdout;
    // Basic sanity: should not have unmatched brackets
    var open_brackets: i32 = 0;
    for (code) |c| {
        if (c == '{') open_brackets += 1;
        if (c == '}') open_brackets -= 1;
    }
    try std.testing.expectEqual(@as(i32, 0), open_brackets);
}

test "shell-hook: fish hook has no syntax errors (basic check)" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const code = result.stdout;
    // Fish uses 'end' to close blocks; basic sanity check
    var function_count: usize = 0;
    var end_count: usize = 0;

    if (std.mem.indexOf(u8, code, "function") != null) function_count += 1;
    var search_pos: usize = 0;
    while (std.mem.indexOf(u8, code[search_pos..], "end") != null) {
        if (std.mem.indexOf(u8, code[search_pos..], "end")) |pos| {
            end_count += 1;
            search_pos += pos + 3;
        } else break;
    }
    // Should have reasonable balance
    try std.testing.expect(end_count >= function_count);
}

test "shell-hook: bash hook installs on first run" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Hook should be self-installing via PROMPT_COMMAND
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "PROMPT_COMMAND") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, ":") != null); // Append syntax
}

test "shell-hook: zsh hook installs on startup" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should have startup call
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "add-zsh-hook") != null);
    // Should call function on startup
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOf(u8, result.stdout[search_pos..], "_zr_load_hook") != null) {
        count += 1;
        if (std.mem.indexOf(u8, result.stdout[search_pos..], "_zr_load_hook")) |pos| {
            search_pos += pos + 13;
            if (search_pos >= result.stdout.len) break;
        } else break;
    }
    try std.testing.expect(count >= 2); // At least: hook definition + startup call
}

test "shell-hook: fish hook installs on startup" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should have startup call
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fish_postexec") != null);
    // Should call function on startup
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOf(u8, result.stdout[search_pos..], "_zr_load_hook") != null) {
        count += 1;
        if (std.mem.indexOf(u8, result.stdout[search_pos..], "_zr_load_hook")) |pos| {
            search_pos += pos + 13;
            if (search_pos >= result.stdout.len) break;
        } else break;
    }
    try std.testing.expect(count >= 2); // At least: function definition + startup call
}

test "shell-hook: bash hook comment mentions purpose" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should have explanatory comment
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "#") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr") != null or std.mem.indexOf(u8, result.stdout, "environment") != null);
}

test "shell-hook: multiple calls produce identical output" {
    var result1 = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result1.deinit();
    var result2 = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result2.deinit();

    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    // Output should be identical (deterministic)
    try std.testing.expectEqualSlices(u8, result1.stdout, result2.stdout);
}

test "shell-hook: different shells produce different output" {
    var bash_result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer bash_result.deinit();
    var zsh_result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "zsh" }, null);
    defer zsh_result.deinit();
    var fish_result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "fish" }, null);
    defer fish_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), bash_result.exit_code);
    try std.testing.expectEqual(@as(u8, 0), zsh_result.exit_code);
    try std.testing.expectEqual(@as(u8, 0), fish_result.exit_code);

    // Outputs should be different
    try std.testing.expect(!std.mem.eql(u8, bash_result.stdout, zsh_result.stdout));
    try std.testing.expect(!std.mem.eql(u8, bash_result.stdout, fish_result.stdout));
    try std.testing.expect(!std.mem.eql(u8, zsh_result.stdout, fish_result.stdout));
}

test "shell-hook: help/version flags should not confuse shell argument" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "--help", "bash" }, null);
    defer result.deinit();

    // Should still fail or complain about invalid shell "--help"
    // (we're testing argument ordering, not that --help works here)
    try std.testing.expect(result.exit_code != 0 or std.mem.indexOf(u8, result.stdout, "--help") == null);
}

test "shell-hook: empty shell argument shows error" {
    // This uses the wrapper to test with empty args
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
}

test "shell-hook: shell name with spaces is rejected" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash zsh" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown shell") != null);
}

test "shell-hook: misspelled shell names are rejected" {
    const bad_shells = [_][]const u8{ "bah", "sh", "ksh", "tcsh", "psh" };
    for (bad_shells) |bad_shell| {
        var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", bad_shell }, null);
        defer result.deinit();

        try std.testing.expect(result.exit_code != 0);
    }
}

test "shell-hook: outputs to stdout, not stderr" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Shell code should be on stdout, not stderr
    try std.testing.expect(result.stdout.len > 0);
    try std.testing.expect(result.stderr.len == 0);
}

test "shell-hook: bash hook uses [[ ]] syntax" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const code = result.stdout;

    // Bash hooks can use [[ ]] which is bash-specific (more powerful than POSIX [ ])
    // This is fine since it's explicitly a bash hook
    try std.testing.expect(std.mem.indexOf(u8, code, "[[") != null);
}

test "shell-hook: all outputs end with newline" {
    const shells = [_][]const u8{ "bash", "zsh", "fish" };
    for (shells) |shell| {
        var result = try helpers.runZr(std.testing.allocator, &.{ "shell-hook", shell }, null);
        defer result.deinit();

        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
        try std.testing.expect(result.stdout.len > 0);
        try std.testing.expectEqual(@as(u8, '\n'), result.stdout[result.stdout.len - 1]);
    }
}
