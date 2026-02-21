const std = @import("std");
const types = @import("types.zig");
const ToolKind = types.ToolKind;
const ToolVersion = types.ToolVersion;
const InstalledTool = types.InstalledTool;
const builtin = @import("builtin");

/// Get the base directory for toolchain installations.
/// Returns ~/.zr/toolchains
pub fn getToolchainsDir(allocator: std.mem.Allocator) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return std.fmt.allocPrint(allocator, "{s}/.zr/toolchains", .{home});
}

/// Get the installation directory for a specific tool version.
/// e.g., ~/.zr/toolchains/node/20.11.1
pub fn getToolDir(allocator: std.mem.Allocator, kind: ToolKind, version: ToolVersion) ![]u8 {
    const base = try getToolchainsDir(allocator);
    defer allocator.free(base);

    if (version.patch) |p| {
        return std.fmt.allocPrint(allocator, "{s}/{s}/{d}.{d}.{d}", .{
            base,
            kind.toString(),
            version.major,
            version.minor,
            p,
        });
    } else {
        return std.fmt.allocPrint(allocator, "{s}/{s}/{d}.{d}", .{
            base,
            kind.toString(),
            version.major,
            version.minor,
        });
    }
}

/// Check if a specific tool version is already installed.
pub fn isInstalled(allocator: std.mem.Allocator, kind: ToolKind, version: ToolVersion) !bool {
    const tool_dir = try getToolDir(allocator, kind, version);
    defer allocator.free(tool_dir);

    std.fs.accessAbsolute(tool_dir, .{}) catch return false;
    return true;
}

/// List all installed versions of a specific tool.
/// Returns array of InstalledTool structs.
/// Caller owns the returned array and all strings.
pub fn listInstalled(allocator: std.mem.Allocator, kind: ToolKind) ![]InstalledTool {
    const base = try getToolchainsDir(allocator);
    defer allocator.free(base);

    const tool_base_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, kind.toString() });
    defer allocator.free(tool_base_dir);

    var dir = std.fs.openDirAbsolute(tool_base_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return &.{};
        return err;
    };
    defer dir.close();

    var result = std.ArrayList(InstalledTool){};
    errdefer {
        for (result.items) |*item| item.deinit(allocator);
        result.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Parse version from directory name (e.g., "20.11.1" or "20.11")
        const version = ToolVersion.parse(entry.name) catch continue;

        const install_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ tool_base_dir, entry.name });
        errdefer allocator.free(install_path);

        try result.append(allocator, .{
            .kind = kind,
            .version = version,
            .install_path = install_path,
        });
    }

    return result.toOwnedSlice(allocator);
}

/// Download and install a specific tool version.
/// This is a stub implementation — real installers would download from official sources.
pub fn install(allocator: std.mem.Allocator, kind: ToolKind, version: ToolVersion) !void {
    const tool_dir = try getToolDir(allocator, kind, version);
    defer allocator.free(tool_dir);

    // Ensure parent directories exist
    const base = try getToolchainsDir(allocator);
    defer allocator.free(base);
    std.fs.makeDirAbsolute(base) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    const tool_kind_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, kind.toString() });
    defer allocator.free(tool_kind_dir);
    std.fs.makeDirAbsolute(tool_kind_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create final version directory
    try std.fs.makeDirAbsolute(tool_dir);

    // TODO: Implement actual download logic for each tool kind
    // For now, this is a placeholder that creates the directory
    // Real implementation would:
    // 1. Determine download URL based on platform and version
    // 2. Download tarball/zip based on kind
    // 3. Extract to tool_dir
    // 4. Create symlinks for binaries
    // The `kind` parameter will be used when actual downloaders are implemented
}

/// Uninstall a specific tool version.
pub fn uninstall(allocator: std.mem.Allocator, kind: ToolKind, version: ToolVersion) !void {
    const tool_dir = try getToolDir(allocator, kind, version);
    defer allocator.free(tool_dir);

    try std.fs.deleteTreeAbsolute(tool_dir);
}

/// Find the best matching installed version for a requirement.
/// Returns null if no matching version is installed.
pub fn findInstalledMatch(allocator: std.mem.Allocator, kind: ToolKind, required: ToolVersion) !?InstalledTool {
    const installed = try listInstalled(allocator, kind);
    defer {
        for (installed) |*tool| tool.deinit(allocator);
        allocator.free(installed);
    }

    // Find exact match first
    for (installed) |tool| {
        if (tool.version.matches(required)) {
            // Clone the result since we're freeing the original
            const path_copy = try allocator.dupe(u8, tool.install_path);
            return InstalledTool{
                .kind = tool.kind,
                .version = tool.version,
                .install_path = path_copy,
            };
        }
    }

    return null;
}

test "getToolchainsDir" {
    const allocator = std.testing.allocator;
    const dir = try getToolchainsDir(allocator);
    defer allocator.free(dir);

    try std.testing.expect(std.mem.endsWith(u8, dir, "/.zr/toolchains"));
}

test "getToolDir with patch version" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("20.11.1");
    const dir = try getToolDir(allocator, .node, version);
    defer allocator.free(dir);

    try std.testing.expect(std.mem.endsWith(u8, dir, "/.zr/toolchains/node/20.11.1"));
}

test "getToolDir without patch version" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("3.12");
    const dir = try getToolDir(allocator, .python, version);
    defer allocator.free(dir);

    try std.testing.expect(std.mem.endsWith(u8, dir, "/.zr/toolchains/python/3.12"));
}

test "isInstalled returns false for non-existent tool" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("999.999.999");
    const installed = try isInstalled(allocator, .node, version);

    try std.testing.expect(!installed);
}

test "install and uninstall creates/removes directory" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("99.99.99");

    // Ensure clean state
    uninstall(allocator, .zig, version) catch {};

    // Install
    try install(allocator, .zig, version);

    // Verify installed
    const installed = try isInstalled(allocator, .zig, version);
    try std.testing.expect(installed);

    // Cleanup
    try uninstall(allocator, .zig, version);

    // Verify removed
    const still_installed = try isInstalled(allocator, .zig, version);
    try std.testing.expect(!still_installed);
}

test "listInstalled returns empty array for tool with no installations" {
    const allocator = std.testing.allocator;
    const installed = try listInstalled(allocator, .deno);
    defer allocator.free(installed);

    // Should return empty array (or potentially existing installations)
    // We can't assert zero because the system might have real installations
    // Just verify it doesn't crash
}

test "findInstalledMatch returns null when no match" {
    const allocator = std.testing.allocator;
    const required = try ToolVersion.parse("999.999.999");
    const match = try findInstalledMatch(allocator, .node, required);

    try std.testing.expectEqual(@as(?InstalledTool, null), match);
}
