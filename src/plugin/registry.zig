const std = @import("std");
const install = @import("install.zig");
const platform = @import("../util/platform.zig");

/// Parsed components of a registry reference string.
/// Format: "org/name@version" or "name@version" or "org/name".
pub const RegistryRef = struct {
    /// Organization prefix (empty string if not present).
    org: []const u8,
    /// Plugin name.
    name: []const u8,
    /// Version tag (empty string means "latest" / default branch).
    version: []const u8,
};

/// Parse a registry source string into its components.
/// Input examples: "zr/docker@1.2.0", "docker@1.0.0", "zr/docker"
/// Caller does NOT own the returned slices — they point into `source`.
pub fn parseRegistryRef(source: []const u8) RegistryRef {
    var org: []const u8 = "";
    var name_ver = source;

    // Split on '/' to find optional org.
    if (std.mem.indexOfScalar(u8, source, '/')) |slash_idx| {
        org = source[0..slash_idx];
        name_ver = source[slash_idx + 1 ..];
    }

    // Split on '@' to find optional version.
    if (std.mem.indexOfScalar(u8, name_ver, '@')) |at_idx| {
        return .{
            .org = org,
            .name = name_ver[0..at_idx],
            .version = name_ver[at_idx + 1 ..],
        };
    }

    return .{ .org = org, .name = name_ver, .version = "" };
}

pub const RegistryInstallError = error{
    InvalidRef,
    GitNotFound,
    CloneFailed,
    AlreadyInstalled,
};

/// Default registry base URL (GitHub org hosting zr-plugin-* repos).
pub const default_registry_base = "https://github.com/zr-runner";

/// Resolve a registry ref to a git URL and install the plugin.
/// Format: "org/name@version" — org defaults to `default_registry_base` if empty.
/// Version is used as a git tag (--branch flag); empty means default branch.
/// Returns the destination path (caller frees).
pub fn installRegistryPlugin(
    allocator: std.mem.Allocator,
    source: []const u8,
    plugin_name_override: ?[]const u8,
) ![]const u8 {
    const ref = parseRegistryRef(source);

    if (ref.name.len == 0) return RegistryInstallError.InvalidRef;

    // Build the git URL.
    // If org is provided and looks like a full org (no dots), use GitHub.
    // Otherwise treat it as a custom org on GitHub.
    const git_url = if (ref.org.len > 0) blk: {
        // org/name → https://github.com/<org>/zr-plugin-<name>
        // Check if name already has "zr-plugin-" prefix to avoid doubling.
        if (std.mem.startsWith(u8, ref.name, "zr-plugin-")) {
            break :blk try std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}", .{ ref.org, ref.name });
        } else {
            break :blk try std.fmt.allocPrint(allocator, "https://github.com/{s}/zr-plugin-{s}", .{ ref.org, ref.name });
        }
    } else blk: {
        // No org: use default registry org.
        if (std.mem.startsWith(u8, ref.name, "zr-plugin-")) {
            break :blk try std.fmt.allocPrint(allocator, "{s}/{s}", .{ default_registry_base, ref.name });
        } else {
            break :blk try std.fmt.allocPrint(allocator, "{s}/zr-plugin-{s}", .{ default_registry_base, ref.name });
        }
    };
    defer allocator.free(git_url);

    // Determine install name: prefer override, then fall back to ref.name.
    const install_name = plugin_name_override orelse ref.name;

    const home = platform.getHome();
    const dest_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, install_name });
    errdefer allocator.free(dest_dir);

    // Check if already installed.
    const already = blk: {
        std.fs.accessAbsolute(dest_dir, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };
    if (already) return RegistryInstallError.AlreadyInstalled;

    // Ensure ~/.zr/plugins/ parent exists.
    const parent = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Build argv: git clone [--branch <version>] --depth=1 <url> <dest>
    var argv = std.ArrayListUnmanaged([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, "git");
    try argv.append(allocator, "clone");
    if (ref.version.len > 0) {
        try argv.append(allocator, "--branch");
        try argv.append(allocator, ref.version);
    }
    try argv.append(allocator, "--depth=1");
    try argv.append(allocator, git_url);
    try argv.append(allocator, dest_dir);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return RegistryInstallError.GitNotFound;
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return RegistryInstallError.CloneFailed,
        else => return RegistryInstallError.CloneFailed,
    }

    // Record registry metadata in plugin.toml.
    writeRegistryRefToMeta(allocator, dest_dir, source) catch {};

    return dest_dir;
}

/// Write (or append) a registry_ref key to a plugin's plugin.toml.
/// Idempotent — will not write if key already exists.
fn writeRegistryRefToMeta(allocator: std.mem.Allocator, plugin_dir: []const u8, registry_ref: []const u8) !void {
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{plugin_dir});
    defer allocator.free(meta_path);

    var existing_buf: [8192]u8 = undefined;
    var existing: []const u8 = "";
    if (std.fs.openFileAbsolute(meta_path, .{})) |f| {
        defer f.close();
        const n = try f.readAll(&existing_buf);
        existing = existing_buf[0..n];
    } else |_| {}

    if (std.mem.indexOf(u8, existing, "registry_ref") != null) return;

    const line = try std.fmt.allocPrint(allocator, "registry_ref = \"{s}\"\n", .{registry_ref});
    defer allocator.free(line);

    const new_content = try std.fmt.allocPrint(allocator, "{s}{s}", .{ existing, line });
    defer allocator.free(new_content);

    const file = try std.fs.createFileAbsolute(meta_path, .{});
    defer file.close();
    try file.writeAll(new_content);
}

/// Read the registry_ref field from a plugin's plugin.toml.
/// Returns null if the field is missing or the file doesn't exist.
/// Caller frees the returned slice.
pub fn readRegistryRef(allocator: std.mem.Allocator, plugin_dir: []const u8) !?[]const u8 {
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{plugin_dir});
    defer allocator.free(meta_path);

    const file = std.fs.openFileAbsolute(meta_path, .{}) catch return null;
    defer file.close();

    var buf: [8192]u8 = undefined;
    const n = try file.readAll(&buf);
    const content = buf[0..n];

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "registry_ref")) continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const raw = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        const val = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
            raw[1 .. raw.len - 1]
        else
            raw;
        return try allocator.dupe(u8, val);
    }
    return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "parseRegistryRef: org/name@version" {
    const ref = parseRegistryRef("zr/docker@1.2.0");
    try std.testing.expectEqualStrings("zr", ref.org);
    try std.testing.expectEqualStrings("docker", ref.name);
    try std.testing.expectEqualStrings("1.2.0", ref.version);
}

test "parseRegistryRef: name@version (no org)" {
    const ref = parseRegistryRef("docker@1.0.0");
    try std.testing.expectEqualStrings("", ref.org);
    try std.testing.expectEqualStrings("docker", ref.name);
    try std.testing.expectEqualStrings("1.0.0", ref.version);
}

test "parseRegistryRef: org/name (no version)" {
    const ref = parseRegistryRef("myorg/myplugin");
    try std.testing.expectEqualStrings("myorg", ref.org);
    try std.testing.expectEqualStrings("myplugin", ref.name);
    try std.testing.expectEqualStrings("", ref.version);
}

test "parseRegistryRef: name only (no org, no version)" {
    const ref = parseRegistryRef("myplugin");
    try std.testing.expectEqualStrings("", ref.org);
    try std.testing.expectEqualStrings("myplugin", ref.name);
    try std.testing.expectEqualStrings("", ref.version);
}

test "installRegistryPlugin: already installed returns AlreadyInstalled" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-registry-dup-88888";

    // Clean up any leftover.
    install.removePlugin(allocator, plugin_name) catch {};

    // Create a fake installed dir to simulate "already installed".
    const home = platform.getHome();
    const fake_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
    defer allocator.free(fake_dir);

    const parent = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    std.fs.makeDirAbsolute(fake_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer install.removePlugin(allocator, plugin_name) catch {};

    const result = installRegistryPlugin(allocator, "zr/docker@1.0.0", plugin_name);
    try std.testing.expectError(RegistryInstallError.AlreadyInstalled, result);
}

test "installRegistryPlugin: invalid empty ref returns InvalidRef" {
    const allocator = std.testing.allocator;
    // An empty string should give InvalidRef (empty name).
    const result = installRegistryPlugin(allocator, "", null);
    try std.testing.expectError(RegistryInstallError.InvalidRef, result);
}

test "writeRegistryRefToMeta and readRegistryRef round-trip" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"docker\"\nversion = \"1.2.0\"\n",
    });

    try writeRegistryRefToMeta(allocator, tmp_path, "zr/docker@1.2.0");

    const ref = try readRegistryRef(allocator, tmp_path);
    defer if (ref) |r| allocator.free(r);

    try std.testing.expect(ref != null);
    try std.testing.expectEqualStrings("zr/docker@1.2.0", ref.?);
}

test "writeRegistryRefToMeta: idempotent" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "plugin.toml", .data = "" });

    try writeRegistryRefToMeta(allocator, tmp_path, "zr/docker@1.0.0");
    try writeRegistryRefToMeta(allocator, tmp_path, "zr/docker@1.0.0");

    const content = try tmp.dir.readFileAlloc(allocator, "plugin.toml", 4096);
    defer allocator.free(content);

    var count: usize = 0;
    var it = std.mem.splitSequence(u8, content, "registry_ref");
    _ = it.next();
    while (it.next()) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "readRegistryRef: returns null when no plugin.toml" {
    const allocator = std.testing.allocator;
    const result = try readRegistryRef(allocator, "/nonexistent/plugin/path");
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "readRegistryRef: returns null when registry_ref key missing" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"nope\"\nversion = \"0.1.0\"\n",
    });

    const result = try readRegistryRef(allocator, tmp_path);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}
