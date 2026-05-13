const std = @import("std");
const sailor = @import("sailor");
const config_types = @import("../config/types.zig");
const man_gen = @import("../output/man.zig");

const Config = config_types.Config;
const Task = config_types.Task;

pub fn cmdHelp(
    config: *const Config,
    task_name: []const u8,
    _use_color: bool,
    w: anytype,
    ew: anytype,
) !void {
    _ = _use_color; // Unused for now
    // Find the task
    const task = config.tasks.get(task_name) orelse {
        try ew.print("Error: Task '{s}' not found\n", .{task_name});
        return error.TaskNotFound;
    };

    // Print task name
    try w.print("{s}", .{task.name});
    try w.writeAll("\n\n");

    // Print description if available
    if (task.description) |desc| {
        const short = desc.getShort();
        try w.print("{s}", .{short});

        if (desc.getLong()) |long| {
            try w.print("\n\n{s}", .{long});
        }
        try w.writeAll("\n\n");
    }

    // Print command
    try w.writeAll("Command:");
    try w.print("\n  {s}\n\n", .{task.cmd});

    // Print examples if available
    if (task.examples) |examples| {
        if (examples.len > 0) {
            try w.writeAll("Examples:");
            try w.writeAll("\n");
            for (examples) |example| {
                try w.print("  {s}\n", .{example});
            }
            try w.writeAll("\n");
        }
    }

    // Print parameters if available
    if (task.task_params.len > 0) {
        try w.writeAll("Parameters:");
        try w.writeAll("\n");
        for (task.task_params) |param| {
            try w.print("  {s}", .{param.name});
            if (param.default == null) {
                try w.writeAll(" (required)");
            } else if (param.default) |default| {
                try w.print(" [default: {s}]", .{default});
            }
            if (param.description) |pdesc| {
                try w.print(" — {s}", .{pdesc});
            }
            try w.writeAll("\n");
        }
        try w.writeAll("\n");
    }

    // Print outputs if available
    if (task.outputs) |outputs| {
        if (outputs.count() > 0) {
            try w.writeAll("Outputs:");
            try w.writeAll("\n");

            var iter = outputs.iterator();
            while (iter.next()) |entry| {
                try w.print("  {s}", .{entry.key_ptr.*});
                try w.print(" — {s}\n", .{entry.value_ptr.*});
            }
            try w.writeAll("\n");
        }
    }

    // Print dependencies if available
    if (task.deps.len > 0) {
        try w.writeAll("Dependencies:");
        try w.writeAll("\n");
        for (task.deps) |dep| {
            try w.print("  {s}\n", .{dep});
        }
        try w.writeAll("\n");
    }

    // Print related tasks if available
    if (task.see_also) |see_also| {
        if (see_also.len > 0) {
            try w.writeAll("See also:");
            try w.writeAll("\n");
            for (see_also) |related| {
                try w.print("  {s}\n", .{related});
            }
            try w.writeAll("\n");
        }
    }
}

pub fn cmdMan(
    allocator: std.mem.Allocator,
    config: *const Config,
    task_name: []const u8,
    w: anytype,
    ew: anytype,
) !void {
    // Find the task
    const task = config.tasks.get(task_name) orelse {
        try ew.print("Error: Task '{s}' not found\n", .{task_name});
        return error.TaskNotFound;
    };

    // Generate man page
    try man_gen.formatManPage(allocator, task, w);
}

// Integration tests for help.zig exist in tests/task_documentation_test.zig
// Unit tests below verify formatting logic in isolation


test "cmdHelp returns error for non-existent task" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var err_buf = std.ArrayList(u8){};
    defer err_buf.deinit(allocator);

    const result = cmdHelp(&config, "nonexistent", true, buf.writer(allocator), err_buf.writer(allocator));
    try std.testing.expectError(error.TaskNotFound, result);

    const err_output = err_buf.items;
    try std.testing.expect(std.mem.indexOf(u8, err_output, "Task 'nonexistent' not found") != null);
}

test "cmdMan returns error for non-existent task" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var err_buf = std.ArrayList(u8){};
    defer err_buf.deinit(allocator);

    const result = cmdMan(allocator, &config, "nonexistent", buf.writer(allocator), err_buf.writer(allocator));
    try std.testing.expectError(error.TaskNotFound, result);

    const err_output = err_buf.items;
    try std.testing.expect(std.mem.indexOf(u8, err_output, "Task 'nonexistent' not found") != null);
}
