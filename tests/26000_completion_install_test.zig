const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrEnv = helpers.runZrEnv;

// ── Shell Completion Installation Tests ────────────────────────────────────
//
// Tests for `zr completion --install <shell>` feature (v1.97.0 milestone):
// 1. --install bash appends eval line to $HOME/.bashrc
// 2. --install zsh appends eval line to $HOME/.zshrc
// 3. --install fish creates $HOME/.config/fish/completions/zr.fish with script
// 4. --install bash is idempotent (second run doesn't duplicate entry)
// 5. --install unknown shell fails with non-zero exit code
// 6. success output mentions install path (e.g., "Installed bash completion to ~/.bashrc")
//

test "26000: zr completion --install bash appends eval line to ~/.bashrc" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a mock HOME directory structure
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", tmp_path);

    // Run: zr completion --install bash
    var result = try runZrEnv(allocator, &.{ "completion", "--install", "bash" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed with exit code 0
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that ~/.bashrc was created/modified
    const bashrc_content = tmp.dir.readFileAlloc(allocator, ".bashrc", 4096) catch |err| {
        if (err == error.FileNotFound) {
            return error.BashrcNotCreated;
        }
        return err;
    };
    defer allocator.free(bashrc_content);

    // Bashrc should contain the eval line
    try std.testing.expect(std.mem.indexOf(u8, bashrc_content, "eval") != null);
    try std.testing.expect(std.mem.indexOf(u8, bashrc_content, "zr completion bash") != null);
}

test "26001: zr completion --install zsh appends eval line to ~/.zshrc" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a mock HOME directory structure
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", tmp_path);

    // Run: zr completion --install zsh
    var result = try runZrEnv(allocator, &.{ "completion", "--install", "zsh" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed with exit code 0
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that ~/.zshrc was created/modified
    const zshrc_content = tmp.dir.readFileAlloc(allocator, ".zshrc", 4096) catch |err| {
        if (err == error.FileNotFound) {
            return error.ZshrcNotCreated;
        }
        return err;
    };
    defer allocator.free(zshrc_content);

    // Zshrc should contain the eval line
    try std.testing.expect(std.mem.indexOf(u8, zshrc_content, "eval") != null);
    try std.testing.expect(std.mem.indexOf(u8, zshrc_content, "zr completion zsh") != null);
}

test "26002: zr completion --install fish creates ~/.config/fish/completions/zr.fish" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a mock HOME directory structure
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", tmp_path);

    // Run: zr completion --install fish
    var result = try runZrEnv(allocator, &.{ "completion", "--install", "fish" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed with exit code 0
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that ~/.config/fish/completions/zr.fish was created
    // First check that .config/fish/completions exists
    var fish_dir = tmp.dir.openDir(".config/fish/completions", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return error.FishCompletionDirNotCreated;
        }
        return err;
    };
    defer fish_dir.close();

    // Check that zr.fish was created
    const zr_fish_content = fish_dir.readFileAlloc(allocator, "zr.fish", 8192) catch |err| {
        if (err == error.FileNotFound) {
            return error.ZrFishNotCreated;
        }
        return err;
    };
    defer allocator.free(zr_fish_content);

    // Fish completion should contain completion-related content
    try std.testing.expect(zr_fish_content.len > 0);
    // Fish completions typically use 'complete' commands
    try std.testing.expect(std.mem.indexOf(u8, zr_fish_content, "complete") != null);
}

test "26003: zr completion --install bash is idempotent (no duplicate entries)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a mock HOME directory structure
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", tmp_path);

    // First install
    var result1 = try runZrEnv(allocator, &.{ "completion", "--install", "bash" }, tmp_path, &env_map);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);

    // Second install
    var result2 = try runZrEnv(allocator, &.{ "completion", "--install", "bash" }, tmp_path, &env_map);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);

    // Check bashrc content
    const bashrc_content = try tmp.dir.readFileAlloc(allocator, ".bashrc", 4096);
    defer allocator.free(bashrc_content);

    // Count occurrences of the eval line
    var count: usize = 0;
    var offset: usize = 0;
    const search_str = "eval \"$(zr completion bash)\"";
    while (std.mem.indexOf(u8, bashrc_content[offset..], search_str)) |idx| {
        count += 1;
        offset += idx + 1;
    }

    // Should have exactly 1 occurrence (idempotent)
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "26004: zr completion --install unknown fails with non-zero exit code" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a mock HOME directory structure
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", tmp_path);

    // Run: zr completion --install unknown
    var result = try runZrEnv(allocator, &.{ "completion", "--install", "unknown" }, tmp_path, &env_map);
    defer result.deinit();

    // Should fail with non-zero exit code
    try std.testing.expect(result.exit_code != 0);
}

test "26005: zr completion --install bash success output mentions install path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a mock HOME directory structure
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", tmp_path);

    // Run: zr completion --install bash
    var result = try runZrEnv(allocator, &.{ "completion", "--install", "bash" }, tmp_path, &env_map);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should mention "bash" and either "~/.bashrc" or the actual path
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "bash") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bashrc") != null or std.mem.indexOf(u8, output, ".bashrc") != null);
}
