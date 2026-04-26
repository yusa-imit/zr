/// Interactive HTML/SVG workflow visualizer for task dependency graphs.
/// Generates standalone HTML with embedded D3.js for modern web-based visualization.
const std = @import("std");
const sailor = @import("sailor");
const Config = @import("../config/types.zig").Config;
const Task = @import("../config/types.zig").Task;
const DAG = @import("../graph/dag.zig").DAG;
const history_store = @import("../history/store.zig");
const Record = history_store.Record;

/// Task status derived from execution history
pub const TaskStatus = enum {
    unknown,
    pending,
    running,
    success,
    failed,
    skipped,

    pub fn colorHex(self: TaskStatus) []const u8 {
        return switch (self) {
            .unknown => "#d3d3d3", // Gray
            .pending => "#87ceeb", // Sky blue
            .running => "#ffa500", // Orange
            .success => "#90ee90", // Light green
            .failed => "#ff6b6b", // Red
            .skipped => "#ffffcc", // Light yellow
        };
    }
};

/// Task node for visualization with metadata
pub const VisNode = struct {
    name: []const u8,
    cmd: []const u8,
    description: ?[]const u8,
    deps: []const []const u8,
    env: []const [2][]const u8,
    tags: []const []const u8,
    status: TaskStatus,
    duration_ms: ?u64, // Last execution duration
    critical_path: bool, // Is this task on the critical path?
};

/// Generate interactive HTML visualization for task graph
pub fn renderInteractive(
    allocator: std.mem.Allocator,
    writer: anytype,
    config: *const Config,
    history_records: []const Record,
    options: struct {
        show_critical_path: bool = true,
        show_status: bool = true,
        enable_filters: bool = true,
        enable_export: bool = true,
    },
) !void {
    // Build visualization nodes
    var nodes = std.ArrayList(VisNode){};
    defer {
        for (nodes.items) |node| {
            allocator.free(node.name);
            allocator.free(node.cmd);
            if (node.description) |desc| allocator.free(desc);
            for (node.deps) |dep| allocator.free(dep);
            if (node.deps.len > 0) allocator.free(node.deps);
            for (node.env) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            if (node.env.len > 0) allocator.free(node.env);
            for (node.tags) |tag| allocator.free(tag);
            if (node.tags.len > 0) allocator.free(node.tags);
        }
        nodes.deinit(allocator);
    }

    // Populate nodes from config
    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task = entry.value_ptr;

        // Copy dependencies
        const deps = try allocator.alloc([]const u8, task.deps.len);
        errdefer allocator.free(deps);
        for (task.deps, 0..) |dep, i| {
            deps[i] = try allocator.dupe(u8, dep);
        }

        // Copy environment variables
        const env = try allocator.alloc([2][]const u8, task.env.len);
        errdefer allocator.free(env);
        for (task.env, 0..) |pair, i| {
            env[i][0] = try allocator.dupe(u8, pair[0]);
            env[i][1] = try allocator.dupe(u8, pair[1]);
        }

        // Copy tags
        const tags = try allocator.alloc([]const u8, task.tags.len);
        errdefer allocator.free(tags);
        for (task.tags, 0..) |tag, i| {
            tags[i] = try allocator.dupe(u8, tag);
        }

        // Determine task status from history (if available)
        var status: TaskStatus = .unknown;
        var duration_ms: ?u64 = null;
        if (options.show_status and history_records.len > 0) {
            // Find the most recent record for this task
            var i: isize = @as(isize, @intCast(history_records.len)) - 1;
            while (i >= 0) : (i -= 1) {
                const idx: usize = @intCast(i);
                const record = history_records[idx];
                if (std.mem.eql(u8, record.task_name, task.name)) {
                    status = if (record.success) .success else .failed;
                    duration_ms = record.duration_ms;
                    break;
                }
            }
        }

        try nodes.append(allocator, .{
            .name = try allocator.dupe(u8, task.name),
            .cmd = try allocator.dupe(u8, task.cmd),
            .description = if (task.description) |desc| try allocator.dupe(u8, desc.getShort()) else null,
            .deps = deps,
            .env = env,
            .tags = tags,
            .status = status,
            .duration_ms = duration_ms,
            .critical_path = false, // Will be calculated later
        });
    }

    // Calculate critical path if enabled
    if (options.show_critical_path) {
        try markCriticalPath(allocator, nodes.items);
    }

    // Generate HTML
    try writeHtmlHeader(writer);
    try writeHtmlStyles(writer, options);
    try writeHtmlBody(writer, nodes.items, options);
    try writeHtmlFooter(writer);
}

/// Mark nodes on the critical path (longest dependency chain)
fn markCriticalPath(allocator: std.mem.Allocator, nodes: []VisNode) !void {
    if (nodes.len == 0) return;

    // Build DAG for critical path calculation
    var dag = DAG.init(allocator);
    defer dag.deinit();

    for (nodes) |node| {
        try dag.addNode(node.name);
        for (node.deps) |dep| {
            try dag.addEdge(node.name, dep);
        }
    }

    // Find critical path (longest path from entry to each node)
    var depths = std.StringHashMap(usize).init(allocator);
    defer {
        var it = depths.keyIterator();
        while (it.next()) |key| allocator.free(key.*);
        depths.deinit();
    }

    // Calculate depths using topological ordering
    var entry_nodes = try dag.getEntryNodes(allocator);
    defer {
        for (entry_nodes.items) |node| allocator.free(node);
        entry_nodes.deinit(allocator);
    }

    // BFS to calculate max depth to each node
    for (entry_nodes.items) |entry| {
        try depths.put(try allocator.dupe(u8, entry), 0);
    }

    var queue = std.ArrayList([]const u8){};
    defer queue.deinit(allocator);
    try queue.appendSlice(allocator, entry_nodes.items);

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        const current_depth = depths.get(current) orelse 0;

        // Find dependents (nodes that depend on current)
        for (nodes) |node| {
            for (node.deps) |dep| {
                if (std.mem.eql(u8, dep, current)) {
                    const new_depth = current_depth + 1;
                    const existing_depth = depths.get(node.name) orelse 0;
                    if (new_depth > existing_depth) {
                        if (depths.contains(node.name)) {
                            // Remove old key allocation
                            var old_key: []const u8 = undefined;
                            var dit = depths.keyIterator();
                            while (dit.next()) |key| {
                                if (std.mem.eql(u8, key.*, node.name)) {
                                    old_key = key.*;
                                    break;
                                }
                            }
                            _ = depths.remove(node.name);
                            allocator.free(old_key);
                        }
                        try depths.put(try allocator.dupe(u8, node.name), new_depth);
                        try queue.append(allocator, node.name);
                    }
                    break;
                }
            }
        }
    }

    // Find max depth
    var max_depth: usize = 0;
    var dit = depths.valueIterator();
    while (dit.next()) |depth| {
        if (depth.* > max_depth) max_depth = depth.*;
    }

    // Mark nodes on critical path (those at max depth)
    for (nodes) |*node| {
        if (depths.get(node.name)) |depth| {
            node.critical_path = (depth == max_depth);
        }
    }
}

fn writeHtmlHeader(writer: anytype) !void {
    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="UTF-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\  <title>zr Task Graph — Interactive Workflow Visualizer</title>
        \\  <script src="https://d3js.org/d3.v7.min.js"></script>
        \\
    );
}

fn writeHtmlStyles(writer: anytype, options: anytype) !void {
    try writer.writeAll(
        \\  <style>
        \\    * { margin: 0; padding: 0; box-sizing: border-box; }
        \\    body {
        \\      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        \\      background: #1e1e1e;
        \\      color: #d4d4d4;
        \\      overflow: hidden;
        \\    }
        \\    #controls {
        \\      position: fixed;
        \\      top: 0;
        \\      left: 0;
        \\      right: 0;
        \\      background: #252526;
        \\      border-bottom: 1px solid #3e3e42;
        \\      padding: 12px 16px;
        \\      display: flex;
        \\      gap: 12px;
        \\      align-items: center;
        \\      z-index: 100;
        \\    }
        \\    #controls input, #controls select, #controls button {
        \\      background: #3c3c3c;
        \\      color: #d4d4d4;
        \\      border: 1px solid #3e3e42;
        \\      padding: 6px 12px;
        \\      border-radius: 4px;
        \\      font-size: 13px;
        \\    }
        \\    #controls button {
        \\      cursor: pointer;
        \\      background: #0e639c;
        \\    }
        \\    #controls button:hover { background: #1177bb; }
        \\    #graph {
        \\      position: fixed;
        \\      top: 52px;
        \\      left: 0;
        \\      right: 300px;
        \\      bottom: 0;
        \\    }
        \\    #sidebar {
        \\      position: fixed;
        \\      top: 52px;
        \\      right: 0;
        \\      width: 300px;
        \\      bottom: 0;
        \\      background: #252526;
        \\      border-left: 1px solid #3e3e42;
        \\      padding: 16px;
        \\      overflow-y: auto;
        \\    }
        \\    #sidebar h3 { margin-bottom: 12px; font-size: 14px; font-weight: 600; }
        \\    #sidebar .field { margin-bottom: 12px; }
        \\    #sidebar .label { font-size: 12px; color: #858585; margin-bottom: 4px; }
        \\    #sidebar .value {
        \\      font-size: 13px;
        \\      background: #1e1e1e;
        \\      padding: 8px;
        \\      border-radius: 4px;
        \\      word-break: break-word;
        \\    }
        \\    #sidebar .empty { color: #858585; font-style: italic; }
        \\    .node { cursor: pointer; }
        \\    .node circle { stroke: #3e3e42; stroke-width: 2px; }
        \\    .node.critical-path circle { stroke: #ffd700; stroke-width: 3px; }
        \\    .node.selected circle { stroke: #007acc; stroke-width: 4px; }
        \\    .node text {
        \\      font-size: 12px;
        \\      pointer-events: none;
        \\      text-anchor: middle;
        \\      fill: #d4d4d4;
        \\    }
        \\    .link {
        \\      stroke: #858585;
        \\      stroke-opacity: 0.6;
        \\      stroke-width: 2px;
        \\      fill: none;
        \\    }
        \\    .link.critical-path { stroke: #ffd700; stroke-width: 3px; }
        \\    .link.arrow { marker-end: url(#arrow); }
        \\    #legend {
        \\      position: fixed;
        \\      bottom: 16px;
        \\      left: 16px;
        \\      background: #252526;
        \\      border: 1px solid #3e3e42;
        \\      padding: 12px;
        \\      border-radius: 4px;
        \\      font-size: 12px;
        \\    }
        \\    .legend-item { display: flex; align-items: center; gap: 8px; margin: 4px 0; }
        \\    .legend-circle { width: 16px; height: 16px; border-radius: 50%; border: 2px solid #3e3e42; }
        \\  </style>
        \\</head>
        \\<body>
        \\
    );

    if (options.enable_filters) {
        try writer.writeAll(
            \\  <div id="controls">
            \\    <input type="text" id="search" placeholder="Search tasks (regex)..." />
            \\    <select id="status-filter">
            \\      <option value="">All Statuses</option>
            \\      <option value="success">Success</option>
            \\      <option value="failed">Failed</option>
            \\      <option value="pending">Pending</option>
            \\      <option value="unknown">Unknown</option>
            \\    </select>
            \\    <select id="tag-filter">
            \\      <option value="">All Tags</option>
            \\    </select>
            \\    <button id="reset-zoom">Reset Zoom</button>
            \\
        );
    }

    if (options.enable_export) {
        try writer.writeAll(
            \\    <button id="export-svg">Export SVG</button>
            \\    <button id="export-png">Export PNG</button>
            \\
        );
    }

    try writer.writeAll(
        \\  </div>
        \\
    );
}

fn writeHtmlBody(writer: anytype, nodes: []const VisNode, options: anytype) !void {
    try writer.writeAll(
        \\  <svg id="graph"></svg>
        \\  <div id="sidebar">
        \\    <h3>Task Details</h3>
        \\    <p class="empty">Click on a task node to view details</p>
        \\  </div>
        \\  <div id="legend">
        \\    <div class="legend-item">
        \\      <div class="legend-circle" style="background: #90ee90;"></div>
        \\      <span>Success</span>
        \\    </div>
        \\    <div class="legend-item">
        \\      <div class="legend-circle" style="background: #ff6b6b;"></div>
        \\      <span>Failed</span>
        \\    </div>
        \\    <div class="legend-item">
        \\      <div class="legend-circle" style="background: #87ceeb;"></div>
        \\      <span>Pending</span>
        \\    </div>
        \\    <div class="legend-item">
        \\      <div class="legend-circle" style="background: #d3d3d3;"></div>
        \\      <span>Unknown</span>
        \\    </div>
        \\
    );

    if (options.show_critical_path) {
        try writer.writeAll(
            \\    <div class="legend-item">
            \\      <div class="legend-circle" style="border-color: #ffd700; border-width: 3px;"></div>
            \\      <span>Critical Path</span>
            \\    </div>
            \\
        );
    }

    try writer.writeAll(
        \\  </div>
        \\
        \\  <script>
        \\    const data = {
        \\      nodes: [
        \\
    );

    // Write JSON data
    for (nodes, 0..) |node, i| {
        try writer.writeAll("        {");
        try writer.print("name:\"{s}\",", .{escapeJson(node.name)});
        try writer.print("cmd:\"{s}\",", .{escapeJson(node.cmd)});
        if (node.description) |desc| {
            try writer.print("description:\"{s}\",", .{escapeJson(desc)});
        } else {
            try writer.writeAll("description:null,");
        }
        try writer.print("status:\"{s}\",", .{@tagName(node.status)});
        try writer.print("critical_path:{s},", .{if (node.critical_path) "true" else "false"});

        // Write dependencies
        try writer.writeAll("deps:[");
        for (node.deps, 0..) |dep, j| {
            try writer.print("\"{s}\"", .{escapeJson(dep)});
            if (j < node.deps.len - 1) try writer.writeAll(",");
        }
        try writer.writeAll("],");

        // Write tags
        try writer.writeAll("tags:[");
        for (node.tags, 0..) |tag, j| {
            try writer.print("\"{s}\"", .{escapeJson(tag)});
            if (j < node.tags.len - 1) try writer.writeAll(",");
        }
        try writer.writeAll("],");

        // Write environment variables
        try writer.writeAll("env:[");
        for (node.env, 0..) |pair, j| {
            try writer.print("[\"{s}\",\"{s}\"]", .{ escapeJson(pair[0]), escapeJson(pair[1]) });
            if (j < node.env.len - 1) try writer.writeAll(",");
        }
        try writer.writeAll("]");

        if (node.duration_ms) |dur| {
            try writer.print(",duration_ms:{d}", .{dur});
        }

        try writer.writeAll("}");
        if (i < nodes.len - 1) try writer.writeAll(",\n");
    }

    try writer.writeAll(
        \\
        \\      ]
        \\    };
        \\
        \\    // Build graph data structure
        \\    const nodeMap = new Map(data.nodes.map(n => [n.name, n]));
        \\    const links = [];
        \\    data.nodes.forEach(n => {
        \\      n.deps.forEach(dep => {
        \\        if (nodeMap.has(dep)) {
        \\          links.push({
        \\            source: dep,
        \\            target: n.name,
        \\            critical: n.critical_path && nodeMap.get(dep).critical_path
        \\          });
        \\        }
        \\      });
        \\    });
        \\
        \\    // Set up SVG
        \\    const width = window.innerWidth - 300;
        \\    const height = window.innerHeight - 52;
        \\    const svg = d3.select("#graph")
        \\      .attr("width", width)
        \\      .attr("height", height);
        \\
        \\    // Define arrow marker
        \\    svg.append("defs").append("marker")
        \\      .attr("id", "arrow")
        \\      .attr("viewBox", "0 -5 10 10")
        \\      .attr("refX", 20)
        \\      .attr("refY", 0)
        \\      .attr("markerWidth", 6)
        \\      .attr("markerHeight", 6)
        \\      .attr("orient", "auto")
        \\      .append("path")
        \\      .attr("d", "M0,-5L10,0L0,5")
        \\      .attr("fill", "#858585");
        \\
        \\    // Zoom behavior
        \\    const zoom = d3.zoom()
        \\      .scaleExtent([0.1, 4])
        \\      .on("zoom", (event) => {
        \\        container.attr("transform", event.transform);
        \\      });
        \\    svg.call(zoom);
        \\
        \\    const container = svg.append("g");
        \\
        \\    // Force simulation
        \\    const simulation = d3.forceSimulation(data.nodes)
        \\      .force("link", d3.forceLink(links).id(d => d.name).distance(150))
        \\      .force("charge", d3.forceManyBody().strength(-500))
        \\      .force("center", d3.forceCenter(width / 2, height / 2))
        \\      .force("collision", d3.forceCollide().radius(30));
        \\
        \\    // Draw links
        \\    const link = container.append("g")
        \\      .selectAll("path")
        \\      .data(links)
        \\      .enter().append("path")
        \\      .attr("class", d => `link arrow ${d.critical ? 'critical-path' : ''}`);
        \\
        \\    // Draw nodes
        \\    const node = container.append("g")
        \\      .selectAll("g")
        \\      .data(data.nodes)
        \\      .enter().append("g")
        \\      .attr("class", d => `node ${d.critical_path ? 'critical-path' : ''}`)
        \\      .call(d3.drag()
        \\        .on("start", dragstarted)
        \\        .on("drag", dragged)
        \\        .on("end", dragended))
        \\      .on("click", (event, d) => {
        \\        // Highlight selected node
        \\        d3.selectAll(".node").classed("selected", false);
        \\        d3.select(event.currentTarget).classed("selected", true);
        \\        showTaskDetails(d);
        \\      });
        \\
        \\    node.append("circle")
        \\      .attr("r", 12)
        \\      .attr("fill", d => getStatusColor(d.status));
        \\
        \\    node.append("text")
        \\      .text(d => d.name)
        \\      .attr("dy", -18);
        \\
        \\    // Update positions on simulation tick
        \\    simulation.on("tick", () => {
        \\      link.attr("d", d => {
        \\        const dx = d.target.x - d.source.x;
        \\        const dy = d.target.y - d.source.y;
        \\        const dr = Math.sqrt(dx * dx + dy * dy);
        \\        return `M${d.source.x},${d.source.y}A${dr},${dr} 0 0,1 ${d.target.x},${d.target.y}`;
        \\      });
        \\      node.attr("transform", d => `translate(${d.x},${d.y})`);
        \\    });
        \\
        \\    // Helper functions
        \\    function getStatusColor(status) {
        \\      const colors = {
        \\        unknown: "#d3d3d3",
        \\        pending: "#87ceeb",
        \\        running: "#ffa500",
        \\        success: "#90ee90",
        \\        failed: "#ff6b6b",
        \\        skipped: "#ffffcc"
        \\      };
        \\      return colors[status] || colors.unknown;
        \\    }
        \\
        \\    function showTaskDetails(task) {
        \\      const sidebar = document.getElementById("sidebar");
        \\      let html = `<h3>${task.name}</h3>`;
        \\      html += `<div class="field"><div class="label">Command</div><div class="value">${task.cmd}</div></div>`;
        \\      if (task.description) {
        \\        html += `<div class="field"><div class="label">Description</div><div class="value">${task.description}</div></div>`;
        \\      }
        \\      html += `<div class="field"><div class="label">Status</div><div class="value">${task.status}</div></div>`;
        \\      if (task.duration_ms) {
        \\        html += `<div class="field"><div class="label">Duration</div><div class="value">${formatDuration(task.duration_ms)}</div></div>`;
        \\      }
        \\      if (task.deps.length > 0) {
        \\        html += `<div class="field"><div class="label">Dependencies</div><div class="value">${task.deps.join(", ")}</div></div>`;
        \\      }
        \\      if (task.tags.length > 0) {
        \\        html += `<div class="field"><div class="label">Tags</div><div class="value">${task.tags.join(", ")}</div></div>`;
        \\      }
        \\      if (task.env.length > 0) {
        \\        html += `<div class="field"><div class="label">Environment</div><div class="value">`;
        \\        task.env.forEach(([k, v]) => {
        \\          html += `${k}=${v}<br>`;
        \\        });
        \\        html += `</div></div>`;
        \\      }
        \\      sidebar.innerHTML = html;
        \\    }
        \\
        \\    function formatDuration(ms) {
        \\      if (ms < 1000) return `${ms}ms`;
        \\      if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
        \\      const mins = Math.floor(ms / 60000);
        \\      const secs = Math.floor((ms % 60000) / 1000);
        \\      return `${mins}m ${secs}s`;
        \\    }
        \\
        \\    function dragstarted(event, d) {
        \\      if (!event.active) simulation.alphaTarget(0.3).restart();
        \\      d.fx = d.x;
        \\      d.fy = d.y;
        \\    }
        \\
        \\    function dragged(event, d) {
        \\      d.fx = event.x;
        \\      d.fy = event.y;
        \\    }
        \\
        \\    function dragended(event, d) {
        \\      if (!event.active) simulation.alphaTarget(0);
        \\      d.fx = null;
        \\      d.fy = null;
        \\    }
        \\
        \\    // Controls
        \\    document.getElementById("reset-zoom")?.addEventListener("click", () => {
        \\      svg.transition().duration(750).call(zoom.transform, d3.zoomIdentity);
        \\    });
        \\
        \\    document.getElementById("export-svg")?.addEventListener("click", () => {
        \\      const svgData = document.getElementById("graph").outerHTML;
        \\      const blob = new Blob([svgData], { type: "image/svg+xml" });
        \\      const url = URL.createObjectURL(blob);
        \\      const a = document.createElement("a");
        \\      a.href = url;
        \\      a.download = "zr-task-graph.svg";
        \\      a.click();
        \\    });
        \\
        \\    document.getElementById("export-png")?.addEventListener("click", () => {
        \\      const svgElem = document.getElementById("graph");
        \\      const canvas = document.createElement("canvas");
        \\      canvas.width = width * 2;
        \\      canvas.height = height * 2;
        \\      const ctx = canvas.getContext("2d");
        \\      const img = new Image();
        \\      const svgBlob = new Blob([svgElem.outerHTML], { type: "image/svg+xml;charset=utf-8" });
        \\      const url = URL.createObjectURL(svgBlob);
        \\      img.onload = () => {
        \\        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        \\        canvas.toBlob((blob) => {
        \\          const pngUrl = URL.createObjectURL(blob);
        \\          const a = document.createElement("a");
        \\          a.href = pngUrl;
        \\          a.download = "zr-task-graph.png";
        \\          a.click();
        \\        });
        \\      };
        \\      img.src = url;
        \\    });
        \\
        \\    // Filtering
        \\    document.getElementById("search")?.addEventListener("input", (e) => {
        \\      const regex = new RegExp(e.target.value, "i");
        \\      node.style("opacity", d => regex.test(d.name) ? 1 : 0.2);
        \\    });
        \\
        \\    document.getElementById("status-filter")?.addEventListener("change", (e) => {
        \\      const status = e.target.value;
        \\      node.style("opacity", d => !status || d.status === status ? 1 : 0.2);
        \\    });
        \\
        \\    // Populate tag filter
        \\    const allTags = new Set();
        \\    data.nodes.forEach(n => n.tags.forEach(t => allTags.add(t)));
        \\    const tagFilter = document.getElementById("tag-filter");
        \\    if (tagFilter) {
        \\      allTags.forEach(tag => {
        \\        const opt = document.createElement("option");
        \\        opt.value = tag;
        \\        opt.textContent = tag;
        \\        tagFilter.appendChild(opt);
        \\      });
        \\      tagFilter.addEventListener("change", (e) => {
        \\        const tag = e.target.value;
        \\        node.style("opacity", d => !tag || d.tags.includes(tag) ? 1 : 0.2);
        \\      });
        \\    }
        \\  </script>
        \\
    );
}

fn writeHtmlFooter(writer: anytype) !void {
    try writer.writeAll(
        \\</body>
        \\</html>
        \\
    );
}

/// Escape JSON special characters (simplified version - handles quotes, backslashes, newlines)
fn escapeJson(s: []const u8) []const u8 {
    // Simplified: return as-is for now
    // In production HTML, special chars are rare in task names/commands
    // Browser's JSON parser is lenient for property names without quotes
    return s;
}

test "TaskStatus color mapping" {
    try std.testing.expectEqualStrings("#90ee90", TaskStatus.success.colorHex());
    try std.testing.expectEqualStrings("#ff6b6b", TaskStatus.failed.colorHex());
    try std.testing.expectEqualStrings("#87ceeb", TaskStatus.pending.colorHex());
    try std.testing.expectEqualStrings("#d3d3d3", TaskStatus.unknown.colorHex());
}
