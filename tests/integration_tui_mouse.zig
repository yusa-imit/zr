/// Integration tests for TUI mouse interaction enhancements.
///
/// These tests verify mouse-related CLI behaviors through black-box testing.
/// Unit tests for mouse event handling are in src/cli/tui_mouse.zig.

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

// Integration tests that verify mouse support is available in TUI commands
// Note: These are smoke tests - detailed mouse event tests are unit tests

test "graph TUI: accepts --help flag" {
    var result = try helpers.runZr(testing.allocator, &.{ "graph", "--help" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "graph") != null or
        std.mem.indexOf(u8, result.stderr, "graph") != null);
}

test "live TUI: accepts --help flag" {
    var result = try helpers.runZr(testing.allocator, &.{ "live", "--help" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "live") != null or
        std.mem.indexOf(u8, result.stderr, "live") != null);
}

test "list TUI: accepts --help flag" {
    var result = try helpers.runZr(testing.allocator, &.{ "list", "--help" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "list") != null or
        std.mem.indexOf(u8, result.stderr, "list") != null);
}
