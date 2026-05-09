const std = @import("std");

/// Represents an available zr release
pub const Release = struct {
    version: []const u8,
    tag_name: []const u8,
    prerelease: bool,
    created_at: []const u8,
    download_url: []const u8,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Release {
        return Release{
            .version = "",
            .tag_name = "",
            .prerelease = false,
            .created_at = "",
            .download_url = "",
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Release) void {
        if (self.version.len > 0) self.allocator.free(self.version);
        if (self.tag_name.len > 0) self.allocator.free(self.tag_name);
        if (self.created_at.len > 0) self.allocator.free(self.created_at);
        if (self.download_url.len > 0) self.allocator.free(self.download_url);
    }
};

/// Options for upgrade command
pub const UpgradeOptions = struct {
    /// Check for updates without installing
    check_only: bool = false,
    /// Install specific version instead of latest
    version: ?[]const u8 = null,
    /// Include prerelease versions
    include_prerelease: bool = false,
    /// Show verbose output
    verbose: bool = false,
};

test "Release init/deinit" {
    const allocator = std.testing.allocator;
    var release = Release.init(allocator);
    defer release.deinit();

    // Verify all fields are initialized to empty strings/false
    try std.testing.expectEqualStrings("", release.version);
    try std.testing.expectEqualStrings("", release.tag_name);
    try std.testing.expectEqual(false, release.prerelease);
    try std.testing.expectEqualStrings("", release.created_at);
    try std.testing.expectEqualStrings("", release.download_url);
}

test "Release deinit with allocated fields" {
    const allocator = std.testing.allocator;
    var release = Release.init(allocator);

    // Allocate and assign strings to all fields
    release.version = try allocator.dupe(u8, "1.2.3");
    release.tag_name = try allocator.dupe(u8, "v1.2.3");
    release.created_at = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
    release.download_url = try allocator.dupe(u8, "https://example.com/zr-1.2.3.tar.gz");
    release.prerelease = true;

    // Verify fields are correctly set before cleanup
    try std.testing.expectEqualStrings("1.2.3", release.version);
    try std.testing.expectEqualStrings("v1.2.3", release.tag_name);
    try std.testing.expectEqual(true, release.prerelease);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", release.created_at);
    try std.testing.expectEqualStrings("https://example.com/zr-1.2.3.tar.gz", release.download_url);

    // deinit should free all allocated memory without leaks
    release.deinit();
}
