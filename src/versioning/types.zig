const std = @import("std");

/// Versioning mode for workspace packages
pub const VersioningMode = enum {
    /// All packages share the same version (Angular style)
    fixed,
    /// Each package has independent version (Babel style)
    independent,

    pub fn fromString(s: []const u8) ?VersioningMode {
        if (std.mem.eql(u8, s, "fixed")) return .fixed;
        if (std.mem.eql(u8, s, "independent")) return .independent;
        return null;
    }
};

/// Convention for determining version bumps
pub const VersioningConvention = enum {
    /// Use conventional commits to determine version bump
    conventional,
    /// Manual version specification
    manual,

    pub fn fromString(s: []const u8) ?VersioningConvention {
        if (std.mem.eql(u8, s, "conventional")) return .conventional;
        if (std.mem.eql(u8, s, "manual")) return .manual;
        return null;
    }
};

/// Type of version bump
pub const BumpType = enum {
    major,
    minor,
    patch,

    pub fn fromString(s: []const u8) ?BumpType {
        if (std.mem.eql(u8, s, "major")) return .major;
        if (std.mem.eql(u8, s, "minor")) return .minor;
        if (std.mem.eql(u8, s, "patch")) return .patch;
        return null;
    }
};

/// Versioning configuration
pub const VersioningConfig = struct {
    mode: VersioningMode,
    convention: VersioningConvention,

    pub fn init(mode: VersioningMode, convention: VersioningConvention) VersioningConfig {
        return .{
            .mode = mode,
            .convention = convention,
        };
    }

    pub fn deinit(_: *VersioningConfig) void {}
};

/// Package version information
pub const PackageVersion = struct {
    name: []const u8,
    version: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !PackageVersion {
        return .{
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PackageVersion) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
    }
};

test "VersioningMode.fromString" {
    try std.testing.expectEqual(VersioningMode.fixed, VersioningMode.fromString("fixed").?);
    try std.testing.expectEqual(VersioningMode.independent, VersioningMode.fromString("independent").?);
    try std.testing.expectEqual(@as(?VersioningMode, null), VersioningMode.fromString("invalid"));
}

test "VersioningConvention.fromString" {
    try std.testing.expectEqual(VersioningConvention.conventional, VersioningConvention.fromString("conventional").?);
    try std.testing.expectEqual(VersioningConvention.manual, VersioningConvention.fromString("manual").?);
    try std.testing.expectEqual(@as(?VersioningConvention, null), VersioningConvention.fromString("invalid"));
}

test "BumpType.fromString" {
    try std.testing.expectEqual(BumpType.major, BumpType.fromString("major").?);
    try std.testing.expectEqual(BumpType.minor, BumpType.fromString("minor").?);
    try std.testing.expectEqual(BumpType.patch, BumpType.fromString("patch").?);
    try std.testing.expectEqual(@as(?BumpType, null), BumpType.fromString("invalid"));
}

test "VersioningConfig init/deinit" {
    var config = VersioningConfig.init(.independent, .conventional);
    defer config.deinit();

    try std.testing.expectEqual(VersioningMode.independent, config.mode);
    try std.testing.expectEqual(VersioningConvention.conventional, config.convention);
}

test "PackageVersion init/deinit" {
    var pv = try PackageVersion.init(std.testing.allocator, "test-pkg", "1.0.0");
    defer pv.deinit();

    try std.testing.expectEqualStrings("test-pkg", pv.name);
    try std.testing.expectEqualStrings("1.0.0", pv.version);
}
