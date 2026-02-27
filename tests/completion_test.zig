const std = @import("std");
const helpers = @import("helpers.zig");

test "completion: requires shell argument" {
    var result = try helpers.runZr(std.testing.allocator, &.{"completion"}, null);
    defer result.deinit();

    // Should fail when no shell specified
    try std.testing.expect(result.exit_code != 0);
}

test "completion: bash generates valid bash completion script" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "completion", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "_zr_completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "complete -F _zr_completion zr") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "COMPREPLY") != null);
}

test "completion: zsh generates valid zsh completion script" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "completion", "zsh" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "#compdef zr") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "_zr") != null);
    try std.testing.expect(result.stdout.len > 100); // Non-trivial script
}

test "completion: fish generates valid fish completion script" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "completion", "fish" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "complete -c zr") != null);
    try std.testing.expect(result.stdout.len > 100); // Non-trivial script
}

test "completion: unsupported shell returns error" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "completion", "powershell" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown shell") != null);
}

test "completion: all shells generate non-empty output" {
    const shells = [_][]const u8{ "bash", "zsh", "fish" };
    for (shells) |shell| {
        var result = try helpers.runZr(std.testing.allocator, &.{ "completion", shell }, null);
        defer result.deinit();

        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
        try std.testing.expect(result.stdout.len > 50);
    }
}

test "completion: bash completion includes common commands" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "completion", "bash" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check for key commands
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "run") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "list") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "graph") != null);
}
