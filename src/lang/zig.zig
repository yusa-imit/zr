const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const ZigProvider: LanguageProvider = .{
    .name = "zig",
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

    const zig_platform = if (std.mem.eql(u8, platform.os, "darwin"))
        "macos"
    else if (std.mem.eql(u8, platform.os, "win"))
        "windows"
    else
        platform.os;

    const zig_arch = if (std.mem.eql(u8, platform.arch, "x64"))
        "x86_64"
    else if (std.mem.eql(u8, platform.arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    const archive_ext = if (std.mem.eql(u8, platform.os, "win")) "zip" else "tar.xz";
    const archive_type: provider.ArchiveType = if (std.mem.eql(u8, platform.os, "win")) .zip else .tar_xz;

    const url = try std.fmt.allocPrint(allocator, "https://ziglang.org/download/{s}/zig-{s}-{s}-{s}.{s}", .{
        version_str,
        zig_platform,
        zig_arch,
        version_str,
        archive_ext,
    });

    return .{ .url = url, .archive_type = archive_type };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://ziglang.org/download/index.json";
    const json_data = try provider.fetchUrl(allocator, url);
    defer allocator.free(json_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidJson;

    if (root.object.get("master")) |master_field| {
        if (master_field == .object) {
            if (master_field.object.get("version")) |ver_field| {
                if (ver_field == .string) {
                    return ToolVersion.parse(ver_field.string) catch return error.InvalidVersion;
                }
            }
        }
    }

    return error.VersionNotFound;
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "zig.exe");
    } else {
        return try allocator.dupe(u8, "zig");
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

    if (dir.access("build.zig", .{})) |_| {
        confidence += 70;
        try files.append(allocator, "build.zig");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    if (dir.access("build.zig.zon", .{})) |_| {
        confidence += 30;
        try files.append(allocator, "build.zig.zon");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    return .{
        .detected = confidence > 0,
        .confidence = @min(confidence, 100),
        .files_found = try files.toOwnedSlice(allocator),
    };
}

fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion {
    _ = dir_path;
    // Basic Zig tasks
    var tasks = std.ArrayList(LanguageProvider.TaskSuggestion){};
    errdefer tasks.deinit(allocator);

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "build"),
        .command = try allocator.dupe(u8, "zig build"),
        .description = try allocator.dupe(u8, "Build the Zig project"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test"),
        .command = try allocator.dupe(u8, "zig build test"),
        .description = try allocator.dupe(u8, "Run Zig tests"),
    });

    return try tasks.toOwnedSlice(allocator);
}
