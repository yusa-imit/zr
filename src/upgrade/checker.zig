//! Update check: fetches the GitHub releases list and reports a newer zr release, if any.
//!
//! Every failure of the network path (DNS, connect, read, oversize or malformed response)
//! degrades to "no update" rather than an error; the response read is bounded by
//! `response_bytes_max`. Returned `Release` values own their strings (see `Release.deinit`).

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const Release = types.Release;

/// GitHub API endpoint for releases
const GITHUB_API_URL = "https://api.github.com/repos/yusa-imit/zr/releases";

/// Upper bound on the GitHub releases response; a page of releases is a few hundred KiB.
const response_bytes_max: usize = 8 * 1024 * 1024;

/// Current version of zr, injected from build.zig.zon via build options
pub const CURRENT_VERSION = @import("build_options").version;

/// Looks up the release `zr upgrade` should install. Without `selection.version` that is the
/// newest release, and only when it is newer than `CURRENT_VERSION`. With an explicit version it
/// is that release, whether older or newer, unless it is the running version. Null means
/// nothing to install (including every network failure).
pub fn checkForUpdate(allocator: std.mem.Allocator, selection: Selection) !?Release {
    var release = (try getLatestRelease(allocator, selection)) orelse return null;
    errdefer release.deinit();

    const wanted = selection.version != null;
    const install = if (wanted)
        !std.mem.eql(u8, release.version, CURRENT_VERSION)
    else
        try isNewerVersion(release.version, CURRENT_VERSION);
    if (install) return release;

    release.deinit();
    return null;
}

/// Get the latest release from GitHub
fn getLatestRelease(allocator: std.mem.Allocator, selection: Selection) !?Release {
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
    const response = try readResponseBounded(allocator, &stream, response_bytes_max) orelse
        return null;
    defer allocator.free(response);

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

    if (parsed.value != .array) return null;
    return try selectRelease(allocator, parsed.value.array.items, selection);
}

/// Which release `selectRelease` is looking for.
pub const Selection = struct {
    /// Let a prerelease win when no explicit `version` is given.
    include_prerelease: bool,
    /// Exact version wanted (`1.2.3` or `v1.2.3`); null means the newest eligible release.
    version: ?[]const u8,
};

/// Picks the release to offer from the GitHub releases array (newest first). Entries that are
/// not objects or lack `tag_name`, `prerelease`, `created_at` or `assets` are skipped: the
/// array comes off the network, so a malformed entry is data, not a programmer error. An
/// explicit `selection.version` matches its own tag even when that release is a prerelease.
fn selectRelease(
    allocator: std.mem.Allocator,
    releases: []const std.json.Value,
    selection: Selection,
) !?Release {
    const wanted: ?[]const u8 = if (selection.version) |ver| trimVersionPrefix(ver) else null;
    if (wanted) |ver| std.debug.assert(ver.len > 0);

    for (releases) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const prerelease_value = obj.get("prerelease") orelse continue;
        const tag_value = obj.get("tag_name") orelse continue;
        const created_value = obj.get("created_at") orelse continue;
        if (prerelease_value != .bool or tag_value != .string or created_value != .string) continue;

        const version = trimVersionPrefix(tag_value.string);
        if (wanted) |ver| {
            if (!std.mem.eql(u8, ver, version)) continue;
        } else if (prerelease_value.bool and !selection.include_prerelease) continue;

        const assets_value = obj.get("assets") orelse continue;
        if (assets_value != .array) continue;

        const download_url = try getDownloadUrlFromAssets(allocator, assets_value.array.items);
        errdefer allocator.free(download_url);

        var release = Release.init(allocator);
        errdefer release.deinit();
        release.download_url = download_url;
        release.version = try allocator.dupe(u8, version);
        release.created_at = try allocator.dupe(u8, created_value.string);
        return release;
    }

    return null;
}

fn trimVersionPrefix(version: []const u8) []const u8 {
    if (std.mem.startsWith(u8, version, "v")) return version[1..];
    return version;
}

/// Reads `source` until end-of-stream into a caller-owned buffer. Returns null when the peer
/// sends more than `bytes_max` bytes or a read fails: an update check must degrade to "no update
/// found", never exhaust memory on a hostile or broken server. `source` needs
/// `fn read(*Source, []u8) !usize`. Precondition: `bytes_max > 0`.
fn readResponseBounded(
    allocator: std.mem.Allocator,
    source: anytype,
    bytes_max: usize,
) error{OutOfMemory}!?[]u8 {
    std.debug.assert(bytes_max > 0);

    var response_buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer response_buf.deinit(allocator);

    var buf: [4096]u8 = undefined;
    // Every iteration either ends the stream or adds at least one byte, so `bytes_max + 1`
    // productive iterations would already have exceeded the limit and returned.
    for (0..bytes_max + 1) |_| {
        const n = source.read(&buf) catch {
            response_buf.deinit(allocator);
            return null;
        };
        if (n == 0) return try response_buf.toOwnedSlice(allocator);
        if (response_buf.items.len + n > bytes_max) {
            response_buf.deinit(allocator);
            return null;
        }
        try response_buf.appendSlice(allocator, buf[0..n]);
    } else unreachable;
}

/// Extract platform-specific download URL from GitHub release assets
fn getDownloadUrlFromAssets(
    allocator: std.mem.Allocator,
    assets: []const std.json.Value,
) error{ OutOfMemory, UnsupportedPlatform, UnsupportedArchitecture, NoMatchingAsset }![]const u8 {
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

    const target_pattern = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ os_name, arch_name });
    defer allocator.free(target_pattern);

    // Find matching asset
    for (assets) |asset_item| {
        if (asset_item != .object) continue;
        const name_value = asset_item.object.get("name") orelse continue;
        const url_value = asset_item.object.get("browser_download_url") orelse continue;
        if (name_value != .string or url_value != .string) continue;

        if (std.mem.indexOf(u8, name_value.string, target_pattern) != null) {
            return try allocator.dupe(u8, url_value.string);
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

/// Test double for a socket: serves `data` in chunks of at most `chunk_size` bytes, then either
/// signals end-of-stream or fails, and never ends when `endless` is set.
const FakeStream = struct {
    data: []const u8,
    chunk_size: usize,
    offset: usize = 0,
    endless: bool = false,
    fail_after_data: bool = false,

    fn read(stream: *FakeStream, buf: []u8) error{ConnectionResetByPeer}!usize {
        if (stream.endless) {
            const n = @min(buf.len, stream.chunk_size);
            @memset(buf[0..n], 'x');
            return n;
        }
        if (stream.offset == stream.data.len) {
            if (stream.fail_after_data) return error.ConnectionResetByPeer;
            return 0;
        }
        const n = @min(@min(buf.len, stream.chunk_size), stream.data.len - stream.offset);
        @memcpy(buf[0..n], stream.data[stream.offset..][0..n]);
        stream.offset += n;
        return n;
    }
};

test "readResponseBounded returns the whole response when under the limit" {
    const allocator = std.testing.allocator;
    var stream: FakeStream = .{ .data = "HTTP/1.1 200 OK\r\n\r\n[]", .chunk_size = 5 };

    const response = (try readResponseBounded(allocator, &stream, 64)).?;
    defer allocator.free(response);

    try std.testing.expectEqualStrings("HTTP/1.1 200 OK\r\n\r\n[]", response);
}

test "readResponseBounded accepts an empty response" {
    const allocator = std.testing.allocator;
    var stream: FakeStream = .{ .data = "", .chunk_size = 5 };

    const response = (try readResponseBounded(allocator, &stream, 64)).?;
    defer allocator.free(response);

    try std.testing.expectEqual(@as(usize, 0), response.len);
}

test "readResponseBounded accepts a response of exactly the limit" {
    const allocator = std.testing.allocator;
    var stream: FakeStream = .{ .data = "0123456789", .chunk_size = 3 };

    const response = (try readResponseBounded(allocator, &stream, 10)).?;
    defer allocator.free(response);

    try std.testing.expectEqualStrings("0123456789", response);
}

test "readResponseBounded rejects a response one byte over the limit" {
    const allocator = std.testing.allocator;
    var stream: FakeStream = .{ .data = "0123456789A", .chunk_size = 3 };

    try std.testing.expectEqual(null, try readResponseBounded(allocator, &stream, 10));
}

test "readResponseBounded stops on a peer that never ends the stream" {
    const allocator = std.testing.allocator;
    var stream: FakeStream = .{ .data = "", .chunk_size = 1, .endless = true };

    try std.testing.expectEqual(null, try readResponseBounded(allocator, &stream, 100));
}

test "readResponseBounded returns null on a read error" {
    const allocator = std.testing.allocator;
    var stream: FakeStream = .{ .data = "partial", .chunk_size = 4, .fail_after_data = true };

    try std.testing.expectEqual(null, try readResponseBounded(allocator, &stream, 64));
}

test "getDownloadUrl platform detection" {
    const allocator = std.testing.allocator;
    var release = Release.init(allocator);
    defer release.deinit();

    release.download_url = try allocator.dupe(u8, "https://example.com/download");

    const url = try getDownloadUrl(release);
    try std.testing.expect(url.len > 0);
}

fn parseReleasesFixture(
    allocator: std.mem.Allocator,
    json_text: []const u8,
) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
}

/// Builds a releases array, newest first, in which every release carries one asset for the
/// platform running the tests. A stray string sits in the array to exercise malformed input.
fn releasesFixtureText(allocator: std.mem.Allocator) ![]u8 {
    const target = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos",
        else => "windows",
    } ++ "-" ++ switch (builtin.cpu.arch) {
        .aarch64 => "aarch64",
        else => "x86_64",
    };
    return try std.fmt.allocPrint(allocator,
        \\[
        \\{{"tag_name":"v2.0.0-rc1","prerelease":true,"created_at":"c3","assets":[
        \\{{"name":"zr-{[t]s}.tgz","browser_download_url":"https://x/rc1"}}]}},
        \\"junk",
        \\{{"tag_name":"v1.5.0","prerelease":false,"created_at":"c2","assets":[
        \\{{"name":"zr-{[t]s}.tgz","browser_download_url":"https://x/150"}}]}},
        \\{{"tag_name":"v1.4.0","prerelease":false,"created_at":"c1","assets":[
        \\{{"name":"zr-{[t]s}.tgz","browser_download_url":"https://x/140"}}]}}
        \\]
    , .{ .t = target });
}

test "selectRelease without a version returns the newest stable release" {
    const allocator = std.testing.allocator;
    const text = try releasesFixtureText(allocator);
    defer allocator.free(text);
    var parsed = try parseReleasesFixture(allocator, text);
    defer parsed.deinit();

    var release = (try selectRelease(allocator, parsed.value.array.items, .{
        .include_prerelease = false,
        .version = null,
    })).?;
    defer release.deinit();

    try std.testing.expectEqualStrings("1.5.0", release.version);
    try std.testing.expectEqualStrings("c2", release.created_at);
    try std.testing.expectEqualStrings("https://x/150", release.download_url);
}

test "selectRelease without a version returns a prerelease only when asked" {
    const allocator = std.testing.allocator;
    const text = try releasesFixtureText(allocator);
    defer allocator.free(text);
    var parsed = try parseReleasesFixture(allocator, text);
    defer parsed.deinit();

    var release = (try selectRelease(allocator, parsed.value.array.items, .{
        .include_prerelease = true,
        .version = null,
    })).?;
    defer release.deinit();

    try std.testing.expectEqualStrings("2.0.0-rc1", release.version);
}

test "selectRelease with a version returns that release, not the newest" {
    const allocator = std.testing.allocator;
    const text = try releasesFixtureText(allocator);
    defer allocator.free(text);
    var parsed = try parseReleasesFixture(allocator, text);
    defer parsed.deinit();

    var plain = (try selectRelease(allocator, parsed.value.array.items, .{
        .include_prerelease = false,
        .version = "1.4.0",
    })).?;
    defer plain.deinit();
    var prefixed = (try selectRelease(allocator, parsed.value.array.items, .{
        .include_prerelease = false,
        .version = "v1.4.0",
    })).?;
    defer prefixed.deinit();

    try std.testing.expectEqualStrings("1.4.0", plain.version);
    try std.testing.expectEqualStrings("https://x/140", plain.download_url);
    try std.testing.expectEqualStrings("1.4.0", prefixed.version);
}

test "selectRelease with a version finds a prerelease without include_prerelease" {
    const allocator = std.testing.allocator;
    const text = try releasesFixtureText(allocator);
    defer allocator.free(text);
    var parsed = try parseReleasesFixture(allocator, text);
    defer parsed.deinit();

    var release = (try selectRelease(allocator, parsed.value.array.items, .{
        .include_prerelease = false,
        .version = "2.0.0-rc1",
    })).?;
    defer release.deinit();

    try std.testing.expectEqualStrings("2.0.0-rc1", release.version);
}

test "selectRelease returns null for a version that was never released" {
    const allocator = std.testing.allocator;
    const text = try releasesFixtureText(allocator);
    defer allocator.free(text);
    var parsed = try parseReleasesFixture(allocator, text);
    defer parsed.deinit();

    try std.testing.expectEqual(null, try selectRelease(allocator, parsed.value.array.items, .{
        .include_prerelease = true,
        .version = "9.9.9",
    }));
}

test "selectRelease skips malformed entries and reports a missing platform asset" {
    const allocator = std.testing.allocator;
    var parsed = try parseReleasesFixture(allocator,
        \\[1, {"tag_name":"v3.0.0"}, {"tag_name":"v2.0.0","prerelease":false,"created_at":"c",
        \\"assets":[{"name":"zr-plan9-arm.tgz","browser_download_url":"https://x/p9"}]}]
    );
    defer parsed.deinit();

    const items = parsed.value.array.items;
    try std.testing.expectError(error.NoMatchingAsset, selectRelease(allocator, items, .{
        .include_prerelease = false,
        .version = null,
    }));
    try std.testing.expectEqual(null, try selectRelease(allocator, items[0..2], .{
        .include_prerelease = false,
        .version = null,
    }));
}
