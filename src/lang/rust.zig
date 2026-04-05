const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const ArchiveType = provider.ArchiveType;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const RustProvider: LanguageProvider = .{
    .name = "rust",
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

    const rust_target = blk: {
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
            } else if (std.mem.eql(u8, platform.arch, "arm64")) {
                break :blk "aarch64-pc-windows-msvc";
            }
        }
        return error.UnsupportedPlatform;
    };

    const url = try std.fmt.allocPrint(allocator, "https://static.rust-lang.org/dist/rust-{s}-{s}.tar.gz", .{
        version_str,
        rust_target,
    });

    return .{ .url = url, .archive_type = .tar_gz };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    _ = allocator;
    return ToolVersion{ .major = 1, .minor = 83, .patch = 0 };
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "bin/rustc.exe");
    } else {
        return try allocator.dupe(u8, "bin/rustc");
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
        .{ .file = "Cargo.toml", .points = 70 },
        .{ .file = "Cargo.lock", .points = 30 },
        .{ .file = "rust-toolchain.toml", .points = 20 },
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

/// Extract common Rust/Cargo tasks
fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion {
    _ = dir_path;

    var tasks = std.ArrayList(LanguageProvider.TaskSuggestion){};
    errdefer {
        for (tasks.items) |task| {
            allocator.free(task.name);
            allocator.free(task.command);
            allocator.free(task.description);
        }
        tasks.deinit(allocator);
    }

    // Common Cargo tasks
    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "build"),
        .command = try allocator.dupe(u8, "cargo build"),
        .description = try allocator.dupe(u8, "Build the project"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "build-release"),
        .command = try allocator.dupe(u8, "cargo build --release"),
        .description = try allocator.dupe(u8, "Build with optimizations"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test"),
        .command = try allocator.dupe(u8, "cargo test"),
        .description = try allocator.dupe(u8, "Run all tests"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test-verbose"),
        .command = try allocator.dupe(u8, "cargo test -- --nocapture"),
        .description = try allocator.dupe(u8, "Run tests with output"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "check"),
        .command = try allocator.dupe(u8, "cargo check"),
        .description = try allocator.dupe(u8, "Check for errors without building"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "clippy"),
        .command = try allocator.dupe(u8, "cargo clippy"),
        .description = try allocator.dupe(u8, "Run Clippy linter"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "fmt"),
        .command = try allocator.dupe(u8, "cargo fmt"),
        .description = try allocator.dupe(u8, "Format code with rustfmt"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "fmt-check"),
        .command = try allocator.dupe(u8, "cargo fmt --check"),
        .description = try allocator.dupe(u8, "Check formatting without changing files"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "doc"),
        .command = try allocator.dupe(u8, "cargo doc --no-deps"),
        .description = try allocator.dupe(u8, "Build documentation"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "run"),
        .command = try allocator.dupe(u8, "cargo run"),
        .description = try allocator.dupe(u8, "Build and run the project"),
    });

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "clean"),
        .command = try allocator.dupe(u8, "cargo clean"),
        .description = try allocator.dupe(u8, "Remove build artifacts"),
    });

    return try tasks.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "RustProvider name" {
    try testing.expectEqualStrings("rust", RustProvider.name);
}

test "resolveDownloadUrl linux-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 75, .patch = 0 };
    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://static.rust-lang.org/dist/rust-1.75.0-x86_64-unknown-linux-gnu.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl linux-arm64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 76, .patch = 0 };
    const platform = PlatformInfo{ .os = "linux", .arch = "arm64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://static.rust-lang.org/dist/rust-1.76.0-aarch64-unknown-linux-gnu.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl darwin-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 77, .patch = 1 };
    const platform = PlatformInfo{ .os = "darwin", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://static.rust-lang.org/dist/rust-1.77.1-x86_64-apple-darwin.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl darwin-arm64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 78, .patch = 0 };
    const platform = PlatformInfo{ .os = "darwin", .arch = "arm64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://static.rust-lang.org/dist/rust-1.78.0-aarch64-apple-darwin.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl windows-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 75, .patch = 0 };
    const platform = PlatformInfo{ .os = "win", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://static.rust-lang.org/dist/rust-1.75.0-x86_64-pc-windows-msvc.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl windows-arm64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 83, .patch = 0 };
    const platform = PlatformInfo{ .os = "win", .arch = "arm64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://static.rust-lang.org/dist/rust-1.83.0-aarch64-pc-windows-msvc.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl unsupported platform" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 1, .minor = 75, .patch = 0 };
    const platform = PlatformInfo{ .os = "freebsd", .arch = "x64" };

    try testing.expectError(error.UnsupportedPlatform, resolveDownloadUrl(allocator, version, platform));
}

test "getBinaryPath unix" {
    const allocator = testing.allocator;
    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };

    const path = try getBinaryPath(allocator, platform);
    defer allocator.free(path);

    try testing.expectEqualStrings("bin/rustc", path);
}

test "getBinaryPath windows" {
    const allocator = testing.allocator;
    const platform = PlatformInfo{ .os = "win", .arch = "x64" };

    const path = try getBinaryPath(allocator, platform);
    defer allocator.free(path);

    try testing.expectEqualStrings("bin/rustc.exe", path);
}

test "getEnvironmentVars is null" {
    try testing.expect(RustProvider.getEnvironmentVars == null);
}

test "fetchLatestVersion returns hardcoded 1.83.0" {
    const allocator = testing.allocator;
    const version = try fetchLatestVersion(allocator);

    try testing.expectEqual(@as(u32, 1), version.major);
    try testing.expectEqual(@as(u32, 83), version.minor);
    try testing.expectEqual(@as(u32, 0), version.patch);
}
