const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const Release = types.Release;

/// GitHub API endpoint for releases
const GITHUB_API_URL = "https://api.github.com/repos/yusa-imit/zr/releases";

/// Current version of zr, injected from build.zig.zon via build options
pub const CURRENT_VERSION = @import("build_options").version;

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
    // Parse URL to extract host and path
    const uri = std.Uri.parse(GITHUB_API_URL) catch return null;

    // Connect to GitHub API
    const host = uri.host orelse return null;
    const port: u16 = uri.port orelse 443;

    const address_list = std.net.getAddressList(allocator, host.percent_encoded, port) catch return null;
    defer address_list.deinit();

    if (address_list.addrs.len == 0) return null;

    const stream = std.net.tcpConnectToAddress(address_list.addrs[0]) catch return null;
    defer stream.close();

    // Build HTTP request
    const path = uri.path.percent_encoded;
    const request = try std.fmt.allocPrint(
        allocator,
        "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "User-Agent: zr/{s}\r\n" ++
            "Accept: application/vnd.github.v3+json\r\n" ++
            "Connection: close\r\n" ++
            "\r\n",
        .{ path, host.percent_encoded, CURRENT_VERSION },
    );
    defer allocator.free(request);

    // Send request
    _ = stream.writeAll(request) catch return null;

    // Read response
    var response_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer response_buf.deinit(allocator);

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = stream.read(&buf) catch return null;
        if (n == 0) break;
        try response_buf.appendSlice(allocator, buf[0..n]);
    }

    const response = response_buf.items;

    // Parse HTTP response
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return null;
    const body = response[header_end + 4 ..];

    // Check status code
    const status_line_end = std.mem.indexOf(u8, response, "\r\n") orelse return null;
    const status_line = response[0..status_line_end];

    if (std.mem.indexOf(u8, status_line, "200") == null) return null;

    // Parse JSON response
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    ) catch return null;
    defer parsed.deinit();

    const releases = parsed.value.array;
    if (releases.items.len == 0) return null;

    // Find the latest non-prerelease version (or latest prerelease if requested)
    for (releases.items) |item| {
        const obj = item.object;
        const is_prerelease = obj.get("prerelease").?.bool;

        // Skip prereleases unless requested
        if (is_prerelease and !include_prerelease) continue;

        const tag_name = obj.get("tag_name").?.string;
        const version = if (std.mem.startsWith(u8, tag_name, "v"))
            tag_name[1..]
        else
            tag_name;

        const created_at = obj.get("created_at").?.string;

        // Construct download URL for current platform
        const download_url = try getDownloadUrlFromAssets(allocator, obj);

        var release = Release.init(allocator);
        release.version = try allocator.dupe(u8, version);
        release.created_at = try allocator.dupe(u8, created_at);
        release.download_url = download_url;

        return release;
    }

    return null;
}

/// Extract platform-specific download URL from GitHub release assets
fn getDownloadUrlFromAssets(allocator: std.mem.Allocator, release_obj: std.json.ObjectMap) ![]const u8 {
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

    const assets = release_obj.get("assets").?.array;
    const target_pattern = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ os_name, arch_name });
    defer allocator.free(target_pattern);

    // Find matching asset
    for (assets.items) |asset_item| {
        const asset = asset_item.object;
        const asset_name = asset.get("name").?.string;

        if (std.mem.indexOf(u8, asset_name, target_pattern) != null) {
            const download_url = asset.get("browser_download_url").?.string;
            return try allocator.dupe(u8, download_url);
        }
    }

    return error.NoMatchingAsset;
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

    // Format: https://github.com/yusa-imit/zr/releases/download/v1.0.0/zr-v1.0.0-linux-x86_64.tar.gz
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
