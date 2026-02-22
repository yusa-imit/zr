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
    release.deinit();
}
