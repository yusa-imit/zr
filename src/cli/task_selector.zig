const std = @import("std");
const types = @import("../config/types.zig");
const glob = @import("../util/glob.zig");

/// Task filtering options for task selection.
pub const TaskFilter = struct {
    /// Glob pattern for task name matching (e.g., "test:*", "build*").
    /// Supports * (single level), ** (multi-level), ? (single char).
    pattern: ?[]const u8 = null,

    /// Tags that tasks MUST have (AND logic). All tags must match.
    include_tags: []const []const u8 = &.{},

    /// Tags that tasks MUST NOT have. Any match excludes the task.
    exclude_tags: []const []const u8 = &.{},

    /// Directory prefix filter: only include tasks whose cwd starts with this path.
    dir_filter: ?[]const u8 = null,
};

/// Result of task selection with filtering applied.
pub const SelectionResult = struct {
    /// Names of tasks that matched the filter criteria.
    task_names: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SelectionResult) void {
        for (self.task_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.task_names);
    }
};

/// Select tasks from config based on filter criteria.
/// Returns list of task names that match ALL filter conditions.
/// Caller owns returned SelectionResult and must call deinit().
pub fn selectTasks(
    allocator: std.mem.Allocator,
    tasks: std.StringHashMap(types.Task),
    filter: TaskFilter,
) !SelectionResult {
    var matched = std.ArrayList([]const u8){};
    errdefer {
        for (matched.items) |name| allocator.free(name);
        matched.deinit(allocator);
    }

    var it = tasks.iterator();
    while (it.next()) |entry| {
        const task_name = entry.key_ptr.*;
        const task = entry.value_ptr.*;

        // Apply pattern matching if provided
        if (filter.pattern) |pattern| {
            if (!glob.match(pattern, task_name)) {
                continue; // Task name doesn't match pattern
            }
        }

        // Apply include_tags filter (AND logic: task must have ALL tags)
        if (filter.include_tags.len > 0) {
            var all_matched = true;
            for (filter.include_tags) |required_tag| {
                var found = false;
                for (task.tags) |task_tag| {
                    if (std.mem.eql(u8, required_tag, task_tag)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    all_matched = false;
                    break;
                }
            }
            if (!all_matched) continue; // Task doesn't have all required tags
        }

        // Apply exclude_tags filter (OR logic: task must have NONE of these tags)
        if (filter.exclude_tags.len > 0) {
            var should_exclude = false;
            for (filter.exclude_tags) |excluded_tag| {
                for (task.tags) |task_tag| {
                    if (std.mem.eql(u8, excluded_tag, task_tag)) {
                        should_exclude = true;
                        break;
                    }
                }
                if (should_exclude) break;
            }
            if (should_exclude) continue; // Task has an excluded tag
        }

        // Apply directory filter: task cwd must start with the given path
        if (filter.dir_filter) |dir| {
            const task_cwd = task.cwd orelse "";
            if (!std.mem.startsWith(u8, task_cwd, dir)) {
                continue;
            }
        }

        // Task passed all filters - add to results
        try matched.append(allocator, try allocator.dupe(u8, task_name));
    }

    return SelectionResult{
        .task_names = try matched.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Parse comma-separated tag list into owned slice.
/// Caller owns returned slice and must free each string + the slice itself.
pub fn parseTags(allocator: std.mem.Allocator, tags_str: []const u8) ![][]const u8 {
    var tags = std.ArrayList([]const u8){};
    errdefer {
        for (tags.items) |tag| allocator.free(tag);
        tags.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, tags_str, ',');
    while (iter.next()) |tag| {
        const trimmed = std.mem.trim(u8, tag, " \t");
        if (trimmed.len > 0) {
            try tags.append(allocator, try allocator.dupe(u8, trimmed));
        }
    }

    return tags.toOwnedSlice(allocator);
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "parseTags: single tag" {
    const allocator = std.testing.allocator;

    const tags = try parseTags(allocator, "ci");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 1), tags.len);
    try std.testing.expectEqualStrings("ci", tags[0]);
}

test "parseTags: multiple tags" {
    const allocator = std.testing.allocator;

    const tags = try parseTags(allocator, "ci,fast,unit");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 3), tags.len);
    try std.testing.expectEqualStrings("ci", tags[0]);
    try std.testing.expectEqualStrings("fast", tags[1]);
    try std.testing.expectEqualStrings("unit", tags[2]);
}

test "parseTags: tags with whitespace" {
    const allocator = std.testing.allocator;

    const tags = try parseTags(allocator, " ci , fast , unit ");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 3), tags.len);
    try std.testing.expectEqualStrings("ci", tags[0]);
    try std.testing.expectEqualStrings("fast", tags[1]);
    try std.testing.expectEqualStrings("unit", tags[2]);
}

test "parseTags: empty string returns empty slice" {
    const allocator = std.testing.allocator;

    const tags = try parseTags(allocator, "");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 0), tags.len);
}

test "parseTags: only whitespace returns empty slice" {
    const allocator = std.testing.allocator;

    const tags = try parseTags(allocator, "   \t  ");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 0), tags.len);
}

test "selectTasks: dir_filter includes only tasks with matching cwd prefix" {
    const allocator = std.testing.allocator;

    var tasks = std.StringHashMap(types.Task).init(allocator);
    defer tasks.deinit();

    var frontend_task = types.Task{
        .name = "build-frontend",
        .cmd = "echo frontend",
        .cwd = "/app/frontend",
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    var backend_task = types.Task{
        .name = "build-backend",
        .cmd = "echo backend",
        .cwd = "/app/backend",
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    var no_cwd_task = types.Task{
        .name = "test",
        .cmd = "echo test",
        .cwd = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };

    try tasks.put("build-frontend", frontend_task);
    try tasks.put("build-backend", backend_task);
    try tasks.put("test", no_cwd_task);

    const filter = TaskFilter{ .dir_filter = "/app/frontend" };
    var result = try selectTasks(allocator, tasks, filter);
    defer result.deinit();

    // Only build-frontend should match (cwd starts with /app/frontend)
    try std.testing.expectEqual(@as(usize, 1), result.task_names.len);
    try std.testing.expectEqualStrings("build-frontend", result.task_names[0]);

    _ = &frontend_task;
    _ = &backend_task;
    _ = &no_cwd_task;
}

test "selectTasks: dir_filter null includes all tasks regardless of cwd" {
    const allocator = std.testing.allocator;

    var tasks = std.StringHashMap(types.Task).init(allocator);
    defer tasks.deinit();

    var t1 = types.Task{
        .name = "a",
        .cmd = "echo a",
        .cwd = "/some/path",
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    var t2 = types.Task{
        .name = "b",
        .cmd = "echo b",
        .cwd = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };

    try tasks.put("a", t1);
    try tasks.put("b", t2);

    const filter = TaskFilter{}; // no dir_filter
    var result = try selectTasks(allocator, tasks, filter);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.task_names.len);

    _ = &t1;
    _ = &t2;
}

test "selectTasks: dir_filter excludes tasks with no cwd" {
    const allocator = std.testing.allocator;

    var tasks = std.StringHashMap(types.Task).init(allocator);
    defer tasks.deinit();

    var t1 = types.Task{
        .name = "with-cwd",
        .cmd = "echo a",
        .cwd = "/project/src",
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    var t2 = types.Task{
        .name = "no-cwd",
        .cmd = "echo b",
        .cwd = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };

    try tasks.put("with-cwd", t1);
    try tasks.put("no-cwd", t2);

    const filter = TaskFilter{ .dir_filter = "/project" };
    var result = try selectTasks(allocator, tasks, filter);
    defer result.deinit();

    // Only "with-cwd" matches since "no-cwd" has null cwd (which becomes "")
    try std.testing.expectEqual(@as(usize, 1), result.task_names.len);
    try std.testing.expectEqualStrings("with-cwd", result.task_names[0]);

    _ = &t1;
    _ = &t2;
}

test "parseTags: trailing comma is ignored" {
    const allocator = std.testing.allocator;

    const tags = try parseTags(allocator, "ci,fast,");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 2), tags.len);
    try std.testing.expectEqualStrings("ci", tags[0]);
    try std.testing.expectEqualStrings("fast", tags[1]);
}

test "parseTags: multiple consecutive commas" {
    const allocator = std.testing.allocator;

    const tags = try parseTags(allocator, "ci,,fast");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 2), tags.len);
    try std.testing.expectEqualStrings("ci", tags[0]);
    try std.testing.expectEqualStrings("fast", tags[1]);
}
