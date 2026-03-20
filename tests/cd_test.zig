const std = @import("std");
const helpers = @import("helpers.zig");

test "cd: requires member argument" {
    var result = try helpers.runZr(std.testing.allocator, &.{"cd"}, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "member") != null or
        std.mem.indexOf(u8, result.stderr, "required") != null);
}

test "cd: fails without zr.toml" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "cd", "member1" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr.toml") != null);
}

test "cd: fails without workspace config" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.build]
        \\script = "echo build"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "cd", "member1" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "workspace") != null);
}

test "cd: returns member path on success" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*"]
    });

    try tmp.dir.makePath("packages/member1");
    try tmp.dir.writeFile(.{ .sub_path = "packages/member1/zr.toml", .data =
        \\[task.test]
        \\script = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "cd", "member1" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "member1") != null);
}

test "cd: fails for nonexistent member" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*"]
    });

    try tmp.dir.makePath("packages/member1");
    try tmp.dir.writeFile(.{ .sub_path = "packages/member1/zr.toml", .data =
        \\[task.test]
        \\script = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "cd", "nonexistent" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
}

test "cd: outputs path to stdout only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*"]
    });

    try tmp.dir.makePath("packages/member1");
    try tmp.dir.writeFile(.{ .sub_path = "packages/member1/zr.toml", .data =
        \\[task.test]
        \\script = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "cd", "member1" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
    try std.testing.expect(result.stderr.len == 0);
}

test "cd: fails for empty workspace members" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*"]
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "cd", "member1" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
}

test "cd: ignores directories without zr.toml" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["packages/*"]
    });

    try tmp.dir.makePath("packages/valid");
    try tmp.dir.makePath("packages/invalid");

    try tmp.dir.writeFile(.{ .sub_path = "packages/valid/zr.toml", .data =
        \\[task.test]
        \\script = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Should find valid
    var result1 = try helpers.runZr(std.testing.allocator, &.{ "cd", "valid" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);

    // Should NOT find invalid
    var result2 = try helpers.runZr(std.testing.allocator, &.{ "cd", "invalid" }, tmp_path);
    defer result2.deinit();
    try std.testing.expect(result2.exit_code != 0);
}
