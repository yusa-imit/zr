const std = @import("std");

/// Ownership pattern for CODEOWNERS file.
pub const OwnerPattern = struct {
    /// File pattern (e.g., "packages/core/**", "*.md").
    pattern: []const u8,
    /// List of owners (e.g., "@backend-team", "@alice", "alice@example.com").
    owners: [][]const u8,

    pub fn deinit(self: *OwnerPattern, allocator: std.mem.Allocator) void {
        allocator.free(self.pattern);
        for (self.owners) |owner| allocator.free(owner);
        allocator.free(self.owners);
    }
};

/// Ownership rule configuration from [codeowners] section.
pub const CodeownersConfig = struct {
    /// Enable CODEOWNERS generation (default: false).
    enabled: bool = false,
    /// Output path (default: "CODEOWNERS").
    output_path: []const u8 = "CODEOWNERS",
    /// Default owners for unmatched files.
    default_owners: [][]const u8 = &.{},
    /// Custom patterns (manual overrides).
    patterns: []OwnerPattern = &.{},
    /// Auto-detect owners from workspace members (default: true).
    auto_detect: bool = true,
    /// Workspace member ownership mapping (member_path -> owners).
    member_owners: std.StringHashMap([][]const u8),

    pub fn init(allocator: std.mem.Allocator) CodeownersConfig {
        return .{
            .member_owners = std.StringHashMap([][]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CodeownersConfig, allocator: std.mem.Allocator) void {
        if (!std.mem.eql(u8, self.output_path, "CODEOWNERS")) {
            allocator.free(self.output_path);
        }
        for (self.default_owners) |owner| allocator.free(owner);
        if (self.default_owners.len > 0) allocator.free(self.default_owners);
        for (self.patterns) |*pattern| pattern.deinit(allocator);
        if (self.patterns.len > 0) allocator.free(self.patterns);

        var it = self.member_owners.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |owner| allocator.free(owner);
            allocator.free(entry.value_ptr.*);
        }
        self.member_owners.deinit();
    }
};

test "CodeownersConfig init/deinit" {
    const allocator = std.testing.allocator;
    var config = CodeownersConfig.init(allocator);
    defer config.deinit(allocator);

    try std.testing.expect(config.enabled == false);
    try std.testing.expect(config.auto_detect == true);
    try std.testing.expectEqualStrings("CODEOWNERS", config.output_path);
}

test "OwnerPattern deinit" {
    const allocator = std.testing.allocator;

    var pattern = OwnerPattern{
        .pattern = try allocator.dupe(u8, "src/**"),
        .owners = try allocator.alloc([]const u8, 1),
    };
    pattern.owners[0] = try allocator.dupe(u8, "@team");

    pattern.deinit(allocator);
}
