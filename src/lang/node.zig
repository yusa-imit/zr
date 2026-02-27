const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

/// Node.js toolchain provider
pub const NodeProvider: LanguageProvider = .{
    .name = "node",
    .resolveDownloadUrl = resolveDownloadUrl,
    .fetchLatestVersion = fetchLatestVersion,
    .getBinaryPath = getBinaryPath,
    .getEnvironmentVars = null, // Node doesn't need extra env vars
    .detectProject = detectProject,
    .extractTasks = extractTasks,
};

/// Resolve Node.js download URL
/// Format: https://nodejs.org/dist/v{version}/node-v{version}-{platform}-{arch}.tar.gz
fn resolveDownloadUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: PlatformInfo) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const archive_ext = if (std.mem.eql(u8, platform.os, "win")) "zip" else "tar.gz";
    const archive_type: provider.ArchiveType = if (std.mem.eql(u8, platform.os, "win")) .zip else .tar_gz;

    const url = try std.fmt.allocPrint(allocator, "https://nodejs.org/dist/v{s}/node-v{s}-{s}-{s}.{s}", .{
        version_str,
        version_str,
        platform.os,
        platform.arch,
        archive_ext,
    });

    return .{
        .url = url,
        .archive_type = archive_type,
    };
}

/// Fetch latest Node.js LTS version from nodejs.org/dist/index.json
fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://nodejs.org/dist/index.json";
    const json_data = try provider.fetchUrl(allocator, url);
    defer allocator.free(json_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .array) return error.InvalidJson;

    for (root.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        // Check if it's an LTS version
        if (obj.get("lts")) |lts_field| {
            if (lts_field == .bool and lts_field.bool) {
                if (obj.get("version")) |ver_field| {
                    if (ver_field == .string) {
                        const ver_str = ver_field.string;
                        const clean_ver = if (ver_str.len > 0 and ver_str[0] == 'v')
                            ver_str[1..]
                        else
                            ver_str;
                        return ToolVersion.parse(clean_ver) catch continue;
                    }
                }
            } else if (lts_field == .string and lts_field.string.len > 0) {
                if (obj.get("version")) |ver_field| {
                    if (ver_field == .string) {
                        const ver_str = ver_field.string;
                        const clean_ver = if (ver_str.len > 0 and ver_str[0] == 'v')
                            ver_str[1..]
                        else
                            ver_str;
                        return ToolVersion.parse(clean_ver) catch continue;
                    }
                }
            }
        }
    }

    return error.VersionNotFound;
}

/// Get Node binary path within toolchain directory
fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "node.exe");
    } else {
        return try allocator.dupe(u8, "bin/node");
    }
}

/// Detect if Node.js is used in the project
fn detectProject(allocator: std.mem.Allocator, dir_path: []const u8) !ProjectInfo {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch {
        return .{ .detected = false, .confidence = 0, .files_found = &.{} };
    };
    defer dir.close();

    var confidence: u8 = 0;
    var files = std.ArrayList([]const u8){};
    defer files.deinit(allocator);

    // Check for package.json
    if (dir.access("package.json", .{})) |_| {
        confidence += 50;
        try files.append(allocator, "package.json");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for node_modules
    if (dir.access("node_modules", .{})) |_| {
        confidence += 30;
        try files.append(allocator, "node_modules/");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for .nvmrc or .node-version
    if (dir.access(".nvmrc", .{})) |_| {
        confidence += 10;
        try files.append(allocator, ".nvmrc");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    if (dir.access(".node-version", .{})) |_| {
        confidence += 10;
        try files.append(allocator, ".node-version");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    return .{
        .detected = confidence > 0,
        .confidence = @min(confidence, 100),
        .files_found = try files.toOwnedSlice(allocator),
    };
}

/// Extract npm scripts from package.json
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
    errdefer tasks.deinit(allocator);

    var iter = scripts_obj.object.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* != .string) continue;

        const name = try allocator.dupe(u8, entry.key_ptr.*);
        const cmd = try std.fmt.allocPrint(allocator, "npm run {s}", .{entry.key_ptr.*});
        const desc = try std.fmt.allocPrint(allocator, "Run npm script: {s}", .{entry.value_ptr.string});

        try tasks.append(allocator, .{
            .name = name,
            .command = cmd,
            .description = desc,
        });
    }

    return try tasks.toOwnedSlice(allocator);
}

test "resolveDownloadUrl" {
    const allocator = std.testing.allocator;
    const version = ToolVersion{ .major = 20, .minor = 11, .patch = 1 };
    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.indexOf(u8, spec.url, "https://nodejs.org/dist/v20.11.1") != null);
    try std.testing.expectEqual(provider.ArchiveType.tar_gz, spec.archive_type);
}

test "getBinaryPath" {
    const allocator = std.testing.allocator;
    const linux = PlatformInfo{ .os = "linux", .arch = "x64" };
    const windows = PlatformInfo{ .os = "win", .arch = "x64" };

    const linux_path = try getBinaryPath(allocator, linux);
    defer allocator.free(linux_path);
    try std.testing.expectEqualStrings("bin/node", linux_path);

    const win_path = try getBinaryPath(allocator, windows);
    defer allocator.free(win_path);
    try std.testing.expectEqualStrings("node.exe", win_path);
}
