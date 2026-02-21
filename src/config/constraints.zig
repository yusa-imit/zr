const std = @import("std");
const types = @import("types.zig");
const Config = types.Config;
const Constraint = types.Constraint;
const ConstraintRule = types.ConstraintRule;
const ConstraintScope = types.ConstraintScope;
const Workspace = types.Workspace;

/// Result of constraint validation.
pub const ValidationResult = struct {
    passed: bool,
    violations: []Violation,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ValidationResult) void {
        for (self.violations) |*v| {
            self.allocator.free(v.from);
            self.allocator.free(v.to);
            if (v.message) |m| self.allocator.free(m);
        }
        if (self.violations.len > 0) self.allocator.free(self.violations);
    }
};

/// A constraint violation.
pub const Violation = struct {
    /// Source project that violates the constraint.
    from: []const u8,
    /// Target project that violates the constraint.
    to: []const u8,
    /// Rule that was violated.
    rule: ConstraintRule,
    /// Custom error message if provided.
    message: ?[]const u8,
};

/// Project metadata for constraint checking.
pub const ProjectInfo = struct {
    path: []const u8,
    tags: []const []const u8,
    dependencies: []const []const u8,
};

/// Validate all constraints in the config against workspace projects.
pub fn validateConstraints(
    allocator: std.mem.Allocator,
    config: *const Config,
    projects: []const ProjectInfo,
) !ValidationResult {
    var violations = std.ArrayList(Violation){};
    errdefer {
        for (violations.items) |*v| {
            allocator.free(v.from);
            allocator.free(v.to);
            if (v.message) |m| allocator.free(m);
        }
        violations.deinit(allocator);
    }

    for (config.constraints) |constraint| {
        switch (constraint.rule) {
            .no_circular => {
                try checkCircularDependencies(allocator, projects, &violations);
            },
            .tag_based => {
                if (constraint.from) |from_scope| {
                    if (constraint.to) |to_scope| {
                        try checkTagBasedConstraint(
                            allocator,
                            projects,
                            from_scope,
                            to_scope,
                            constraint.allow,
                            constraint.message,
                            &violations,
                        );
                    }
                }
            },
            .banned_dependency => {
                if (constraint.from) |from_scope| {
                    if (constraint.to) |to_scope| {
                        try checkBannedDependency(
                            allocator,
                            projects,
                            from_scope,
                            to_scope,
                            constraint.message,
                            &violations,
                        );
                    }
                }
            },
        }
    }

    const owned_violations = try allocator.alloc(Violation, violations.items.len);
    @memcpy(owned_violations, violations.items);
    violations.clearRetainingCapacity();

    return ValidationResult{
        .passed = owned_violations.len == 0,
        .violations = owned_violations,
        .allocator = allocator,
    };
}

/// Check for circular dependencies in the project graph.
fn checkCircularDependencies(
    allocator: std.mem.Allocator,
    projects: []const ProjectInfo,
    violations: *std.ArrayList(Violation),
) !void {
    // Build adjacency list
    var adj = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = adj.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        adj.deinit();
    }

    for (projects) |proj| {
        var deps = std.ArrayList([]const u8){};
        for (proj.dependencies) |dep| {
            try deps.append(allocator, dep);
        }
        try adj.put(proj.path, deps);
    }

    // DFS to detect cycles
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();
    var rec_stack = std.StringHashMap(void).init(allocator);
    defer rec_stack.deinit();

    for (projects) |proj| {
        if (visited.get(proj.path) == null) {
            try detectCycle(allocator, proj.path, &adj, &visited, &rec_stack, violations);
        }
    }
}

/// DFS helper to detect cycles.
fn detectCycle(
    allocator: std.mem.Allocator,
    node: []const u8,
    adj: *std.StringHashMap(std.ArrayList([]const u8)),
    visited: *std.StringHashMap(void),
    rec_stack: *std.StringHashMap(void),
    violations: *std.ArrayList(Violation),
) !void {
    try visited.put(node, {});
    try rec_stack.put(node, {});

    if (adj.get(node)) |neighbors| {
        for (neighbors.items) |neighbor| {
            if (visited.get(neighbor) == null) {
                try detectCycle(allocator, neighbor, adj, visited, rec_stack, violations);
            } else if (rec_stack.get(neighbor) != null) {
                // Cycle detected: neighbor is in recursion stack
                try violations.append(allocator, Violation{
                    .from = try allocator.dupe(u8, node),
                    .to = try allocator.dupe(u8, neighbor),
                    .rule = .no_circular,
                    .message = try allocator.dupe(u8, "Circular dependency detected"),
                });
            }
        }
    }

    _ = rec_stack.remove(node);
}

/// Check tag-based constraint (e.g., app → lib allowed).
fn checkTagBasedConstraint(
    allocator: std.mem.Allocator,
    projects: []const ProjectInfo,
    from_scope: ConstraintScope,
    to_scope: ConstraintScope,
    allow: bool,
    message: ?[]const u8,
    violations: *std.ArrayList(Violation),
) !void {
    for (projects) |proj| {
        if (!matchesScope(proj, from_scope)) continue;

        for (proj.dependencies) |dep| {
            const dep_proj = findProject(projects, dep) orelse continue;

            const matches_to = matchesScope(dep_proj, to_scope);

            // If allow=true, violation is when dep does NOT match to_scope
            // If allow=false, violation is when dep DOES match to_scope
            const is_violation = if (allow) !matches_to else matches_to;

            if (is_violation) {
                const msg = message orelse if (allow)
                    "Dependency violates allowed tag constraint"
                else
                    "Dependency violates banned tag constraint";

                try violations.append(allocator, Violation{
                    .from = try allocator.dupe(u8, proj.path),
                    .to = try allocator.dupe(u8, dep),
                    .rule = .tag_based,
                    .message = try allocator.dupe(u8, msg),
                });
            }
        }
    }
}

/// Check banned dependency constraint.
fn checkBannedDependency(
    allocator: std.mem.Allocator,
    projects: []const ProjectInfo,
    from_scope: ConstraintScope,
    to_scope: ConstraintScope,
    message: ?[]const u8,
    violations: *std.ArrayList(Violation),
) !void {
    for (projects) |proj| {
        if (!matchesScope(proj, from_scope)) continue;

        for (proj.dependencies) |dep| {
            const dep_proj = findProject(projects, dep) orelse continue;

            if (matchesScope(dep_proj, to_scope)) {
                const msg = message orelse "Banned dependency detected";

                try violations.append(allocator, Violation{
                    .from = try allocator.dupe(u8, proj.path),
                    .to = try allocator.dupe(u8, dep),
                    .rule = .banned_dependency,
                    .message = try allocator.dupe(u8, msg),
                });
            }
        }
    }
}

/// Check if a project matches a scope selector.
fn matchesScope(proj: ProjectInfo, scope: ConstraintScope) bool {
    switch (scope) {
        .all => return true,
        .tag => |tag| {
            for (proj.tags) |t| {
                if (std.mem.eql(u8, t, tag)) return true;
            }
            return false;
        },
        .path => |path| {
            return std.mem.eql(u8, proj.path, path);
        },
    }
}

/// Find a project by path.
fn findProject(projects: []const ProjectInfo, path: []const u8) ?ProjectInfo {
    for (projects) |proj| {
        if (std.mem.eql(u8, proj.path, path)) return proj;
    }
    return null;
}

// ───────────────────────────────────────────────────────────────────────────
// Tests
// ───────────────────────────────────────────────────────────────────────────

test "no violations with empty constraints" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    const projects = [_]ProjectInfo{
        .{ .path = "packages/a", .tags = &.{}, .dependencies = &.{} },
    };

    var result = try validateConstraints(allocator, &config, &projects);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(usize, 0), result.violations.len);
}

test "detect circular dependency" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Add no-circular constraint
    const constraints = try allocator.alloc(Constraint, 1);
    constraints[0] = Constraint{
        .rule = .no_circular,
        .scope = .all,
    };
    config.constraints = constraints;

    const projects = [_]ProjectInfo{
        .{ .path = "packages/a", .tags = &.{}, .dependencies = &[_][]const u8{"packages/b"} },
        .{ .path = "packages/b", .tags = &.{}, .dependencies = &[_][]const u8{"packages/a"} },
    };

    var result = try validateConstraints(allocator, &config, &projects);
    defer result.deinit();

    try std.testing.expect(!result.passed);
    try std.testing.expect(result.violations.len > 0);
}

test "tag-based constraint allows valid dependencies" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Add tag-based constraint: app → lib allowed
    const constraints = try allocator.alloc(Constraint, 1);
    constraints[0] = Constraint{
        .rule = .tag_based,
        .from = ConstraintScope{ .tag = try allocator.dupe(u8, "app") },
        .to = ConstraintScope{ .tag = try allocator.dupe(u8, "lib") },
        .allow = true,
    };
    config.constraints = constraints;

    const app_tag = [_][]const u8{"app"};
    const lib_tag = [_][]const u8{"lib"};
    const projects = [_]ProjectInfo{
        .{ .path = "packages/frontend", .tags = &app_tag, .dependencies = &[_][]const u8{"packages/core"} },
        .{ .path = "packages/core", .tags = &lib_tag, .dependencies = &.{} },
    };

    var result = try validateConstraints(allocator, &config, &projects);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(usize, 0), result.violations.len);
}

test "banned dependency constraint detects violations" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Add banned-dependency constraint: frontend → internal-api banned
    const constraints = try allocator.alloc(Constraint, 1);
    constraints[0] = Constraint{
        .rule = .banned_dependency,
        .from = ConstraintScope{ .path = try allocator.dupe(u8, "packages/frontend") },
        .to = ConstraintScope{ .path = try allocator.dupe(u8, "packages/internal-api") },
        .allow = false,
    };
    config.constraints = constraints;

    const projects = [_]ProjectInfo{
        .{ .path = "packages/frontend", .tags = &.{}, .dependencies = &[_][]const u8{"packages/internal-api"} },
        .{ .path = "packages/internal-api", .tags = &.{}, .dependencies = &.{} },
    };

    var result = try validateConstraints(allocator, &config, &projects);
    defer result.deinit();

    try std.testing.expect(!result.passed);
    try std.testing.expect(result.violations.len > 0);
}
