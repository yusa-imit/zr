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

