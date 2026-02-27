const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const BunProvider: LanguageProvider = .{
    .name = "bun",
    .resolveDownloadUrl = resolveDownloadUrl,
    .fetchLatestVersion = fetchLatestVersion,
    .getBinaryPath = getBinaryPath,
    .getEnvironmentVars = null,
    .detectProject = detectProject,
    .extractTasks = null,
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
