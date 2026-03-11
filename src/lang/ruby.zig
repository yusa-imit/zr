const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const RubyProvider: LanguageProvider = .{
    .name = "ruby",
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

    // Verify platform support
    if (!std.mem.eql(u8, platform.os, "darwin") and !std.mem.eql(u8, platform.os, "linux")) {
        return error.UnsupportedPlatform; // Windows typically uses RubyInstaller
    }

    if (!std.mem.eql(u8, platform.arch, "x64") and !std.mem.eql(u8, platform.arch, "arm64")) {
        return error.UnsupportedArchitecture;
    }

    // Ruby source tarball URL
    const url = try std.fmt.allocPrint(allocator, "https://cache.ruby-lang.org/pub/ruby/{s}/ruby-{s}.tar.gz", .{
        version_str[0..3], // e.g., "3.3" from "3.3.0"
        version_str,
    });

    return .{ .url = url, .archive_type = .tar_gz };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    // Fetch latest stable version from ruby-lang.org
    const url = "https://www.ruby-lang.org/en/downloads/";
    const content = try provider.fetchUrl(allocator, url);
    defer allocator.free(content);

    // For simplicity, default to 3.3 (latest stable as of 2026)
    // A full implementation would parse the HTML/JSON response
    return ToolVersion.parse("3.3.0") catch return error.InvalidVersion;
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    _ = platform;
    return try allocator.dupe(u8, "bin/ruby");
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
        .{ .file = "Gemfile", .points = 70 },
        .{ .file = "Gemfile.lock", .points = 30 },
        .{ .file = "Rakefile", .points = 40 },
        .{ .file = ".ruby-version", .points = 30 },
        .{ .file = ".ruby-gemset", .points = 20 },
        .{ .file = "config.ru", .points = 25 },
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

/// Extract common Ruby tasks (bundle, rake, test, etc.)
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

    // Check for Rakefile to extract Rake tasks
    const has_rakefile = blk: {
        dir.access("Rakefile", .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    const has_gemfile = blk: {
        dir.access("Gemfile", .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    // Common Ruby tasks
    if (has_gemfile) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "install"),
            .command = try allocator.dupe(u8, "bundle install"),
            .description = try allocator.dupe(u8, "Install Ruby gem dependencies"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "update"),
            .command = try allocator.dupe(u8, "bundle update"),
            .description = try allocator.dupe(u8, "Update Ruby gems"),
        });
    }

    if (has_rakefile) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "rake"),
            .command = try allocator.dupe(u8, "rake"),
            .description = try allocator.dupe(u8, "Run default Rake task"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "test"),
            .command = try allocator.dupe(u8, "rake test"),
            .description = try allocator.dupe(u8, "Run tests with Rake"),
        });
    }

    // RSpec tests
    const has_spec = blk: {
        dir.access("spec", .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    if (has_spec) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "spec"),
            .command = try allocator.dupe(u8, "bundle exec rspec"),
            .description = try allocator.dupe(u8, "Run RSpec tests"),
        });
    }

    // Rails-specific tasks
    const has_rails = blk: {
        dir.access("bin/rails", .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    if (has_rails) {
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "server"),
            .command = try allocator.dupe(u8, "bundle exec rails server"),
            .description = try allocator.dupe(u8, "Start Rails development server"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "console"),
            .command = try allocator.dupe(u8, "bundle exec rails console"),
            .description = try allocator.dupe(u8, "Start Rails console"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "db-migrate"),
            .command = try allocator.dupe(u8, "bundle exec rails db:migrate"),
            .description = try allocator.dupe(u8, "Run database migrations"),
        });
    }

    return try tasks.toOwnedSlice(allocator);
}

test "RubyProvider basic" {
    try std.testing.expectEqualStrings("ruby", RubyProvider.name);
}

test "RubyProvider getBinaryPath" {
    const allocator = std.testing.allocator;

    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };
    const bin_path = try RubyProvider.getBinaryPath(allocator, platform);
    defer allocator.free(bin_path);
    try std.testing.expectEqualStrings("bin/ruby", bin_path);
}

test "RubyProvider extractTasks" {
    const allocator = std.testing.allocator;

    // Test with non-existent directory (should return empty array)
    const tasks = try RubyProvider.extractTasks.?(allocator, "/nonexistent");
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
