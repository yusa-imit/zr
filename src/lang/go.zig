const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const GoProvider: LanguageProvider = .{
    .name = "go",
    .resolveDownloadUrl = resolveDownloadUrl,
    .fetchLatestVersion = fetchLatestVersion,
    .getBinaryPath = getBinaryPath,
    .getEnvironmentVars = getEnvironmentVars,
    .detectProject = detectProject,
    .extractTasks = extractTasks,
};

fn resolveDownloadUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: PlatformInfo) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const go_platform = if (std.mem.eql(u8, platform.os, "darwin"))
        "darwin"
    else if (std.mem.eql(u8, platform.os, "win"))
        "windows"
    else
        platform.os;

    const go_arch = if (std.mem.eql(u8, platform.arch, "x64"))
        "amd64"
    else if (std.mem.eql(u8, platform.arch, "arm64"))
        "arm64"
    else
        return error.UnsupportedArchitecture;

    const archive_ext = if (std.mem.eql(u8, platform.os, "win")) "zip" else "tar.gz";
    const archive_type: provider.ArchiveType = if (std.mem.eql(u8, platform.os, "win")) .zip else .tar_gz;

    const url = try std.fmt.allocPrint(allocator, "https://go.dev/dl/go{s}.{s}-{s}.{s}", .{
        version_str,
        go_platform,
        go_arch,
        archive_ext,
    });

    return .{ .url = url, .archive_type = archive_type };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://go.dev/VERSION?m=text";
    const content = try provider.fetchUrl(allocator, url);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    if (lines.next()) |first_line| {
        const trimmed = std.mem.trim(u8, first_line, &std.ascii.whitespace);
        if (std.mem.startsWith(u8, trimmed, "go")) {
            return ToolVersion.parse(trimmed[2..]) catch return error.InvalidVersion;
        }
    }

    return error.VersionNotFound;
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "bin/go.exe");
    } else {
        return try allocator.dupe(u8, "bin/go");
    }
}

fn getEnvironmentVars(allocator: std.mem.Allocator, install_dir: []const u8) !std.StringHashMap([]const u8) {
    var env_map = std.StringHashMap([]const u8).init(allocator);
    errdefer env_map.deinit();

    const goroot = try allocator.dupe(u8, install_dir);
    try env_map.put("GOROOT", goroot);

    return env_map;
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
        .{ .file = "go.mod", .points = 70 },
        .{ .file = "go.sum", .points = 30 },
        .{ .file = ".go-version", .points = 20 },
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

/// Extract common Go tasks (build, test, run, etc.)
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

    // Check if go.mod exists to determine module name
    var module_name: ?[]const u8 = null;
    defer if (module_name) |name| allocator.free(name);

    if (dir.openFile("go.mod", .{})) |file| {
        defer file.close();
        if (file.readToEndAlloc(allocator, 1024 * 1024)) |content| {
            defer allocator.free(content);
            module_name = try extractModuleName(allocator, content);
        } else |_| {}
    } else |_| {}

    // Common Go tasks
    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "build"),
        .command = try allocator.dupe(u8, "go build ./..."),
        .description = try allocator.dupe(u8, "Build all Go packages"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test"),
        .command = try allocator.dupe(u8, "go test ./..."),
        .description = try allocator.dupe(u8, "Run all tests"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test-verbose"),
        .command = try allocator.dupe(u8, "go test -v ./..."),
        .description = try allocator.dupe(u8, "Run tests with verbose output"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test-coverage"),
        .command = try allocator.dupe(u8, "go test -cover ./..."),
        .description = try allocator.dupe(u8, "Run tests with coverage"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "vet"),
        .command = try allocator.dupe(u8, "go vet ./..."),
        .description = try allocator.dupe(u8, "Run go vet for suspicious code"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "fmt"),
        .command = try allocator.dupe(u8, "go fmt ./..."),
        .description = try allocator.dupe(u8, "Format all Go code"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "mod-tidy"),
        .command = try allocator.dupe(u8, "go mod tidy"),
        .description = try allocator.dupe(u8, "Tidy go.mod dependencies"),
    });

    // If there's a main package, add run task
    if (try hasMainPackage(dir)) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "run"),
            .command = try allocator.dupe(u8, "go run ."),
            .description = try allocator.dupe(u8, "Run main package"),
        });
    }

    return try tasks.toOwnedSlice(allocator);
}

/// Extract module name from go.mod content
fn extractModuleName(allocator: std.mem.Allocator, content: []const u8) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (std.mem.startsWith(u8, trimmed, "module ")) {
            const module_part = std.mem.trim(u8, trimmed[7..], &std.ascii.whitespace);
            if (module_part.len > 0) {
                return try allocator.dupe(u8, module_part);
            }
        }
    }
    return null;
}

/// Check if directory contains a main package (main.go with package main)
fn hasMainPackage(dir: std.fs.Dir) !bool {
    const file = dir.openFile("main.go", .{}) catch return false;
    defer file.close();

    // Read first 256 bytes to check for "package main"
    var buf: [256]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    const content = buf[0..bytes_read];

    return std.mem.indexOf(u8, content, "package main") != null;
}
