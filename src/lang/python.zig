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
    .extractTasks = extractTasks,
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

/// Extract common Python tasks from pyproject.toml, setup.py, or infer from requirements.txt
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

    // Try pyproject.toml (Poetry/Hatch/PDM scripts)
    if (dir.openFile("pyproject.toml", .{})) |file| {
        defer file.close();
        if (file.readToEndAlloc(allocator, 1024 * 1024)) |content| {
            defer allocator.free(content);
            try extractFromPyprojectToml(allocator, content, &tasks);
        } else |_| {
            // File exists but can't read, skip
        }
    } else |_| {}

    // Always add common Python tasks if not already present
    const has_test = for (tasks.items) |t| {
        if (std.mem.eql(u8, t.name, "test")) break true;
    } else false;

    if (!has_test) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "test"),
            .command = try allocator.dupe(u8, "python -m pytest"),
            .description = try allocator.dupe(u8, "Run tests with pytest"),
        });
    }

    const has_lint = for (tasks.items) |t| {
        if (std.mem.eql(u8, t.name, "lint")) break true;
    } else false;

    if (!has_lint) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "lint"),
            .command = try allocator.dupe(u8, "python -m ruff check ."),
            .description = try allocator.dupe(u8, "Lint code with ruff"),
        });
    }

    const has_format = for (tasks.items) |t| {
        if (std.mem.eql(u8, t.name, "format")) break true;
    } else false;

    if (!has_format) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "format"),
            .command = try allocator.dupe(u8, "python -m black ."),
            .description = try allocator.dupe(u8, "Format code with black"),
        });
    }

    return try tasks.toOwnedSlice(allocator);
}

/// Extract scripts from pyproject.toml [tool.poetry.scripts] or [project.scripts]
fn extractFromPyprojectToml(allocator: std.mem.Allocator, content: []const u8, tasks: *std.ArrayList(LanguageProvider.TaskSuggestion)) !void {
    // Simple line-by-line parser for [tool.poetry.scripts] or [project.scripts] sections
    var in_scripts_section = false;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Detect section headers
        if (std.mem.startsWith(u8, trimmed, "[tool.poetry.scripts]") or
            std.mem.startsWith(u8, trimmed, "[project.scripts]"))
        {
            in_scripts_section = true;
            continue;
        }

        // Exit section on new header
        if (std.mem.startsWith(u8, trimmed, "[") and in_scripts_section) {
            in_scripts_section = false;
            continue;
        }

        if (!in_scripts_section) continue;

        // Parse script lines: name = "command" or name = "module:function"
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
            const name_part = std.mem.trim(u8, trimmed[0..eq_pos], &std.ascii.whitespace);
            const value_part = std.mem.trim(u8, trimmed[eq_pos + 1 ..], &std.ascii.whitespace);

            if (name_part.len == 0 or value_part.len == 0) continue;

            // Remove quotes from value
            const unquoted = if (std.mem.startsWith(u8, value_part, "\"") and std.mem.endsWith(u8, value_part, "\""))
                value_part[1 .. value_part.len - 1]
            else if (std.mem.startsWith(u8, value_part, "'") and std.mem.endsWith(u8, value_part, "'"))
                value_part[1 .. value_part.len - 1]
            else
                value_part;

            const name = try allocator.dupe(u8, name_part);
            const cmd = try std.fmt.allocPrint(allocator, "python -m {s}", .{unquoted});
            const desc = try std.fmt.allocPrint(allocator, "Run Python script: {s}", .{unquoted});

            try tasks.append(allocator, .{
                .name = name,
                .command = cmd,
                .description = desc,
            });
        }
    }
}
