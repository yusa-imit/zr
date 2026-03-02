const std = @import("std");
const helpers = @import("helpers.zig");

test "844: zr registry help" {
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

test "845: zr registry serve --help" {
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

test "846: zr registry serve rejects missing --host value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "serve", "--host" }, cwd);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Missing value for --host") != null);
}

test "847: zr registry serve rejects missing --port value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "serve", "--port" }, cwd);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Missing value for --port") != null);
}

test "848: zr registry serve rejects invalid port" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "serve", "--port", "invalid" }, cwd);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid port number") != null);
}

test "849: zr registry serve rejects missing --data-dir value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "serve", "--data-dir" }, cwd);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Missing value for --data-dir") != null);
}

test "850: zr registry serve rejects unknown option" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "serve", "--unknown" }, cwd);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unknown option") != null);
}

test "851: zr registry unknown subcommand" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    var result = try helpers.runZr(allocator, &.{ "registry", "invalid" }, cwd);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unknown registry subcommand") != null);
}
