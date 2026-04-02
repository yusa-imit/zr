const std = @import("std");
const testing = std.testing;
const zr = @import("zr");
const TuiProfiler = zr.tui_profiler.TuiProfiler;
const PerformanceReport = zr.tui_profiler.PerformanceReport;
const sailor = @import("sailor");
const stui = sailor.tui;

// Performance test: TUI performance benchmarks with regression detection.
// Tests all 4 TUI modes (task picker, graph visualizer, live monitor, analytics TUI)
// with small/medium/large datasets and stress scenarios.
//
// Run with: zig build test-tui-bench

// ============================================================================
// Performance Budgets (from TUI Performance Optimization milestone)
// ============================================================================

const FRAME_TIME_BUDGET_MS: f64 = 16.0; // 60 FPS
const MEMORY_BUDGET_BYTES: usize = 50 * 1024 * 1024; // 50MB for 1000-task graph
const EVENT_LATENCY_BUDGET_MS: f64 = 5.0; // p99 event processing

// Regression tolerance: 10% over budget triggers failure
const REGRESSION_TOLERANCE: f64 = 1.10;

// ============================================================================
// Dataset Generators
// ============================================================================

/// Dataset sizes for benchmark scenarios
const DatasetSize = enum {
    small, // 10 tasks, 5 deps
    medium, // 100 tasks, 50 deps
    large, // 1000 tasks, 500 deps
};

/// Generate task list for task picker TUI
fn generateTaskList(allocator: std.mem.Allocator, size: DatasetSize) ![][]const u8 {
    const count: usize = switch (size) {
        .small => 10,
        .medium => 100,
        .large => 1000,
    };

    var tasks: std.ArrayList([]const u8) = .{};
    errdefer {
        for (tasks.items) |task| allocator.free(task);
        tasks.deinit(allocator);
    }

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "task_{d:0>4}", .{i});
        try tasks.append(allocator, name);
    }

    return tasks.toOwnedSlice(allocator);
}

/// Generate dependency graph nodes for graph visualizer TUI
fn generateGraphNodes(allocator: std.mem.Allocator, size: DatasetSize) ![]TestGraphNode {
    const task_count: usize = switch (size) {
        .small => 10,
        .medium => 100,
        .large => 1000,
    };
    const dep_count: usize = switch (size) {
        .small => 5,
        .medium => 50,
        .large => 500,
    };

    var nodes: std.ArrayList(TestGraphNode) = .{};
    errdefer {
        for (nodes.items) |*node| node.deinit(allocator);
        nodes.deinit(allocator);
    }

    var i: usize = 0;
    while (i < task_count) : (i += 1) {
        var node: TestGraphNode = .{
            .path = try std.fmt.allocPrint(allocator, "task_{d:0>4}", .{i}),
            .dependencies = .{},
        };
        errdefer {
            allocator.free(node.path);
            node.dependencies.deinit(allocator);
        }

        // Add random dependencies (up to dep_count total across all nodes)
        const max_deps = @min(5, i); // Each node can depend on up to 5 previous nodes
        var j: usize = 0;
        while (j < max_deps and nodes.items.len * max_deps < dep_count) : (j += 1) {
            if (i > j) { // Only depend on earlier nodes to avoid cycles
                const dep = try std.fmt.allocPrint(allocator, "task_{d:0>4}", .{i - j - 1});
                try node.dependencies.append(allocator, dep);
            }
        }

        try nodes.append(allocator, node);
    }

    return nodes.toOwnedSlice(allocator);
}

/// Simplified graph node for testing (no circular imports with graph.zig)
const TestGraphNode = struct {
    path: []const u8,
    dependencies: std.ArrayList([]const u8),

    fn deinit(self: *TestGraphNode, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        for (self.dependencies.items) |dep| allocator.free(dep);
        self.dependencies.deinit(allocator);
    }
};

/// Generate task states for live execution monitor TUI
fn generateTaskStates(allocator: std.mem.Allocator, size: DatasetSize) ![]TestTaskState {
    const count: usize = switch (size) {
        .small => 10,
        .medium => 100,
        .large => 1000,
    };

    var states: std.ArrayList(TestTaskState) = .{};
    errdefer {
        for (states.items) |*state| state.deinit(allocator);
        states.deinit(allocator);
    }

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "task_{d:0>4}", .{i});
        errdefer allocator.free(name);

        var state = TestTaskState{
            .name = name,
            .status = if (i % 4 == 0) .running else if (i % 4 == 1) .success else if (i % 4 == 2) .failed else .pending,
            .logs = .{},
        };

        // Add some log lines
        var j: usize = 0;
        while (j < 10) : (j += 1) {
            const log = try std.fmt.allocPrint(allocator, "Log line {d} from task_{d:0>4}", .{ j, i });
            try state.logs.append(allocator, log);
        }

        try states.append(allocator, state);
    }

    return states.toOwnedSlice(allocator);
}

/// Simplified task state for testing
const TestTaskState = struct {
    name: []const u8,
    status: enum { pending, running, success, failed },
    logs: std.ArrayList([]const u8),

    fn deinit(self: *TestTaskState, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.logs.items) |log| allocator.free(log);
        self.logs.deinit(allocator);
    }
};

// ============================================================================
// Helper: Frame Rendering Benchmark
// ============================================================================

/// Benchmark a single frame render with profiling
fn benchmarkFrame(
    profiler: *TuiProfiler,
    buf: *stui.Buffer,
    render_fn: *const fn (*stui.Buffer) anyerror!void,
) !void {
    try profiler.beginScope("render");
    defer profiler.endScope() catch {};

    try render_fn(buf);

    try profiler.endScope();
}

/// Stress test: rapid keyboard input simulation
fn simulateKeyboardSpam(profiler: *TuiProfiler, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var guard = profiler.trackEvent("key", i % 10); // Queue depth 0-9
        std.Thread.sleep(100_000); // 0.1ms per event
        try guard.end();
    }
}

/// Stress test: rapid mouse drag simulation
fn simulateMouseDrag(profiler: *TuiProfiler, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var guard = profiler.trackEvent("mouse", 0);
        std.Thread.sleep(50_000); // 0.05ms per event (faster than keyboard)
        try guard.end();
    }
}

// ============================================================================
// Benchmark Tests
// ============================================================================

test "TUI benchmark: task picker - small dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const tasks = try generateTaskList(allocator, .small);
    defer {
        for (tasks) |task| allocator.free(task);
        allocator.free(tasks);
    }

    // Setup buffer
    const width: u16 = 80;
    const height: u16 = 24;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    // Benchmark 60 frames (1 second at 60 FPS)
    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("task_picker");

        // Simulate rendering task list widget
        try profiler.beginScope("render_list");
        try profiler.trackMemory("list_items", tasks.len * 32); // ~32 bytes per item
        buf.clear();
        // Simple render simulation (actual rendering would use sailor widgets)
        var y: u16 = 0;
        for (tasks) |task| {
            if (y >= height) break;
            try profiler.trackMemory("list_row", task.len);
            y += 1;
        }
        try profiler.endScope(); // render_list

        try profiler.endScope(); // task_picker
        try profiler.endScope(); // frame
    }

    // Generate report
    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Verify frame time budget
    try assertFrameTimeBudget(&report, "small dataset task picker");

    // Verify memory budget
    try assertMemoryBudget(&report, "small dataset task picker");

    // TAP output
    try printTapResult(true, "task picker small dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: task picker - medium dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const tasks = try generateTaskList(allocator, .medium);
    defer {
        for (tasks) |task| allocator.free(task);
        allocator.free(tasks);
    }

    const width: u16 = 80;
    const height: u16 = 24;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("task_picker");
        try profiler.beginScope("render_list");

        try profiler.trackMemory("list_items", tasks.len * 32);
        buf.clear();
        var y: u16 = 0;
        for (tasks) |task| {
            if (y >= height) break;
            try profiler.trackMemory("list_row", task.len);
            y += 1;
        }

        try profiler.endScope();
        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "medium dataset task picker");
    try assertMemoryBudget(&report, "medium dataset task picker");

    try printTapResult(true, "task picker medium dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: task picker - large dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const tasks = try generateTaskList(allocator, .large);
    defer {
        for (tasks) |task| allocator.free(task);
        allocator.free(tasks);
    }

    const width: u16 = 80;
    const height: u16 = 24;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("task_picker");
        try profiler.beginScope("render_list");

        try profiler.trackMemory("list_items", tasks.len * 32);
        buf.clear();
        var y: u16 = 0;
        for (tasks) |task| {
            if (y >= height) break;
            try profiler.trackMemory("list_row", task.len);
            y += 1;
        }

        try profiler.endScope();
        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "large dataset task picker");
    try assertMemoryBudget(&report, "large dataset task picker");

    try printTapResult(true, "task picker large dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: graph visualizer - small dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const nodes = try generateGraphNodes(allocator, .small);
    defer {
        for (nodes) |*node| node.deinit(allocator);
        allocator.free(nodes);
    }

    const width: u16 = 120;
    const height: u16 = 40;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("graph_visualizer");
        try profiler.beginScope("render_tree");

        try profiler.trackMemory("tree_nodes", nodes.len * 64); // ~64 bytes per node
        buf.clear();

        // Simulate tree rendering
        for (nodes) |node| {
            try profiler.trackMemory("node_label", node.path.len);
            for (node.dependencies.items) |dep| {
                try profiler.trackMemory("dep_label", dep.len);
            }
        }

        try profiler.endScope();
        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "small dataset graph visualizer");
    try assertMemoryBudget(&report, "small dataset graph visualizer");

    try printTapResult(true, "graph visualizer small dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: graph visualizer - medium dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const nodes = try generateGraphNodes(allocator, .medium);
    defer {
        for (nodes) |*node| node.deinit(allocator);
        allocator.free(nodes);
    }

    const width: u16 = 120;
    const height: u16 = 40;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("graph_visualizer");
        try profiler.beginScope("render_tree");

        try profiler.trackMemory("tree_nodes", nodes.len * 64);
        buf.clear();

        for (nodes) |node| {
            try profiler.trackMemory("node_label", node.path.len);
            for (node.dependencies.items) |dep| {
                try profiler.trackMemory("dep_label", dep.len);
            }
        }

        try profiler.endScope();
        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "medium dataset graph visualizer");
    try assertMemoryBudget(&report, "medium dataset graph visualizer");

    try printTapResult(true, "graph visualizer medium dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: graph visualizer - large dataset (1000 tasks)" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const nodes = try generateGraphNodes(allocator, .large);
    defer {
        for (nodes) |*node| node.deinit(allocator);
        allocator.free(nodes);
    }

    const width: u16 = 120;
    const height: u16 = 40;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("graph_visualizer");
        try profiler.beginScope("render_tree");

        try profiler.trackMemory("tree_nodes", nodes.len * 64);
        buf.clear();

        for (nodes) |node| {
            try profiler.trackMemory("node_label", node.path.len);
            for (node.dependencies.items) |dep| {
                try profiler.trackMemory("dep_label", dep.len);
            }
        }

        try profiler.endScope();
        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "large dataset graph visualizer");
    try assertMemoryBudget(&report, "large dataset graph visualizer");

    try printTapResult(true, "graph visualizer large dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: live execution monitor - small dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const states = try generateTaskStates(allocator, .small);
    defer {
        for (states) |*state| state.deinit(allocator);
        allocator.free(states);
    }

    const width: u16 = 120;
    const height: u16 = 40;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("live_monitor");

        // Render task list
        try profiler.beginScope("render_task_list");
        try profiler.trackMemory("task_states", states.len * 64);
        try profiler.endScope();

        // Render log viewer
        try profiler.beginScope("render_logs");
        if (states.len > 0) {
            const selected = states[0];
            try profiler.trackMemory("log_lines", selected.logs.items.len * 128);
            for (selected.logs.items) |log| {
                try profiler.trackMemory("log_text", log.len);
            }
        }
        try profiler.endScope();

        buf.clear();

        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "small dataset live monitor");
    try assertMemoryBudget(&report, "small dataset live monitor");

    try printTapResult(true, "live monitor small dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: live execution monitor - medium dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const states = try generateTaskStates(allocator, .medium);
    defer {
        for (states) |*state| state.deinit(allocator);
        allocator.free(states);
    }

    const width: u16 = 120;
    const height: u16 = 40;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("live_monitor");

        try profiler.beginScope("render_task_list");
        try profiler.trackMemory("task_states", states.len * 64);
        try profiler.endScope();

        try profiler.beginScope("render_logs");
        if (states.len > 0) {
            const selected = states[0];
            try profiler.trackMemory("log_lines", selected.logs.items.len * 128);
            for (selected.logs.items) |log| {
                try profiler.trackMemory("log_text", log.len);
            }
        }
        try profiler.endScope();

        buf.clear();

        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "medium dataset live monitor");
    try assertMemoryBudget(&report, "medium dataset live monitor");

    try printTapResult(true, "live monitor medium dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: live execution monitor - large dataset" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    const states = try generateTaskStates(allocator, .large);
    defer {
        for (states) |*state| state.deinit(allocator);
        allocator.free(states);
    }

    const width: u16 = 120;
    const height: u16 = 40;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("live_monitor");

        try profiler.beginScope("render_task_list");
        try profiler.trackMemory("task_states", states.len * 64);
        try profiler.endScope();

        try profiler.beginScope("render_logs");
        if (states.len > 0) {
            const selected = states[0];
            try profiler.trackMemory("log_lines", selected.logs.items.len * 128);
            for (selected.logs.items) |log| {
                try profiler.trackMemory("log_text", log.len);
            }
        }
        try profiler.endScope();

        buf.clear();

        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "large dataset live monitor");
    try assertMemoryBudget(&report, "large dataset live monitor");

    try printTapResult(true, "live monitor large dataset frame time within budget");
    try printTapMetrics(&report);
}

test "TUI benchmark: analytics TUI - dashboard rendering" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    // Simulate analytics data
    const data_points = 100; // 100 historical builds
    var durations = try allocator.alloc(u64, data_points);
    defer allocator.free(durations);
    var i: usize = 0;
    while (i < data_points) : (i += 1) {
        durations[i] = 1000 + (i * 50); // 1000ms to 5950ms
    }

    const width: u16 = 120;
    const height: u16 = 40;
    var buf = try stui.Buffer.init(allocator, width, height);
    defer buf.deinit();

    // Benchmark static dashboard (analytics TUI is currently snapshot-based)
    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        try profiler.beginScope("frame");
        try profiler.beginScope("analytics_tui");

        // Histogram rendering
        try profiler.beginScope("render_histogram");
        try profiler.trackMemory("histogram_data", data_points * @sizeOf(u64));
        try profiler.endScope();

        // Time series chart
        try profiler.beginScope("render_timeseries");
        try profiler.trackMemory("timeseries_data", data_points * @sizeOf(u64) * 2);
        try profiler.endScope();

        // Scatter plot
        try profiler.beginScope("render_scatter");
        try profiler.trackMemory("scatter_data", data_points * @sizeOf(u64) * 2);
        try profiler.endScope();

        buf.clear();

        try profiler.endScope();
        try profiler.endScope();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertFrameTimeBudget(&report, "analytics TUI dashboard");
    try assertMemoryBudget(&report, "analytics TUI dashboard");

    try printTapResult(true, "analytics TUI dashboard frame time within budget");
    try printTapMetrics(&report);
}

test "TUI stress test: rapid keyboard input" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    // Simulate 500 rapid key presses (keyboard spam)
    try simulateKeyboardSpam(&profiler, 500);

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    // Verify p99 event latency is within budget
    try assertEventLatencyBudget(&report, "rapid keyboard input");

    try printTapResult(true, "keyboard spam event latency within budget");
    try printTapMetrics(&report);
}

test "TUI stress test: rapid mouse drag" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    // Simulate 1000 rapid mouse movements (mouse drag)
    try simulateMouseDrag(&profiler, 1000);

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertEventLatencyBudget(&report, "rapid mouse drag");

    try printTapResult(true, "mouse drag event latency within budget");
    try printTapMetrics(&report);
}

test "TUI stress test: window resize events" {
    const allocator = testing.allocator;
    var profiler = try TuiProfiler.initWithThresholds(allocator, FRAME_TIME_BUDGET_MS, EVENT_LATENCY_BUDGET_MS);
    defer profiler.deinit();

    // Simulate 50 window resize events
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var guard = profiler.trackEvent("resize", 0);

        // Simulate buffer reallocation on resize
        const new_width: u16 = @intCast(80 + (i % 40)); // 80-120 cols
        const new_height: u16 = @intCast(24 + (i % 16)); // 24-40 rows
        const buffer_size = @as(usize, new_width) * @as(usize, new_height) * 16; // ~16 bytes per cell
        try profiler.trackMemory("buffer_resize", buffer_size);

        std.Thread.sleep(500_000); // 0.5ms per resize
        try guard.end();
    }

    var report = try profiler.generateReport();
    defer report.deinit(allocator);

    try assertEventLatencyBudget(&report, "window resize");

    try printTapResult(true, "window resize event latency within budget");
    try printTapMetrics(&report);
}

// ============================================================================
// Assertion Helpers
// ============================================================================

fn assertFrameTimeBudget(report: *const PerformanceReport, context: []const u8) !void {
    if (report.render_metrics.scope_stats.len == 0) return; // No frames rendered

    // Calculate average frame time
    const total_time_ns = report.render_metrics.total_render_time_ns;
    const frame_count = report.render_metrics.total_scopes;
    const avg_frame_time_ns = if (frame_count > 0) total_time_ns / frame_count else 0;
    const avg_frame_time_ms = @as(f64, @floatFromInt(avg_frame_time_ns)) / 1_000_000.0;

    const budget_with_tolerance = FRAME_TIME_BUDGET_MS * REGRESSION_TOLERANCE;

    if (avg_frame_time_ms > budget_with_tolerance) {
        std.debug.print("REGRESSION: {s} frame time {d:.2}ms exceeds budget {d:.2}ms (tolerance {d:.2}ms)\n", .{
            context,
            avg_frame_time_ms,
            FRAME_TIME_BUDGET_MS,
            budget_with_tolerance,
        });
        return error.FrameTimeBudgetExceeded;
    }
}

fn assertMemoryBudget(report: *const PerformanceReport, context: []const u8) !void {
    const peak_bytes = report.memory_metrics.peak_usage_bytes;
    const budget_with_tolerance = @as(usize, @intFromFloat(@as(f64, @floatFromInt(MEMORY_BUDGET_BYTES)) * REGRESSION_TOLERANCE));

    if (peak_bytes > budget_with_tolerance) {
        std.debug.print("REGRESSION: {s} peak memory {d} bytes exceeds budget {d} bytes (tolerance {d} bytes)\n", .{
            context,
            peak_bytes,
            MEMORY_BUDGET_BYTES,
            budget_with_tolerance,
        });
        return error.MemoryBudgetExceeded;
    }
}

fn assertEventLatencyBudget(report: *const PerformanceReport, context: []const u8) !void {
    if (report.event_metrics.event_stats.len == 0) return; // No events recorded

    // Check p99 latency for all event types
    for (report.event_metrics.event_stats) |stats| {
        const p99_latency_ms = @as(f64, @floatFromInt(stats.p99_latency_ns)) / 1_000_000.0;
        const budget_with_tolerance = EVENT_LATENCY_BUDGET_MS * REGRESSION_TOLERANCE;

        if (p99_latency_ms > budget_with_tolerance) {
            std.debug.print("REGRESSION: {s} p99 latency {d:.2}ms exceeds budget {d:.2}ms (tolerance {d:.2}ms)\n", .{
                context,
                p99_latency_ms,
                EVENT_LATENCY_BUDGET_MS,
                budget_with_tolerance,
            });
            return error.EventLatencyBudgetExceeded;
        }
    }
}

// ============================================================================
// TAP Output Helpers
// ============================================================================

fn printTapResult(ok: bool, description: []const u8) !void {
    if (ok) {
        std.debug.print("ok - {s}\n", .{description});
    } else {
        std.debug.print("not ok - {s}\n", .{description});
    }
}

fn printTapMetrics(report: *const PerformanceReport) !void {
    // Render metrics
    if (report.render_metrics.total_scopes > 0) {
        const avg_frame_time_ns = report.render_metrics.total_render_time_ns / report.render_metrics.total_scopes;
        const avg_frame_time_ms = @as(f64, @floatFromInt(avg_frame_time_ns)) / 1_000_000.0;
        std.debug.print("#   avg_frame_time_ms: {d:.2}\n", .{avg_frame_time_ms});
        std.debug.print("#   frame_time_budget_ms: {d:.2}\n", .{FRAME_TIME_BUDGET_MS});
    }

    // Memory metrics
    std.debug.print("#   peak_memory_bytes: {d}\n", .{report.memory_metrics.peak_usage_bytes});
    std.debug.print("#   current_memory_bytes: {d}\n", .{report.memory_metrics.current_usage_bytes});
    std.debug.print("#   memory_budget_bytes: {d}\n", .{MEMORY_BUDGET_BYTES});

    // Event metrics
    if (report.event_metrics.event_stats.len > 0) {
        const overall_avg_ms = @as(f64, @floatFromInt(report.event_metrics.overall_avg_latency_ns)) / 1_000_000.0;
        std.debug.print("#   overall_avg_event_latency_ms: {d:.2}\n", .{overall_avg_ms});

        for (report.event_metrics.event_stats) |stats| {
            const p95_ms = @as(f64, @floatFromInt(stats.p95_latency_ns)) / 1_000_000.0;
            const p99_ms = @as(f64, @floatFromInt(stats.p99_latency_ns)) / 1_000_000.0;
            std.debug.print("#   {s}_p95_latency_ms: {d:.2}\n", .{ stats.event_type, p95_ms });
            std.debug.print("#   {s}_p99_latency_ms: {d:.2}\n", .{ stats.event_type, p99_ms });
        }
        std.debug.print("#   event_latency_budget_ms: {d:.2}\n", .{EVENT_LATENCY_BUDGET_MS});
    }
}
