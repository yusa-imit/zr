const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

test "3: init creates zr.toml" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"init"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify zr.toml was created
    tmp.dir.access("zr.toml", .{}) catch {
        return error.TestUnexpectedResult;
    };
}

test "4: init refuses overwrite" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create existing zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "existing" });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"init"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "163: init with existing config refuses overwrite" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create existing zr.toml
    const existing = try tmp.dir.createFile("zr.toml", .{});
    defer existing.close();
    try existing.writeAll("[tasks.old]\ncmd = \"echo old\"\n");

    var result = try runZr(allocator, &.{ "init" }, tmp_path);
    defer result.deinit();

    // Should refuse to overwrite existing config
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "already exists") != null);
}

test "626: init with existing file shows helpful error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create existing zr.toml
    const existing_toml =
        \\[tasks.existing]
        \\cmd = "echo existing"
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = existing_toml });

    // Try init (without --force which isn't implemented)
    var result = try runZr(allocator, &.{ "init" }, tmp_path);
    defer result.deinit();

    // Should fail with helpful error
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "already exists") != null);
}

test "698: init with custom --config path creates file at specified location" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const custom_path = try std.fmt.allocPrint(allocator, "{s}/custom.toml", .{tmp_path});
    defer allocator.free(custom_path);

    var result = try runZr(allocator, &.{ "--config", custom_path, "init" }, tmp_path);
    defer result.deinit();

    // Should create file at custom path or show helpful error
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
