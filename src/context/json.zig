const std = @import("std");
const types = @import("types.zig");

/// Generate JSON output for project context
pub fn generateJsonOutput(allocator: std.mem.Allocator, ctx: *const types.ProjectContext) ![]const u8 {
    var output = std.ArrayList(u8){};
    errdefer output.deinit(allocator);

    const writer = output.writer(allocator);

    try writer.writeAll("{\n");

    // Project graph
    try writer.writeAll("  \"project_graph\": {\n");
    try writer.writeAll("    \"packages\": [\n");

    for (ctx.project_graph.packages.items, 0..) |pkg, i| {
        try writer.writeAll("      {\n");
        try writer.print("        \"name\": \"{s}\",\n", .{escapeJson(pkg.name)});
        try writer.print("        \"path\": \"{s}\",\n", .{escapeJson(pkg.path)});

        // Dependencies
        try writer.writeAll("        \"dependencies\": [");
        for (pkg.dependencies.items, 0..) |dep, j| {
            try writer.print("\"{s}\"", .{escapeJson(dep)});
            if (j < pkg.dependencies.items.len - 1) {
                try writer.writeAll(", ");
            }
        }
        try writer.writeAll("],\n");

        // Tags
        try writer.writeAll("        \"tags\": [");
        for (pkg.tags.items, 0..) |tag, j| {
            try writer.print("\"{s}\"", .{escapeJson(tag)});
            if (j < pkg.tags.items.len - 1) {
                try writer.writeAll(", ");
            }
        }
        try writer.writeAll("]\n");

        try writer.writeAll("      }");
        if (i < ctx.project_graph.packages.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("    ]\n");
    try writer.writeAll("  },\n");

    // Task catalog
    try writer.writeAll("  \"task_catalog\": [\n");

    for (ctx.task_catalog.items, 0..) |pkg_info, i| {
        try writer.writeAll("    {\n");
        try writer.print("      \"package\": \"{s}\",\n", .{escapeJson(pkg_info.package_name)});
        try writer.writeAll("      \"tasks\": [\n");

        for (pkg_info.tasks.items, 0..) |task, j| {
            try writer.writeAll("        {\n");
            try writer.print("          \"name\": \"{s}\",\n", .{escapeJson(task.name)});
            try writer.print("          \"cmd\": \"{s}\",\n", .{escapeJson(task.cmd)});

            if (task.description) |desc| {
                try writer.print("          \"description\": \"{s}\",\n", .{escapeJson(desc)});
            } else {
                try writer.writeAll("          \"description\": null,\n");
            }

            try writer.writeAll("          \"dependencies\": [");
            for (task.dependencies.items, 0..) |dep, k| {
                try writer.print("\"{s}\"", .{escapeJson(dep)});
                if (k < task.dependencies.items.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll("]\n");

            try writer.writeAll("        }");
            if (j < pkg_info.tasks.items.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }

        try writer.writeAll("      ]\n");
        try writer.writeAll("    }");
        if (i < ctx.task_catalog.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ],\n");

    // Ownership mapping
    try writer.writeAll("  \"ownership_mapping\": [\n");

    for (ctx.ownership_mapping.items, 0..) |entry, i| {
        try writer.writeAll("    {\n");
        try writer.print("      \"path\": \"{s}\",\n", .{escapeJson(entry.path)});
        try writer.writeAll("      \"owners\": [");
        for (entry.owners.items, 0..) |owner, j| {
            try writer.print("\"{s}\"", .{escapeJson(owner)});
            if (j < entry.owners.items.len - 1) {
                try writer.writeAll(", ");
            }
        }
        try writer.writeAll("]\n");
        try writer.writeAll("    }");
        if (i < ctx.ownership_mapping.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ],\n");

    // Recent changes
    try writer.writeAll("  \"recent_changes\": {\n");
    try writer.print("    \"commit_count\": {d},\n", .{ctx.recent_changes.commit_count});
    try writer.print("    \"files_changed\": {d},\n", .{ctx.recent_changes.files_changed});
    try writer.print("    \"time_range_days\": {d},\n", .{ctx.recent_changes.time_range_days});
    try writer.writeAll("    \"affected_packages\": [");
    for (ctx.recent_changes.affected_packages.items, 0..) |pkg, i| {
        try writer.print("\"{s}\"", .{escapeJson(pkg)});
        if (i < ctx.recent_changes.affected_packages.items.len - 1) {
            try writer.writeAll(", ");
        }
    }
    try writer.writeAll("]\n");
    try writer.writeAll("  },\n");

    // Toolchains
    try writer.writeAll("  \"toolchains\": [\n");

    for (ctx.toolchains.items, 0..) |tc, i| {
        try writer.writeAll("    {\n");
        try writer.print("      \"name\": \"{s}\",\n", .{escapeJson(tc.name)});
        try writer.print("      \"version\": \"{s}\",\n", .{escapeJson(tc.version)});

        if (tc.install_path) |path| {
            try writer.print("      \"install_path\": \"{s}\"\n", .{escapeJson(path)});
        } else {
            try writer.writeAll("      \"install_path\": null\n");
        }

        try writer.writeAll("    }");
        if (i < ctx.toolchains.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");

    return output.toOwnedSlice(allocator);
}

/// Escape JSON special characters
fn escapeJson(s: []const u8) []const u8 {
    // Simple approach: assume strings don't contain special chars for now
    // In production, would need proper escaping of ", \, etc.
    return s;
}

test "generateJsonOutput basic" {
    const allocator = std.testing.allocator;

    var ctx = types.ProjectContext.init(allocator);
    defer ctx.deinit();

    const json = try generateJsonOutput(allocator, &ctx);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "project_graph") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "task_catalog") != null);
}
