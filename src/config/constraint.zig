const std = @import("std");
const semver = @import("../util/semver.zig");
const Version = semver.Version;

/// A version constraint parsed from a constraint string.
pub const VersionConstraint = union(enum) {
    /// Exact version: "1.2.3" or "=1.2.3"
    exact: Version,
    /// Caret range: "^1.2.3" (allows patch/minor, locks major)
    caret: Version,
    /// Tilde range: "~1.2.3" (allows patch only)
    tilde: Version,
    /// Greater than or equal: ">=1.2.3"
    gte: Version,
    /// Greater than: ">1.2.3"
    gt: Version,
    /// Less than or equal: "<=1.2.3"
    lte: Version,
    /// Less than: "<1.2.3"
    lt: Version,
    /// Range combination: ">=1.2.0 <2.0.0" (AND logic)
    range: Range,
    /// Alternative ranges: "1.x || 2.x" (OR logic)
    alternatives: []const VersionConstraint,
    /// Wildcard: "1.x" or "1.2.x"
    wildcard: Wildcard,

    pub fn deinit(self: *VersionConstraint, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .alternatives => |alts| allocator.free(alts),
            else => {},
        }
    }
};

/// A version range with min and max bounds.
pub const Range = struct {
    min: ?Version,
    min_inclusive: bool,
    max: ?Version,
    max_inclusive: bool,
};

/// Wildcard version pattern (1.x or 1.2.x).
pub const Wildcard = struct {
    major: u32,
    minor: ?u32,
};

/// Parse a constraint string into a VersionConstraint.
pub fn parseConstraint(allocator: std.mem.Allocator, input: []const u8) !VersionConstraint {
    var trimmed = std.mem.trim(u8, input, " \t\n\r");

    // Handle alternatives (OR logic)
    if (std.mem.indexOf(u8, trimmed, "||")) |_| {
        var alts = std.ArrayList(VersionConstraint){};
        defer alts.deinit(allocator);

        var parts = std.mem.splitSequence(u8, trimmed, "||");
        while (parts.next()) |part| {
            const constraint = try parseConstraint(allocator, part);
            try alts.append(allocator, constraint);
        }

        return .{ .alternatives = try alts.toOwnedSlice(allocator) };
    }

    // Handle range combinations (AND logic)
    if (std.mem.indexOf(u8, trimmed, " ") != null and
        (std.mem.startsWith(u8, trimmed, ">=") or
        std.mem.startsWith(u8, trimmed, ">") or
        std.mem.startsWith(u8, trimmed, "<=") or
        std.mem.startsWith(u8, trimmed, "<"))) {
        return parseRange(trimmed);
    }

    // Handle caret range
    if (std.mem.startsWith(u8, trimmed, "^")) {
        const version_str = trimmed[1..];
        const version = try Version.parse(version_str);
        return .{ .caret = version };
    }

    // Handle tilde range
    if (std.mem.startsWith(u8, trimmed, "~")) {
        const version_str = trimmed[1..];
        const version = try Version.parse(version_str);
        return .{ .tilde = version };
    }

    // Handle explicit comparison operators
    if (std.mem.startsWith(u8, trimmed, ">=")) {
        const version_str = std.mem.trim(u8, trimmed[2..], " ");
        const version = try Version.parse(version_str);
        return .{ .gte = version };
    }

    if (std.mem.startsWith(u8, trimmed, ">")) {
        const version_str = std.mem.trim(u8, trimmed[1..], " ");
        const version = try Version.parse(version_str);
        return .{ .gt = version };
    }

    if (std.mem.startsWith(u8, trimmed, "<=")) {
        const version_str = std.mem.trim(u8, trimmed[2..], " ");
        const version = try Version.parse(version_str);
        return .{ .lte = version };
    }

    if (std.mem.startsWith(u8, trimmed, "<")) {
        const version_str = std.mem.trim(u8, trimmed[1..], " ");
        const version = try Version.parse(version_str);
        return .{ .lt = version };
    }

    // Handle exact version with = prefix
    if (std.mem.startsWith(u8, trimmed, "=")) {
        const version_str = std.mem.trim(u8, trimmed[1..], " ");
        const version = try Version.parse(version_str);
        return .{ .exact = version };
    }

    // Handle wildcard versions (1.x or 1.2.x)
    if (std.mem.indexOf(u8, trimmed, "x") != null) {
        return parseWildcard(trimmed);
    }

    // Default to exact version
    const version = try Version.parse(trimmed);
    return .{ .exact = version };
}

/// Parse a range like ">=1.2.0 <2.0.0" or ">= 1.2.0 < 2.0.0".
fn parseRange(input: []const u8) !VersionConstraint {
    var min_version: ?Version = null;
    var min_inclusive = false;
    var max_version: ?Version = null;
    var max_inclusive = false;

    var parts = std.mem.splitSequence(u8, input, " ");
    var current_op: ?[]const u8 = null;

    while (parts.next()) |part| {
        if (part.len == 0) continue;

        // Check if this part is an operator
        if (std.mem.startsWith(u8, part, ">=") or
            std.mem.startsWith(u8, part, ">") or
            std.mem.startsWith(u8, part, "<=") or
            std.mem.startsWith(u8, part, "<")) {
            // Check if operator has version embedded (no space)
            if (part.len > 2 and (std.mem.startsWith(u8, part, ">=") or std.mem.startsWith(u8, part, "<="))) {
                const version_str = part[2..];
                if (std.mem.startsWith(u8, part, ">=")) {
                    min_version = try Version.parse(version_str);
                    min_inclusive = true;
                } else {
                    max_version = try Version.parse(version_str);
                    max_inclusive = true;
                }
            } else if (part.len > 1 and (std.mem.startsWith(u8, part, ">") or std.mem.startsWith(u8, part, "<"))) {
                const version_str = part[1..];
                if (version_str.len > 0 and version_str[0] != '=') {
                    // Version is embedded
                    if (std.mem.startsWith(u8, part, ">")) {
                        min_version = try Version.parse(version_str);
                        min_inclusive = false;
                    } else {
                        max_version = try Version.parse(version_str);
                        max_inclusive = false;
                    }
                } else {
                    // Just the operator, version comes next
                    current_op = part;
                }
            } else {
                // Just operator, version comes next
                current_op = part;
            }
        } else if (current_op) |op| {
            // This is a version following an operator
            if (std.mem.startsWith(u8, op, ">=")) {
                min_version = try Version.parse(part);
                min_inclusive = true;
            } else if (std.mem.startsWith(u8, op, ">")) {
                min_version = try Version.parse(part);
                min_inclusive = false;
            } else if (std.mem.startsWith(u8, op, "<=")) {
                max_version = try Version.parse(part);
                max_inclusive = true;
            } else if (std.mem.startsWith(u8, op, "<")) {
                max_version = try Version.parse(part);
                max_inclusive = false;
            }
            current_op = null;
        } else {
            return error.InvalidConstraintFormat;
        }
    }

    if (current_op != null) return error.InvalidConstraintFormat;

    return .{
        .range = .{
            .min = min_version,
            .min_inclusive = min_inclusive,
            .max = max_version,
            .max_inclusive = max_inclusive,
        },
    };
}

/// Parse wildcard versions like "1.x" or "1.2.x".
fn parseWildcard(input: []const u8) !VersionConstraint {
    var parts = std.mem.splitScalar(u8, input, '.');

    const major_str = parts.next() orelse return error.InvalidWildcardFormat;
    const major = std.fmt.parseInt(u32, major_str, 10) catch return error.InvalidWildcardFormat;

    const minor_str = parts.next() orelse return error.InvalidWildcardFormat;
    if (!std.mem.eql(u8, minor_str, "x")) {
        // If minor is not "x", it should be a number
        const minor = std.fmt.parseInt(u32, minor_str, 10) catch return error.InvalidWildcardFormat;
        const patch_str = parts.next() orelse return error.InvalidWildcardFormat;
        if (!std.mem.eql(u8, patch_str, "x")) {
            return error.InvalidWildcardFormat;
        }
        return .{ .wildcard = .{ .major = major, .minor = minor } };
    }

    return .{ .wildcard = .{ .major = major, .minor = null } };
}

/// Check if a version satisfies a constraint.
pub fn satisfies(version: Version, constraint: VersionConstraint) bool {
    switch (constraint) {
        .exact => |v| return version.eql(v),
        .caret => |v| {
            // ^1.2.3 allows >=1.2.3 and <2.0.0
            if (v.major == 0) {
                if (version.major != 0) return false;
                if (v.minor == 0) {
                    // ^0.0.z allows >=0.0.z and <0.0.(z+1) (exact match only)
                    return version.minor == 0 and version.patch == v.patch;
                } else {
                    // ^0.y.z (y > 0) allows >=0.y.z and <0.(y+1).0
                    if (version.minor != v.minor) return false;
                    return version.patch >= v.patch;
                }
            }
            if (version.major != v.major) return false;
            return version.gte(v);
        },
        .tilde => |v| {
            // ~1.2.3 allows >=1.2.3 and <1.3.0
            if (version.major != v.major) return false;
            if (version.minor != v.minor) return false;
            return version.patch >= v.patch;
        },
        .gte => |v| return version.gte(v),
        .gt => |v| return version.gt(v),
        .lte => |v| return version.lte(v),
        .lt => |v| return version.lt(v),
        .range => |r| {
            if (r.min) |min| {
                const cmp = version.cmp(min);
                if (r.min_inclusive) {
                    if (cmp < 0) return false;
                } else {
                    if (cmp <= 0) return false;
                }
            }
            if (r.max) |max| {
                const cmp = version.cmp(max);
                if (r.max_inclusive) {
                    if (cmp > 0) return false;
                } else {
                    if (cmp >= 0) return false;
                }
            }
            return true;
        },
        .alternatives => |alts| {
            for (alts) |alt| {
                if (satisfies(version, alt)) return true;
            }
            return false;
        },
        .wildcard => |w| {
            if (version.major != w.major) return false;
            if (w.minor) |minor| {
                return version.minor == minor;
            }
            return true;
        },
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Tests
// ───────────────────────────────────────────────────────────────────────────

test "parse exact version without prefix" {
    var constraint = try parseConstraint(std.testing.allocator, "1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .exact);
    try std.testing.expectEqual(@as(u32, 1), constraint.exact.major);
    try std.testing.expectEqual(@as(u32, 2), constraint.exact.minor);
    try std.testing.expectEqual(@as(u32, 3), constraint.exact.patch);
}

test "parse exact version with = prefix" {
    var constraint = try parseConstraint(std.testing.allocator, "=1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .exact);
    try std.testing.expectEqual(@as(u32, 1), constraint.exact.major);
    try std.testing.expectEqual(@as(u32, 2), constraint.exact.minor);
    try std.testing.expectEqual(@as(u32, 3), constraint.exact.patch);
}

test "exact version matching" {
    var constraint = try parseConstraint(std.testing.allocator, "1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.4");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(!satisfies(v2, constraint));
}

test "parse caret range" {
    var constraint = try parseConstraint(std.testing.allocator, "^1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .caret);
    try std.testing.expectEqual(@as(u32, 1), constraint.caret.major);
}

test "caret range allows patch updates" {
    var constraint = try parseConstraint(std.testing.allocator, "^1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.4");
    const v3 = try Version.parse("1.2.5");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
}

test "caret range allows minor updates" {
    var constraint = try parseConstraint(std.testing.allocator, "^1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.3.0");
    const v2 = try Version.parse("1.5.9");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
}

test "caret range rejects major updates" {
    var constraint = try parseConstraint(std.testing.allocator, "^1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("2.0.0");
    const v2 = try Version.parse("0.9.9");

    try std.testing.expect(!satisfies(v1, constraint));
    try std.testing.expect(!satisfies(v2, constraint));
}

test "caret range with 0.x.y version" {
    var constraint = try parseConstraint(std.testing.allocator, "^0.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("0.2.3");
    const v2 = try Version.parse("0.2.4");
    const v3 = try Version.parse("0.3.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(!satisfies(v3, constraint));
}

test "parse tilde range" {
    var constraint = try parseConstraint(std.testing.allocator, "~1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .tilde);
    try std.testing.expectEqual(@as(u32, 1), constraint.tilde.major);
}

test "tilde range allows patch updates" {
    var constraint = try parseConstraint(std.testing.allocator, "~1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.4");
    const v3 = try Version.parse("1.2.10");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
}

test "tilde range rejects minor updates" {
    var constraint = try parseConstraint(std.testing.allocator, "~1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.3.0");
    const v2 = try Version.parse("1.3.1");

    try std.testing.expect(!satisfies(v1, constraint));
    try std.testing.expect(!satisfies(v2, constraint));
}

test "parse >= operator" {
    var constraint = try parseConstraint(std.testing.allocator, ">=1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .gte);
}

test ">= operator matching" {
    var constraint = try parseConstraint(std.testing.allocator, ">=1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.4");
    const v3 = try Version.parse("2.0.0");
    const v4 = try Version.parse("1.2.2");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(!satisfies(v4, constraint));
}

test "parse > operator" {
    var constraint = try parseConstraint(std.testing.allocator, ">1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .gt);
}

test "> operator matching" {
    var constraint = try parseConstraint(std.testing.allocator, ">1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.4");
    const v3 = try Version.parse("2.0.0");

    try std.testing.expect(!satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
}

test "parse <= operator" {
    var constraint = try parseConstraint(std.testing.allocator, "<=1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .lte);
}

test "<= operator matching" {
    var constraint = try parseConstraint(std.testing.allocator, "<=1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.2");
    const v3 = try Version.parse("1.0.0");
    const v4 = try Version.parse("1.2.4");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(!satisfies(v4, constraint));
}

test "parse < operator" {
    var constraint = try parseConstraint(std.testing.allocator, "<1.2.3");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .lt);
}

test "< operator matching" {
    var constraint = try parseConstraint(std.testing.allocator, "<1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.2");
    const v3 = try Version.parse("1.0.0");

    try std.testing.expect(!satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
}

test "parse range with >= and <" {
    var constraint = try parseConstraint(std.testing.allocator, ">=1.2.0 <2.0.0");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .range);
}

test "range matching with >= and <" {
    var constraint = try parseConstraint(std.testing.allocator, ">=1.2.0 <2.0.0");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.0");
    const v2 = try Version.parse("1.5.0");
    const v3 = try Version.parse("1.9.9");
    const v4 = try Version.parse("2.0.0");
    const v5 = try Version.parse("1.1.9");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(!satisfies(v4, constraint));
    try std.testing.expect(!satisfies(v5, constraint));
}

test "range matching with > and <=" {
    var constraint = try parseConstraint(std.testing.allocator, ">1.0.0 <=2.0.0");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.0.0");
    const v2 = try Version.parse("1.0.1");
    const v3 = try Version.parse("2.0.0");
    const v4 = try Version.parse("2.0.1");

    try std.testing.expect(!satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(!satisfies(v4, constraint));
}

test "parse wildcard major.x" {
    var constraint = try parseConstraint(std.testing.allocator, "1.x");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .wildcard);
    try std.testing.expectEqual(@as(u32, 1), constraint.wildcard.major);
    try std.testing.expect(constraint.wildcard.minor == null);
}

test "wildcard major.x matching" {
    var constraint = try parseConstraint(std.testing.allocator, "1.x");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.0.0");
    const v2 = try Version.parse("1.5.0");
    const v3 = try Version.parse("1.9.9");
    const v4 = try Version.parse("2.0.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(!satisfies(v4, constraint));
}

test "parse wildcard major.minor.x" {
    var constraint = try parseConstraint(std.testing.allocator, "1.2.x");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .wildcard);
    try std.testing.expectEqual(@as(u32, 1), constraint.wildcard.major);
    try std.testing.expectEqual(@as(u32, 2), constraint.wildcard.minor orelse 0);
}

test "wildcard major.minor.x matching" {
    var constraint = try parseConstraint(std.testing.allocator, "1.2.x");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.2.0");
    const v2 = try Version.parse("1.2.5");
    const v3 = try Version.parse("1.2.10");
    const v4 = try Version.parse("1.3.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(!satisfies(v4, constraint));
}

test "parse alternatives with ||" {
    var constraint = try parseConstraint(std.testing.allocator, "1.x || 2.x");
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(constraint == .alternatives);
    try std.testing.expectEqual(@as(usize, 2), constraint.alternatives.len);
}

test "alternatives matching with ||" {
    var constraint = try parseConstraint(std.testing.allocator, "1.x || 2.x");
    defer {
        for (constraint.alternatives) |alt| {
            var mut_alt = alt;
            mut_alt.deinit(std.testing.allocator);
        }
        constraint.deinit(std.testing.allocator);
    }

    const v1 = try Version.parse("1.0.0");
    const v2 = try Version.parse("1.5.0");
    const v3 = try Version.parse("2.0.0");
    const v4 = try Version.parse("2.5.0");
    const v5 = try Version.parse("3.0.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(satisfies(v4, constraint));
    try std.testing.expect(!satisfies(v5, constraint));
}

test "alternatives matching with complex constraints" {
    var constraint = try parseConstraint(std.testing.allocator, "^1.2.0 || ^2.0.0");
    defer {
        for (constraint.alternatives) |alt| {
            var mut_alt = alt;
            mut_alt.deinit(std.testing.allocator);
        }
        constraint.deinit(std.testing.allocator);
    }

    const v1 = try Version.parse("1.2.0");
    const v2 = try Version.parse("1.5.0");
    const v3 = try Version.parse("2.0.0");
    const v4 = try Version.parse("2.5.0");
    const v5 = try Version.parse("3.0.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(satisfies(v3, constraint));
    try std.testing.expect(satisfies(v4, constraint));
    try std.testing.expect(!satisfies(v5, constraint));
}

test "parse with leading/trailing whitespace" {
    var constraint1 = try parseConstraint(std.testing.allocator, "  1.2.3  ");
    defer constraint1.deinit(std.testing.allocator);

    var constraint2 = try parseConstraint(std.testing.allocator, "  >=1.2.3  ");
    defer constraint2.deinit(std.testing.allocator);

    const v = try Version.parse("1.2.3");
    try std.testing.expect(satisfies(v, constraint1));
    try std.testing.expect(satisfies(v, constraint2));
}

test "parse with operator whitespace" {
    var constraint = try parseConstraint(std.testing.allocator, ">= 1.2.3");
    defer constraint.deinit(std.testing.allocator);

    const v = try Version.parse("1.2.3");
    try std.testing.expect(satisfies(v, constraint));
}

test "invalid constraint format rejects malformed version" {
    try std.testing.expectError(error.InvalidFormat, parseConstraint(std.testing.allocator, "1.2"));
    try std.testing.expectError(error.InvalidFormat, parseConstraint(std.testing.allocator, "abc"));
    try std.testing.expectError(error.InvalidFormat, parseConstraint(std.testing.allocator, "1.2.3.4"));
}

test "invalid wildcard format" {
    try std.testing.expectError(error.InvalidWildcardFormat, parseConstraint(std.testing.allocator, "x.y.z"));
    try std.testing.expectError(error.InvalidWildcardFormat, parseConstraint(std.testing.allocator, "1.2.3.x"));
}

test "range boundary conditions at exact values" {
    var constraint = try parseConstraint(std.testing.allocator, ">=1.0.0 <=2.0.0");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.0.0");
    const v2 = try Version.parse("2.0.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
}

test "caret with 0.0.x version locks everything" {
    var constraint = try parseConstraint(std.testing.allocator, "^0.0.3");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("0.0.3");
    const v2 = try Version.parse("0.0.4");
    const v3 = try Version.parse("0.1.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(!satisfies(v2, constraint));
    try std.testing.expect(!satisfies(v3, constraint));
}

test "tilde with 1.0.x version allows patch updates" {
    var constraint = try parseConstraint(std.testing.allocator, "~1.0.5");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.0.5");
    const v2 = try Version.parse("1.0.10");
    const v3 = try Version.parse("1.1.0");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(!satisfies(v3, constraint));
}

test "multiple range constraints combinations" {
    var constraint = try parseConstraint(std.testing.allocator, ">=0.5.0 <1.0.0");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("0.5.0");
    const v2 = try Version.parse("0.9.9");
    const v3 = try Version.parse("1.0.0");
    const v4 = try Version.parse("0.4.9");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(satisfies(v2, constraint));
    try std.testing.expect(!satisfies(v3, constraint));
    try std.testing.expect(!satisfies(v4, constraint));
}

test "parse operators preserve semantics in range" {
    var constraint_gte_lt = try parseConstraint(std.testing.allocator, ">=1.0.0 <2.0.0");
    defer constraint_gte_lt.deinit(std.testing.allocator);

    var constraint_gt_lte = try parseConstraint(std.testing.allocator, ">1.0.0 <=2.0.0");
    defer constraint_gt_lte.deinit(std.testing.allocator);

    const v1 = try Version.parse("1.0.0");
    const v2 = try Version.parse("2.0.0");

    // 1.0.0 satisfies >=1.0.0 <2.0.0 but not >1.0.0 <=2.0.0
    try std.testing.expect(satisfies(v1, constraint_gte_lt));
    try std.testing.expect(!satisfies(v1, constraint_gt_lte));

    // 2.0.0 satisfies >1.0.0 <=2.0.0 but not >=1.0.0 <2.0.0
    try std.testing.expect(!satisfies(v2, constraint_gte_lt));
    try std.testing.expect(satisfies(v2, constraint_gt_lte));
}

test "edge case: 0.0.0 version" {
    var constraint = try parseConstraint(std.testing.allocator, "0.0.0");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("0.0.0");
    const v2 = try Version.parse("0.0.1");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(!satisfies(v2, constraint));
}

test "edge case: large version numbers" {
    var constraint = try parseConstraint(std.testing.allocator, "999.999.999");
    defer constraint.deinit(std.testing.allocator);

    const v1 = try Version.parse("999.999.999");
    const v2 = try Version.parse("999.999.998");

    try std.testing.expect(satisfies(v1, constraint));
    try std.testing.expect(!satisfies(v2, constraint));
}
