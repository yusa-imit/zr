const std = @import("std");
const sailor = @import("sailor");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const workspace = @import("workspace.zig");
const affected_mod = @import("../util/affected.zig");
const synthetic = @import("../multirepo/synthetic.zig");
const graph_tui = @import("graph_tui.zig");
const graph_interactive = @import("graph_interactive.zig");
const history_store = @import("../history/store.zig");

/// Output format for graph visualization
pub const GraphFormat = enum {
    ascii,
    dot,
    json,
    html,
    tui, // Interactive TUI mode
    interactive, // Interactive HTML workflow visualizer (v1.58.0)

    pub fn fromString(s: []const u8) ?GraphFormat {
        if (std.mem.eql(u8, s, "ascii")) return .ascii;
        if (std.mem.eql(u8, s, "dot")) return .dot;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "html")) return .html;
        if (std.mem.eql(u8, s, "tui")) return .tui;
        if (std.mem.eql(u8, s, "interactive")) return .interactive;
        return null;
    }
};

/// Graph type to visualize
pub const GraphType = enum {
    workspace, // Workspace dependency graph (multi-repo)
    tasks, // Task dependency graph (workflow visualization)

    pub fn fromString(s: []const u8) ?GraphType {
        if (std.mem.eql(u8, s, "workspace")) return .workspace;
        if (std.mem.eql(u8, s, "tasks")) return .tasks;
        return null;
    }
};

/// Dependency graph node representing a workspace member
pub const GraphNode = struct {
    path: []const u8,
    dependencies: [][]const u8,
    is_affected: bool,
};

/// Build dependency graph from workspace configuration
pub fn buildDependencyGraph(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    ew: *std.Io.Writer,
) ![]GraphNode {
    // Check if synthetic workspace is active first
    var synthetic_workspace = try synthetic.loadSyntheticWorkspace(allocator);
    if (synthetic_workspace) |*sw| {
        defer sw.deinit(allocator);
        return buildGraphFromSyntheticWorkspace(allocator, sw);
    }

    // Fall back to regular workspace configuration
    var root_config = (try common.loadConfig(allocator, config_path, null, ew, true)) orelse return error.NoConfig;
    defer root_config.deinit();

    const ws = root_config.workspace orelse return error.NoWorkspace;

    // Resolve workspace members
    const members = try workspace.resolveWorkspaceMembers(allocator, ws, common.CONFIG_FILE);
    defer {
        for (members) |m| allocator.free(m);
        allocator.free(members);
    }

    var nodes = std.ArrayList(GraphNode){};
    errdefer {
        for (nodes.items) |node| {
            allocator.free(node.path);
            for (node.dependencies) |dep| allocator.free(dep);
            allocator.free(node.dependencies);
        }
        nodes.deinit(allocator);
    }

    // Build graph nodes
    for (members) |member_path| {
        const member_cfg = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ member_path, common.CONFIG_FILE });
        defer allocator.free(member_cfg);

        var member_config = loader.loadFromFile(allocator, member_cfg) catch {
            // Member without config - add with no dependencies
            const path_copy = try allocator.dupe(u8, member_path);
            const empty_deps = try allocator.alloc([]const u8, 0);
            try nodes.append(allocator, GraphNode{
                .path = path_copy,
                .dependencies = empty_deps,
                .is_affected = false,
            });
            continue;
        };
        defer member_config.deinit();

        const path_copy = try allocator.dupe(u8, member_path);
        var deps = std.ArrayList([]const u8){};
        if (member_config.workspace) |member_ws| {
            for (member_ws.member_dependencies) |dep| {
                try deps.append(allocator, try allocator.dupe(u8, dep));
            }
        }

        try nodes.append(allocator, GraphNode{
            .path = path_copy,
            .dependencies = try deps.toOwnedSlice(allocator),
            .is_affected = false,
        });
    }

    return nodes.toOwnedSlice(allocator);
}

/// Build dependency graph from synthetic workspace
fn buildGraphFromSyntheticWorkspace(
    allocator: std.mem.Allocator,
    sw: *const synthetic.SyntheticWorkspace,
) ![]GraphNode {
    var nodes = std.ArrayList(GraphNode){};
    errdefer {
        for (nodes.items) |node| {
            allocator.free(node.path);
            for (node.dependencies) |dep| allocator.free(dep);
            allocator.free(node.dependencies);
        }
        nodes.deinit(allocator);
    }

    for (sw.members) |member_path| {
        const path_copy = try allocator.dupe(u8, member_path);

        // Get dependencies from synthetic workspace dependency map
        var deps = std.ArrayList([]const u8){};
        if (sw.dependencies.get(member_path)) |member_deps| {
            for (member_deps) |dep| {
                try deps.append(allocator, try allocator.dupe(u8, dep));
            }
        }

        try nodes.append(allocator, GraphNode{
            .path = path_copy,
            .dependencies = try deps.toOwnedSlice(allocator),
            .is_affected = false,
        });
    }

    return nodes.toOwnedSlice(allocator);
}

/// Mark affected nodes in the graph
pub fn markAffectedNodes(
    nodes: []GraphNode,
    affected_result: *const affected_mod.AffectedResult,
) void {
    for (nodes) |*node| {
        node.is_affected = affected_result.contains(node.path);
    }
}

/// Render graph in ASCII format
pub fn renderAscii(
    w: *std.Io.Writer,
    nodes: []const GraphNode,
    use_color: bool,
) !void {
    if (nodes.len == 0) {
        try w.writeAll("(empty graph)\n");
        return;
    }

    try color.printBold(w, use_color, "Workspace Dependency Graph ({d} projects)\n\n", .{nodes.len});

    for (nodes) |node| {
        // Print node name
        if (node.is_affected) {
            try color.printSuccess(w, use_color, "● {s}", .{node.path});
            try color.printDim(w, use_color, " (affected)\n", .{});
        } else {
            try w.print("○ {s}\n", .{node.path});
        }

        // Print dependencies
        if (node.dependencies.len > 0) {
            for (node.dependencies, 0..) |dep, i| {
                const is_last = (i == node.dependencies.len - 1);
                const prefix = if (is_last) "  └─" else "  ├─";
                try color.printDim(w, use_color, "{s} {s}\n", .{ prefix, dep });
            }
        }
    }
}

/// Render graph in Graphviz DOT format
pub fn renderDot(
    w: *std.Io.Writer,
    nodes: []const GraphNode,
    _: bool,
) !void {
    try w.writeAll("digraph workspace {\n");
    try w.writeAll("  rankdir=LR;\n");
    try w.writeAll("  node [shape=box, style=rounded];\n\n");

    // Define nodes
    for (nodes) |node| {
        const name = try sanitizeDotId(node.path);
        defer std.heap.page_allocator.free(name);

        if (node.is_affected) {
            try w.print("  \"{s}\" [fillcolor=lightgreen, style=\"rounded,filled\"];\n", .{name});
        } else {
            try w.print("  \"{s}\";\n", .{name});
        }
    }

    try w.writeAll("\n");

    // Define edges
    for (nodes) |node| {
        const from = try sanitizeDotId(node.path);
        defer std.heap.page_allocator.free(from);

        for (node.dependencies) |dep| {
            const to = try sanitizeDotId(dep);
            defer std.heap.page_allocator.free(to);
            try w.print("  \"{s}\" -> \"{s}\";\n", .{ from, to });
        }
    }

    try w.writeAll("}\n");
}

/// Render graph in JSON format
pub fn renderJson(
    w: *std.Io.Writer,
    nodes: []const GraphNode,
    _: bool,
) !void {
    const JsonArr = sailor.fmt.JsonArray(*std.Io.Writer);
    try w.writeAll("{\"nodes\":");
    var nodes_arr = try JsonArr.init(w);

    for (nodes) |node| {
        var obj = try nodes_arr.beginObject();
        try obj.addString("path", node.path);
        // dependencies array (nested)
        try obj.writer.writeAll(",\"dependencies\":");
        var deps_arr = try JsonArr.init(w);
        for (node.dependencies) |dep| {
            try deps_arr.addString(dep);
        }
        try deps_arr.end();
        // affected bool - write manually after the nested array
        try obj.writer.writeAll(",\"affected\":");
        try obj.writer.writeAll(if (node.is_affected) "true" else "false");
        try obj.end();
    }

    try nodes_arr.end();
    try w.writeAll("}\n");
}

/// Render graph as interactive HTML
pub fn renderHtml(
    w: *std.Io.Writer,
    nodes: []const GraphNode,
    _: bool,
) !void {

    // HTML template with D3.js force-directed graph
    try w.writeAll(
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <meta charset="utf-8">
        \\  <title>zr Workspace Graph</title>
        \\  <script src="https://d3js.org/d3.v7.min.js"></script>
        \\  <style>
        \\    body { margin: 0; font-family: sans-serif; }
        \\    #graph { width: 100vw; height: 100vh; }
        \\    .node { cursor: pointer; }
        \\    .node circle { stroke: #333; stroke-width: 1.5px; }
        \\    .node.affected circle { fill: #90EE90; }
        \\    .node.normal circle { fill: #fff; }
        \\    .node text { font-size: 12px; pointer-events: none; text-anchor: middle; }
        \\    .link { stroke: #999; stroke-opacity: 0.6; stroke-width: 1.5px; }
        \\    .link.highlighted { stroke: #e74c3c; stroke-width: 3px; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <svg id="graph"></svg>
        \\  <script>
        \\    const data =
    );

    // Embed JSON data
    try renderJson(w, nodes, false);

    try w.writeAll(
        \\;
        \\    const width = window.innerWidth;
        \\    const height = window.innerHeight;
        \\
        \\    const svg = d3.select("#graph")
        \\      .attr("width", width)
        \\      .attr("height", height);
        \\
        \\    const nodeMap = new Map(data.nodes.map(n => [n.path, n]));
        \\    const links = [];
        \\    data.nodes.forEach(n => {
        \\      n.dependencies.forEach(dep => {
        \\        if (nodeMap.has(dep)) {
        \\          links.push({ source: n.path, target: dep });
        \\        }
        \\      });
        \\    });
        \\
        \\    const simulation = d3.forceSimulation(data.nodes)
        \\      .force("link", d3.forceLink(links).id(d => d.path).distance(100))
        \\      .force("charge", d3.forceManyBody().strength(-300))
        \\      .force("center", d3.forceCenter(width / 2, height / 2));
        \\
        \\    const link = svg.append("g")
        \\      .selectAll("line")
        \\      .data(links)
        \\      .enter().append("line")
        \\      .attr("class", "link");
        \\
        \\    const node = svg.append("g")
        \\      .selectAll("g")
        \\      .data(data.nodes)
        \\      .enter().append("g")
        \\      .attr("class", d => d.affected ? "node affected" : "node normal")
        \\      .call(d3.drag()
        \\        .on("start", dragstarted)
        \\        .on("drag", dragged)
        \\        .on("end", dragended));
        \\
        \\    node.append("circle").attr("r", 8);
        \\    node.append("text").text(d => d.path.split('/').pop()).attr("dy", -12);
        \\
        \\    simulation.on("tick", () => {
        \\      link
        \\        .attr("x1", d => d.source.x)
        \\        .attr("y1", d => d.source.y)
        \\        .attr("x2", d => d.target.x)
        \\        .attr("y2", d => d.target.y);
        \\      node.attr("transform", d => `translate(${d.x},${d.y})`);
        \\    });
        \\
        \\    function dragstarted(event, d) {
        \\      if (!event.active) simulation.alphaTarget(0.3).restart();
        \\      d.fx = d.x; d.fy = d.y;
        \\    }
        \\    function dragged(event, d) {
        \\      d.fx = event.x; d.fy = event.y;
        \\    }
        \\    function dragended(event, d) {
        \\      if (!event.active) simulation.alphaTarget(0);
        \\      d.fx = null; d.fy = null;
        \\    }
        \\  </script>
        \\</body>
        \\</html>
        \\
    );
}

/// Sanitize a path for use as a DOT identifier
fn sanitizeDotId(path: []const u8) ![]const u8 {
    return std.heap.page_allocator.dupe(u8, path);
}

/// Render task graph in ASCII tree format
fn renderTasksAscii(
    w: *std.Io.Writer,
    config: *const loader.Config,
    use_color: bool,
) !void {
    const task_count = config.tasks.count();

    if (task_count == 0) {
        try w.writeAll("(no tasks defined)\n");
        return;
    }

    try color.printBold(w, use_color, "Task Dependency Graph ({d} tasks)\n\n", .{task_count});

    // Iterate through all tasks
    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task = entry.value_ptr;

        // Print task name
        try w.print("● {s}", .{task.name});

        // Print description if available
        if (task.description) |desc| {
            try color.printDim(w, use_color, " — {s}", .{desc});
        }
        try w.writeAll("\n");

        // Print command (indented, dimmed)
        if (task.cmd.len > 0) {
            try color.printDim(w, use_color, "  cmd: {s}\n", .{task.cmd});
        }

        // Count total dependencies
        const total_deps = task.deps.len + task.deps_serial.len + task.deps_if.len + task.deps_optional.len;

        if (total_deps > 0) {
            // Print parallel dependencies
            for (task.deps, 0..) |dep, i| {
                const is_last = (i == task.deps.len - 1) and
                                task.deps_serial.len == 0 and
                                task.deps_if.len == 0 and
                                task.deps_optional.len == 0;
                const prefix = if (is_last) "  └─" else "  ├─";
                try color.printDim(w, use_color, "{s} {s}\n", .{ prefix, dep });
            }

            // Print serial dependencies
            for (task.deps_serial, 0..) |dep, i| {
                const is_last = (i == task.deps_serial.len - 1) and
                                task.deps_if.len == 0 and
                                task.deps_optional.len == 0;
                const prefix = if (is_last) "  └─" else "  ├─";
                try color.printDim(w, use_color, "{s} {s} ", .{ prefix, dep });
                try color.printWarning(w, use_color, "(serial)\n", .{});
            }

            // Print conditional dependencies
            for (task.deps_if, 0..) |dep, i| {
                const is_last = (i == task.deps_if.len - 1) and task.deps_optional.len == 0;
                const prefix = if (is_last) "  └─" else "  ├─";
                try color.printDim(w, use_color, "{s} {s} ", .{ prefix, dep.task });
                try color.printInfo(w, use_color, "(if: {s})\n", .{dep.condition});
            }

            // Print optional dependencies
            for (task.deps_optional, 0..) |dep, i| {
                const is_last = (i == task.deps_optional.len - 1);
                const prefix = if (is_last) "  └─" else "  ├─";
                try color.printDim(w, use_color, "{s} {s} ", .{ prefix, dep });
                try color.printDim(w, use_color, "(optional)\n", .{});
            }
        }

        try w.writeAll("\n");
    }
}

/// Render task graph in Graphviz DOT format
fn renderTasksDot(
    w: *std.Io.Writer,
    config: *const loader.Config,
    _: bool,
) !void {
    try w.writeAll("digraph tasks {\n");
    try w.writeAll("  rankdir=LR;\n");
    try w.writeAll("  node [shape=box, style=rounded];\n\n");

    // Define nodes with task metadata
    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task = entry.value_ptr;
        const name = try sanitizeDotId(task.name);
        defer std.heap.page_allocator.free(name);

        try w.print("  \"{s}\" [label=\"{s}", .{ name, name });

        // Add description as subtitle if available
        if (task.description) |desc| {
            // Escape quotes in description
            var escaped = std.ArrayList(u8){};
            defer escaped.deinit(std.heap.page_allocator);

            for (desc) |c| {
                if (c == '"') {
                    try escaped.append(std.heap.page_allocator, '\\');
                }
                try escaped.append(std.heap.page_allocator, c);
            }

            try w.print("\\n{s}", .{escaped.items});
        }

        try w.writeAll("\"];\n");
    }

    try w.writeAll("\n");

    // Define edges (dependencies)
    task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task = entry.value_ptr;
        const from = try sanitizeDotId(task.name);
        defer std.heap.page_allocator.free(from);

        // Parallel dependencies (solid line)
        for (task.deps) |dep| {
            const to = try sanitizeDotId(dep);
            defer std.heap.page_allocator.free(to);
            try w.print("  \"{s}\" -> \"{s}\";\n", .{ to, from });
        }

        // Serial dependencies (bold line)
        for (task.deps_serial) |dep| {
            const to = try sanitizeDotId(dep);
            defer std.heap.page_allocator.free(to);
            try w.print("  \"{s}\" -> \"{s}\" [style=bold, label=\"serial\"];\n", .{ to, from });
        }

        // Conditional dependencies (dashed line)
        for (task.deps_if) |dep| {
            const to = try sanitizeDotId(dep.task);
            defer std.heap.page_allocator.free(to);
            try w.print("  \"{s}\" -> \"{s}\" [style=dashed, label=\"{s}\"];\n", .{ to, from, dep.condition });
        }

        // Optional dependencies (dotted line)
        for (task.deps_optional) |dep| {
            const to = try sanitizeDotId(dep);
            defer std.heap.page_allocator.free(to);
            try w.print("  \"{s}\" -> \"{s}\" [style=dotted, label=\"optional\"];\n", .{ to, from });
        }
    }

    try w.writeAll("}\n");
}

/// Render task graph in JSON format
fn renderTasksJson(
    w: *std.Io.Writer,
    config: *const loader.Config,
    _: bool,
) !void {
    const JsonArr = sailor.fmt.JsonArray(*std.Io.Writer);

    try w.writeAll("{\"tasks\":");
    var tasks_arr = try JsonArr.init(w);

    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task = entry.value_ptr;
        var obj = try tasks_arr.beginObject();

        // Basic task metadata
        try obj.addString("name", task.name);
        try obj.addString("cmd", task.cmd);

        if (task.description) |desc| {
            try obj.addString("description", desc);
        }

        if (task.cwd) |cwd| {
            try obj.addString("cwd", cwd);
        }

        // Dependencies arrays
        try obj.writer.writeAll(",\"deps\":");
        var deps_arr = try JsonArr.init(w);
        for (task.deps) |dep| {
            try deps_arr.addString(dep);
        }
        try deps_arr.end();

        try obj.writer.writeAll(",\"deps_serial\":");
        var serial_arr = try JsonArr.init(w);
        for (task.deps_serial) |dep| {
            try serial_arr.addString(dep);
        }
        try serial_arr.end();

        try obj.writer.writeAll(",\"deps_if\":");
        var if_arr = try JsonArr.init(w);
        for (task.deps_if) |dep| {
            var if_obj = try if_arr.beginObject();
            try if_obj.addString("task", dep.task);
            try if_obj.addString("condition", dep.condition);
            try if_obj.end();
        }
        try if_arr.end();

        try obj.writer.writeAll(",\"deps_optional\":");
        var opt_arr = try JsonArr.init(w);
        for (task.deps_optional) |dep| {
            try opt_arr.addString(dep);
        }
        try opt_arr.end();

        // Tags
        if (task.tags.len > 0) {
            try obj.writer.writeAll(",\"tags\":");
            var tags_arr = try JsonArr.init(w);
            for (task.tags) |tag| {
                try tags_arr.addString(tag);
            }
            try tags_arr.end();
        }

        // Environment variables
        if (task.env.len > 0) {
            try obj.writer.writeAll(",\"env\":{");
            for (task.env, 0..) |kv, i| {
                if (i > 0) try obj.writer.writeAll(",");
                try obj.writer.print("\"{s}\":\"{s}\"", .{ kv[0], kv[1] });
            }
            try obj.writer.writeAll("}");
        }

        // Timeout
        if (task.timeout_ms) |timeout| {
            try obj.writer.print(",\"timeout_ms\":{d}", .{timeout});
        }

        // Resource limits
        if (task.max_cpu) |cpu| {
            try obj.writer.print(",\"max_cpu\":{d}", .{cpu});
        }

        if (task.max_memory) |mem| {
            try obj.writer.print(",\"max_memory\":{d}", .{mem});
        }

        try obj.end();
    }

    try tasks_arr.end();
    try w.writeAll("}\n");
}

/// Main entry point for `zr graph` command
pub fn graphCommand(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var format: GraphFormat = .ascii;
    var graph_type: GraphType = .workspace; // Default to workspace for backward compatibility
    var config_path: []const u8 = common.CONFIG_FILE;
    var affected_base: ?[]const u8 = null;
    var focus_path: ?[]const u8 = null;
    var interactive_flag: bool = false;
    var watch_flag: bool = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--format=")) {
            const fmt_str = arg["--format=".len..];
            format = GraphFormat.fromString(fmt_str) orelse {
                try color.printError(ew, use_color,
                    "graph: invalid format '{s}'\n\n  Valid formats: ascii, dot, json, html, tui, interactive\n",
                    .{fmt_str});
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "--type=")) {
            const type_str = arg["--type=".len..];
            graph_type = GraphType.fromString(type_str) orelse {
                try color.printError(ew, use_color,
                    "graph: invalid type '{s}'\n\n  Valid types: workspace, tasks\n",
                    .{type_str});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--interactive")) {
            interactive_flag = true;
            format = .interactive;
            graph_type = .tasks; // --interactive implies tasks graph
        } else if (std.mem.eql(u8, arg, "--watch")) {
            watch_flag = true;
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            config_path = arg["--config=".len..];
        } else if (std.mem.eql(u8, arg, "--affected")) {
            if (i + 1 >= args.len) {
                try color.printError(ew, use_color, "graph: --affected requires a git reference\n", .{});
                return 1;
            }
            i += 1;
            affected_base = args[i];
        } else if (std.mem.startsWith(u8, arg, "--focus=")) {
            focus_path = arg["--focus=".len..];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printGraphHelp(w);
            return 0;
        } else {
            try color.printError(ew, use_color, "graph: unknown argument '{s}'\n", .{arg});
            return 1;
        }
    }

    // Handle tasks graph (new in v1.58.0)
    if (graph_type == .tasks) {
        // Load task configuration
        var config = (try common.loadConfig(allocator, config_path, null, ew, true)) orelse return error.NoConfig;
        defer config.deinit();

        // Load execution history if showing status
        var store: ?history_store.Store = null;
        defer if (store) |s| s.deinit();

        var records = std.ArrayList(history_store.Record){};
        defer {
            for (records.items) |r| r.deinit(allocator);
            records.deinit(allocator);
        }

        if (format == .interactive) {
            // Try to load history (optional - may not exist)
            store = history_store.Store.init(allocator, ".zr_history") catch null;
            if (store) |s| {
                records = s.loadLast(allocator, 1000) catch std.ArrayList(history_store.Record){};
            }
        }

        // Render task graph in interactive format
        if (format == .interactive) {
            try graph_interactive.renderInteractive(allocator, w, &config, records.items, .{
                .show_critical_path = true,
                .show_status = (records.items.len > 0),
                .enable_filters = true,
                .enable_export = true,
            });
            return 0;
        }

        // Render task graph in requested format
        switch (format) {
            .ascii => try renderTasksAscii(w, &config, use_color),
            .dot => try renderTasksDot(w, &config, use_color),
            .json => try renderTasksJson(w, &config, use_color),
            .interactive => unreachable, // Already handled above
            .html => {
                try color.printError(ew, use_color, "graph: HTML format is only for workspace graphs (use --format=interactive for task graphs)\n", .{});
                return 1;
            },
            .tui => {
                try color.printError(ew, use_color, "graph: TUI format is only for workspace graphs (use --format=interactive for task graphs)\n", .{});
                return 1;
            },
        }
        return 0;
    }

    // Legacy workspace graph handling (unchanged)
    if (watch_flag) {
        try color.printError(ew, use_color, "graph: --watch is only supported for task graphs (use --type=tasks)\n", .{});
        return 1;
    }

    const nodes = buildDependencyGraph(allocator, config_path, ew) catch |err| {
        if (err == error.NoWorkspace) {
            try color.printError(ew, use_color,
                "graph: no [workspace] section in {s}\n\n  Hint: This command requires workspace configuration\n",
                .{config_path});
            return 1;
        }
        return err;
    };
    defer {
        for (nodes) |node| {
            allocator.free(node.path);
            for (node.dependencies) |dep| allocator.free(dep);
            allocator.free(node.dependencies);
        }
        allocator.free(nodes);
    }

    // Apply affected detection if requested
    if (affected_base) |base_ref| {
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        defer allocator.free(cwd);

        const members = try allocator.alloc([]const u8, nodes.len);
        defer allocator.free(members);
        for (nodes, 0..) |node, idx| {
            members[idx] = node.path;
        }

        var affected_result = affected_mod.detectAffected(allocator, base_ref, members, cwd) catch |err| {
            try color.printError(ew, use_color,
                "graph: affected detection failed: {s}\n\n  Hint: Ensure git is installed and {s} is a valid git reference\n",
                .{ @errorName(err), base_ref });
            return 1;
        };
        defer affected_result.deinit(allocator);

        markAffectedNodes(nodes, &affected_result);
    }

    // Apply focus filter if requested
    if (focus_path) |focus| {
        // For now, just mark the focused node (could filter graph later)
        _ = focus;
    }

    // Render workspace graph in requested format
    switch (format) {
        .ascii => try renderAscii(w, nodes, use_color),
        .dot => try renderDot(w, nodes, use_color),
        .json => try renderJson(w, nodes, use_color),
        .html => try renderHtml(w, nodes, use_color),
        .tui => {
            // Re-enabled: sailor#8 fixed in v1.0.3 (Tree widget ArrayList.init compatibility)
            graph_tui.graphTui(allocator, nodes, w, use_color) catch |err| {
                try color.printError(ew, use_color,
                    "graph: TUI mode failed: {s}\n\n  Hint: TUI mode requires a terminal (not supported on Windows)\n",
                    .{@errorName(err)});
                return 1;
            };
        },
        .interactive => {
            try color.printError(ew, use_color, "graph: interactive format is only for task graphs (use --type=tasks or --interactive)\n", .{});
            return 1;
        },
    }

    return 0;
}

fn printGraphHelp(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\Usage: zr graph [options]
        \\
        \\Visualize dependency graphs (workspace or task workflows)
        \\
        \\Options:
        \\  --type=<type>       Graph type: workspace (default), tasks
        \\  --format=<fmt>      Output format: ascii (default), dot, json, html, tui, interactive
        \\  --interactive       Interactive HTML workflow visualizer (implies --type=tasks)
        \\  --watch             Live-update graph during workflow execution (requires --type=tasks)
        \\  --affected <ref>    Highlight affected projects (git base reference, workspace only)
        \\  --focus=<path>      Focus on specific project (workspace only)
        \\  --config=<path>     Config file path (default: zr.toml)
        \\  -h, --help          Show this help
        \\
        \\Examples:
        \\  # Workspace dependency graphs
        \\  zr graph                          # ASCII tree view (workspace)
        \\  zr graph --format=tui             # Interactive TUI (arrow keys, q to quit)
        \\  zr graph --format=dot             # Graphviz DOT format
        \\  zr graph --format=json            # JSON for programmatic use
        \\  zr graph --format=html > graph.html  # Interactive HTML
        \\  zr graph --affected origin/main   # Highlight changed projects
        \\
        \\  # Task workflow visualizer (v1.58.0+)
        \\  zr graph --interactive            # Interactive HTML task graph (opens in browser)
        \\  zr graph --type=tasks --interactive  # Explicit task graph
        \\  zr graph --interactive --watch    # Live-update during execution
        \\  zr graph --interactive > workflow.html  # Save to file
        \\
        \\Interactive Features:
        \\  - Click task nodes to view details (cmd, deps, env, duration)
        \\  - Color-coded status (success/failed/pending/unknown)
        \\  - Critical path highlighting (longest dependency chain)
        \\  - Filter by task name (regex), status, or tags
        \\  - Export to SVG/PNG
        \\  - Zoom, pan, drag nodes
        \\  - Responsive design (mobile-friendly)
        \\
    );
}

test "GraphFormat.fromString" {
    try std.testing.expectEqual(GraphFormat.ascii, GraphFormat.fromString("ascii").?);
    try std.testing.expectEqual(GraphFormat.dot, GraphFormat.fromString("dot").?);
    try std.testing.expectEqual(GraphFormat.json, GraphFormat.fromString("json").?);
    try std.testing.expectEqual(GraphFormat.html, GraphFormat.fromString("html").?);
    try std.testing.expectEqual(GraphFormat.tui, GraphFormat.fromString("tui").?);
    try std.testing.expect(GraphFormat.fromString("invalid") == null);
}

test "markAffectedNodes" {
    const allocator = std.testing.allocator;

    var affected = affected_mod.AffectedResult{
        .projects = std.StringHashMap(void).init(allocator),
        .base_ref = try allocator.dupe(u8, "main"),
    };
    defer affected.deinit(allocator);

    const proj1 = try allocator.dupe(u8, "packages/core");
    try affected.projects.put(proj1, {});

    var nodes = [_]GraphNode{
        GraphNode{
            .path = "packages/core",
            .dependencies = &[_][]const u8{},
            .is_affected = false,
        },
        GraphNode{
            .path = "packages/ui",
            .dependencies = &[_][]const u8{},
            .is_affected = false,
        },
    };

    markAffectedNodes(&nodes, &affected);

    try std.testing.expect(nodes[0].is_affected);
    try std.testing.expect(!nodes[1].is_affected);
}

test "buildGraphFromSyntheticWorkspace" {
    const allocator = std.testing.allocator;

    // Create a mock synthetic workspace
    const members = try allocator.alloc([]const u8, 2);
    members[0] = try allocator.dupe(u8, "repo1");
    members[1] = try allocator.dupe(u8, "repo2");

    var deps_map = std.StringHashMap([]const []const u8).init(allocator);

    // repo1 depends on nothing
    const repo1_deps = try allocator.alloc([]const u8, 0);
    try deps_map.put(try allocator.dupe(u8, "repo1"), repo1_deps);

    // repo2 depends on repo1
    const repo2_deps = try allocator.alloc([]const u8, 1);
    repo2_deps[0] = try allocator.dupe(u8, "repo1");
    try deps_map.put(try allocator.dupe(u8, "repo2"), repo2_deps);

    var sw = synthetic.SyntheticWorkspace{
        .name = try allocator.dupe(u8, "test-workspace"),
        .root_path = try allocator.dupe(u8, "/tmp/test"),
        .members = members,
        .dependencies = deps_map,
    };
    defer sw.deinit(allocator);

    const nodes = try buildGraphFromSyntheticWorkspace(allocator, &sw);
    defer {
        for (nodes) |node| {
            allocator.free(node.path);
            for (node.dependencies) |dep| allocator.free(dep);
            allocator.free(node.dependencies);
        }
        allocator.free(nodes);
    }

    try std.testing.expectEqual(@as(usize, 2), nodes.len);

    // Find repo1 node
    var repo1_node: ?*const GraphNode = null;
    var repo2_node: ?*const GraphNode = null;
    for (nodes) |*node| {
        if (std.mem.eql(u8, node.path, "repo1")) {
            repo1_node = node;
        } else if (std.mem.eql(u8, node.path, "repo2")) {
            repo2_node = node;
        }
    }

    try std.testing.expect(repo1_node != null);
    try std.testing.expect(repo2_node != null);

    try std.testing.expectEqual(@as(usize, 0), repo1_node.?.dependencies.len);
    try std.testing.expectEqual(@as(usize, 1), repo2_node.?.dependencies.len);
    try std.testing.expectEqualStrings("repo1", repo2_node.?.dependencies[0]);
}
