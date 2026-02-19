const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const cycle_detect = @import("../graph/cycle_detect.zig");
const topo_sort = @import("../graph/topo_sort.zig");
const cache_store = @import("../cache/store.zig");

pub fn cmdList(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, null, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    // Collect task names for sorted output
    var names = std.ArrayList([]const u8){};
    defer names.deinit(allocator);

    var it = config.tasks.keyIterator();
    while (it.next()) |key| {
        try names.append(allocator, key.*);
    }

    // Sort for deterministic output
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    if (json_output) {
        // Collect workflow names too
        var wf_names = std.ArrayList([]const u8){};
        defer wf_names.deinit(allocator);
        var wit2 = config.workflows.keyIterator();
        while (wit2.next()) |key| {
            try wf_names.append(allocator, key.*);
        }
        std.mem.sort([]const u8, wf_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        try w.writeAll("{\"tasks\":[");
        for (names.items, 0..) |name, i| {
            const task = config.tasks.get(name).?;
            if (i > 0) try w.writeAll(",");
            try w.print("{{\"name\":", .{});
            try common.writeJsonString(w, name);
            try w.print(",\"cmd\":", .{});
            try common.writeJsonString(w, task.cmd);
            if (task.description) |desc| {
                try w.print(",\"description\":", .{});
                try common.writeJsonString(w, desc);
            } else {
                try w.writeAll(",\"description\":null");
            }
            try w.print(",\"deps_count\":{d}}}", .{task.deps.len});
        }
        try w.writeAll("],\"workflows\":[");
        for (wf_names.items, 0..) |name, i| {
            const wf = config.workflows.get(name).?;
            if (i > 0) try w.writeAll(",");
            try w.print("{{\"name\":", .{});
            try common.writeJsonString(w, name);
            if (wf.description) |desc| {
                try w.print(",\"description\":", .{});
                try common.writeJsonString(w, desc);
            } else {
                try w.writeAll(",\"description\":null");
            }
            try w.print(",\"stages\":{d}}}", .{wf.stages.len});
        }
        try w.writeAll("]}\n");
        return 0;
    }

    try color.printHeader(w, use_color, "Tasks:", .{});

    for (names.items) |name| {
        const task = config.tasks.get(name).?;
        try w.print("  ", .{});
        try color.printInfo(w, use_color, "{s:<20}", .{name});
        if (task.description) |desc| {
            try color.printDim(w, use_color, " {s}", .{desc});
        }
        try w.print("\n", .{});
    }

    if (config.workflows.count() > 0) {
        try w.print("\n", .{});
        try color.printHeader(w, use_color, "Workflows:", .{});

        var wf_names = std.ArrayList([]const u8){};
        defer wf_names.deinit(allocator);

        var wit = config.workflows.keyIterator();
        while (wit.next()) |key| {
            try wf_names.append(allocator, key.*);
        }
        std.mem.sort([]const u8, wf_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (wf_names.items) |name| {
            const wf = config.workflows.get(name).?;
            try w.print("  ", .{});
            try color.printInfo(w, use_color, "{s:<20}", .{name});
            if (wf.description) |desc| {
                try color.printDim(w, use_color, " {s}", .{desc});
            }
            try color.printDim(w, use_color, " ({d} stages)", .{wf.stages.len});
            try w.print("\n", .{});
        }
    }

    return 0;
}

pub fn cmdGraph(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, null, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    var dag = try common.buildDag(allocator, &config);
    defer dag.deinit();

    // Check for cycles first
    var cycle_result = try cycle_detect.detectCycle(allocator, &dag);
    defer cycle_result.deinit(allocator);

    if (cycle_result.has_cycle) {
        try color.printError(err_writer, use_color,
            "graph: Cycle detected in dependency graph\n\n  Hint: Check your deps fields for circular references\n",
            .{},
        );
        return 1;
    }

    // Get execution levels for structured output
    var levels = try topo_sort.getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    if (json_output) {
        // {"levels":[{"index":0,"tasks":[{"name":"t","deps":["a","b"]}]}]}
        try w.writeAll("{\"levels\":[");
        for (levels.levels.items, 0..) |level, level_idx| {
            if (level_idx > 0) try w.writeAll(",");
            try w.print("{{\"index\":{d},\"tasks\":[", .{level_idx});

            // Sort for deterministic output
            var sorted_level = std.ArrayList([]const u8){};
            defer sorted_level.deinit(allocator);
            for (level.items) |name| {
                try sorted_level.append(allocator, name);
            }
            std.mem.sort([]const u8, sorted_level.items, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.lessThan(u8, a, b);
                }
            }.lessThan);

            for (sorted_level.items, 0..) |name, ti| {
                const task = config.tasks.get(name) orelse continue;
                if (ti > 0) try w.writeAll(",");
                try w.print("{{\"name\":", .{});
                try common.writeJsonString(w, name);
                try w.writeAll(",\"deps\":[");
                for (task.deps, 0..) |dep, di| {
                    if (di > 0) try w.writeAll(",");
                    try common.writeJsonString(w, dep);
                }
                try w.writeAll("]}");
            }
            try w.writeAll("]}");
        }
        try w.writeAll("]}\n");
        return 0;
    }

    try color.printHeader(w, use_color, "Dependency Graph:", .{});
    try w.print("\n", .{});

    for (levels.levels.items, 0..) |level, level_idx| {
        try color.printDim(w, use_color, "  Level {d}:\n", .{level_idx});

        // Sort names within level for deterministic output
        var sorted_level = std.ArrayList([]const u8){};
        defer sorted_level.deinit(allocator);

        for (level.items) |name| {
            try sorted_level.append(allocator, name);
        }
        std.mem.sort([]const u8, sorted_level.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (sorted_level.items) |name| {
            const task = config.tasks.get(name) orelse continue;
            try w.print("    ", .{});
            try color.printInfo(w, use_color, "{s}", .{name});
            if (task.deps.len > 0) {
                try color.printDim(w, use_color, " -> [", .{});
                for (task.deps, 0..) |dep, i| {
                    if (i > 0) try color.printDim(w, use_color, ", ", .{});
                    try color.printDim(w, use_color, "{s}", .{dep});
                }
                try color.printDim(w, use_color, "]", .{});
            }
            try w.print("\n", .{});
        }
    }

    return 0;
}

pub fn cmdCache(
    allocator: std.mem.Allocator,
    sub: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (std.mem.eql(u8, sub, "clear")) {
        var store = cache_store.CacheStore.init(allocator) catch |err| {
            try color.printError(ew, use_color,
                "cache: failed to open cache directory: {}\n\n  Hint: Check permissions on ~/.zr/cache/\n",
                .{err});
            return 1;
        };
        defer store.deinit();

        const removed = store.clearAll() catch |err| {
            try color.printError(ew, use_color,
                "cache: error while clearing cache: {}\n", .{err});
            return 1;
        };
        try color.printSuccess(w, use_color, "Cleared {d} cached task result(s)\n", .{removed});
        return 0;
    } else if (sub.len == 0) {
        try color.printError(ew, use_color,
            "cache: missing subcommand\n\n  Hint: zr cache clear\n", .{});
        return 1;
    } else {
        try color.printError(ew, use_color,
            "cache: unknown subcommand '{s}'\n\n  Hint: zr cache clear\n", .{sub});
        return 1;
    }
}
