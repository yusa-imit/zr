const std = @import("std");
const semver = @import("../util/semver.zig");
const constraint = @import("constraint.zig");

const Version = semver.Version;
const VersionConstraint = constraint.VersionConstraint;

/// Metadata about the lock file itself.
pub const LockFileMetadata = struct {
    generated: []const u8, // ISO 8601 timestamp, e.g., "2026-05-04T15:50:00Z"
    zr_version: []const u8, // zr version that generated the lock, e.g., "1.82.0"

    pub fn deinit(self: *LockFileMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.generated);
        allocator.free(self.zr_version);
    }
};

/// A single resolved dependency entry.
pub const LockFileDependency = struct {
    tool: []const u8, // e.g., "node", "python", "zig"
    constraint: []const u8, // Original constraint string, e.g., ">=18.0.0"
    resolved: []const u8, // Resolved version, e.g., "18.17.0"
    detected_at: []const u8, // ISO 8601 timestamp when detected

    pub fn deinit(self: *LockFileDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.tool);
        allocator.free(self.constraint);
        allocator.free(self.resolved);
        allocator.free(self.detected_at);
    }
};

/// Complete lock file structure.
pub const LockFile = struct {
    metadata: LockFileMetadata,
    dependencies: []LockFileDependency,

    pub fn deinit(self: *LockFile, allocator: std.mem.Allocator) void {
        self.metadata.deinit(allocator);
        for (self.dependencies) |*dep| {
            dep.deinit(allocator);
        }
        allocator.free(self.dependencies);
    }
};

// ───────────────────────────────────────────────────────────────────────────
// Public API Functions (Stubs for tests)
// ───────────────────────────────────────────────────────────────────────────

/// Generate a lock file from task constraints.
/// Writes a .zr-lock.toml file with resolved versions.
pub fn generateLockFile(
    allocator: std.mem.Allocator,
    output_path: []const u8,
    dependencies: []const LockFileDependency,
    zr_version: []const u8,
) !void {
    _ = allocator;
    _ = output_path;
    _ = dependencies;
    _ = zr_version;
    // Implementation will be added by zig-developer
    return error.NotImplemented;
}

/// Parse an existing lock file from disk.
pub fn parseLockFile(allocator: std.mem.Allocator, path: []const u8) !LockFile {
    _ = allocator;
    _ = path;
    // Implementation will be added by zig-developer
    return error.NotImplemented;
}

/// Verify if a lock file is valid for the current constraints.
/// Returns true if all constraints are satisfied by resolved versions.
pub fn verifyLockFile(
    allocator: std.mem.Allocator,
    lock: LockFile,
    constraints: []const ConstraintEntry,
) !bool {
    _ = allocator;
    _ = lock;
    _ = constraints;
    // Implementation will be added by zig-developer
    return error.NotImplemented;
}

/// Check if a lock file needs updating based on new constraints.
pub fn needsUpdate(
    lock: LockFile,
    constraints: []const ConstraintEntry,
) bool {
    _ = lock;
    _ = constraints;
    // Implementation will be added by zig-developer
    return false;
}

/// A constraint entry in verification.
pub const ConstraintEntry = struct {
    tool: []const u8,
    constraint: []const u8,
};

/// Get a resolved version from lock file for a tool.
pub fn getResolvedVersion(
    lock: LockFile,
    tool: []const u8,
) ?[]const u8 {
    for (lock.dependencies) |dep| {
        if (std.mem.eql(u8, dep.tool, tool)) {
            return dep.resolved;
        }
    }
    return null;
}

// ───────────────────────────────────────────────────────────────────────────
// Test Suite
// ───────────────────────────────────────────────────────────────────────────

test "LockFileDependency initialization and cleanup" {
    const dep = LockFileDependency{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };
    var mut_dep = dep;
    defer mut_dep.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("node", dep.tool);
    try std.testing.expectEqualStrings(">=18.0.0", dep.constraint);
    try std.testing.expectEqualStrings("18.17.0", dep.resolved);
    try std.testing.expectEqualStrings("2026-05-04T15:50:00Z", dep.detected_at);
}

test "LockFileMetadata initialization and cleanup" {
    const metadata = LockFileMetadata{
        .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
        .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
    };
    var mut_metadata = metadata;
    defer mut_metadata.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("2026-05-04T15:50:00Z", metadata.generated);
    try std.testing.expectEqualStrings("1.82.0", metadata.zr_version);
}

test "LockFile initialization with single dependency" {
    const deps = try std.testing.allocator.alloc(LockFileDependency, 1);
    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lock.dependencies.len);
    try std.testing.expectEqualStrings("node", lock.dependencies[0].tool);
}

test "LockFile with multiple dependencies" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 3);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[1] = .{
        .tool = try std.testing.allocator.dupe(u8, "python"),
        .constraint = try std.testing.allocator.dupe(u8, "~3.11"),
        .resolved = try std.testing.allocator.dupe(u8, "3.11.4"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[2] = .{
        .tool = try std.testing.allocator.dupe(u8, "zig"),
        .constraint = try std.testing.allocator.dupe(u8, "0.15.2"),
        .resolved = try std.testing.allocator.dupe(u8, "0.15.2"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), lock.dependencies.len);
    try std.testing.expectEqualStrings("node", lock.dependencies[0].tool);
    try std.testing.expectEqualStrings("python", lock.dependencies[1].tool);
    try std.testing.expectEqualStrings("zig", lock.dependencies[2].tool);
}

test "getResolvedVersion returns correct version for tool" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 2);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[1] = .{
        .tool = try std.testing.allocator.dupe(u8, "python"),
        .constraint = try std.testing.allocator.dupe(u8, "~3.11"),
        .resolved = try std.testing.allocator.dupe(u8, "3.11.4"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    const node_version = getResolvedVersion(lock, "node");
    const python_version = getResolvedVersion(lock, "python");
    const go_version = getResolvedVersion(lock, "go");

    try std.testing.expectEqualStrings("18.17.0", node_version.?);
    try std.testing.expectEqualStrings("3.11.4", python_version.?);
    try std.testing.expect(go_version == null);
}

test "getResolvedVersion returns null for missing tool" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 1);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    const result = getResolvedVersion(lock, "nonexistent");
    try std.testing.expect(result == null);
}

test "Lock file with empty dependencies list" {
    const deps = try std.testing.allocator.alloc(LockFileDependency, 0);

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), lock.dependencies.len);
    try std.testing.expect(getResolvedVersion(lock, "node") == null);
}

test "Lock file constraint strings preserve exact format" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 4);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[1] = .{
        .tool = try std.testing.allocator.dupe(u8, "python"),
        .constraint = try std.testing.allocator.dupe(u8, "~3.11"),
        .resolved = try std.testing.allocator.dupe(u8, "3.11.4"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[2] = .{
        .tool = try std.testing.allocator.dupe(u8, "zig"),
        .constraint = try std.testing.allocator.dupe(u8, "^0.15.0"),
        .resolved = try std.testing.allocator.dupe(u8, "0.15.2"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[3] = .{
        .tool = try std.testing.allocator.dupe(u8, "go"),
        .constraint = try std.testing.allocator.dupe(u8, "1.x"),
        .resolved = try std.testing.allocator.dupe(u8, "1.21.5"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(">=18.0.0", lock.dependencies[0].constraint);
    try std.testing.expectEqualStrings("~3.11", lock.dependencies[1].constraint);
    try std.testing.expectEqualStrings("^0.15.0", lock.dependencies[2].constraint);
    try std.testing.expectEqualStrings("1.x", lock.dependencies[3].constraint);
}

test "Lock file resolved versions are preserved exactly" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 3);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[1] = .{
        .tool = try std.testing.allocator.dupe(u8, "python"),
        .constraint = try std.testing.allocator.dupe(u8, "~3.11"),
        .resolved = try std.testing.allocator.dupe(u8, "3.11.4"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[2] = .{
        .tool = try std.testing.allocator.dupe(u8, "zig"),
        .constraint = try std.testing.allocator.dupe(u8, "0.15.2"),
        .resolved = try std.testing.allocator.dupe(u8, "0.15.2"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("18.17.0", lock.dependencies[0].resolved);
    try std.testing.expectEqualStrings("3.11.4", lock.dependencies[1].resolved);
    try std.testing.expectEqualStrings("0.15.2", lock.dependencies[2].resolved);
}

test "Lock file metadata timestamp is ISO 8601 format" {
    const metadata = LockFileMetadata{
        .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
        .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
    };
    var mut_metadata = metadata;
    defer mut_metadata.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("2026-05-04T15:50:00Z", metadata.generated);
    try std.testing.expect(std.mem.indexOf(u8, metadata.generated, "T") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata.generated, "Z") != null);
}

test "Lock file zr_version tracks semantic version" {
    const versions = [_][]const u8{ "1.0.0", "1.82.0", "2.0.0" };

    for (versions) |v| {
        const metadata = LockFileMetadata{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, v),
        };
        var mut_metadata = metadata;
        defer mut_metadata.deinit(std.testing.allocator);

        try std.testing.expectEqualStrings(v, metadata.zr_version);
    }
}

test "Lock file tracks detected_at timestamp for each dependency" {
    var dep1 = LockFileDependency{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };
    defer dep1.deinit(std.testing.allocator);

    var dep2 = LockFileDependency{
        .tool = try std.testing.allocator.dupe(u8, "python"),
        .constraint = try std.testing.allocator.dupe(u8, "~3.11"),
        .resolved = try std.testing.allocator.dupe(u8, "3.11.4"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T16:00:00Z"),
    };
    defer dep2.deinit(std.testing.allocator);

    // Each dependency can have different detection timestamps
    try std.testing.expect(!std.mem.eql(u8, dep1.detected_at, dep2.detected_at));
}

test "Lock file dependency lookup is case-sensitive for tool names" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 1);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "Node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    // Case-sensitive lookup: "Node" is found, "node" is not
    try std.testing.expect(getResolvedVersion(lock, "Node") != null);
    try std.testing.expect(getResolvedVersion(lock, "node") == null);
}

test "Lock file supports various constraint formats" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 6);

    const constraints = [_][]const u8{ "1.0.0", ">=1.0.0", "~1.2.3", "^1.2.3", "1.x", "^1.0.0 || ^2.0.0" };
    const tools = [_][]const u8{ "tool1", "tool2", "tool3", "tool4", "tool5", "tool6" };

    for (constraints, tools, 0..) |c, t, i| {
        deps[i] = .{
            .tool = try std.testing.allocator.dupe(u8, t),
            .constraint = try std.testing.allocator.dupe(u8, c),
            .resolved = try std.testing.allocator.dupe(u8, "1.0.0"),
            .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
        };
    }

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    // Verify different constraint formats are preserved
    for (lock.dependencies, 0..) |dep, idx| {
        if (idx < constraints.len) {
            try std.testing.expectEqualStrings(constraints[idx], dep.constraint);
        }
    }
}

test "Lock file deinit cleans up all allocated memory" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 2);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    deps[1] = .{
        .tool = try std.testing.allocator.dupe(u8, "python"),
        .constraint = try std.testing.allocator.dupe(u8, "~3.11"),
        .resolved = try std.testing.allocator.dupe(u8, "3.11.4"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };

    // This should clean up all strings and arrays
    lock.deinit(std.testing.allocator);

    // No way to verify deallocation directly, but at least test it doesn't crash
}

test "generateLockFile returns NotImplemented error" {
    try std.testing.expectError(error.NotImplemented, generateLockFile(
        std.testing.allocator,
        "/tmp/test.zr-lock.toml",
        &[_]LockFileDependency{},
        "1.82.0",
    ));
}

test "parseLockFile returns NotImplemented error" {
    try std.testing.expectError(error.NotImplemented, parseLockFile(
        std.testing.allocator,
        "/tmp/test.zr-lock.toml",
    ));
}

test "verifyLockFile returns NotImplemented error" {
    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = try std.testing.allocator.alloc(LockFileDependency, 0),
    };
    defer lock.deinit(std.testing.allocator);

    try std.testing.expectError(error.NotImplemented, verifyLockFile(
        std.testing.allocator,
        lock,
        &[_]ConstraintEntry{},
    ));
}

test "needsUpdate returns false for valid lock" {
    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = try std.testing.allocator.alloc(LockFileDependency, 0),
    };
    defer lock.deinit(std.testing.allocator);

    const result = needsUpdate(lock, &[_]ConstraintEntry{});
    try std.testing.expect(!result);
}

test "Lock file with large number of dependencies" {
    const dep_count = 50;
    const deps = try std.testing.allocator.alloc(LockFileDependency, dep_count);

    for (deps, 0..) |*dep, i| {
        const tool_buf = try std.testing.allocator.alloc(u8, 20);
        const tool_str = try std.fmt.bufPrint(tool_buf, "tool{d}", .{i});

        dep.tool = try std.testing.allocator.dupe(u8, tool_str);
        dep.constraint = try std.testing.allocator.dupe(u8, ">=1.0.0");
        dep.resolved = try std.testing.allocator.dupe(u8, "1.5.0");
        dep.detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z");

        std.testing.allocator.free(tool_buf);
    }

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, dep_count), lock.dependencies.len);
}

test "Lock file constraint and resolved have different values" {
    var deps = try std.testing.allocator.alloc(LockFileDependency, 1);

    deps[0] = .{
        .tool = try std.testing.allocator.dupe(u8, "node"),
        .constraint = try std.testing.allocator.dupe(u8, ">=18.0.0"),
        .resolved = try std.testing.allocator.dupe(u8, "18.17.0"),
        .detected_at = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
    };

    var lock = LockFile{
        .metadata = .{
            .generated = try std.testing.allocator.dupe(u8, "2026-05-04T15:50:00Z"),
            .zr_version = try std.testing.allocator.dupe(u8, "1.82.0"),
        },
        .dependencies = deps,
    };
    defer lock.deinit(std.testing.allocator);

    const dep = lock.dependencies[0];
    try std.testing.expect(!std.mem.eql(u8, dep.constraint, dep.resolved));
    try std.testing.expectEqualStrings(">=18.0.0", dep.constraint);
    try std.testing.expectEqualStrings("18.17.0", dep.resolved);
}
