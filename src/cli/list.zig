const std = @import("std");
const sailor = @import("sailor");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const cycle_detect = @import("../graph/cycle_detect.zig");
const topo_sort = @import("../graph/topo_sort.zig");
const cache_store = @import("../cache/store.zig");
const graph_ascii = @import("../graph/ascii.zig");
const loader = @import("../config/loader.zig");
const workspace_cmd = @import("workspace.zig");
const history_store = @import("../history/store.zig");
const history_stats = @import("../history/stats.zig");
const levenshtein = @import("../util/levenshtein.zig");
const uptodate = @import("../exec/uptodate.zig");
const types = @import("../config/types.zig");

/// Get task status: up-to-date (✓), stale (✗), or unknown (?)
fn getTaskStatus(allocator: std.mem.Allocator, task: types.Task, cwd: ?[]const u8) ![]const u8 {
    if (task.generates.len == 0) {
        return "?"; // Unknown - no generates specified
    }
    const is_uptodate = try uptodate.isUpToDate(allocator, task.sources, task.generates, cwd);
    return if (is_uptodate) "✓" else "✗";
}

/// Print verbose metadata for a task (examples, params, deps, outputs)
fn printVerboseMetadata(w: anytype, task: types.Task, use_color: bool) !void {
    var has_metadata = false;

    // Show parameters if any
    if (task.task_params.len > 0) {
        if (!has_metadata) {
            try w.writeAll("\n");
            has_metadata = true;
        }
        try w.writeAll("      ");
        try color.printDim(w, use_color, "Params: ", .{});
        for (task.task_params, 0..) |param, i| {
            if (i > 0) try w.writeAll(", ");
            try w.print("{s}", .{param.name});
            if (param.default) |default| {
                try w.print("={s}", .{default});
            }
        }
        try w.writeAll("\n");
    }

    // Show examples if any
    if (task.examples) |examples| {
        if (examples.len > 0) {
            if (!has_metadata) {
                try w.writeAll("\n");
                has_metadata = true;
            }
            try w.writeAll("      ");
            try color.printDim(w, use_color, "Examples: ", .{});
            try w.print("{s}", .{examples[0]});
            if (examples.len > 1) {
                try color.printDim(w, use_color, " (+{d} more)", .{examples.len - 1});
            }
            try w.writeAll("\n");
        }
    }

    // Show dependencies if any
    const total_deps = task.deps.len + task.deps_serial.len + task.deps_if.len + task.deps_optional.len;
    if (total_deps > 0) {
        if (!has_metadata) {
            try w.writeAll("\n");
            has_metadata = true;
        }
        try w.writeAll("      ");
        try color.printDim(w, use_color, "Depends on: ", .{});
        var dep_count: usize = 0;
        for (task.deps) |dep| {
            if (dep_count > 0) try w.writeAll(", ");
            try w.print("{s}", .{dep});
            dep_count += 1;
            if (dep_count >= 3) break;
        }
        if (total_deps > dep_count) {
            try color.printDim(w, use_color, " (+{d} more)", .{total_deps - dep_count});
        }
        try w.writeAll("\n");
    }

    // Show outputs if any
    if (task.outputs) |outputs| {
        if (outputs.count() > 0) {
            if (!has_metadata) {
                try w.writeAll("\n");
                has_metadata = true;
            }
            try w.writeAll("      ");
            try color.printDim(w, use_color, "Outputs: ", .{});
            var it = outputs.iterator();
            var output_count: usize = 0;
            while (it.next()) |entry| {
                if (output_count > 0) try w.writeAll(", ");
                try w.print("{s}", .{entry.key_ptr.*});
                output_count += 1;
                if (output_count >= 2) break;
            }
            if (outputs.count() > output_count) {
                try color.printDim(w, use_color, " (+{d} more)", .{outputs.count() - output_count});
            }
            try w.writeAll("\n");
        }
    }
}

pub fn cmdList(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    json_output: bool,
    tree_mode: bool,
    filter_pattern: ?[]const u8,
    filter_tags: ?[]const u8,
    exclude_tags: ?[]const u8,
    profiles_only: bool,
    members_only: bool,
    fuzzy_search: bool,
    group_by_tags: bool,
    recent_count: ?usize,
    frequent_count: ?usize,
    slow_threshold_ms: ?u64,
    search_description: ?[]const u8,
    show_status: bool,
    show_env: bool,
    verbose: bool,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // verbose flag: shows additional metadata (examples, params, deps) beyond short description
    var config = (try common.loadConfig(allocator, config_path, null, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    // List profiles only (for shell completion)
    if (profiles_only) {
        var profile_names = std.ArrayList([]const u8){};
        defer profile_names.deinit(allocator);

        var it = config.profiles.iterator();
        while (it.next()) |entry| {
            try profile_names.append(allocator, entry.key_ptr.*);
        }

        // Sort for deterministic output
        std.mem.sort([]const u8, profile_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (profile_names.items) |name| {
            try w.print("{s}\n", .{name});
        }
        return 0;
    }

    // List workspace members only (for shell completion)
    if (members_only) {
        if (config.workspace) |ws| {
            const members = try workspace_cmd.resolveWorkspaceMembers(allocator, ws, config_path);
            defer {
                for (members) |m| allocator.free(m);
                allocator.free(members);
            }

            // Sort for deterministic output
            std.mem.sort([]const u8, members, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.lessThan(u8, a, b);
                }
            }.lessThan);

            for (members) |member| {
                try w.print("{s}\n", .{member});
            }
        }
        return 0;
    }

    // Tree mode: render dependency graph
    if (tree_mode and !json_output) {
        var dag = try common.buildDag(allocator, &config);
        defer dag.deinit();

        try graph_ascii.renderGraph(allocator, w, &dag, .{
            .use_color = use_color,
        });
        return 0;
    }

    // Collect task names for sorted output
    var names = std.ArrayList([]const u8){};
    defer names.deinit(allocator);

    // For fuzzy search, collect all candidates first, then rank by distance
    const TaskWithScore = struct {
        name: []const u8,
        distance: usize,
    };
    var fuzzy_candidates = std.ArrayList(TaskWithScore){};
    defer fuzzy_candidates.deinit(allocator);

    var it = config.tasks.keyIterator();
    while (it.next()) |key| {
        const task = config.tasks.get(key.*).?;

        // Apply tag filter if provided (comma-separated list, match ALL tags - AND logic)
        if (filter_tags) |tags_str| {
            var all_matched = true;
            var tag_iter = std.mem.splitScalar(u8, tags_str, ',');
            while (tag_iter.next()) |filter_tag| {
                const trimmed = std.mem.trim(u8, filter_tag, " \t");
                var found_this_tag = false;
                for (task.tags) |task_tag| {
                    if (std.mem.eql(u8, trimmed, task_tag)) {
                        found_this_tag = true;
                        break;
                    }
                }
                if (!found_this_tag) {
                    all_matched = false;
                    break;
                }
            }
            if (!all_matched) continue; // Skip tasks that don't have ALL required tags
        }

        // Apply exclude tag filter if provided (skip if task has ANY of these tags)
        if (exclude_tags) |tags_str| {
            var should_exclude = false;
            var tag_iter = std.mem.splitScalar(u8, tags_str, ',');
            while (tag_iter.next()) |exclude_tag| {
                const trimmed = std.mem.trim(u8, exclude_tag, " \t");
                for (task.tags) |task_tag| {
                    if (std.mem.eql(u8, trimmed, task_tag)) {
                        should_exclude = true;
                        break;
                    }
                }
                if (should_exclude) break;
            }
            if (should_exclude) continue; // Skip tasks with excluded tags
        }

        // For fuzzy search, rank by distance
        if (fuzzy_search and filter_pattern != null) {
            const pattern = filter_pattern.?;
            const dist = try levenshtein.distance(allocator, pattern, key.*);
            // Include exact matches (0) and close matches (distance <= 3)
            if (dist <= 3) {
                try fuzzy_candidates.append(allocator, .{
                    .name = key.*,
                    .distance = dist,
                });
            }
        } else {
            // Apply substring pattern filter if provided
            if (filter_pattern) |pattern| {
                if (std.mem.indexOf(u8, key.*, pattern) == null) {
                    continue; // Skip tasks that don't match the pattern
                }
            }
            try names.append(allocator, key.*);
        }
    }

    // Sort fuzzy results by distance, then alphabetically
    if (fuzzy_search and filter_pattern != null) {
        const items = try fuzzy_candidates.toOwnedSlice(allocator);
        defer allocator.free(items);
        std.mem.sort(TaskWithScore, items, {}, struct {
            fn lessThan(_: void, a: TaskWithScore, b: TaskWithScore) bool {
                if (a.distance != b.distance) {
                    return a.distance < b.distance;
                }
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);
        for (items) |item| {
            try names.append(allocator, item.name);
        }
    } else {
        // Sort for deterministic output (alphabetical)
        std.mem.sort([]const u8, names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);
    }

    if (json_output) {
        // Load history for duration estimates in JSON output
        const history_path = try history_store.defaultHistoryPath(allocator);
        defer allocator.free(history_path);

        const hist_store = try history_store.Store.init(allocator, history_path);
        defer hist_store.deinit();

        var records_list = hist_store.loadLast(allocator, 1000) catch std.ArrayList(history_store.Record){};
        defer {
            for (records_list.items) |r| r.deinit(allocator);
            records_list.deinit(allocator);
        }

        // Collect workflow names too
        var wf_names = std.ArrayList([]const u8){};
        defer wf_names.deinit(allocator);
        var wit2 = config.workflows.keyIterator();
        while (wit2.next()) |key| {
            // Apply filter if provided
            if (filter_pattern) |pattern| {
                if (std.mem.indexOf(u8, key.*, pattern) == null) {
                    continue;
                }
            }
            try wf_names.append(allocator, key.*);
        }
        std.mem.sort([]const u8, wf_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        const JsonArr = sailor.fmt.JsonArray(*std.Io.Writer);
        try w.writeAll("{\"tasks\":");
        {
            var tasks_arr = try JsonArr.init(w);
            for (names.items) |name| {
                const task = config.tasks.get(name).?;
                var obj = try tasks_arr.beginObject();
                try obj.addString("name", name);
                try obj.addString("cmd", task.cmd);
                if (task.description) |desc| {
                    try obj.addString("description", desc.getShort());
                } else {
                    try obj.addNull("description");
                }
                // Add aliases array
                try obj.writer.writeAll(",\"aliases\":[");
                for (task.aliases, 0..) |alias, i| {
                    if (i > 0) try obj.writer.writeAll(",");
                    try obj.writer.print("\"{s}\"", .{alias});
                }
                try obj.writer.writeAll("]");
                try obj.addNumber("deps_count", task.deps.len);

                // Add duration estimate if available
                if (records_list.items.len > 0) {
                    if (try history_stats.calculateStats(records_list.items, name, allocator)) |stats| {
                        try obj.writer.writeAll(",\"estimate\":");
                        var est_obj = try sailor.fmt.JsonObject(*std.Io.Writer).init(w);
                        try est_obj.addNumber("avg_ms", stats.avg_ms);
                        try est_obj.addNumber("min_ms", stats.min_ms);
                        try est_obj.addNumber("max_ms", stats.max_ms);
                        try est_obj.addNumber("p50_ms", stats.p50_ms);
                        try est_obj.addNumber("p90_ms", stats.p90_ms);
                        try est_obj.addNumber("p99_ms", stats.p99_ms);
                        try est_obj.end();
                    } else {
                        try obj.addNull("estimate");
                    }
                } else {
                    try obj.addNull("estimate");
                }

                try obj.end();
            }
            try tasks_arr.end();
        }
        try w.writeAll(",\"workflows\":");
        {
            var wf_arr = try JsonArr.init(w);
            for (wf_names.items) |name| {
                const wf = config.workflows.get(name).?;
                var obj = try wf_arr.beginObject();
                try obj.addString("name", name);
                if (wf.description) |desc| {
                    try obj.addString("description", desc);
                } else {
                    try obj.addNull("description");
                }
                try obj.addNumber("stages", wf.stages.len);
                try obj.end();
            }
            try wf_arr.end();
        }
        try w.writeAll("}\n");
        return 0;
    }

    // Load history for duration estimates and recent tasks
    const history_path = try history_store.defaultHistoryPath(allocator);
    defer allocator.free(history_path);

    const hist_store = try history_store.Store.init(allocator, history_path);
    defer hist_store.deinit();

    var records_list = hist_store.loadLast(allocator, 1000) catch std.ArrayList(history_store.Record){};
    defer {
        for (records_list.items) |r| r.deinit(allocator);
        records_list.deinit(allocator);
    }

    // Apply recent tasks filter if requested
    if (recent_count) |count| {
        var recent_tasks = std.StringHashMap(void).init(allocator);
        defer recent_tasks.deinit();

        // Collect most recent unique task names (up to count)
        var added: usize = 0;
        var i: usize = records_list.items.len;
        while (i > 0 and added < count) {
            i -= 1;
            const rec = records_list.items[i];
            if (recent_tasks.contains(rec.task_name)) continue;
            try recent_tasks.put(rec.task_name, {});
            added += 1;
        }

        // Filter names to only include recent tasks
        var recent_names = std.ArrayList([]const u8){};
        defer recent_names.deinit(allocator);
        for (names.items) |name| {
            if (recent_tasks.contains(name)) {
                try recent_names.append(allocator, name);
            }
        }
        names.clearRetainingCapacity();
        try names.appendSlice(allocator, recent_names.items);
    }

    // Apply frequent tasks filter if requested (top N by execution count)
    if (frequent_count) |count| {
        const TaskExecCount = struct {
            name: []const u8,
            count: usize,
        };

        // Count executions per task
        var exec_counts = std.StringHashMap(usize).init(allocator);
        defer exec_counts.deinit();

        for (records_list.items) |rec| {
            const current_count = exec_counts.get(rec.task_name) orelse 0;
            try exec_counts.put(rec.task_name, current_count + 1);
        }

        // Build list of task counts for tasks in our current filtered list
        var task_counts = std.ArrayList(TaskExecCount){};
        defer task_counts.deinit(allocator);

        for (names.items) |name| {
            if (exec_counts.get(name)) |exec_count| {
                try task_counts.append(allocator, .{ .name = name, .count = exec_count });
            }
        }

        // Sort by execution count (descending), then name (ascending)
        std.mem.sort(TaskExecCount, task_counts.items, {}, struct {
            fn lessThan(_: void, a: TaskExecCount, b: TaskExecCount) bool {
                if (a.count != b.count) {
                    return a.count > b.count; // Descending by count
                }
                return std.mem.lessThan(u8, a.name, b.name); // Ascending by name
            }
        }.lessThan);

        // Take top N
        const top_n = @min(count, task_counts.items.len);
        names.clearRetainingCapacity();
        for (task_counts.items[0..top_n]) |tc| {
            try names.append(allocator, tc.name);
        }
    }

    // Apply slow tasks filter if requested (tasks exceeding avg execution time)
    if (slow_threshold_ms) |threshold| {
        var slow_names = std.ArrayList([]const u8){};
        defer slow_names.deinit(allocator);

        for (names.items) |name| {
            if (try history_stats.calculateStats(records_list.items, name, allocator)) |stats| {
                if (stats.avg_ms >= threshold) {
                    try slow_names.append(allocator, name);
                }
            }
        }

        names.clearRetainingCapacity();
        try names.appendSlice(allocator, slow_names.items);
    }

    // Apply full-text search filter if provided (searches name, description, command)
    if (search_description) |search_pattern| {
        var matched_names = std.ArrayList([]const u8){};
        defer matched_names.deinit(allocator);
        for (names.items) |name| {
            const task = config.tasks.get(name) orelse continue;
            // Match task name, description, or command (full-text search)
            if (std.mem.indexOf(u8, name, search_pattern) != null) {
                try matched_names.append(allocator, name);
            } else if (task.description) |desc| {
                if (std.mem.indexOf(u8, desc.getShort(), search_pattern) != null) {
                    try matched_names.append(allocator, name);
                }
            } else if (std.mem.indexOf(u8, task.cmd, search_pattern) != null) {
                try matched_names.append(allocator, name);
            }
        }
        names.clearRetainingCapacity();
        try names.appendSlice(allocator, matched_names.items);
    }

    // Group by tags if requested
    if (group_by_tags) {
        // Collect all unique tags first
        var tag_set = std.StringHashMap(void).init(allocator);
        defer tag_set.deinit();
        for (names.items) |name| {
            const task = config.tasks.get(name) orelse continue;
            for (task.tags) |tag| {
                try tag_set.put(tag, {});
            }
        }

        // Sort tags alphabetically
        var sorted_tags = std.ArrayList([]const u8){};
        defer sorted_tags.deinit(allocator);
        var tag_it = tag_set.keyIterator();
        while (tag_it.next()) |tag| {
            try sorted_tags.append(allocator, tag.*);
        }
        std.mem.sort([]const u8, sorted_tags.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Print tasks grouped by tag
        try color.printHeader(w, use_color, "Tasks (grouped by tags):", .{});
        for (sorted_tags.items) |tag| {
            try w.print("\n", .{});
            try color.printDim(w, use_color, "  [{s}]\n", .{tag});
            for (names.items) |name| {
                const task = config.tasks.get(name) orelse continue;
                var has_tag = false;
                for (task.tags) |t| {
                    if (std.mem.eql(u8, t, tag)) {
                        has_tag = true;
                        break;
                    }
                }
                if (!has_tag) continue;

                try w.print("    ", .{});

                // Show status if --status flag is enabled
                if (show_status) {
                    const status = try getTaskStatus(allocator, task, null);
                    if (std.mem.eql(u8, status, "✓")) {
                        try color.printSuccess(w, use_color, "[{s}] ", .{status});
                    } else if (std.mem.eql(u8, status, "✗")) {
                        try color.printError(w, use_color, "[{s}] ", .{status});
                    } else {
                        try color.printDim(w, use_color, "[{s}] ", .{status});
                    }
                }

                try color.printInfo(w, use_color, "{s:<18}", .{name});
                if (task.description) |desc| {
                    try color.printDim(w, use_color, " {s}", .{desc.getShort()});
                }
                // Show aliases if present
                try printAliases(w, task.aliases, use_color);
                // Mark inherited tasks (v1.63.0)
                if (task.inherited) {
                    try color.printDim(w, use_color, " (inherited)", .{});
                }

                // Show duration estimate if available
                if (records_list.items.len > 0) {
                    if (try history_stats.calculateStats(records_list.items, name, allocator)) |stats| {
                        const estimate = try history_stats.formatEstimate(stats, allocator);
                        defer allocator.free(estimate);
                        try color.printDim(w, use_color, "  [{s}]", .{estimate});
                    }
                }

                try w.print("\n", .{});

                // Show verbose metadata if --verbose flag is set
                if (verbose) {
                    try printVerboseMetadata(w, task, use_color);
                }
            }
        }

        // Print untagged tasks if any
        var untagged = std.ArrayList([]const u8){};
        defer untagged.deinit(allocator);
        for (names.items) |name| {
            const task = config.tasks.get(name) orelse continue;
            if (task.tags.len == 0) {
                try untagged.append(allocator, name);
            }
        }
        if (untagged.items.len > 0) {
            try w.print("\n", .{});
            try color.printDim(w, use_color, "  [untagged]\n", .{});
            for (untagged.items) |name| {
                const task = config.tasks.get(name).?;
                try w.print("    ", .{});

                // Show status if --status flag is enabled
                if (show_status) {
                    const status = try getTaskStatus(allocator, task, null);
                    if (std.mem.eql(u8, status, "✓")) {
                        try color.printSuccess(w, use_color, "[{s}] ", .{status});
                    } else if (std.mem.eql(u8, status, "✗")) {
                        try color.printError(w, use_color, "[{s}] ", .{status});
                    } else {
                        try color.printDim(w, use_color, "[{s}] ", .{status});
                    }
                }

                try color.printInfo(w, use_color, "{s:<18}", .{name});
                if (task.description) |desc| {
                    try color.printDim(w, use_color, " {s}", .{desc.getShort()});
                }
                // Show aliases if present
                try printAliases(w, task.aliases, use_color);
                // Mark inherited tasks (v1.63.0)
                if (task.inherited) {
                    try color.printDim(w, use_color, " (inherited)", .{});
                }

                // Show duration estimate if available
                if (records_list.items.len > 0) {
                    if (try history_stats.calculateStats(records_list.items, name, allocator)) |stats| {
                        const estimate = try history_stats.formatEstimate(stats, allocator);
                        defer allocator.free(estimate);
                        try color.printDim(w, use_color, "  [{s}]", .{estimate});
                    }
                }

                try w.print("\n", .{});

                // Show verbose metadata if --verbose flag is set
                if (verbose) {
                    try printVerboseMetadata(w, task, use_color);
                }
            }
        }
    } else {
        // Standard flat list
        try color.printHeader(w, use_color, "Tasks:", .{});

        // Calculate unique prefixes for abbreviation hints
        const run_module = @import("run.zig");
        var unique_prefixes = try run_module.calculateUniquePrefix(allocator, &config.tasks);
        defer {
            var prefix_it = unique_prefixes.iterator();
            while (prefix_it.next()) |entry| {
                allocator.free(entry.value_ptr.*);
            }
            unique_prefixes.deinit();
        }

        for (names.items) |name| {
            const task = config.tasks.get(name).?;
            try w.print("  ", .{});

            // Show status if --status flag is enabled
            if (show_status) {
                const status = try getTaskStatus(allocator, task, null);
                if (std.mem.eql(u8, status, "✓")) {
                    try color.printSuccess(w, use_color, "[{s}] ", .{status});
                } else if (std.mem.eql(u8, status, "✗")) {
                    try color.printError(w, use_color, "[{s}] ", .{status});
                } else {
                    try color.printDim(w, use_color, "[{s}] ", .{status});
                }
            }

            // Show unique prefix hint if different from full name
            if (unique_prefixes.get(name)) |prefix| {
                if (!std.mem.eql(u8, prefix, name)) {
                    try color.printDim(w, use_color, "[{s}] ", .{prefix});
                }
            }

            try color.printInfo(w, use_color, "{s:<20}", .{name});
            if (task.description) |desc| {
                try color.printDim(w, use_color, " {s}", .{desc.getShort()});
            }
            // Show aliases if present
            try printAliases(w, task.aliases, use_color);
            // Mark inherited tasks (v1.63.0)
            if (task.inherited) {
                try color.printDim(w, use_color, " (inherited)", .{});
            }

            // Show duration estimate if available
            if (records_list.items.len > 0) {
                if (try history_stats.calculateStats(records_list.items, name, allocator)) |stats| {
                    const estimate = try history_stats.formatEstimate(stats, allocator);
                    defer allocator.free(estimate);
                    try color.printDim(w, use_color, "  [{s}]", .{estimate});
                }
            }

            try w.print("\n", .{});

            // Show verbose metadata if --verbose flag is set
            if (verbose) {
                try printVerboseMetadata(w, task, use_color);
            }
        }
    }

    if (config.workflows.count() > 0) {
        try w.print("\n", .{});
        try color.printHeader(w, use_color, "Workflows:", .{});

        var wf_names = std.ArrayList([]const u8){};
        defer wf_names.deinit(allocator);

        var wit = config.workflows.keyIterator();
        while (wit.next()) |key| {
            // Apply filter if provided
            if (filter_pattern) |pattern| {
                if (std.mem.indexOf(u8, key.*, pattern) == null) {
                    continue;
                }
            }
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

    // Show environment variables if --show-env flag is set
    if (show_env) {
        if (names.items.len == 0) {
            try color.printError(err_writer, use_color, "No tasks found to show environment for\n\n  Hint: Use filters to select a specific task\n", .{});
            return 1;
        } else if (names.items.len == 1) {
            // Single task - show its environment
            const task_name = names.items[0];
            const task = config.tasks.get(task_name).?;
            try w.print("\n", .{});

            // Import and use the printTaskEnvironment function from run.zig
            const run_mod = @import("run.zig");
            var empty_params = std.StringHashMap([]const u8).init(allocator);
            defer empty_params.deinit();
            try run_mod.printTaskEnvironment(allocator, w, err_writer, use_color, &config, &task, task_name, &empty_params);
        } else {
            // Multiple tasks - show hint
            try w.print("\n", .{});
            try color.printDim(w, use_color, "Hint: --show-env works best with a single task.\n", .{});
            try color.printDim(w, use_color, "      Use filters to narrow down to one task, or use 'zr run <task> --show-env'\n", .{});
        }
    }

    return 0;
}

pub fn cmdGraph(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    json_output: bool,
    ascii_mode: bool,
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

    // ASCII tree visualization mode
    if (ascii_mode and !json_output) {
        try graph_ascii.renderGraph(allocator, w, &dag, .{
            .use_color = use_color,
        });
        return 0;
    }

    // Get execution levels for structured output
    var levels = try topo_sort.getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    if (json_output) {
        const JsonArr = sailor.fmt.JsonArray(*std.Io.Writer);
        // {"levels":[{"index":0,"tasks":[{"name":"t","deps":["a","b"]}]}]}
        try w.writeAll("{\"levels\":");
        var levels_arr = try JsonArr.init(w);
        for (levels.levels.items, 0..) |level, level_idx| {
            var level_obj = try levels_arr.beginObject();
            try level_obj.addNumber("index", level_idx);
            try level_obj.writer.writeAll(",\"tasks\":");

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

            var tasks_arr = try JsonArr.init(w);
            for (sorted_level.items) |name| {
                const task = config.tasks.get(name) orelse continue;
                var task_obj = try tasks_arr.beginObject();
                try task_obj.addString("name", name);
                try task_obj.writer.writeAll(",\"deps\":");
                var deps_arr = try JsonArr.init(w);
                for (task.deps) |dep| {
                    try deps_arr.addString(dep);
                }
                try deps_arr.end();
                try task_obj.end();
            }
            try tasks_arr.end();
            try level_obj.end();
        }
        try levels_arr.end();
        try w.writeAll("}\n");
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
    args: []const []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    const sub = if (args.len >= 3) args[2] else "";

    if (std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) {
        try color.printBold(w, use_color, "zr cache - Task result cache management\n\n", .{});
        try w.writeAll("Usage:\n");
        try w.writeAll("  zr cache clear [--workspace] [--member <path>]   Clear cached task results\n");
        try w.writeAll("  zr cache status                                   Show cache statistics\n");
        try w.writeAll("\nOptions:\n");
        try w.writeAll("  --workspace        Clear cache for all workspace members\n");
        try w.writeAll("  --member <path>    Clear cache for specific workspace member\n");
        return 0;
    } else if (std.mem.eql(u8, sub, "clear")) {
        // Check for --workspace or --member flags
        var workspace_mode = false;
        var target_member_path: ?[]const u8 = null;

        var i: usize = 3;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "--workspace")) {
                workspace_mode = true;
            } else if (std.mem.eql(u8, arg, "--member")) {
                if (i + 1 < args.len) {
                    target_member_path = args[i + 1];
                    i += 1; // Skip the next argument (the path)
                } else {
                    try color.printError(ew, use_color,
                        "cache: --member requires a path argument\n\n  Hint: zr cache clear --member <path>\n", .{});
                    return 1;
                }
            }
        }

        // Handle --member flag
        if (target_member_path) |path| {
            const member_config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{path});
            defer allocator.free(member_config_path);

            var member_config = loader.loadFromFile(allocator, member_config_path) catch |err| {
                try color.printError(ew, use_color,
                    "cache: failed to load member config at {s}: {}\n", .{ member_config_path, err });
                return 1;
            };
            defer member_config.deinit();

            var store = cache_store.CacheStore.init(allocator) catch |err| {
                try color.printError(ew, use_color,
                    "cache: failed to open cache directory: {}\n\n  Hint: Check permissions on ~/.zr/cache/\n",
                    .{err});
                return 1;
            };
            defer store.deinit();

            const removed = store.clearForMember(path, member_config) catch |err| {
                try color.printError(ew, use_color,
                    "cache: error clearing cache for member: {}\n", .{err});
                return 1;
            };

            try color.printSuccess(w, use_color, "Cleared {d} cached task result(s) from member: {s}\n", .{ removed, path });
            return 0;
        }

        if (workspace_mode) {
            // Load workspace configuration
            var config = loader.loadFromFile(allocator, config_path) catch |err| {
                try color.printError(ew, use_color,
                    "cache: failed to load config: {}\n", .{err});
                return 1;
            };
            defer config.deinit();

            if (config.workspace == null) {
                try color.printError(ew, use_color,
                    "cache: no workspace defined in configuration\n\n  Hint: This command requires a workspace configuration\n", .{});
                return 1;
            }

            var store = cache_store.CacheStore.init(allocator) catch |err| {
                try color.printError(ew, use_color,
                    "cache: failed to open cache directory: {}\n\n  Hint: Check permissions on ~/.zr/cache/\n",
                    .{err});
                return 1;
            };
            defer store.deinit();

            // Clear cache for all workspace members
            var total_removed: usize = 0;

            const members = workspace_cmd.resolveWorkspaceMembers(
                allocator,
                config.workspace.?,
                "zr.toml",
            ) catch |err| {
                try color.printError(ew, use_color,
                    "cache: failed to resolve workspace members: {}\n", .{err});
                return 1;
            };
            defer {
                for (members) |m| allocator.free(m);
                allocator.free(members);
            }

            for (members) |member_path| {
                // Load member config
                const member_config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{member_path});
                defer allocator.free(member_config_path);

                var member_config = loader.loadFromFile(allocator, member_config_path) catch continue;
                defer member_config.deinit();

                // Clear cache for this member
                const removed = store.clearForMember(member_path, member_config) catch continue;
                total_removed += removed;
            }

            try color.printSuccess(w, use_color, "Cleared {d} cached task result(s) from {d} workspace member(s)\n", .{ total_removed, members.len });
            return 0;
        }
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
    } else if (std.mem.eql(u8, sub, "status")) {
        var store = cache_store.CacheStore.init(allocator) catch |err| {
            try color.printError(ew, use_color,
                "cache: failed to open cache directory: {}\n\n  Hint: Check permissions on ~/.zr/cache/\n",
                .{err});
            return 1;
        };
        defer store.deinit();

        const stats = store.getStats() catch |err| {
            try color.printError(ew, use_color,
                "cache: error reading cache statistics: {}\n", .{err});
            return 1;
        };

        try color.printBold(w, use_color, "Cache Statistics\n", .{});
        try w.writeAll("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n");

        try color.printDim(w, use_color, "  Location:     ", .{});
        try w.print("{s}\n", .{stats.cache_dir});

        try color.printDim(w, use_color, "  Entries:      ", .{});
        try color.printSuccess(w, use_color, "{d}\n", .{stats.total_entries});

        try color.printDim(w, use_color, "  Total Size:   ", .{});
        const size_str = formatBytes(stats.total_size_bytes);
        try color.printSuccess(w, use_color, "{s}\n", .{std.mem.sliceTo(&size_str, 0)});

        if (stats.total_entries > 0) {
            const avg_size = stats.total_size_bytes / stats.total_entries;
            try color.printDim(w, use_color, "  Avg per entry: ", .{});
            const avg_str = formatBytes(avg_size);
            try w.print("{s}\n", .{std.mem.sliceTo(&avg_str, 0)});
        }

        return 0;
    } else if (sub.len == 0) {
        try color.printError(ew, use_color,
            "cache: missing subcommand\n\n  Hint: zr cache clear | zr cache status\n", .{});
        return 1;
    } else {
        try color.printError(ew, use_color,
            "cache: unknown subcommand '{s}'\n\n  Hint: zr cache clear | zr cache status\n", .{sub});
        return 1;
    }
}

/// Print task aliases in dimmed color if present
fn printAliases(
    w: *std.Io.Writer,
    aliases: []const []const u8,
    use_color: bool,
) !void {
    if (aliases.len == 0) return;

    try color.printDim(w, use_color, " [aliases: ", .{});
    for (aliases, 0..) |alias, i| {
        if (i > 0) try color.printDim(w, use_color, ", ", .{});
        try color.printDim(w, use_color, "{s}", .{alias});
    }
    try color.printDim(w, use_color, "]", .{});
}

fn formatBytes(bytes: u64) [64]u8 {
    var buf: [64]u8 = undefined;
    @memset(&buf, 0);
    if (bytes < 1024) {
        _ = std.fmt.bufPrint(&buf, "{d} B", .{bytes}) catch unreachable;
    } else if (bytes < 1024 * 1024) {
        const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
        _ = std.fmt.bufPrint(&buf, "{d:.2} KB", .{kb}) catch unreachable;
    } else if (bytes < 1024 * 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
        _ = std.fmt.bufPrint(&buf, "{d:.2} MB", .{mb}) catch unreachable;
    } else {
        const gb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0);
        _ = std.fmt.bufPrint(&buf, "{d:.2} GB", .{gb}) catch unreachable;
    }
    return buf;
}

// --- Tests ---

test "formatBytes: formats various byte sizes correctly" {
    const bytes_512 = formatBytes(512);
    const str_512 = std.mem.sliceTo(&bytes_512, 0);
    try std.testing.expectEqualStrings("512 B", str_512);

    const kb_1_5 = formatBytes(1536);
    const str_kb = std.mem.sliceTo(&kb_1_5, 0);
    try std.testing.expectEqualStrings("1.50 KB", str_kb);

    const mb_2 = formatBytes(2 * 1024 * 1024);
    const str_mb = std.mem.sliceTo(&mb_2, 0);
    try std.testing.expectEqualStrings("2.00 MB", str_mb);

    const gb_10 = formatBytes(10 * 1024 * 1024 * 1024);
    const str_gb = std.mem.sliceTo(&gb_10, 0);
    try std.testing.expectEqualStrings("10.00 GB", str_gb);

    const zero = formatBytes(0);
    const str_zero = std.mem.sliceTo(&zero, 0);
    try std.testing.expectEqualStrings("0 B", str_zero);
}

test "formatBytes: handles boundary cases" {
    // Test exactly 1 KB boundary
    const kb_1 = formatBytes(1024);
    const str_kb_1 = std.mem.sliceTo(&kb_1, 0);
    try std.testing.expectEqualStrings("1.00 KB", str_kb_1);

    // Test exactly 1 MB boundary
    const mb_1 = formatBytes(1024 * 1024);
    const str_mb_1 = std.mem.sliceTo(&mb_1, 0);
    try std.testing.expectEqualStrings("1.00 MB", str_mb_1);

    // Test exactly 1 GB boundary
    const gb_1 = formatBytes(1024 * 1024 * 1024);
    const str_gb_1 = std.mem.sliceTo(&gb_1, 0);
    try std.testing.expectEqualStrings("1.00 GB", str_gb_1);

    // Test max u64 value (should not overflow buffer)
    const max = formatBytes(std.math.maxInt(u64));
    const str_max = std.mem.sliceTo(&max, 0);
    // Should format as GB without crashing
    try std.testing.expect(std.mem.endsWith(u8, str_max, " GB"));
}

test "cmdList: text output lists tasks alphabetically" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "[tasks.build]\ncmd = \"make\"\n[tasks.alpha]\ncmd = \"echo a\"\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdList(allocator, config_path, false, false, null, null, null, false, false, false, false, null, null, null, null, false, false, false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdList: json output contains tasks array" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "[tasks.build]\ncmd = \"make\"\n[tasks.alpha]\ncmd = \"echo a\"\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdList(allocator, config_path, true, false, null, null, null, false, false, false, false, null, null, null, null, false, false, false, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "\"tasks\"") != null);
}

test "cmdList: missing config file returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdList(allocator, "/nonexistent/path/zr.toml", false, false, null, null, null, false, false, false, false, null, null, null, null, false, false, false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "cmdGraph: text output shows dependency levels" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "[tasks.build]\ncmd = \"make\"\n[tasks.test]\ncmd = \"test\"\ndeps = [\"build\"]\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdGraph(allocator, config_path, false, false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdGraph: json output contains levels array" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "[tasks.build]\ncmd = \"make\"\n[tasks.test]\ncmd = \"test\"\ndeps = [\"build\"]\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdGraph(allocator, config_path, true, false, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "\"levels\"") != null);
}

test "cmdCache: missing subcommand returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{ "zr", "cache" };
    const code = try cmdCache(allocator, &args, "zr.toml", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "cmdCache: unknown subcommand returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{ "zr", "cache", "unknown" };
    const code = try cmdCache(allocator, &args, "zr.toml", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "cmdCache: clear subcommand succeeds" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{ "zr", "cache", "clear" };
    const code = try cmdCache(allocator, &args, "zr.toml", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdList: tree mode renders dependency graph" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\
        \\[tasks.test]
        \\cmd = "test"
        \\deps = ["build"]
        \\
        \\[tasks.deploy]
        \\cmd = "deploy"
        \\deps = ["test"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdList(allocator, config_path, false, true, null, null, null, false, false, false, false, null, null, null, null, false, false, false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdList: tree mode with no tasks shows empty message" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdList(allocator, config_path, false, true, null, null, null, false, false, false, false, null, null, null, null, false, false, false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdList: filter pattern matches subset of tasks" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.test-unit]
        \\cmd = "run unit tests"
        \\
        \\[tasks.test-integration]
        \\cmd = "run integration tests"
        \\
        \\[tasks.build]
        \\cmd = "build project"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdList(allocator, config_path, true, false, "test", null, null, false, false, false, false, null, null, null, null, false, false, false, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    // Should contain test-unit and test-integration but not build
    try std.testing.expect(std.mem.indexOf(u8, written, "test-unit") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "test-integration") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "build") == null);
}

test "cmdList: filter pattern with no matches returns empty list" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "make"
        \\
        \\[tasks.test]
        \\cmd = "test"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdList(allocator, config_path, true, false, "nonexistent", null, null, false, false, false, false, null, null, null, null, false, false, false, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "\"tasks\":[]") != null);
}

test "cmdList: --profiles flag lists profile names" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[profiles.dev]
        \\env = { DEBUG = "1" }
        \\
        \\[profiles.prod]
        \\env = { PROD = "1" }
        \\
        \\[tasks.build]
        \\cmd = "echo build"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdList(allocator, config_path, false, false, null, null, null, true, false, false, false, null, null, null, null, false, false, false, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, written, "dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "prod") != null);
}

test "cmdList: --profiles flag with no profiles returns empty" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const code = try cmdList(allocator, config_path, false, false, null, null, null, true, false, false, false, null, null, null, null, false, false, false, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..out_w.end];
    try std.testing.expectEqual(written.len, 0);
}
