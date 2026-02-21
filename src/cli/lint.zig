const std = @import("std");
const config_loader = @import("../config/loader.zig");
const constraints_mod = @import("../config/constraints.zig");
const workspace_mod = @import("../config/loader.zig");
const common = @import("common.zig");

const Config = @import("../config/types.zig").Config;
const Workspace = @import("../config/types.zig").Workspace;
const ProjectInfo = constraints_mod.ProjectInfo;
const ValidationResult = constraints_mod.ValidationResult;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var config_path: []const u8 = "zr.toml";
    var verbose = false;

    // Parse command-line arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --config requires a path\n", .{});
                return 1;
            }
            i += 1;
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return 0;
        }
    }

    // Load config
    var config = config_loader.loadFromFile(allocator, config_path) catch |err| {
        std.debug.print("✗ Failed to load config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer config.deinit();

    // Check if constraints are defined
    if (config.constraints.len == 0) {
        std.debug.print("ℹ No architecture constraints defined in {s}\n", .{config_path});
        std.debug.print("\n  Add constraints to enforce dependency rules:\n", .{});
        std.debug.print("  [[constraints]]\n", .{});
        std.debug.print("  rule = \"no-circular\"\n", .{});
        std.debug.print("  scope = \"all\"\n", .{});
        return 0;
    }

    // Gather workspace projects
    const projects = try gatherProjects(allocator, &config);
    defer {
        for (projects) |*proj| {
            allocator.free(proj.path);
            for (proj.tags) |tag| allocator.free(tag);
            if (proj.tags.len > 0) allocator.free(proj.tags);
            for (proj.dependencies) |dep| allocator.free(dep);
            if (proj.dependencies.len > 0) allocator.free(proj.dependencies);
        }
        if (projects.len > 0) allocator.free(projects);
    }

    if (verbose) {
        std.debug.print("Found {d} project(s)\n", .{projects.len});
        std.debug.print("Validating {d} constraint(s)...\n\n", .{config.constraints.len});
    }

    // Validate constraints
    var result = try constraints_mod.validateConstraints(allocator, &config, projects);
    defer result.deinit();

    if (result.passed) {
        std.debug.print("✓ All architecture constraints passed\n", .{});
        if (verbose) {
            std.debug.print("\n  Checked:\n", .{});
            for (config.constraints) |constraint| {
                const rule_str = switch (constraint.rule) {
                    .no_circular => "no-circular",
                    .tag_based => "tag-based",
                    .banned_dependency => "banned-dependency",
                };
                std.debug.print("    - {s}\n", .{rule_str});
            }
        }
        return 0;
    } else {
        std.debug.print("✗ Found {d} constraint violation(s)\n\n", .{result.violations.len});

        for (result.violations, 1..) |violation, idx| {
            const rule_str = switch (violation.rule) {
                .no_circular => "no-circular",
                .tag_based => "tag-based",
                .banned_dependency => "banned-dependency",
            };

            std.debug.print("  {d}. {s}\n", .{ idx, rule_str });
            std.debug.print("     From: {s}\n", .{violation.from});
            std.debug.print("     To:   {s}\n", .{violation.to});
            if (violation.message) |msg| {
                std.debug.print("     {s}\n", .{msg});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("  Hint: Review your workspace dependencies and constraint rules\n", .{});
        return 1;
    }
}

/// Gather project information from workspace config.
fn gatherProjects(allocator: std.mem.Allocator, config: *const Config) ![]ProjectInfo {
    var project_list = std.ArrayList(ProjectInfo){};
    errdefer {
        for (project_list.items) |*proj| {
            allocator.free(proj.path);
            for (proj.tags) |tag| allocator.free(tag);
            if (proj.tags.len > 0) allocator.free(proj.tags);
            for (proj.dependencies) |dep| allocator.free(dep);
            if (proj.dependencies.len > 0) allocator.free(proj.dependencies);
        }
        project_list.deinit(allocator);
    }

    const ws = config.workspace orelse {
        // No workspace — single project
        try project_list.append(allocator, ProjectInfo{
            .path = try allocator.dupe(u8, "."),
            .tags = &.{},
            .dependencies = &.{},
        });
        const owned = try allocator.alloc(ProjectInfo, project_list.items.len);
        @memcpy(owned, project_list.items);
        project_list.clearRetainingCapacity();
        return owned;
    };

    // TODO: For now, use member_dependencies from workspace config.
    // In a real implementation, this would discover all workspace members
    // from the filesystem and parse their zr.toml files.
    if (ws.member_dependencies.len > 0) {
        try project_list.append(allocator, ProjectInfo{
            .path = try allocator.dupe(u8, "."),
            .tags = &.{},
            .dependencies = try dupeStringSlice(allocator, ws.member_dependencies),
        });
    } else {
        try project_list.append(allocator, ProjectInfo{
            .path = try allocator.dupe(u8, "."),
            .tags = &.{},
            .dependencies = &.{},
        });
    }

    const owned = try allocator.alloc(ProjectInfo, project_list.items.len);
    @memcpy(owned, project_list.items);
    project_list.clearRetainingCapacity();
    return owned;
}

fn dupeStringSlice(allocator: std.mem.Allocator, slice: []const []const u8) ![][]const u8 {
    const result = try allocator.alloc([]const u8, slice.len);
    var duped: usize = 0;
    errdefer {
        for (result[0..duped]) |s| allocator.free(s);
        allocator.free(result);
    }
    for (slice, 0..) |s, i| {
        result[i] = try allocator.dupe(u8, s);
        duped += 1;
    }
    return result;
}

fn printHelp() void {
    const help =
        \\Usage: zr lint [options]
        \\
        \\Validate architecture constraints defined in zr.toml
        \\
        \\Options:
        \\  -c, --config <path>    Path to config file (default: zr.toml)
        \\  -v, --verbose          Show detailed validation output
        \\  -h, --help             Show this help message
        \\
        \\Examples:
        \\  zr lint                         # Validate constraints in zr.toml
        \\  zr lint --config custom.toml    # Use custom config file
        \\  zr lint --verbose               # Show detailed output
        \\
        \\Constraint Types:
        \\  no-circular         Prohibit circular dependencies
        \\  tag-based           Control dependencies based on project tags
        \\  banned-dependency   Explicitly ban specific dependencies
        \\
        \\For more information: https://github.com/YOUR_ORG/zr
        \\
    ;
    std.debug.print("{s}", .{help});
}

// ───────────────────────────────────────────────────────────────────────────
// Tests
// ───────────────────────────────────────────────────────────────────────────

test "lint command with no constraints" {
    // This test would require file I/O, skipping for now
}
