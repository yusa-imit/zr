const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

// C# (.NET) language provider for .csproj and .sln projects
pub const CSharpProvider: LanguageProvider = .{
    .name = "csharp",
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

    // .NET SDK download URLs
    const dotnet_platform = if (std.mem.eql(u8, platform.os, "darwin"))
        "osx"
    else if (std.mem.eql(u8, platform.os, "win"))
        "win"
    else if (std.mem.eql(u8, platform.os, "linux"))
        "linux"
    else
        return error.UnsupportedPlatform;

    const dotnet_arch = if (std.mem.eql(u8, platform.arch, "x64"))
        "x64"
    else if (std.mem.eql(u8, platform.arch, "arm64"))
        "arm64"
    else
        return error.UnsupportedArchitecture;

    const archive_ext = if (std.mem.eql(u8, platform.os, "win")) "zip" else "tar.gz";
    const archive_type: provider.ArchiveType = if (std.mem.eql(u8, platform.os, "win")) .zip else .tar_gz;

    // .NET SDK download URL format
    const url = try std.fmt.allocPrint(allocator, "https://download.visualstudio.microsoft.com/download/pr/dotnet-sdk-{s}-{s}-{s}.{s}", .{
        version_str,
        dotnet_platform,
        dotnet_arch,
        archive_ext,
    });

    return .{ .url = url, .archive_type = archive_type };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    // Fetch latest LTS version from .NET release metadata
    const url = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json";
    const content = try provider.fetchUrl(allocator, url);
    defer allocator.free(content);

    // Parse JSON to find latest-sdk version
    // For simplicity, we'll default to 9.0 (latest LTS as of 2026)
    // A full implementation would parse the JSON response
    return ToolVersion.parse("9.0") catch return error.InvalidVersion;
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "dotnet.exe");
    } else {
        return try allocator.dupe(u8, "dotnet");
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
        .{ .file = "*.csproj", .points = 70 },
        .{ .file = "*.sln", .points = 60 },
        .{ .file = "global.json", .points = 30 },
        .{ .file = "nuget.config", .points = 20 },
    };

    for (markers) |marker| {
        // For glob patterns, we'd need to iterate directory
        // For now, check exact file names
        if (std.mem.indexOf(u8, marker.file, "*")) |_| {
            // Glob pattern - iterate to find matching files
            var iter = dir.iterate();
            while (iter.next() catch null) |entry| {
                if (entry.kind != .file) continue;

                const ext = std.fs.path.extension(entry.name);
                if (std.mem.eql(u8, marker.file, "*.csproj") and std.mem.eql(u8, ext, ".csproj")) {
                    confidence += marker.points;
                    try files.append(allocator, marker.file);
                    break;
                } else if (std.mem.eql(u8, marker.file, "*.sln") and std.mem.eql(u8, ext, ".sln")) {
                    confidence += marker.points;
                    try files.append(allocator, marker.file);
                    break;
                }
            }
        } else {
            // Exact file name
            if (dir.access(marker.file, .{})) |_| {
                confidence += marker.points;
                try files.append(allocator, marker.file);
            } else |err| {
                if (err != error.FileNotFound) return err;
            }
        }
    }

    return .{
        .detected = confidence > 0,
        .confidence = @min(confidence, 100),
        .files_found = try files.toOwnedSlice(allocator),
    };
}

/// Extract common C# tasks (build, test, run, etc.)
fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch return &.{};
    defer dir.close();

    var tasks = std.ArrayList(LanguageProvider.TaskSuggestion){};
    errdefer {
        for (tasks.items) |task| {
            allocator.free(task.name);
            allocator.free(task.command);
            allocator.free(task.description);
        }
        tasks.deinit(allocator);
    }

    // Common .NET tasks
    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "build"),
        .command = try allocator.dupe(u8, "dotnet build"),
        .description = try allocator.dupe(u8, "Build the .NET project"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test"),
        .command = try allocator.dupe(u8, "dotnet test"),
        .description = try allocator.dupe(u8, "Run .NET tests"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "run"),
        .command = try allocator.dupe(u8, "dotnet run"),
        .description = try allocator.dupe(u8, "Run the .NET application"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "clean"),
        .command = try allocator.dupe(u8, "dotnet clean"),
        .description = try allocator.dupe(u8, "Clean build artifacts"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "restore"),
        .command = try allocator.dupe(u8, "dotnet restore"),
        .description = try allocator.dupe(u8, "Restore NuGet packages"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "publish"),
        .command = try allocator.dupe(u8, "dotnet publish -c Release"),
        .description = try allocator.dupe(u8, "Publish release build"),
    });

    return try tasks.toOwnedSlice(allocator);
}

test "CSharpProvider basic" {
    try std.testing.expectEqualStrings("csharp", CSharpProvider.name);
}

test "CSharpProvider getBinaryPath" {
    const allocator = std.testing.allocator;

    const platform_unix = PlatformInfo{ .os = "linux", .arch = "x64" };
    const bin_path_unix = try CSharpProvider.getBinaryPath(allocator, platform_unix);
    defer allocator.free(bin_path_unix);
    try std.testing.expectEqualStrings("dotnet", bin_path_unix);

    const platform_win = PlatformInfo{ .os = "win", .arch = "x64" };
    const bin_path_win = try CSharpProvider.getBinaryPath(allocator, platform_win);
    defer allocator.free(bin_path_win);
    try std.testing.expectEqualStrings("dotnet.exe", bin_path_win);
}

test "CSharpProvider extractTasks" {
    const allocator = std.testing.allocator;

    // Test with non-existent directory (should return empty array)
    const tasks = try CSharpProvider.extractTasks.?(allocator, "/nonexistent");
    defer {
        for (tasks) |task| {
            allocator.free(task.name);
            allocator.free(task.command);
            allocator.free(task.description);
        }
        allocator.free(tasks);
    }

    // Should return empty array for non-existent directory
    try std.testing.expect(tasks.len == 0);
}
