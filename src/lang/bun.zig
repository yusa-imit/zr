const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const ArchiveType = provider.ArchiveType;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const BunProvider: LanguageProvider = .{
    .name = "bun",
    .resolveDownloadUrl = resolveDownloadUrl,
    .fetchLatestVersion = fetchLatestVersion,
    .getBinaryPath = getBinaryPath,
    .getEnvironmentVars = null,
    .detectProject = detectProject,
    .extractTasks = extractTasks,
};

fn resolveDownloadUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: PlatformInfo) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const bun_platform = blk: {
        if (std.mem.eql(u8, platform.os, "linux")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "linux-x64";
            } else if (std.mem.eql(u8, platform.arch, "arm64")) {
                break :blk "linux-aarch64";
            }
        } else if (std.mem.eql(u8, platform.os, "darwin")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "darwin-x64";
            } else if (std.mem.eql(u8, platform.arch, "arm64")) {
                break :blk "darwin-aarch64";
            }
        } else if (std.mem.eql(u8, platform.os, "win")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "windows-x64";
            }
        }
        return error.UnsupportedPlatform;
    };

    const url = try std.fmt.allocPrint(allocator, "https://github.com/oven-sh/bun/releases/download/bun-v{s}/bun-{s}.zip", .{
        version_str,
        bun_platform,
    });

    return .{ .url = url, .archive_type = .zip };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://api.github.com/repos/oven-sh/bun/releases/latest";
    const json_data = try provider.fetchUrl(allocator, url);
    defer allocator.free(json_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidJson;

    if (root.object.get("tag_name")) |tag_field| {
        if (tag_field == .string) {
            const tag = tag_field.string;
            const clean_tag = if (std.mem.startsWith(u8, tag, "bun-v"))
                tag[5..]
            else if (std.mem.startsWith(u8, tag, "v"))
                tag[1..]
            else
                tag;
            return ToolVersion.parse(clean_tag) catch return error.InvalidVersion;
        }
    }

    return error.VersionNotFound;
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "bun.exe");
    } else {
        return try allocator.dupe(u8, "bun");
    }
}

fn detectProject(allocator: std.mem.Allocator, dir_path: []const u8) !ProjectInfo {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch {
        return .{ .detected = false, .confidence = 0, .files_found = &.{} };
    };
    defer dir.close();

    var confidence: u8 = 0;
    var files = std.ArrayList([]const u8){};
    defer files.deinit(allocator);

    const markers = [_]struct { file: []const u8, points: u8 }{
        .{ .file = "bun.lockb", .points = 60 },
        .{ .file = "bunfig.toml", .points = 40 },
    };

    for (markers) |marker| {
        if (dir.access(marker.file, .{})) |_| {
            confidence += marker.points;
            try files.append(allocator, marker.file);
        } else |err| {
            if (err != error.FileNotFound) return err;
        }
    }

    // Also check for package.json (but lower confidence)
    if (dir.access("package.json", .{})) |_| {
        if (confidence == 0) confidence = 20; // Only if no bun-specific files
        try files.append(allocator, "package.json");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    return .{
        .detected = confidence > 0,
        .confidence = @min(confidence, 100),
        .files_found = try files.toOwnedSlice(allocator),
    };
}

/// Extract npm scripts from package.json (like Node, but using bun commands)
fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch return &.{};
    defer dir.close();

    const file = dir.openFile("package.json", .{}) catch return &.{};
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return &.{};

    const scripts_obj = root.object.get("scripts") orelse return &.{};
    if (scripts_obj != .object) return &.{};

    var tasks = std.ArrayList(LanguageProvider.TaskSuggestion){};
    errdefer {
        for (tasks.items) |task| {
            allocator.free(task.name);
            allocator.free(task.command);
            allocator.free(task.description);
        }
        tasks.deinit(allocator);
    }

    var iter = scripts_obj.object.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* != .string) continue;

        const name = try allocator.dupe(u8, entry.key_ptr.*);
        const cmd = try std.fmt.allocPrint(allocator, "bun run {s}", .{entry.key_ptr.*});
        const desc = try std.fmt.allocPrint(allocator, "Run bun script: {s}", .{entry.value_ptr.string});

        try tasks.append(allocator, .{
            .name = name,
            .command = cmd,
            .description = desc,
        });
    }

    return try tasks.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "BunProvider name" {
    try testing.expectEqualStrings("bun", BunProvider.name);
}

test "resolveDownloadUrl linux-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 0, .patch = 36 };
    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/oven-sh/bun/releases/download/bun-v1.0.36/bun-linux-x64.zip", spec.url);
    try testing.expectEqual(ArchiveType.zip, spec.archive_type);
}

test "resolveDownloadUrl linux-arm64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 1, .patch = 0 };
    const platform = PlatformInfo{ .os = "linux", .arch = "arm64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/oven-sh/bun/releases/download/bun-v1.1.0/bun-linux-aarch64.zip", spec.url);
    try testing.expectEqual(ArchiveType.zip, spec.archive_type);
}

test "resolveDownloadUrl darwin-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 0, .patch = 0 };
    const platform = PlatformInfo{ .os = "darwin", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/oven-sh/bun/releases/download/bun-v1.0.0/bun-darwin-x64.zip", spec.url);
    try testing.expectEqual(ArchiveType.zip, spec.archive_type);
}

test "resolveDownloadUrl darwin-arm64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 2, .patch = 3 };
    const platform = PlatformInfo{ .os = "darwin", .arch = "arm64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/oven-sh/bun/releases/download/bun-v1.2.3/bun-darwin-aarch64.zip", spec.url);
    try testing.expectEqual(ArchiveType.zip, spec.archive_type);
}

test "resolveDownloadUrl windows-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 0, .patch = 36 };
    const platform = PlatformInfo{ .os = "win", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/oven-sh/bun/releases/download/bun-v1.0.36/bun-windows-x64.zip", spec.url);
    try testing.expectEqual(ArchiveType.zip, spec.archive_type);
}

test "resolveDownloadUrl unsupported platform" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 0, .patch = 0 };
    const platform = PlatformInfo{ .os = "freebsd", .arch = "x64" };

    try testing.expectError(error.UnsupportedPlatform, resolveDownloadUrl(allocator, version, platform));
}

test "getBinaryPath unix" {
    const allocator = testing.allocator;
    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };

    const path = try getBinaryPath(allocator, platform);
    defer allocator.free(path);

    try testing.expectEqualStrings("bun", path);
}

test "getBinaryPath windows" {
    const allocator = testing.allocator;
    const platform = PlatformInfo{ .os = "win", .arch = "x64" };

    const path = try getBinaryPath(allocator, platform);
    defer allocator.free(path);

    try testing.expectEqualStrings("bun.exe", path);
}

test "getEnvironmentVars is null" {
    try testing.expect(BunProvider.getEnvironmentVars == null);
}
