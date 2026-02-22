const std = @import("std");
const types = @import("types.zig");

/// Generate YAML output for project context
pub fn generateYamlOutput(allocator: std.mem.Allocator, ctx: *const types.ProjectContext) ![]const u8 {
    var output = std.ArrayList(u8){};
    errdefer output.deinit(allocator);

    const writer = output.writer(allocator);

    // Project graph
    try writer.writeAll("project_graph:\n");
    try writer.writeAll("  packages:\n");

    for (ctx.project_graph.packages.items) |pkg| {
        try writer.print("    - name: \"{s}\"\n", .{pkg.name});
        try writer.print("      path: \"{s}\"\n", .{pkg.path});

        // Dependencies
        try writer.writeAll("      dependencies:\n");
        if (pkg.dependencies.items.len == 0) {
            try writer.writeAll("        []\n");
        } else {
            for (pkg.dependencies.items) |dep| {
                try writer.print("        - \"{s}\"\n", .{dep});
            }
        }

        // Tags
        try writer.writeAll("      tags:\n");
        if (pkg.tags.items.len == 0) {
            try writer.writeAll("        []\n");
        } else {
            for (pkg.tags.items) |tag| {
                try writer.print("        - \"{s}\"\n", .{tag});
            }
        }
    }

    // Task catalog
    try writer.writeAll("\ntask_catalog:\n");

    for (ctx.task_catalog.items) |pkg_info| {
        try writer.print("  - package: \"{s}\"\n", .{pkg_info.package_name});
        try writer.writeAll("    tasks:\n");

        if (pkg_info.tasks.items.len == 0) {
            try writer.writeAll("      []\n");
        } else {
            for (pkg_info.tasks.items) |task| {
                try writer.print("      - name: \"{s}\"\n", .{task.name});
                try writer.print("        cmd: \"{s}\"\n", .{task.cmd});

                if (task.description) |desc| {
                    try writer.print("        description: \"{s}\"\n", .{desc});
                } else {
                    try writer.writeAll("        description: null\n");
                }

                try writer.writeAll("        dependencies:\n");
                if (task.dependencies.items.len == 0) {
                    try writer.writeAll("          []\n");
                } else {
                    for (task.dependencies.items) |dep| {
                        try writer.print("          - \"{s}\"\n", .{dep});
                    }
                }
            }
        }
    }

    // Ownership mapping
    try writer.writeAll("\nownership_mapping:\n");

    if (ctx.ownership_mapping.items.len == 0) {
        try writer.writeAll("  []\n");
    } else {
        for (ctx.ownership_mapping.items) |entry| {
            try writer.print("  - path: \"{s}\"\n", .{entry.path});
            try writer.writeAll("    owners:\n");
            for (entry.owners.items) |owner| {
                try writer.print("      - \"{s}\"\n", .{owner});
            }
        }
    }

    // Recent changes
    try writer.writeAll("\nrecent_changes:\n");
    try writer.print("  commit_count: {d}\n", .{ctx.recent_changes.commit_count});
    try writer.print("  time_range_days: {d}\n", .{ctx.recent_changes.time_range_days});
    try writer.writeAll("  affected_packages:\n");

    if (ctx.recent_changes.affected_packages.items.len == 0) {
        try writer.writeAll("    []\n");
    } else {
        for (ctx.recent_changes.affected_packages.items) |pkg| {
            try writer.print("    - \"{s}\"\n", .{pkg});
        }
    }

    // Toolchains
    try writer.writeAll("\ntoolchains:\n");

    if (ctx.toolchains.items.len == 0) {
        try writer.writeAll("  []\n");
    } else {
        for (ctx.toolchains.items) |tc| {
            try writer.print("  - name: \"{s}\"\n", .{tc.name});
            try writer.print("    version: \"{s}\"\n", .{tc.version});

            if (tc.install_path) |path| {
                try writer.print("    install_path: \"{s}\"\n", .{path});
            } else {
                try writer.writeAll("    install_path: null\n");
            }
        }
    }

    return output.toOwnedSlice(allocator);
}

test "generateYamlOutput basic" {
    const allocator = std.testing.allocator;

    var ctx = types.ProjectContext.init(allocator);
    defer ctx.deinit();

    const yaml = try generateYamlOutput(allocator, &ctx);
    defer allocator.free(yaml);

    try std.testing.expect(yaml.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, yaml, "project_graph:") != null);
    try std.testing.expect(std.mem.indexOf(u8, yaml, "task_catalog:") != null);
}
