const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
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
