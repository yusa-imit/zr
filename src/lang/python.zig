const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const PythonProvider: LanguageProvider = .{
    .name = "python",
    .resolveDownloadUrl = resolveDownloadUrl,
    .fetchLatestVersion = fetchLatestVersion,
    .getBinaryPath = getBinaryPath,
    .getEnvironmentVars = null,
    .detectProject = detectProject,
    .extractTasks = null, // TODO: Could parse setup.py, pyproject.toml
};

fn resolveDownloadUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: PlatformInfo) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const pbs_platform = if (std.mem.eql(u8, platform.os, "darwin"))
        "apple-darwin"
    else if (std.mem.eql(u8, platform.os, "linux"))
        "unknown-linux-gnu"
    else if (std.mem.eql(u8, platform.os, "win"))
        "pc-windows-msvc-shared"
    else
        return error.UnsupportedPlatform;

    const pbs_arch = if (std.mem.eql(u8, platform.arch, "x64"))
        "x86_64"
    else if (std.mem.eql(u8, platform.arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    const tag = "20240107";
    const url = try std.fmt.allocPrint(allocator, "https://github.com/indygreg/python-build-standalone/releases/download/{s}/cpython-{s}+{s}-{s}-{s}.tar.gz", .{
        tag,
        version_str,
        tag,
        pbs_arch,
        pbs_platform,
    });

    return .{ .url = url, .archive_type = .tar_gz };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    _ = allocator;
    return ToolVersion{ .major = 3, .minor = 12, .patch = 7 };
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "python.exe");
    } else {
        return try allocator.dupe(u8, "bin/python3");
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
        .{ .file = "requirements.txt", .points = 40 },
        .{ .file = "setup.py", .points = 40 },
        .{ .file = "pyproject.toml", .points = 40 },
        .{ .file = ".python-version", .points = 20 },
        .{ .file = "Pipfile", .points = 30 },
        .{ .file = "poetry.lock", .points = 30 },
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
