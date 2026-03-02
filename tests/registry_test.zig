const std = @import("std");
const helpers = @import("helpers.zig");

test "zr registry help" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "--help" }, cwd);
    defer result.deinit();

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr registry") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "serve") != null);
}

test "zr registry serve --help" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "serve", "--help" }, cwd);
    defer result.deinit();

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Start the plugin registry HTTP server") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--host") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--port") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--data-dir") != null);
}
