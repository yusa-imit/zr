const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

// ── Joined-Argv Normalization Tests (issue #100) ─────────────────────────────
//
// Verifies that zr transparently handles the case where multiple argv elements
// arrive pre-joined as a single space-separated string (macOS arm64 issue).
// Simulated by passing a space-containing string as a single argv element.
//
// 35000: "cache status" as one arg dispatches to cache status (not "Unknown command")
// 35001: "list --help" as one arg dispatches correctly
// 35002: "version" as one arg still works (single-word command unaffected)
// 35003: unknown joined command gives "Unknown command" for first token only
// 35004: "cache clear" as one arg dispatches to cache clear
//

// Test 35000: joined "cache status" dispatches to cache status, not unknown command
test "joined-argv: cache status as single arg dispatches correctly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
        \\
    ;
    const tmp_path = try helpers.writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(tmp_path);

    const cwd_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(cwd_path);

    // Pass "cache status" as a single argv element — simulates the joined-argv bug
    var result = try runZr(testing.allocator, &.{"cache status"}, cwd_path);
    defer result.deinit();

    // Should NOT fail with "Unknown command: cache status"
    try testing.expect(!std.mem.containsAtLeast(u8, result.stderr, 1, "Unknown command: cache status"));
    // Exit code 0 = dispatched and ran (cache status always succeeds, even with empty cache)
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 35001: joined "list --help" dispatches to list help, not unknown command
test "joined-argv: list --help as single arg dispatches correctly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
        \\
    ;
    const tmp_path = try helpers.writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(tmp_path);

    const cwd_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(cwd_path);

    // "list --help" as a single argv element
    var result = try runZr(testing.allocator, &.{"list --help"}, cwd_path);
    defer result.deinit();

    try testing.expect(!std.mem.containsAtLeast(u8, result.stderr, 1, "Unknown command"));
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

// Test 35002: single-word command still works (no regression)
test "joined-argv: single-word command unaffected by normalization" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
        \\
    ;
    const tmp_path = try helpers.writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(tmp_path);

    const cwd_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(cwd_path);

    var result = try runZr(testing.allocator, &.{"list"}, cwd_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "build"));
}

// Test 35003: unknown joined command gives "Unknown command" for first token
test "joined-argv: unknown joined command reports first token as unknown" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
        \\
    ;
    const tmp_path = try helpers.writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(tmp_path);

    const cwd_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(cwd_path);

    // "foobar baz" as one arg — neither is a known command; after split, "foobar" is unknown
    var result = try runZr(testing.allocator, &.{"foobar baz"}, cwd_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    // Error should mention "foobar" (first token after split), not "foobar baz"
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Unknown command: foobar"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stderr, 1, "Unknown command: foobar baz"));
}

// Test 35004: joined "cache clear" dispatches to cache clear
test "joined-argv: cache clear as single arg dispatches correctly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
        \\
    ;
    const tmp_path = try helpers.writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(tmp_path);

    const cwd_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(cwd_path);

    // "cache clear" as a single argv element
    var result = try runZr(testing.allocator, &.{"cache clear"}, cwd_path);
    defer result.deinit();

    try testing.expect(!std.mem.containsAtLeast(u8, result.stderr, 1, "Unknown command: cache clear"));
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}
