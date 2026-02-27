const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const DenoProvider: LanguageProvider = .{
    .name = "deno",
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

    const deno_platform = blk: {
        if (std.mem.eql(u8, platform.os, "linux")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "x86_64-unknown-linux-gnu";
            } else if (std.mem.eql(u8, platform.arch, "arm64")) {
                break :blk "aarch64-unknown-linux-gnu";
            }
        } else if (std.mem.eql(u8, platform.os, "darwin")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "x86_64-apple-darwin";
            } else if (std.mem.eql(u8, platform.arch, "arm64")) {
                break :blk "aarch64-apple-darwin";
            }
        } else if (std.mem.eql(u8, platform.os, "win")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "x86_64-pc-windows-msvc";
            }
        }
        return error.UnsupportedPlatform;
    };

    const url = try std.fmt.allocPrint(allocator, "https://github.com/denoland/deno/releases/download/v{s}/deno-{s}.zip", .{
        version_str,
        deno_platform,
    });

    return .{ .url = url, .archive_type = .zip };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://dl.deno.land/release-latest.txt";
    const content = try provider.fetchUrl(allocator, url);
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);
    if (std.mem.startsWith(u8, trimmed, "v")) {
        return ToolVersion.parse(trimmed[1..]) catch return error.InvalidVersion;
    }

    return ToolVersion.parse(trimmed) catch return error.InvalidVersion;
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "deno.exe");
    } else {
        return try allocator.dupe(u8, "deno");
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
        .{ .file = "deno.json", .points = 70 },
        .{ .file = "deno.jsonc", .points = 70 },
        .{ .file = "deno.lock", .points = 30 },
    };

    for (markers) |marker| {
        if (dir.access(marker.file, .{})) |_| {
            confidence += marker.points;
            try files.append(allocator, marker.file);
        } else |err| {
            if (err != error.FileNotFound) return err;
        }
    }

    return .{
        .detected = confidence > 0,
        .confidence = @min(confidence, 100),
        .files_found = try files.toOwnedSlice(allocator),
    };
}

fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion {
    _ = dir_path;
    var tasks = std.ArrayList(LanguageProvider.TaskSuggestion){};
    errdefer tasks.deinit(allocator);

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "run"),
        .command = try allocator.dupe(u8, "deno run main.ts"),
        .description = try allocator.dupe(u8, "Run Deno project"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test"),
        .command = try allocator.dupe(u8, "deno test"),
        .description = try allocator.dupe(u8, "Run Deno tests"),
    });

    return try tasks.toOwnedSlice(allocator);
}
