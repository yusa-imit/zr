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

    /// Directory filter (not yet implemented in v1.77.0).
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
    var matched = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (matched.items) |name| allocator.free(name);
        matched.deinit();
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

        // Task passed all filters - add to results
        try matched.append(try allocator.dupe(u8, task_name));
    }

    return SelectionResult{
        .task_names = try matched.toOwnedSlice(),
        .allocator = allocator,
    };
}

/// Parse comma-separated tag list into owned slice.
/// Caller owns returned slice and must free each string + the slice itself.
pub fn parseTags(allocator: std.mem.Allocator, tags_str: []const u8) ![][]const u8 {
    var tags = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (tags.items) |tag| allocator.free(tag);
        tags.deinit();
    }

    var iter = std.mem.splitScalar(u8, tags_str, ',');
    while (iter.next()) |tag| {
        const trimmed = std.mem.trim(u8, tag, " \t");
        if (trimmed.len > 0) {
            try tags.append(try allocator.dupe(u8, trimmed));
        }
    }

    return tags.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "parseTags: single tag" {
    const allocator = std.testing.allocator;
    const tags = try parseTags(allocator, "integration");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 1), tags.len);
    try std.testing.expectEqualStrings("integration", tags[0]);
}

test "parseTags: multiple tags with spaces" {
    const allocator = std.testing.allocator;
    const tags = try parseTags(allocator, " critical , backend , fast ");
    defer {
        for (tags) |tag| allocator.free(tag);
        allocator.free(tags);
    }

    try std.testing.expectEqual(@as(usize, 3), tags.len);
    try std.testing.expectEqualStrings("critical", tags[0]);
    try std.testing.expectEqualStrings("backend", tags[1]);
    try std.testing.expectEqualStrings("fast", tags[2]);
}

test "parseTags: empty string" {
    const allocator = std.testing.allocator;
    const tags = try parseTags(allocator, "");
    defer allocator.free(tags);

    try std.testing.expectEqual(@as(usize, 0), tags.len);
}

test "selectTasks: pattern matching" {
    const allocator = std.testing.allocator;
    var tasks = std.StringHashMap(types.Task).init(allocator);
    defer tasks.deinit();

    // Create test tasks
    var task1 = types.Task.init(allocator);
    task1.cmd = try allocator.dupe(u8, "echo test1");
    try tasks.put("test:unit", task1);

    var task2 = types.Task.init(allocator);
    task2.cmd = try allocator.dupe(u8, "echo test2");
    try tasks.put("test:integration", task2);

    var task3 = types.Task.init(allocator);
    task3.cmd = try allocator.dupe(u8, "echo build");
    try tasks.put("build", task3);

    defer {
        var it = tasks.iterator();
        while (it.next()) |entry| {
            var t = entry.value_ptr.*;
            t.deinit();
        }
    }

    // Test pattern matching
    const filter = TaskFilter{ .pattern = "test:*" };
    var result = try selectTasks(allocator, tasks, filter);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.task_names.len);
    // Results are unordered, so check both are present
    var found_unit = false;
    var found_integration = false;
    for (result.task_names) |name| {
        if (std.mem.eql(u8, name, "test:unit")) found_unit = true;
        if (std.mem.eql(u8, name, "test:integration")) found_integration = true;
    }
    try std.testing.expect(found_unit);
    try std.testing.expect(found_integration);
}

test "selectTasks: tag inclusion (AND logic)" {
    const allocator = std.testing.allocator;
    var tasks = std.StringHashMap(types.Task).init(allocator);
    defer tasks.deinit();

    // Task with both tags
    var task1 = types.Task.init(allocator);
    task1.cmd = try allocator.dupe(u8, "echo task1");
    task1.tags = try allocator.alloc([]const u8, 2);
    task1.tags[0] = try allocator.dupe(u8, "critical");
    task1.tags[1] = try allocator.dupe(u8, "backend");
    try tasks.put("api-deploy", task1);

    // Task with only one tag
    var task2 = types.Task.init(allocator);
    task2.cmd = try allocator.dupe(u8, "echo task2");
    task2.tags = try allocator.alloc([]const u8, 1);
    task2.tags[0] = try allocator.dupe(u8, "critical");
    try tasks.put("frontend-deploy", task2);

    defer {
        var it = tasks.iterator();
        while (it.next()) |entry| {
            var t = entry.value_ptr.*;
            t.deinit();
        }
    }

    // Filter: must have BOTH critical AND backend
    const include = [_][]const u8{ "critical", "backend" };
    const filter = TaskFilter{ .include_tags = &include };
    var result = try selectTasks(allocator, tasks, filter);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.task_names.len);
    try std.testing.expectEqualStrings("api-deploy", result.task_names[0]);
}

test "selectTasks: tag exclusion" {
    const allocator = std.testing.allocator;
    var tasks = std.StringHashMap(types.Task).init(allocator);
    defer tasks.deinit();

    // Fast task
    var task1 = types.Task.init(allocator);
    task1.cmd = try allocator.dupe(u8, "echo fast");
    task1.tags = try allocator.alloc([]const u8, 1);
    task1.tags[0] = try allocator.dupe(u8, "fast");
    try tasks.put("unit-test", task1);

    // Slow task
    var task2 = types.Task.init(allocator);
    task2.cmd = try allocator.dupe(u8, "echo slow");
    task2.tags = try allocator.alloc([]const u8, 1);
    task2.tags[0] = try allocator.dupe(u8, "slow");
    try tasks.put("integration-test", task2);

    defer {
        var it = tasks.iterator();
        while (it.next()) |entry| {
            var t = entry.value_ptr.*;
            t.deinit();
        }
    }

    // Exclude slow tasks
    const exclude = [_][]const u8{"slow"};
    const filter = TaskFilter{ .exclude_tags = &exclude };
    var result = try selectTasks(allocator, tasks, filter);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.task_names.len);
    try std.testing.expectEqualStrings("unit-test", result.task_names[0]);
}

test "selectTasks: combined filters" {
    const allocator = std.testing.allocator;
    var tasks = std.StringHashMap(types.Task).init(allocator);
    defer tasks.deinit();

    // Critical, backend, fast
    var task1 = types.Task.init(allocator);
    task1.cmd = try allocator.dupe(u8, "echo task1");
    task1.tags = try allocator.alloc([]const u8, 3);
    task1.tags[0] = try allocator.dupe(u8, "critical");
    task1.tags[1] = try allocator.dupe(u8, "backend");
    task1.tags[2] = try allocator.dupe(u8, "fast");
    try tasks.put("api:deploy", task1);

    // Critical, backend, slow (should be excluded)
    var task2 = types.Task.init(allocator);
    task2.cmd = try allocator.dupe(u8, "echo task2");
    task2.tags = try allocator.alloc([]const u8, 3);
    task2.tags[0] = try allocator.dupe(u8, "critical");
    task2.tags[1] = try allocator.dupe(u8, "backend");
    task2.tags[2] = try allocator.dupe(u8, "slow");
    try tasks.put("api:test", task2);

    // Critical, frontend (missing backend tag)
    var task3 = types.Task.init(allocator);
    task3.cmd = try allocator.dupe(u8, "echo task3");
    task3.tags = try allocator.alloc([]const u8, 2);
    task3.tags[0] = try allocator.dupe(u8, "critical");
    task3.tags[1] = try allocator.dupe(u8, "frontend");
    try tasks.put("web:deploy", task3);

    defer {
        var it = tasks.iterator();
        while (it.next()) |entry| {
            var t = entry.value_ptr.*;
            t.deinit();
        }
    }

    // Filter: pattern "api:*" + include "critical,backend" + exclude "slow"
    const include = [_][]const u8{ "critical", "backend" };
    const exclude = [_][]const u8{"slow"};
    const filter = TaskFilter{
        .pattern = "api:*",
        .include_tags = &include,
        .exclude_tags = &exclude,
    };
    var result = try selectTasks(allocator, tasks, filter);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.task_names.len);
    try std.testing.expectEqualStrings("api:deploy", result.task_names[0]);
}
