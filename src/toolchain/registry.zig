const std = @import("std");
const types = @import("types.zig");
const ToolKind = types.ToolKind;
const ToolVersion = types.ToolVersion;
const lang_registry = @import("../lang/registry.zig");

/// Fetch the latest stable version for a given toolchain from its official registry.
/// Now delegates to the LanguageProvider system
pub fn fetchLatestVersion(allocator: std.mem.Allocator, kind: ToolKind) !ToolVersion {
    const provider = lang_registry.getProvider(kind);
    return try provider.fetchLatestVersion(allocator);
}

/// Fetch latest Node.js LTS version from nodejs.org/dist/index.json
fn fetchNodeLatest(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://nodejs.org/dist/index.json";
    const json_data = try fetchUrl(allocator, url);
    defer allocator.free(json_data);

    // Parse JSON to find first LTS version
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
                // Found LTS, extract version
                if (obj.get("version")) |ver_field| {
                    if (ver_field == .string) {
                        const ver_str = ver_field.string;
                        // Version format: "v20.11.1" - strip leading 'v'
                        const clean_ver = if (ver_str.len > 0 and ver_str[0] == 'v')
                            ver_str[1..]
                        else
                            ver_str;
                        return ToolVersion.parse(clean_ver) catch continue;
                    }
                }
            } else if (lts_field == .string and lts_field.string.len > 0) {
                // LTS with codename (e.g., "Iron")
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

/// Fetch latest Python version from python.org
fn fetchPythonLatest(allocator: std.mem.Allocator) !ToolVersion {
    // Python doesn't have a simple JSON API, return commonly known latest stable
    _ = allocator;
    return ToolVersion{ .major = 3, .minor = 12, .patch = 7 };
}

/// Fetch latest Zig version from ziglang.org/download/index.json
fn fetchZigLatest(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://ziglang.org/download/index.json";
    const json_data = try fetchUrl(allocator, url);
    defer allocator.free(json_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidJson;

    // Get the "master" field which contains the latest version
    if (root.object.get("master")) |master_field| {
        if (master_field == .object) {
            if (master_field.object.get("version")) |ver_field| {
                if (ver_field == .string) {
                    return ToolVersion.parse(ver_field.string) catch return error.InvalidVersion;
                }
            }
        }
    }

    return error.VersionNotFound;
}

/// Fetch latest Go version from go.dev/dl/?mode=json
fn fetchGoLatest(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://go.dev/dl/?mode=json";
    const json_data = try fetchUrl(allocator, url);
    defer allocator.free(json_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .array) return error.InvalidJson;
    if (root.array.items.len == 0) return error.VersionNotFound;

    // First item is the latest stable version
    const latest = root.array.items[0];
    if (latest != .object) return error.InvalidJson;

    if (latest.object.get("version")) |ver_field| {
        if (ver_field == .string) {
            const ver_str = ver_field.string;
            // Version format: "go1.22.0" - strip "go" prefix
            const clean_ver = if (std.mem.startsWith(u8, ver_str, "go"))
                ver_str[2..]
            else
                ver_str;
            return ToolVersion.parse(clean_ver) catch return error.InvalidVersion;
        }
    }

    return error.VersionNotFound;
}

/// Fetch latest Rust version from static.rust-lang.org/dist/channel-rust-stable.toml
fn fetchRustLatest(allocator: std.mem.Allocator) !ToolVersion {
    // Rust API is complex (TOML parsing required), return commonly known latest stable
    _ = allocator;
    return ToolVersion{ .major = 1, .minor = 83, .patch = 0 };
}

/// Fetch latest Deno version from GitHub API
fn fetchDenoLatest(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://api.github.com/repos/denoland/deno/releases/latest";
    const json_data = try fetchUrl(allocator, url);
    defer allocator.free(json_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidJson;

    if (root.object.get("tag_name")) |tag_field| {
        if (tag_field == .string) {
            const tag_str = tag_field.string;
            // Tag format: "v1.40.0" - strip 'v' prefix
            const clean_ver = if (tag_str.len > 0 and tag_str[0] == 'v')
                tag_str[1..]
            else
                tag_str;
            return ToolVersion.parse(clean_ver) catch return error.InvalidVersion;
        }
    }

    return error.VersionNotFound;
}

/// Fetch latest Bun version from GitHub API
fn fetchBunLatest(allocator: std.mem.Allocator) !ToolVersion {
    const url = "https://api.github.com/repos/oven-sh/bun/releases/latest";
    const json_data = try fetchUrl(allocator, url);
    defer allocator.free(json_data);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidJson;

    if (root.object.get("tag_name")) |tag_field| {
        if (tag_field == .string) {
            const tag_str = tag_field.string;
            // Tag format: "bun-v1.0.25" - strip "bun-v" prefix
            const clean_ver = if (std.mem.startsWith(u8, tag_str, "bun-v"))
                tag_str[5..]
            else if (tag_str.len > 0 and tag_str[0] == 'v')
                tag_str[1..]
            else
                tag_str;
            return ToolVersion.parse(clean_ver) catch return error.InvalidVersion;
        }
    }

    return error.VersionNotFound;
}

/// Fetch latest Java LTS version (hardcoded for now as adoptium API is complex)
fn fetchJavaLatest(allocator: std.mem.Allocator) !ToolVersion {
    _ = allocator;
    return ToolVersion{ .major = 21, .minor = 0, .patch = 5 };
}

/// Fetch URL content using curl (simple HTTP client)
fn fetchUrl(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    // Use curl for HTTP requests
    const argv = &[_][]const u8{ "curl", "-s", "-L", url };

    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = child.stdout.?;
    const output = try stdout.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) {
        allocator.free(output);
        return error.CurlFailed;
    }

    return output;
}

test "ToolVersion comparison" {
    const v1 = ToolVersion{ .major = 20, .minor = 11, .patch = 1 };
    const v2 = ToolVersion{ .major = 20, .minor = 12, .patch = 0 };
    const v3 = ToolVersion{ .major = 20, .minor = 11, .patch = 2 };

    try std.testing.expect(!v1.matches(v2));
    try std.testing.expect(!v1.matches(v3));
}

test "ToolVersion parse" {
    const v1 = try ToolVersion.parse("20.11.1");
    try std.testing.expectEqual(@as(u32, 20), v1.major);
    try std.testing.expectEqual(@as(u32, 11), v1.minor);
    try std.testing.expectEqual(@as(?u32, 1), v1.patch);

    const v2 = try ToolVersion.parse("3.12");
    try std.testing.expectEqual(@as(u32, 3), v2.major);
    try std.testing.expectEqual(@as(u32, 12), v2.minor);
    try std.testing.expectEqual(@as(?u32, null), v2.patch);
}
