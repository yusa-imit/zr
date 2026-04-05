const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const ArchiveType = provider.ArchiveType;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const JavaProvider: LanguageProvider = .{
    .name = "java",
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

    const java_platform = blk: {
        if (std.mem.eql(u8, platform.os, "linux")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "linux-x64";
            } else if (std.mem.eql(u8, platform.arch, "arm64")) {
                break :blk "linux-aarch64";
            }
        } else if (std.mem.eql(u8, platform.os, "darwin")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "macos-x64";
            } else if (std.mem.eql(u8, platform.arch, "arm64")) {
                break :blk "macos-aarch64";
            }
        } else if (std.mem.eql(u8, platform.os, "win")) {
            if (std.mem.eql(u8, platform.arch, "x64")) {
                break :blk "windows-x64";
            }
        }
        return error.UnsupportedPlatform;
    };

    // Using Adoptium (Eclipse Temurin) builds
    const url = try std.fmt.allocPrint(allocator, "https://github.com/adoptium/temurin{s}-binaries/releases/download/jdk-{s}/OpenJDK{s}U-jdk_{s}_hotspot_{s}.tar.gz", .{
        version_str,
        version_str,
        version_str,
        java_platform,
        version_str,
    });

    return .{ .url = url, .archive_type = .tar_gz };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    _ = allocator;
    return ToolVersion{ .major = 21, .minor = 0, .patch = 1 };
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "bin/java.exe");
    } else {
        return try allocator.dupe(u8, "bin/java");
    }
}

fn getEnvironmentVars(allocator: std.mem.Allocator, install_dir: []const u8) !std.StringHashMap([]const u8) {
    var env_map = std.StringHashMap([]const u8).init(allocator);
    errdefer env_map.deinit();

    const java_home = try allocator.dupe(u8, install_dir);
    try env_map.put("JAVA_HOME", java_home);

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
        .{ .file = "pom.xml", .points = 60 },
        .{ .file = "build.gradle", .points = 60 },
        .{ .file = "build.gradle.kts", .points = 60 },
        .{ .file = "gradlew", .points = 40 },
        .{ .file = "mvnw", .points = 40 },
        .{ .file = ".java-version", .points = 20 },
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

/// Extract common Java tasks based on build tool (Maven or Gradle)
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

    // Detect build tool
    const is_maven = (dir.access("pom.xml", .{}) catch null) != null;
    const is_gradle = (dir.access("build.gradle", .{}) catch null) != null or
        (dir.access("build.gradle.kts", .{}) catch null) != null;
    const has_gradle_wrapper = (dir.access("gradlew", .{}) catch null) != null;
    const has_maven_wrapper = (dir.access("mvnw", .{}) catch null) != null;

    if (is_maven) {
        const mvn_cmd = if (has_maven_wrapper) "./mvnw" else "mvn";

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "build"),
            .command = try std.fmt.allocPrint(allocator, "{s} clean package", .{mvn_cmd}),
            .description = try allocator.dupe(u8, "Build project with Maven"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "test"),
            .command = try std.fmt.allocPrint(allocator, "{s} test", .{mvn_cmd}),
            .description = try allocator.dupe(u8, "Run tests with Maven"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "clean"),
            .command = try std.fmt.allocPrint(allocator, "{s} clean", .{mvn_cmd}),
            .description = try allocator.dupe(u8, "Clean build artifacts"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "install"),
            .command = try std.fmt.allocPrint(allocator, "{s} install", .{mvn_cmd}),
            .description = try allocator.dupe(u8, "Install to local Maven repository"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "verify"),
            .command = try std.fmt.allocPrint(allocator, "{s} verify", .{mvn_cmd}),
            .description = try allocator.dupe(u8, "Run integration tests and verification"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "run"),
            .command = try std.fmt.allocPrint(allocator, "{s} exec:java", .{mvn_cmd}),
            .description = try allocator.dupe(u8, "Execute main class"),
        });
    } else if (is_gradle) {
        const gradle_cmd = if (has_gradle_wrapper) "./gradlew" else "gradle";

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "build"),
            .command = try std.fmt.allocPrint(allocator, "{s} build", .{gradle_cmd}),
            .description = try allocator.dupe(u8, "Build project with Gradle"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "test"),
            .command = try std.fmt.allocPrint(allocator, "{s} test", .{gradle_cmd}),
            .description = try allocator.dupe(u8, "Run tests with Gradle"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "clean"),
            .command = try std.fmt.allocPrint(allocator, "{s} clean", .{gradle_cmd}),
            .description = try allocator.dupe(u8, "Clean build artifacts"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "assemble"),
            .command = try std.fmt.allocPrint(allocator, "{s} assemble", .{gradle_cmd}),
            .description = try allocator.dupe(u8, "Assemble project artifacts"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "check"),
            .command = try std.fmt.allocPrint(allocator, "{s} check", .{gradle_cmd}),
            .description = try allocator.dupe(u8, "Run all checks (tests, linting, etc.)"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "run"),
            .command = try std.fmt.allocPrint(allocator, "{s} run", .{gradle_cmd}),
            .description = try allocator.dupe(u8, "Run the application"),
        });
    } else {
        // Generic Java tasks (no build tool detected)
        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "compile"),
            .command = try allocator.dupe(u8, "javac -d bin src/**/*.java"),
            .description = try allocator.dupe(u8, "Compile Java sources"),
        });

        try tasks.append(allocator, .{
            .name = try allocator.dupe(u8, "run"),
            .command = try allocator.dupe(u8, "java -cp bin Main"),
            .description = try allocator.dupe(u8, "Run main class"),
        });
    }

    return try tasks.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "JavaProvider name" {
    try testing.expectEqualStrings("java", JavaProvider.name);
}

test "resolveDownloadUrl linux-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 21, .minor = 0, .patch = 1 };
    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/adoptium/temurin21.0.1-binaries/releases/download/jdk-21.0.1/OpenJDK21.0.1U-jdk_linux-x64_hotspot_21.0.1.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl linux-arm64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 17, .minor = 0, .patch = 9 };
    const platform = PlatformInfo{ .os = "linux", .arch = "arm64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/adoptium/temurin17.0.9-binaries/releases/download/jdk-17.0.9/OpenJDK17.0.9U-jdk_linux-aarch64_hotspot_17.0.9.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl darwin-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 11, .minor = 0, .patch = 21 };
    const platform = PlatformInfo{ .os = "darwin", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/adoptium/temurin11.0.21-binaries/releases/download/jdk-11.0.21/OpenJDK11.0.21U-jdk_macos-x64_hotspot_11.0.21.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl darwin-arm64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 21, .minor = 0, .patch = 2 };
    const platform = PlatformInfo{ .os = "darwin", .arch = "arm64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/adoptium/temurin21.0.2-binaries/releases/download/jdk-21.0.2/OpenJDK21.0.2U-jdk_macos-aarch64_hotspot_21.0.2.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl windows-x64" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 21, .minor = 0, .patch = 1 };
    const platform = PlatformInfo{ .os = "win", .arch = "x64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try testing.expectEqualStrings("https://github.com/adoptium/temurin21.0.1-binaries/releases/download/jdk-21.0.1/OpenJDK21.0.1U-jdk_windows-x64_hotspot_21.0.1.tar.gz", spec.url);
    try testing.expectEqual(ArchiveType.tar_gz, spec.archive_type);
}

test "resolveDownloadUrl unsupported platform" {
    const allocator = testing.allocator;
    const version = ToolVersion{ .major = 21, .minor = 0, .patch = 1 };
    const platform = PlatformInfo{ .os = "freebsd", .arch = "x64" };

    try testing.expectError(error.UnsupportedPlatform, resolveDownloadUrl(allocator, version, platform));
}

test "getBinaryPath unix" {
    const allocator = testing.allocator;
    const platform = PlatformInfo{ .os = "linux", .arch = "x64" };

    const path = try getBinaryPath(allocator, platform);
    defer allocator.free(path);

    try testing.expectEqualStrings("bin/java", path);
}

test "getBinaryPath windows" {
    const allocator = testing.allocator;
    const platform = PlatformInfo{ .os = "win", .arch = "x64" };

    const path = try getBinaryPath(allocator, platform);
    defer allocator.free(path);

    try testing.expectEqualStrings("bin/java.exe", path);
}

test "getEnvironmentVars sets JAVA_HOME" {
    const allocator = testing.allocator;
    const install_dir = "/opt/java/jdk-21.0.1";

    var env_map = try getEnvironmentVars(allocator, install_dir);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqual(@as(usize, 1), env_map.count());
    const java_home = env_map.get("JAVA_HOME").?;
    try testing.expectEqualStrings(install_dir, java_home);
}

test "fetchLatestVersion returns hardcoded 21.0.1" {
    const allocator = testing.allocator;
    const version = try fetchLatestVersion(allocator);

    try testing.expectEqual(@as(u32, 21), version.major);
    try testing.expectEqual(@as(u32, 0), version.minor);
    try testing.expectEqual(@as(u32, 1), version.patch);
}
