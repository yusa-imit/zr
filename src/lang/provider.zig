const std = @import("std");
const builtin = @import("builtin");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;

/// Archive type for toolchain downloads
pub const ArchiveType = enum {
    tar_gz,
    tar_xz,
    zip,
};

/// Download specification for a toolchain
pub const DownloadSpec = struct {
    url: []const u8,
    archive_type: ArchiveType,
};

/// Platform and architecture information
pub const PlatformInfo = struct {
    os: []const u8, // "linux", "darwin", "win"
    arch: []const u8, // "x64", "arm64"

    pub fn current() PlatformInfo {
        const os_tag = builtin.os.tag;
        const arch_tag = builtin.cpu.arch;

        const os_str = switch (os_tag) {
            .linux => "linux",
            .macos => "darwin",
            .windows => "win",
            else => "unknown",
        };

        const arch_str = switch (arch_tag) {
            .x86_64 => "x64",
            .aarch64 => "arm64",
            else => "unknown",
        };

        return .{
            .os = os_str,
            .arch = arch_str,
        };
    }
};

/// Project detection result
pub const ProjectInfo = struct {
    detected: bool,
    confidence: u8, // 0-100
    files_found: []const []const u8, // e.g., ["package.json", "node_modules/"]
};

/// Language-specific toolchain provider interface
pub const LanguageProvider = struct {
    /// Name of the language/toolchain (e.g., "node", "python")
    name: []const u8,

    /// Function to resolve download URL for a version
    resolveDownloadUrl: *const fn (allocator: std.mem.Allocator, version: ToolVersion, platform: PlatformInfo) anyerror!DownloadSpec,

    /// Function to fetch latest version from registry
    fetchLatestVersion: *const fn (allocator: std.mem.Allocator) anyerror!ToolVersion,

    /// Function to get binary path within toolchain directory
    /// e.g., for Node: "bin/node", for Python: "bin/python3"
    getBinaryPath: *const fn (allocator: std.mem.Allocator, platform: PlatformInfo) anyerror![]const u8,

    /// Function to get additional environment variables needed
    /// e.g., JAVA_HOME, GOROOT
    getEnvironmentVars: ?*const fn (allocator: std.mem.Allocator, install_dir: []const u8) anyerror!std.StringHashMap([]const u8),

    /// Detect if this language is used in a project directory
    detectProject: *const fn (allocator: std.mem.Allocator, dir_path: []const u8) anyerror!ProjectInfo,

    /// Extract common tasks from project (e.g., npm scripts, Makefile targets)
    /// Returns null if not implemented
    extractTasks: ?*const fn (allocator: std.mem.Allocator, dir_path: []const u8) anyerror![]TaskSuggestion,

    /// Suggested task for auto-generation
    pub const TaskSuggestion = struct {
        name: []const u8,
        command: []const u8,
        description: []const u8,
    };
};

/// Helper function to fetch URL content using curl
pub fn fetchUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var argv = [_][]const u8{
        "curl",
        "-sL", // silent, follow redirects
        url,
    };

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
    });

    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.CurlFailed;
    }

    return result.stdout; // caller owns memory
}

test "PlatformInfo.current" {
    const platform = PlatformInfo.current();
    try std.testing.expect(platform.os.len > 0);
    try std.testing.expect(platform.arch.len > 0);
}
