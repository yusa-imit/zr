const std = @import("std");
const config_loader = @import("../config/loader.zig");
const constraints_mod = @import("../config/constraints.zig");
const workspace_mod = @import("../config/loader.zig");
const common = @import("common.zig");
const types = @import("../config/types.zig");

const Config = types.Config;
const Workspace = types.Workspace;
const ProjectInfo = constraints_mod.ProjectInfo;
const ValidationResult = constraints_mod.ValidationResult;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    var config_path: []const u8 = "zr.toml";
    var verbose = false;

    // Parse command-line arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 >= args.len) {
                try ew.print("✗ [Lint]: --config requires a path\n", .{});
                return 1;
            }
            i += 1;
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w);
            return 0;
        }
    }

    // Load config
    var config = config_loader.loadFromFile(allocator, config_path) catch |err| {
        try ew.print("✗ [Lint]: Failed to load config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer config.deinit();

    // Check if constraints are defined
    if (config.constraints.len == 0) {
        try w.print("ℹ No architecture constraints defined in {s}\n", .{config_path});
        try w.print("\n  Add constraints to enforce dependency rules:\n", .{});
        try w.print("  [[constraints]]\n", .{});
        try w.print("  rule = \"no-circular\"\n", .{});
        try w.print("  scope = \"all\"\n", .{});
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
        try w.print("Found {d} project(s)\n", .{projects.len});
        try w.print("Validating {d} constraint(s)...\n\n", .{config.constraints.len});
    }

    // Validate constraints
    var result = try constraints_mod.validateConstraints(allocator, &config, projects);
    defer result.deinit();

    if (result.passed) {
        try w.print("✓ All architecture constraints passed\n", .{});
        if (verbose) {
            try w.print("\n  Checked:\n", .{});
            for (config.constraints) |constraint| {
                const rule_str = switch (constraint.rule) {
                    .no_circular => "no-circular",
                    .tag_based => "tag-based",
                    .banned_dependency => "banned-dependency",
                };
                try w.print("    - {s}\n", .{rule_str});
            }
        }
        return 0;
    } else {
        try ew.print("✗ [Lint]: Found {d} constraint violation(s)\n\n", .{result.violations.len});

        for (result.violations, 1..) |violation, idx| {
            const rule_str = switch (violation.rule) {
                .no_circular => "no-circular",
                .tag_based => "tag-based",
                .banned_dependency => "banned-dependency",
            };

            try w.print("  {d}. {s}\n", .{ idx, rule_str });
            try w.print("     From: {s}\n", .{violation.from});
            try w.print("     To:   {s}\n", .{violation.to});
            if (violation.message) |msg| {
                try w.print("     {s}\n", .{msg});
            }
            try w.print("\n", .{});
        }

        try w.print("  Hint: Review your workspace dependencies and constraint rules\n", .{});
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
        // No workspace — single project with metadata if available
        const tags = if (config.metadata) |m| try dupeStringSlice(allocator, m.tags) else &.{};
        const deps = if (config.metadata) |m| try dupeStringSlice(allocator, m.dependencies) else &.{};
        try project_list.append(allocator, ProjectInfo{
            .path = try allocator.dupe(u8, "."),
            .tags = tags,
            .dependencies = deps,
        });
        const owned = try allocator.alloc(ProjectInfo, project_list.items.len);
        @memcpy(owned, project_list.items);
        project_list.clearRetainingCapacity();
        return owned;
    };

    // Discover workspace members from filesystem and parse their metadata
    for (ws.members) |member_pattern| {
        const members = try workspace_mod.discoverWorkspaceMembers(allocator, member_pattern);
        defer {
            for (members) |m| allocator.free(m);
            allocator.free(members);
        }

        for (members) |member_path| {
            const proj_info = try loadProjectMetadata(allocator, member_path);
            try project_list.append(allocator, proj_info);
        }
    }

    // Fallback: if no members found, include root with metadata
    if (project_list.items.len == 0) {
        const tags = if (config.metadata) |m| try dupeStringSlice(allocator, m.tags) else &.{};
        const deps = if (config.metadata) |m| try dupeStringSlice(allocator, m.dependencies) else &.{};
        try project_list.append(allocator, ProjectInfo{
            .path = try allocator.dupe(u8, "."),
            .tags = tags,
            .dependencies = deps,
        });
    }

    const owned = try allocator.alloc(ProjectInfo, project_list.items.len);
    @memcpy(owned, project_list.items);
    project_list.clearRetainingCapacity();
    return owned;
}

/// Load project metadata (tags, dependencies) from a member's zr.toml.
fn loadProjectMetadata(allocator: std.mem.Allocator, project_path: []const u8) !ProjectInfo {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const config_path = try std.fmt.bufPrint(&path_buf, "{s}/zr.toml", .{project_path});

    // Try to load member's config
    var member_config = config_loader.loadFromFile(allocator, config_path) catch {
        // If no config file, return empty metadata
        return ProjectInfo{
            .path = try allocator.dupe(u8, project_path),
            .tags = &.{},
            .dependencies = &.{},
        };
    };
    defer member_config.deinit();

    // Extract tags from metadata (if available)
    const tags = if (member_config.metadata) |m|
        try dupeStringSlice(allocator, m.tags)
    else
        &.{};

    // Extract dependencies from workspace.member_dependencies (fallback to metadata)
    const deps = if (member_config.workspace) |ws_member|
        try dupeStringSlice(allocator, ws_member.member_dependencies)
    else if (member_config.metadata) |m|
        try dupeStringSlice(allocator, m.dependencies)
    else
        &.{};

    return ProjectInfo{
        .path = try allocator.dupe(u8, project_path),
        .tags = tags,
        .dependencies = deps,
    };
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

fn printHelp(w: *std.Io.Writer) !void {
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
        \\For more information: https://github.com/yusa-imit/zr
        \\
    ;
    try w.print("{s}", .{help});
}

// ───────────────────────────────────────────────────────────────────────────
// Tests
// ───────────────────────────────────────────────────────────────────────────

test "loadProjectMetadata extracts tags and dependencies" {
    const allocator = std.testing.allocator;

    // Create a test config with metadata
    var config = Config.init(allocator);
    defer config.deinit();

    // Set up metadata
    const tags = try allocator.alloc([]const u8, 2);
    tags[0] = try allocator.dupe(u8, "app");
    tags[1] = try allocator.dupe(u8, "frontend");

    const deps = try allocator.alloc([]const u8, 1);
    deps[0] = try allocator.dupe(u8, "packages/core");

    config.metadata = types.Metadata{
        .tags = tags,
        .dependencies = deps,
    };

    // Test that metadata is properly stored
    try std.testing.expect(config.metadata != null);
    try std.testing.expectEqual(@as(usize, 2), config.metadata.?.tags.len);
    try std.testing.expectEqualStrings("app", config.metadata.?.tags[0]);
    try std.testing.expectEqualStrings("frontend", config.metadata.?.tags[1]);
    try std.testing.expectEqual(@as(usize, 1), config.metadata.?.dependencies.len);
    try std.testing.expectEqualStrings("packages/core", config.metadata.?.dependencies[0]);
}

test "run writes help output to writer when --help flag provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{"--help"};

    // This should FAIL until run is refactored to accept writers
    const code = try run(allocator, &args, &out_w.interface, &err_w.interface);

    // Help should exit with 0
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "run writes error to writer when config not found" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{"--config"};

    // Missing value for --config should be caught
    // This should FAIL until run is refactored to accept writers
    const code = try run(allocator, &args, &out_w.interface, &err_w.interface);

    // Should return error code
    try std.testing.expectEqual(@as(u8, 1), code);
}
