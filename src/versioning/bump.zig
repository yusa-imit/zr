const std = @import("std");
const types = @import("types.zig");
const semver_mod = @import("../util/semver.zig");

/// Bump a version string according to the bump type
pub fn bumpVersion(allocator: std.mem.Allocator, version: []const u8, bump_type: types.BumpType) ![]const u8 {
    // Parse the input version
    const ver = try semver_mod.Version.parse(version);

    // Increment based on bump type
    const new_ver = switch (bump_type) {
        .major => semver_mod.Version{ .major = ver.major + 1, .minor = 0, .patch = 0 },
        .minor => semver_mod.Version{ .major = ver.major, .minor = ver.minor + 1, .patch = 0 },
        .patch => semver_mod.Version{ .major = ver.major, .minor = ver.minor, .patch = ver.patch + 1 },
    };

    // Format as string
    return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ new_ver.major, new_ver.minor, new_ver.patch });
}

/// Read version from package.json file
pub fn readPackageJsonVersion(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    // Simple JSON parsing - find "version": "X.Y.Z"
    const version_key = "\"version\"";
    const version_idx = std.mem.indexOf(u8, content, version_key) orelse return error.VersionNotFound;

    // Find the value after "version":
    var i = version_idx + version_key.len;
    while (i < content.len and (content[i] == ' ' or content[i] == ':' or content[i] == '\t' or content[i] == '\n')) : (i += 1) {}

    if (i >= content.len or content[i] != '"') return error.InvalidVersionFormat;

    const start = i + 1;
    const end = std.mem.indexOfScalarPos(u8, content, start, '"') orelse return error.InvalidVersionFormat;

    return try allocator.dupe(u8, content[start..end]);
}

/// Write version to package.json file
pub fn writePackageJsonVersion(allocator: std.mem.Allocator, path: []const u8, new_version: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Find and replace version
    const version_key = "\"version\"";
    const version_idx = std.mem.indexOf(u8, content, version_key) orelse return error.VersionNotFound;

    var i = version_idx + version_key.len;
    while (i < content.len and (content[i] == ' ' or content[i] == ':' or content[i] == '\t' or content[i] == '\n')) : (i += 1) {}

    if (i >= content.len or content[i] != '"') return error.InvalidVersionFormat;

    const start = i + 1;
    const end = std.mem.indexOfScalarPos(u8, content, start, '"') orelse return error.InvalidVersionFormat;

    // Build new content
    const new_content = try std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}",
        .{ content[0..start], new_version, content[end..] },
    );
    defer allocator.free(new_content);

    // Write back
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = new_content });
}

test "bumpVersion patch" {
    const result = try bumpVersion(std.testing.allocator, "1.2.3", .patch);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("1.2.4", result);
}

test "bumpVersion minor" {
    const result = try bumpVersion(std.testing.allocator, "1.2.3", .minor);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("1.3.0", result);
}

test "bumpVersion major" {
    const result = try bumpVersion(std.testing.allocator, "1.2.3", .major);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("2.0.0", result);
}

test "bumpVersion from 0.0.0" {
    const result = try bumpVersion(std.testing.allocator, "0.0.0", .patch);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("0.0.1", result);
}
