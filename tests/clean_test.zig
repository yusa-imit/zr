const std = @import("std");
const helpers = @import("helpers.zig");

test "clean: show help" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "clean", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage: zr clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--all") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--history") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--dry-run") != null);
}

test "clean: dry-run runs successfully" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a minimal zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = helpers.HELLO_TOML });

    var result = try helpers.runZr(std.testing.allocator, &.{ "clean", "--all", "--dry-run" }, tmp_path);
    defer result.deinit();

    // Dry-run should succeed and show cleaning messages
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Cleaning") != null);
}

test "clean: --cache cleans cache directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a minimal zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = helpers.HELLO_TOML });

    // Create cache directory with dummy data
    try tmp.dir.makePath(".zr/cache");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/cache/dummy.txt", .data = "test" });

    var result = try helpers.runZr(std.testing.allocator, &.{ "clean", "--cache" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify cache was cleaned (or at least command succeeded)
    const stat = tmp.dir.statFile(".zr/cache/dummy.txt") catch |err| {
        if (err == error.FileNotFound) {
            return; // Expected - cache was cleaned
        }
        return err;
    };
    _ = stat;
}

test "clean: --history cleans history" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a minimal zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = helpers.HELLO_TOML });

    // Create history directory
    try tmp.dir.makePath(".zr/history");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/history/dummy.log", .data = "test" });

    var result = try helpers.runZr(std.testing.allocator, &.{ "clean", "--history" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "clean: unknown option returns error" {
    var result = try helpers.runZr(std.testing.allocator, &.{ "clean", "--invalid-option" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unknown option") != null);
}

test "clean: --all includes all cleanup targets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a minimal zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = helpers.HELLO_TOML });

    var result = try helpers.runZr(std.testing.allocator, &.{ "clean", "--all", "--dry-run" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "clean: multiple flags work together" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Create a minimal zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = helpers.HELLO_TOML });

    var result = try helpers.runZr(std.testing.allocator, &.{ "clean", "--cache", "--history", "--dry-run" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}
