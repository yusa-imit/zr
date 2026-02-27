const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

const VERSION_TOML =
    \\[versioning]
    \\mode = "independent"
    \\convention = "conventional"
    \\
    \\[tasks.test]
    \\cmd = "echo test"
    \\
;

const PACKAGE_JSON =
    \\{
    \\  "name": "test-package",
    \\  "version": "1.2.3"
    \\}
    \\
;

test "716: version shows current version" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = VERSION_TOML });
    try tmp.dir.writeFile(.{ .sub_path = "package.json", .data = PACKAGE_JSON });

    var result = try runZr(allocator, &.{"version"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Current version: 1.2.3") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Versioning mode: independent") != null);
}

test "717: version bumps patch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = VERSION_TOML });
    try tmp.dir.writeFile(.{ .sub_path = "package.json", .data = PACKAGE_JSON });

    var result = try runZr(allocator, &.{ "version", "--bump", "patch" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "1.2.3 → 1.2.4") != null);

    // Verify package.json was updated
    const content = try tmp.dir.readFileAlloc(allocator, "package.json", 1024);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"version\": \"1.2.4\"") != null);
}

test "718: version bumps minor" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = VERSION_TOML });
    try tmp.dir.writeFile(.{ .sub_path = "package.json", .data = PACKAGE_JSON });

    var result = try runZr(allocator, &.{ "version", "--bump", "minor" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "1.2.3 → 1.3.0") != null);

    const content = try tmp.dir.readFileAlloc(allocator, "package.json", 1024);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"version\": \"1.3.0\"") != null);
}

test "719: version bumps major" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = VERSION_TOML });
    try tmp.dir.writeFile(.{ .sub_path = "package.json", .data = PACKAGE_JSON });

    var result = try runZr(allocator, &.{ "version", "--bump", "major" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "1.2.3 → 2.0.0") != null);

    const content = try tmp.dir.readFileAlloc(allocator, "package.json", 1024);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"version\": \"2.0.0\"") != null);
}

test "720: version fails without versioning section" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const no_version_toml = "[tasks.test]\ncmd = \"echo test\"\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = no_version_toml });

    var result = try runZr(allocator, &.{"version"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "[versioning] section not found") != null);
}

test "721: version fails without package.json" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = VERSION_TOML });

    var result = try runZr(allocator, &.{"version"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "package.json not found") != null);
}

test "722: version uses custom package path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = VERSION_TOML });
    try tmp.dir.writeFile(.{ .sub_path = "custom.json", .data = PACKAGE_JSON });

    var result = try runZr(allocator, &.{ "version", "--package", "custom.json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "1.2.3") != null);
}

test "723: version rejects invalid bump type" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = VERSION_TOML });
    try tmp.dir.writeFile(.{ .sub_path = "package.json", .data = PACKAGE_JSON });

    var result = try runZr(allocator, &.{ "version", "--bump", "invalid" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid bump type") != null);
}

test "724: version shows help" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "version", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage: zr version") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--bump") != null);
}
