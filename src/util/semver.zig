const std = @import("std");

/// Semantic version with major, minor, patch components.
pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,

    /// Parse a semver string like "1.2.3" into a Version.
    /// Returns error.InvalidFormat if the string is malformed.
    pub fn parse(s: []const u8) !Version {
        var parts = std.mem.splitScalar(u8, s, '.');

        const major_str = parts.next() orelse return error.InvalidFormat;
        const minor_str = parts.next() orelse return error.InvalidFormat;
        const patch_str = parts.next() orelse return error.InvalidFormat;

        // Ensure no extra parts
        if (parts.next() != null) return error.InvalidFormat;

        return .{
            .major = std.fmt.parseInt(u32, major_str, 10) catch return error.InvalidFormat,
            .minor = std.fmt.parseInt(u32, minor_str, 10) catch return error.InvalidFormat,
            .patch = std.fmt.parseInt(u32, patch_str, 10) catch return error.InvalidFormat,
        };
    }

    /// Compare two versions. Returns:
    /// - negative if self < other
    /// - 0 if self == other
    /// - positive if self > other
    pub fn cmp(self: Version, other: Version) i32 {
        if (self.major != other.major) {
            return @as(i32, @intCast(self.major)) - @as(i32, @intCast(other.major));
        }
        if (self.minor != other.minor) {
            return @as(i32, @intCast(self.minor)) - @as(i32, @intCast(other.minor));
        }
        return @as(i32, @intCast(self.patch)) - @as(i32, @intCast(other.patch));
    }

    /// Returns true if self >= other.
    pub fn gte(self: Version, other: Version) bool {
        return self.cmp(other) >= 0;
    }

    /// Returns true if self > other.
    pub fn gt(self: Version, other: Version) bool {
        return self.cmp(other) > 0;
    }

    /// Returns true if self <= other.
    pub fn lte(self: Version, other: Version) bool {
        return self.cmp(other) <= 0;
    }

    /// Returns true if self < other.
    pub fn lt(self: Version, other: Version) bool {
        return self.cmp(other) < 0;
    }

    /// Returns true if self == other.
    pub fn eql(self: Version, other: Version) bool {
        return self.cmp(other) == 0;
    }

    /// Format the version as "major.minor.patch".
    pub fn format(
        self: Version,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Version.parse - valid" {
    const v = try Version.parse("1.2.3");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
}

test "Version.parse - invalid formats" {
    try std.testing.expectError(error.InvalidFormat, Version.parse("1.2"));
    try std.testing.expectError(error.InvalidFormat, Version.parse("1.2.3.4"));
    try std.testing.expectError(error.InvalidFormat, Version.parse("a.b.c"));
    try std.testing.expectError(error.InvalidFormat, Version.parse(""));
    try std.testing.expectError(error.InvalidFormat, Version.parse("1"));
}

test "Version.cmp - equality" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.3");
    try std.testing.expectEqual(@as(i32, 0), v1.cmp(v2));
}

test "Version.cmp - major difference" {
    const v1 = try Version.parse("2.0.0");
    const v2 = try Version.parse("1.9.9");
    try std.testing.expect(v1.cmp(v2) > 0);
    try std.testing.expect(v2.cmp(v1) < 0);
}

test "Version.cmp - minor difference" {
    const v1 = try Version.parse("1.5.0");
    const v2 = try Version.parse("1.3.9");
    try std.testing.expect(v1.cmp(v2) > 0);
    try std.testing.expect(v2.cmp(v1) < 0);
}

test "Version.cmp - patch difference" {
    const v1 = try Version.parse("1.2.5");
    const v2 = try Version.parse("1.2.3");
    try std.testing.expect(v1.cmp(v2) > 0);
    try std.testing.expect(v2.cmp(v1) < 0);
}

test "Version.gte" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.3");
    const v3 = try Version.parse("1.2.4");

    try std.testing.expect(v1.gte(v2));
    try std.testing.expect(v3.gte(v1));
    try std.testing.expect(!v1.gte(v3));
}

test "Version.gt" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.3");
    const v3 = try Version.parse("1.2.4");

    try std.testing.expect(!v1.gt(v2));
    try std.testing.expect(v3.gt(v1));
    try std.testing.expect(!v1.gt(v3));
}

test "Version.lte" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.3");
    const v3 = try Version.parse("1.2.4");

    try std.testing.expect(v1.lte(v2));
    try std.testing.expect(v1.lte(v3));
    try std.testing.expect(!v3.lte(v1));
}

test "Version.lt" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.3");
    const v3 = try Version.parse("1.2.4");

    try std.testing.expect(!v1.lt(v2));
    try std.testing.expect(v1.lt(v3));
    try std.testing.expect(!v3.lt(v1));
}

test "Version.eql" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.3");
    const v3 = try Version.parse("1.2.4");

    try std.testing.expect(v1.eql(v2));
    try std.testing.expect(!v1.eql(v3));
}

test "Version.format" {
    const v = try Version.parse("1.2.3");
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try v.format("", .{}, stream.writer());
    const result = stream.getWritten();
    try std.testing.expectEqualStrings("1.2.3", result);
}
