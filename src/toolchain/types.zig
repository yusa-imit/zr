const std = @import("std");

/// Supported toolchain types (language runtimes and tools).
pub const ToolKind = enum {
    node,
    python,
    zig,
    go,
    rust,
    deno,
    bun,
    java,

    pub fn fromString(s: []const u8) ?ToolKind {
        const map = std.StaticStringMap(ToolKind).initComptime(.{
            .{ "node", .node },
            .{ "python", .python },
            .{ "zig", .zig },
            .{ "go", .go },
            .{ "rust", .rust },
            .{ "deno", .deno },
            .{ "bun", .bun },
            .{ "java", .java },
        });
        return map.get(s);
    }

    pub fn toString(self: ToolKind) []const u8 {
        return switch (self) {
            .node => "node",
            .python => "python",
            .zig => "zig",
            .go => "go",
            .rust => "rust",
            .deno => "deno",
            .bun => "bun",
            .java => "java",
        };
    }
};

/// A specific version requirement for a tool (e.g., "20.11", "3.12", "0.15.2").
pub const ToolVersion = struct {
    major: u32,
    minor: u32,
    patch: ?u32, // null = any patch version

    /// Parse a version string like "20.11" or "0.15.2".
    pub fn parse(s: []const u8) !ToolVersion {
        var parts = std.mem.splitScalar(u8, s, '.');
        const major_str = parts.next() orelse return error.InvalidVersion;
        const minor_str = parts.next() orelse return error.InvalidVersion;
        const patch_str = parts.next();

        const major = try std.fmt.parseInt(u32, major_str, 10);
        const minor = try std.fmt.parseInt(u32, minor_str, 10);
        const patch: ?u32 = if (patch_str) |p| try std.fmt.parseInt(u32, p, 10) else null;

        return ToolVersion{ .major = major, .minor = minor, .patch = patch };
    }

    /// Convert to string (caller owns the returned memory).
    pub fn toString(self: ToolVersion, allocator: std.mem.Allocator) ![]u8 {
        if (self.patch) |p| {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.major, self.minor, p });
        } else {
            return std.fmt.allocPrint(allocator, "{d}.{d}", .{ self.major, self.minor });
        }
    }

    /// Check if this version matches a requirement (semantic).
    /// If req.patch is null, any patch version is accepted.
    pub fn matches(self: ToolVersion, req: ToolVersion) bool {
        if (self.major != req.major or self.minor != req.minor) return false;
        if (req.patch) |req_p| {
            return (self.patch orelse 0) == req_p;
        }
        return true; // req.patch is null, so any patch matches
    }
};

/// A tool specification from [tools] section in zr.toml.
pub const ToolSpec = struct {
    kind: ToolKind,
    version: ToolVersion,

    pub fn deinit(_: *ToolSpec, _: std.mem.Allocator) void {
        // No dynamic allocations yet
    }
};

/// Configuration for all tools declared in [tools] section.
pub const ToolchainConfig = struct {
    tools: []ToolSpec,

    pub fn init(_: std.mem.Allocator) ToolchainConfig {
        return .{ .tools = &.{} };
    }

    pub fn deinit(self: *ToolchainConfig, allocator: std.mem.Allocator) void {
        for (self.tools) |*t| t.deinit(allocator);
        if (self.tools.len > 0) allocator.free(self.tools);
    }
};

/// Represents an installed toolchain on disk.
pub const InstalledTool = struct {
    kind: ToolKind,
    version: ToolVersion,
    install_path: []const u8, // e.g., "~/.zr/toolchains/node/20.11.1"

    pub fn deinit(self: *InstalledTool, allocator: std.mem.Allocator) void {
        allocator.free(self.install_path);
    }
};

test "ToolKind fromString/toString roundtrip" {
    const kinds = [_]ToolKind{ .node, .python, .zig, .go, .rust, .deno, .bun, .java };
    for (kinds) |k| {
        const s = k.toString();
        const parsed = ToolKind.fromString(s);
        try std.testing.expectEqual(k, parsed.?);
    }
}

test "ToolVersion parse and format" {
    const v1 = try ToolVersion.parse("20.11");
    try std.testing.expectEqual(@as(u32, 20), v1.major);
    try std.testing.expectEqual(@as(u32, 11), v1.minor);
    try std.testing.expectEqual(@as(?u32, null), v1.patch);

    const v2 = try ToolVersion.parse("0.15.2");
    try std.testing.expectEqual(@as(u32, 0), v2.major);
    try std.testing.expectEqual(@as(u32, 15), v2.minor);
    try std.testing.expectEqual(@as(?u32, 2), v2.patch);

    const allocator = std.testing.allocator;
    const formatted = try v1.toString(allocator);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("20.11", formatted);

    const formatted2 = try v2.toString(allocator);
    defer allocator.free(formatted2);
    try std.testing.expectEqualStrings("0.15.2", formatted2);
}

test "ToolVersion matches" {
    const req_any_patch = try ToolVersion.parse("20.11");
    const v1 = try ToolVersion.parse("20.11.0");
    const v2 = try ToolVersion.parse("20.11.5");
    const v3 = try ToolVersion.parse("20.12.0");

    try std.testing.expect(v1.matches(req_any_patch));
    try std.testing.expect(v2.matches(req_any_patch));
    try std.testing.expect(!v3.matches(req_any_patch));

    const req_exact = try ToolVersion.parse("0.15.2");
    const v4 = try ToolVersion.parse("0.15.2");
    const v5 = try ToolVersion.parse("0.15.3");

    try std.testing.expect(v4.matches(req_exact));
    try std.testing.expect(!v5.matches(req_exact));
}
