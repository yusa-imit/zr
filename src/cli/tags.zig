const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const types = @import("../config/types.zig");

const SortMode = enum { name, count };

const TagEntry = struct {
    tag: []const u8,
    count: usize,
};

fn sortByName(_: void, a: TagEntry, b: TagEntry) bool {
    return std.mem.lessThan(u8, a.tag, b.tag);
}

fn sortByCount(_: void, a: TagEntry, b: TagEntry) bool {
    if (a.count != b.count) return a.count > b.count;
    return std.mem.lessThan(u8, a.tag, b.tag);
}

fn sortStrings(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

pub fn cmdTags(
    allocator: Allocator,
    args: []const []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var json_output = false;
    var sort_mode = SortMode.name;
    var filter_tag: ?[]const u8 = null;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try w.print("Usage: zr tags [<tag>] [options]\n\n", .{});
            try w.print("List all tags used in the project, or show tasks for a specific tag.\n\n", .{});
            try w.print("Options:\n", .{});
            try w.print("  --json              Output in JSON format\n", .{});
            try w.print("  --sort=name         Sort tags alphabetically (default)\n", .{});
            try w.print("  --sort=count        Sort tags by task count (descending)\n", .{});
            try w.print("  --help              Show this help message\n\n", .{});
            try w.print("Examples:\n", .{});
            try w.print("  zr tags                # List all tags\n", .{});
            try w.print("  zr tags ci             # Show tasks tagged 'ci'\n", .{});
            try w.print("  zr tags --sort=count   # Sort by number of tasks\n", .{});
            try w.print("  zr tags --json         # JSON output\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--sort=count")) {
            sort_mode = .count;
        } else if (std.mem.eql(u8, arg, "--sort=name")) {
            sort_mode = .name;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            filter_tag = arg;
        }
    }

    var config = (try common.loadConfig(allocator, config_path, null, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    // Build tag -> task names mapping (tag keys are slices into config memory, valid for config lifetime)
    var tag_map = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = tag_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        tag_map.deinit();
    }

    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task = entry.value_ptr;
        for (task.tags) |tag| {
            const gop = try tag_map.getOrPut(tag);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList([]const u8){};
            }
            try gop.value_ptr.append(allocator, entry.key_ptr.*);
        }
    }

    if (filter_tag) |tag| {
        const tasks_list = tag_map.get(tag) orelse {
            try color.printError(err_writer, use_color,
                "✗ [tags]: No tasks found with tag '{s}'\n\n  Hint: Use 'zr tags' to see all available tags\n",
                .{tag});
            return 1;
        };

        const sorted_tasks = try allocator.dupe([]const u8, tasks_list.items);
        defer allocator.free(sorted_tasks);
        std.mem.sort([]const u8, sorted_tasks, {}, sortStrings);

        if (json_output) {
            try w.print("[", .{});
            for (sorted_tasks, 0..) |task_name, i| {
                if (i > 0) try w.print(",", .{});
                const task = config.tasks.get(task_name).?;
                try w.print("{{\"name\":", .{});
                try common.writeJsonString(w, task_name);
                if (task.description) |desc| {
                    try w.print(",\"description\":", .{});
                    try common.writeJsonString(w, desc.getShort());
                }
                try w.print("}}", .{});
            }
            try w.print("]\n", .{});
        } else {
            try color.printBold(w, use_color, "Tasks tagged '{s}':\n", .{tag});

            var max_len: usize = 0;
            for (sorted_tasks) |name| {
                if (name.len > max_len) max_len = name.len;
            }

            for (sorted_tasks) |task_name| {
                const task = config.tasks.get(task_name).?;
                const pad = max_len - task_name.len + 2;
                try w.print("  {s}", .{task_name});
                for (0..pad) |_| try w.writeByte(' ');
                if (task.description) |desc| {
                    try color.printDim(w, use_color, "{s}", .{desc.getShort()});
                } else {
                    try color.printDim(w, use_color, "{s}", .{task.cmd});
                }
                try w.print("\n", .{});
            }
        }
        return 0;
    }

    // List all tags
    if (tag_map.count() == 0) {
        if (json_output) {
            try w.print("[]\n", .{});
        }
        return 0;
    }

    var tag_list = std.ArrayList(TagEntry){};
    defer tag_list.deinit(allocator);

    var it = tag_map.iterator();
    while (it.next()) |entry| {
        try tag_list.append(allocator, .{
            .tag = entry.key_ptr.*,
            .count = entry.value_ptr.items.len,
        });
    }

    switch (sort_mode) {
        .name => std.mem.sort(TagEntry, tag_list.items, {}, sortByName),
        .count => std.mem.sort(TagEntry, tag_list.items, {}, sortByCount),
    }

    if (json_output) {
        try w.print("[", .{});
        for (tag_list.items, 0..) |entry, i| {
            if (i > 0) try w.print(",", .{});
            const tasks_list = tag_map.get(entry.tag).?;

            const sorted_tasks = try allocator.dupe([]const u8, tasks_list.items);
            defer allocator.free(sorted_tasks);
            std.mem.sort([]const u8, sorted_tasks, {}, sortStrings);

            try w.print("{{\"tag\":", .{});
            try common.writeJsonString(w, entry.tag);
            try w.print(",\"count\":{d},\"tasks\":[", .{entry.count});
            for (sorted_tasks, 0..) |task_name, j| {
                if (j > 0) try w.print(",", .{});
                try common.writeJsonString(w, task_name);
            }
            try w.print("]}}", .{});
        }
        try w.print("]\n", .{});
    } else {
        var max_len: usize = 0;
        for (tag_list.items) |entry| {
            if (entry.tag.len > max_len) max_len = entry.tag.len;
        }

        for (tag_list.items) |entry| {
            const pad = max_len - entry.tag.len + 2;
            try color.printBold(w, use_color, "  {s}", .{entry.tag});
            for (0..pad) |_| try w.writeByte(' ');
            if (entry.count == 1) {
                try color.printDim(w, use_color, "1 task\n", .{});
            } else {
                try color.printDim(w, use_color, "{d} tasks\n", .{entry.count});
            }
        }
    }

    return 0;
}
