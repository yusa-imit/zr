const std = @import("std");
const graph = @import("../graph/dag.zig");

/// Represents the result of affected detection
pub const AffectedResult = struct {
    /// Set of affected project paths (owned by allocator)
    projects: std.StringHashMap(void),
    /// Git base reference used for comparison
    base_ref: []const u8,

    pub fn deinit(self: *AffectedResult, allocator: std.mem.Allocator) void {
        var it = self.projects.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        self.projects.deinit();
        allocator.free(self.base_ref);
    }

    pub fn contains(self: *const AffectedResult, project_path: []const u8) bool {
        return self.projects.contains(project_path);
    }
};

/// Detect affected projects based on git changes
/// `base_ref` - git ref to compare against (e.g., "origin/main", "HEAD~1")
/// `workspace_members` - list of workspace member directories
/// `cwd` - current working directory
pub fn detectAffected(
    allocator: std.mem.Allocator,
    base_ref: []const u8,
    workspace_members: []const []const u8,
    cwd: []const u8,
) !AffectedResult {
    var affected_map = std.StringHashMap(void).init(allocator);
    errdefer {
        var it = affected_map.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        affected_map.deinit();
    }

    // Get changed files from git diff
    const changed_files = try getChangedFiles(allocator, base_ref, cwd);
    defer {
        for (changed_files) |f| allocator.free(f);
        allocator.free(changed_files);
    }

    // Map each changed file to its workspace member
    for (changed_files) |file_path| {
        const project = findProjectForFile(workspace_members, file_path);
        if (project) |proj_path| {
            // Add to affected set if not already present
            const gop = try affected_map.getOrPut(proj_path);
            if (!gop.found_existing) {
                gop.key_ptr.* = try allocator.dupe(u8, proj_path);
            }
        }
    }

    return AffectedResult{
        .projects = affected_map,
        .base_ref = try allocator.dupe(u8, base_ref),
    };
}

/// Execute git diff to get list of changed files
fn getChangedFiles(
    allocator: std.mem.Allocator,
    base_ref: []const u8,
    cwd: []const u8,
) ![][]const u8 {
    // Build git command: git diff --name-only <base_ref>...HEAD
    const args = [_][]const u8{
        "git",
        "diff",
        "--name-only",
        try std.fmt.allocPrint(allocator, "{s}...HEAD", .{base_ref}),
    };
    defer allocator.free(args[3]);

    var child = std.process.Child.init(&args, allocator);
    child.cwd = cwd;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(stdout);

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) {
        return error.GitDiffFailed;
    }

    // Parse output lines
    var files = std.ArrayList([]const u8){};
    errdefer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        try files.append(allocator, try allocator.dupe(u8, trimmed));
    }

    return files.toOwnedSlice(allocator);
}

/// Find which workspace member owns a given file path
fn findProjectForFile(workspace_members: []const []const u8, file_path: []const u8) ?[]const u8 {
    // Find the longest matching prefix (most specific project)
    var best_match: ?[]const u8 = null;
    var best_len: usize = 0;

    for (workspace_members) |member| {
        // Normalize member path (remove trailing slash)
        const normalized = if (member.len > 0 and member[member.len - 1] == '/')
            member[0 .. member.len - 1]
        else
            member;

        // Check if file_path starts with member path
        if (std.mem.startsWith(u8, file_path, normalized)) {
            // Ensure it's a directory boundary (next char is '/' or end of string)
            if (file_path.len == normalized.len or
                (file_path.len > normalized.len and file_path[normalized.len] == '/')) {
                if (normalized.len > best_len) {
                    best_match = member;
                    best_len = normalized.len;
                }
            }
        }
    }

    return best_match;
}

/// Expand affected projects to include their dependents
/// This traverses the dependency graph to find all projects that depend on affected ones
pub fn expandWithDependents(
    allocator: std.mem.Allocator,
    affected: *AffectedResult,
    dependencies: std.StringHashMap([]const []const u8), // project -> list of dependencies
) !void {
    // Build reverse dependency map (project -> list of dependents)
    var dependents = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = dependents.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        dependents.deinit();
    }

    // Populate reverse map
    var dep_it = dependencies.iterator();
    while (dep_it.next()) |entry| {
        const project = entry.key_ptr.*;
        const deps = entry.value_ptr.*;
        for (deps) |dep| {
            const gop = try dependents.getOrPut(dep);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList([]const u8){};
            }
            try gop.value_ptr.*.append(allocator, project);
        }
    }

    // BFS traversal to find all transitive dependents
    var queue = std.ArrayList([]const u8){};
    defer queue.deinit(allocator);

    // Seed queue with currently affected projects
    var affected_it = affected.projects.keyIterator();
    while (affected_it.next()) |proj| {
        try queue.append(allocator, proj.*);
    }

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);

        // Mark as visited
        try visited.put(current, {});

        // Find dependents
        if (dependents.get(current)) |deps| {
            for (deps.items) |dependent| {
                // Add to affected if not already there
                const gop = try affected.projects.getOrPut(dependent);
                if (!gop.found_existing) {
                    gop.key_ptr.* = try allocator.dupe(u8, dependent);
                }

                // Add to queue if not visited
                if (!visited.contains(dependent)) {
                    try queue.append(allocator, dependent);
                }
            }
        }
    }
}

test "findProjectForFile" {
    const members = [_][]const u8{
        "packages/core",
        "packages/utils",
        "apps/web",
    };

    try std.testing.expectEqualStrings("packages/core", findProjectForFile(&members, "packages/core/src/main.zig").?);
    try std.testing.expectEqualStrings("apps/web", findProjectForFile(&members, "apps/web/index.html").?);
    try std.testing.expect(findProjectForFile(&members, "README.md") == null);
    try std.testing.expect(findProjectForFile(&members, "docs/guide.md") == null);
}

test "findProjectForFile - longest match" {
    const members = [_][]const u8{
        "packages",
        "packages/core",
    };

    // Should match the more specific path
    try std.testing.expectEqualStrings("packages/core", findProjectForFile(&members, "packages/core/src/main.zig").?);
    try std.testing.expectEqualStrings("packages", findProjectForFile(&members, "packages/utils/test.zig").?);
}

test "affected detection - basic" {
    // Mock changed files
    const files = [_][]const u8{
        "packages/core/src/main.zig",
        "packages/utils/helper.zig",
    };

    const members = [_][]const u8{
        "packages/core",
        "packages/utils",
        "apps/web",
    };

    // Test file-to-project mapping
    for (files) |file| {
        const proj = findProjectForFile(&members, file);
        try std.testing.expect(proj != null);
    }
}

test "affected result - contains check" {
    const allocator = std.testing.allocator;

    var affected = AffectedResult{
        .projects = std.StringHashMap(void).init(allocator),
        .base_ref = try allocator.dupe(u8, "main"),
    };
    defer affected.deinit(allocator);

    const proj1 = try allocator.dupe(u8, "packages/core");
    try affected.projects.put(proj1, {});

    try std.testing.expect(affected.contains("packages/core"));
    try std.testing.expect(!affected.contains("packages/utils"));
}

test "findProjectForFile - no match" {
    const members = [_][]const u8{
        "packages/core",
        "apps/web",
    };

    try std.testing.expect(findProjectForFile(&members, "docs/README.md") == null);
    try std.testing.expect(findProjectForFile(&members, "scripts/build.sh") == null);
}

test "findProjectForFile - exact prefix match" {
    const members = [_][]const u8{
        "packages/core-utils",
        "packages/core",
    };

    // Should match the exact directory, not just prefix
    const result = findProjectForFile(&members, "packages/core/main.zig");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("packages/core", result.?);
}

test "expandWithDependents - single level" {
    const allocator = std.testing.allocator;

    // Setup: packages/ui depends on packages/core
    var deps_map = std.StringHashMap([]const []const u8).init(allocator);
    defer {
        var it = deps_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            allocator.free(entry.value_ptr.*);
        }
        deps_map.deinit();
    }

    const ui_deps = try allocator.alloc([]const u8, 1);
    ui_deps[0] = try allocator.dupe(u8, "packages/core");
    try deps_map.put(try allocator.dupe(u8, "packages/ui"), ui_deps);

    // Create affected result with only core affected
    var affected = AffectedResult{
        .projects = std.StringHashMap(void).init(allocator),
        .base_ref = try allocator.dupe(u8, "main"),
    };
    defer affected.deinit(allocator);

    const core = try allocator.dupe(u8, "packages/core");
    try affected.projects.put(core, {});

    // Expand to include dependents
    try expandWithDependents(allocator, &affected, deps_map);

    // Should now include both core and ui
    try std.testing.expect(affected.contains("packages/core"));
    try std.testing.expect(affected.contains("packages/ui"));
}

test "expandWithDependents - transitive dependencies" {
    const allocator = std.testing.allocator;

    // Setup dependency chain: app -> ui -> core
    var deps_map = std.StringHashMap([]const []const u8).init(allocator);
    defer {
        var it = deps_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            allocator.free(entry.value_ptr.*);
        }
        deps_map.deinit();
    }

    const ui_deps = try allocator.alloc([]const u8, 1);
    ui_deps[0] = try allocator.dupe(u8, "packages/core");
    try deps_map.put(try allocator.dupe(u8, "packages/ui"), ui_deps);

    const app_deps = try allocator.alloc([]const u8, 1);
    app_deps[0] = try allocator.dupe(u8, "packages/ui");
    try deps_map.put(try allocator.dupe(u8, "apps/web"), app_deps);

    // Only core is affected initially
    var affected = AffectedResult{
        .projects = std.StringHashMap(void).init(allocator),
        .base_ref = try allocator.dupe(u8, "main"),
    };
    defer affected.deinit(allocator);

    const core = try allocator.dupe(u8, "packages/core");
    try affected.projects.put(core, {});

    // Expand - should find ui and app transitively
    try expandWithDependents(allocator, &affected, deps_map);

    try std.testing.expect(affected.contains("packages/core"));
    try std.testing.expect(affected.contains("packages/ui"));
    try std.testing.expect(affected.contains("apps/web"));
}

test "expandWithDependents - multiple initial affected" {
    const allocator = std.testing.allocator;

    // Setup: app1 -> utils, app2 -> utils, ui -> core
    var deps_map = std.StringHashMap([]const []const u8).init(allocator);
    defer {
        var it = deps_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            allocator.free(entry.value_ptr.*);
        }
        deps_map.deinit();
    }

    const app1_deps = try allocator.alloc([]const u8, 1);
    app1_deps[0] = try allocator.dupe(u8, "packages/utils");
    try deps_map.put(try allocator.dupe(u8, "apps/app1"), app1_deps);

    const app2_deps = try allocator.alloc([]const u8, 1);
    app2_deps[0] = try allocator.dupe(u8, "packages/utils");
    try deps_map.put(try allocator.dupe(u8, "apps/app2"), app2_deps);

    const ui_deps = try allocator.alloc([]const u8, 1);
    ui_deps[0] = try allocator.dupe(u8, "packages/core");
    try deps_map.put(try allocator.dupe(u8, "packages/ui"), ui_deps);

    // Both utils and core are affected
    var affected = AffectedResult{
        .projects = std.StringHashMap(void).init(allocator),
        .base_ref = try allocator.dupe(u8, "main"),
    };
    defer affected.deinit(allocator);

    const utils = try allocator.dupe(u8, "packages/utils");
    try affected.projects.put(utils, {});
    const core = try allocator.dupe(u8, "packages/core");
    try affected.projects.put(core, {});

    try expandWithDependents(allocator, &affected, deps_map);

    // Should include utils, core, app1, app2, ui
    try std.testing.expect(affected.contains("packages/utils"));
    try std.testing.expect(affected.contains("packages/core"));
    try std.testing.expect(affected.contains("apps/app1"));
    try std.testing.expect(affected.contains("apps/app2"));
    try std.testing.expect(affected.contains("packages/ui"));
}

test "expandWithDependents - no dependents" {
    const allocator = std.testing.allocator;

    // Empty dependency map
    var deps_map = std.StringHashMap([]const []const u8).init(allocator);
    defer deps_map.deinit();

    var affected = AffectedResult{
        .projects = std.StringHashMap(void).init(allocator),
        .base_ref = try allocator.dupe(u8, "main"),
    };
    defer affected.deinit(allocator);

    const core = try allocator.dupe(u8, "packages/core");
    try affected.projects.put(core, {});

    // Should not crash, affected should remain unchanged
    try expandWithDependents(allocator, &affected, deps_map);

    try std.testing.expect(affected.contains("packages/core"));
    try std.testing.expectEqual(@as(usize, 1), affected.projects.count());
}

test "expandWithDependents - circular dependencies" {
    const allocator = std.testing.allocator;

    // Setup circular: a -> b -> c -> a
    var deps_map = std.StringHashMap([]const []const u8).init(allocator);
    defer {
        var it = deps_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            allocator.free(entry.value_ptr.*);
        }
        deps_map.deinit();
    }

    const a_deps = try allocator.alloc([]const u8, 1);
    a_deps[0] = try allocator.dupe(u8, "b");
    try deps_map.put(try allocator.dupe(u8, "a"), a_deps);

    const b_deps = try allocator.alloc([]const u8, 1);
    b_deps[0] = try allocator.dupe(u8, "c");
    try deps_map.put(try allocator.dupe(u8, "b"), b_deps);

    const c_deps = try allocator.alloc([]const u8, 1);
    c_deps[0] = try allocator.dupe(u8, "a");
    try deps_map.put(try allocator.dupe(u8, "c"), c_deps);

    var affected = AffectedResult{
        .projects = std.StringHashMap(void).init(allocator),
        .base_ref = try allocator.dupe(u8, "main"),
    };
    defer affected.deinit(allocator);

    const a = try allocator.dupe(u8, "a");
    try affected.projects.put(a, {});

    // Should handle circular dependencies without infinite loop
    try expandWithDependents(allocator, &affected, deps_map);

    // All three should be affected
    try std.testing.expect(affected.contains("a"));
    try std.testing.expect(affected.contains("b"));
    try std.testing.expect(affected.contains("c"));
}
