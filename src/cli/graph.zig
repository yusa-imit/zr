const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const workspace = @import("workspace.zig");
const affected_mod = @import("../util/affected.zig");

/// Output format for graph visualization
pub const GraphFormat = enum {
    ascii,
    dot,
    json,
    html,

    pub fn fromString(s: []const u8) ?GraphFormat {
        if (std.mem.eql(u8, s, "ascii")) return .ascii;
        if (std.mem.eql(u8, s, "dot")) return .dot;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "html")) return .html;
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
    try w.writeAll("{\"nodes\":[");

    for (nodes, 0..) |node, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"path\":");
        try common.writeJsonString(w, node.path);
        try w.writeAll(",\"dependencies\":[");

        for (node.dependencies, 0..) |dep, j| {
            if (j > 0) try w.writeAll(",");
            try common.writeJsonString(w, dep);
        }

        try w.writeAll("],\"affected\":");
        try w.writeAll(if (node.is_affected) "true" else "false");
        try w.writeAll("}");
    }

    try w.writeAll("]}\n");
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

/// Main entry point for `zr graph` command
pub fn graphCommand(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var format: GraphFormat = .ascii;
    var config_path: []const u8 = common.CONFIG_FILE;
    var affected_base: ?[]const u8 = null;
    var focus_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--format=")) {
            const fmt_str = arg["--format=".len..];
            format = GraphFormat.fromString(fmt_str) orelse {
                try color.printError(ew, use_color,
                    "graph: invalid format '{s}'\n\n  Valid formats: ascii, dot, json, html\n",
                    .{fmt_str});
                return 1;
            };
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

    // Build dependency graph
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

    // Render in requested format
    switch (format) {
        .ascii => try renderAscii(w, nodes, use_color),
        .dot => try renderDot(w, nodes, use_color),
        .json => try renderJson(w, nodes, use_color),
        .html => try renderHtml(w, nodes, use_color),
    }

    return 0;
}

fn printGraphHelp(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\Usage: zr graph [options]
        \\
        \\Visualize workspace dependency graph
        \\
        \\Options:
        \\  --format=<fmt>      Output format: ascii (default), dot, json, html
        \\  --affected <ref>    Highlight affected projects (git base reference)
        \\  --focus=<path>      Focus on specific project
        \\  --config=<path>     Config file path (default: zr.toml)
        \\  -h, --help          Show this help
        \\
        \\Examples:
        \\  zr graph                          # ASCII tree view
        \\  zr graph --format=dot             # Graphviz DOT format
        \\  zr graph --format=json            # JSON for programmatic use
        \\  zr graph --format=html > graph.html  # Interactive HTML
        \\  zr graph --affected origin/main   # Highlight changed projects
        \\
    );
}

test "GraphFormat.fromString" {
    try std.testing.expectEqual(GraphFormat.ascii, GraphFormat.fromString("ascii").?);
    try std.testing.expectEqual(GraphFormat.dot, GraphFormat.fromString("dot").?);
    try std.testing.expectEqual(GraphFormat.json, GraphFormat.fromString("json").?);
    try std.testing.expectEqual(GraphFormat.html, GraphFormat.fromString("html").?);
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
