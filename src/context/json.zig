//! JSON rendering of a project context.
//!
//! `generateJsonOutput` writes the project graph, task catalog, ownership mapping, recent changes
//! and toolchains as one pretty-printed JSON object. Every package, task, path, owner and tag
//! string goes through `std.json.fmt`, so quotes, backslashes and control bytes are escaped.
//! Ownership: the returned slice is owned by the caller and freed with the same allocator; the
//! context is only read.

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
        try writer.print("        \"name\": {f},\n", .{std.json.fmt(pkg.name, .{})});
        try writer.print("        \"path\": {f},\n", .{std.json.fmt(pkg.path, .{})});

        // Dependencies
        try writer.writeAll("        \"dependencies\": [");
        for (pkg.dependencies.items, 0..) |dep, j| {
            try writer.print("{f}", .{std.json.fmt(dep, .{})});
            if (j < pkg.dependencies.items.len - 1) {
                try writer.writeAll(", ");
            }
        }
        try writer.writeAll("],\n");

        // Tags
        try writer.writeAll("        \"tags\": [");
        for (pkg.tags.items, 0..) |tag, j| {
            try writer.print("{f}", .{std.json.fmt(tag, .{})});
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
        try writer.print("      \"package\": {f},\n", .{std.json.fmt(pkg_info.package_name, .{})});
        try writer.writeAll("      \"tasks\": [\n");

        for (pkg_info.tasks.items, 0..) |task, j| {
            try writer.writeAll("        {\n");
            try writer.print("          \"name\": {f},\n", .{std.json.fmt(task.name, .{})});
            try writer.print("          \"cmd\": {f},\n", .{std.json.fmt(task.cmd, .{})});

            if (task.description) |desc| {
                try writer.print("          \"description\": {f},\n", .{std.json.fmt(desc, .{})});
            } else {
                try writer.writeAll("          \"description\": null,\n");
            }

            try writer.writeAll("          \"dependencies\": [");
            for (task.dependencies.items, 0..) |dep, k| {
                try writer.print("{f}", .{std.json.fmt(dep, .{})});
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
        try writer.print("      \"path\": {f},\n", .{std.json.fmt(entry.path, .{})});
        try writer.writeAll("      \"owners\": [");
        for (entry.owners.items, 0..) |owner, j| {
            try writer.print("{f}", .{std.json.fmt(owner, .{})});
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
        try writer.print("{f}", .{std.json.fmt(pkg, .{})});
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
        try writer.print("      \"name\": {f},\n", .{std.json.fmt(tc.name, .{})});
        try writer.print("      \"version\": {f},\n", .{std.json.fmt(tc.version, .{})});

        if (tc.install_path) |path| {
            try writer.print("      \"install_path\": {f}\n", .{std.json.fmt(path, .{})});
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

test "generateJsonOutput escapes quotes and control bytes in task fields" {
    const allocator = std.testing.allocator;

    var ctx = types.ProjectContext.init(allocator);
    defer ctx.deinit();

    const pkg = try types.PackageTaskInfo.init(allocator, "pkg\"one");
    try ctx.task_catalog.append(allocator, pkg);
    const pkg_ptr = &ctx.task_catalog.items[0];
    const task = try types.TaskInfo.init(allocator, "say \"hi\"", "echo a\\b\nc", "tab\there");
    try pkg_ptr.tasks.append(allocator, task);

    const json = try generateJsonOutput(allocator, &ctx);
    defer allocator.free(json);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const catalog = parsed.value.object.get("task_catalog").?.array.items;
    try std.testing.expectEqualStrings("pkg\"one", catalog[0].object.get("package").?.string);
    const task_obj = catalog[0].object.get("tasks").?.array.items[0].object;
    try std.testing.expectEqualStrings("say \"hi\"", task_obj.get("name").?.string);
    try std.testing.expectEqualStrings("echo a\\b\nc", task_obj.get("cmd").?.string);
    try std.testing.expectEqualStrings("tab\there", task_obj.get("description").?.string);
}
