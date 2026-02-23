const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const Release = types.Release;

/// GitHub API endpoint for releases
const GITHUB_API_URL = "https://api.github.com/repos/YOUR_ORG/zr/releases";

/// Current version of zr (from build config)
pub const CURRENT_VERSION = "0.0.5";

/// Check if a newer version is available
pub fn checkForUpdate(
    allocator: std.mem.Allocator,
    include_prerelease: bool,
) !?Release {
    const latest = try getLatestRelease(allocator, include_prerelease);

    if (latest) |rel| {
        // Compare versions
        if (try isNewerVersion(rel.version, CURRENT_VERSION)) {
            return rel;
        } else {
            var mutable_rel = rel;
            mutable_rel.deinit();
            return null;
        }
    }

    return null;
}

/// Get the latest release from GitHub
fn getLatestRelease(
    allocator: std.mem.Allocator,
    include_prerelease: bool,
) !?Release {
    // For now, return null as placeholder
    // In production, this would:
    // 1. Make HTTP request to GitHub API
    // 2. Parse JSON response
    // 3. Find appropriate release for current platform
    // 4. Extract version and download URL
    _ = allocator;
    _ = include_prerelease;
    return null;
}

/// Compare semantic versions
fn isNewerVersion(new_ver: []const u8, current_ver: []const u8) !bool {
    const semver = @import("../util/semver.zig");

    const new_parsed = try semver.Version.parse(new_ver);
    const current_parsed = try semver.Version.parse(current_ver);

    return new_parsed.gt(current_parsed);
}

/// Get platform-specific download URL for a release
pub fn getDownloadUrl(release: Release) ![]const u8 {
    // Construct URL based on platform
    const os_name = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        else => return error.UnsupportedPlatform,
    };

    const arch_name = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => return error.UnsupportedArchitecture,
    };

    // Format: https://github.com/ORG/zr/releases/download/v0.0.5/zr-v0.0.5-linux-x86_64.tar.gz
    _ = os_name;
    _ = arch_name;
    return release.download_url;
}

test "isNewerVersion comparison" {
    try std.testing.expect(try isNewerVersion("0.0.5", "0.0.4"));
    try std.testing.expect(try isNewerVersion("0.1.0", "0.0.4"));
    try std.testing.expect(try isNewerVersion("1.0.0", "0.0.4"));
    try std.testing.expect(!try isNewerVersion("0.0.4", "0.0.4"));
    try std.testing.expect(!try isNewerVersion("0.0.3", "0.0.4"));
}

test "getDownloadUrl platform detection" {
    const allocator = std.testing.allocator;
    var release = Release.init(allocator);
    defer release.deinit();

    release.download_url = try allocator.dupe(u8, "https://example.com/download");

    const url = try getDownloadUrl(release);
    try std.testing.expect(url.len > 0);
}
