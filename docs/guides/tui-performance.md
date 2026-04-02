# TUI Performance Optimization Guide

> **Target**: 60 FPS (16ms per frame), <50MB memory for 1000-task graphs, <5ms p99 event latency

---

## Overview

zr uses [sailor](https://github.com/yusa-imit/sailor) v1.31.0's profiling tools to systematically optimize TUI performance. This guide covers profiling workflow, performance budgets, and optimization techniques for zr's four TUI modes.

---

## TUI Modes

| Mode | File | Purpose | Typical Load |
|------|------|---------|--------------|
| **Task Picker** | `src/cli/tui.zig` | Interactive task/workflow selection | 10-100 items |
| **Graph Visualizer** | `src/cli/graph_tui.zig` | Dependency graph tree view | 10-1000 nodes |
| **Live Execution Monitor** | `src/cli/tui_runner.zig` | Real-time task log streaming | 10-100 tasks |
| **Analytics TUI** | `src/cli/analytics_tui.zig` | Execution history dashboard | 100-1000 data points |

---

## Performance Budgets

### Frame Time Budget (60 FPS)

| Component | Budget (ms) | Typical (ms) | Headroom |
|-----------|-------------|--------------|----------|
| **Event processing** | 2ms | 0.5ms | 75% |
| **Widget rendering** | 10ms | 2ms | 80% |
| **Buffer composition** | 2ms | 0.5ms | 75% |
| **Terminal output** | 2ms | 1ms | 50% |
| **Total per frame** | **16ms** | **4ms** | **75%** |

**Target**: All TUI modes should render <16ms per frame (60 FPS) under typical load.

### Memory Budget

| Dataset Size | Peak Memory Budget | Typical Usage | Headroom |
|--------------|-------------------|---------------|----------|
| **Small (10 tasks)** | 5MB | 200KB | 96% |
| **Medium (100 tasks)** | 10MB | 2MB | 80% |
| **Large (1000 tasks)** | **50MB** | **5MB** | **90%** |

**Target**: <50MB peak memory for 1000-task graphs with full execution history.

### Event Latency Budget

| Event Type | p99 Budget (ms) | Typical (ms) | Headroom |
|------------|-----------------|--------------|----------|
| **Keyboard** | 5ms | 1ms | 80% |
| **Mouse click** | 5ms | 1ms | 80% |
| **Mouse drag** | 5ms | 2ms | 60% |
| **Window resize** | 10ms | 5ms | 50% |

**Target**: p99 event processing latency <5ms for interactive events, <10ms for resize.

---

## Profiling Workflow

### 1. Baseline Profiling

Run benchmarks to establish current performance:

```bash
# Run all TUI benchmarks
zig build test-tui-bench

# Example output:
# ok - task picker large dataset frame time within budget
#   avg_frame_time_ms: 0.63
#   frame_time_budget_ms: 16.00
#   peak_memory_bytes: 4641900
#   memory_budget_bytes: 52428800
```

### 2. Identify Hot Spots

Use `TuiProfiler` to collect detailed metrics:

```zig
const tui_profiler = @import("../util/tui_profiler.zig");

pub fn renderInteractiveTui() !void {
    var profiler = tui_profiler.TuiProfiler.init(allocator);
    defer profiler.deinit();

    while (true) {
        profiler.beginScope("frame");
        defer profiler.endScope();

        // Render work
        profiler.beginScope("widgets");
        try renderWidgets();
        profiler.endScope();

        profiler.beginScope("buffer_flush");
        try buffer.flush();
        profiler.endScope();

        // Event handling
        if (try readEvent()) |event| {
            var guard = profiler.trackEvent("keyboard", event_queue_depth);
            defer guard.end();
            try handleEvent(event);
        }
    }

    // Generate report
    const report = try profiler.generateReport();
    try std.io.getStdErr().writer().print(
        "Avg frame time: {d:.2}ms\n",
        .{report.render_metrics.avg_frame_time_ms}
    );
}
```

### 3. Analyze Results

Export flame graph for visualization:

```zig
const flame_json = try profiler.exportFlameGraph();
defer allocator.free(flame_json);

// Save to file
const file = try std.fs.cwd().createFile("profile.json", .{});
defer file.close();
try file.writeAll(flame_json);
```

View in [Speedscope](https://www.speedscope.app/) or Chrome DevTools.

### 4. Optimize Hot Spots

Target scopes with high **self time** (exclusive time) or **call count**:

```
Render Metrics:
- frame: total=1000ms, self=50ms, calls=100 (avg 10ms/call)
  - widgets: total=800ms, self=300ms, calls=100 (avg 8ms/call)
    - list_render: total=500ms, self=500ms, calls=100 (avg 5ms/call) ← HOT SPOT
  - buffer_flush: total=150ms, self=150ms, calls=100 (avg 1.5ms/call)
```

**Optimization priorities**:
1. High self time + high call count → cache results, reduce allocations
2. High total time + many children → optimize child scopes first
3. High self time + low call count → algorithmic improvement (O(n²) → O(n log n))

### 5. Memory Optimization

Identify allocation hot spots:

```
Memory Metrics:
- Peak: 12.5MB, Current: 12.5MB
- Top allocations:
  1. tree_node_labels: 8.5MB (680,000 allocations)
  2. event_buffer: 2.0MB (50,000 allocations)
  3. widget_render: 1.8MB (90,000 allocations)
```

**Optimization techniques**:
- **Object pooling**: Reuse frequently allocated objects (tree nodes, log lines)
- **Arena allocators**: Use arena for frame-scoped allocations, reset per frame
- **Lazy evaluation**: Defer expensive computations until needed
- **String interning**: Reuse repeated strings (task names, file paths)

### 6. Event Loop Optimization

Check event latency percentiles:

```
Event Metrics:
- keyboard: p95=1.2ms, p99=2.5ms, count=500
- mouse: p95=1.8ms, p99=4.2ms, count=1000
- resize: p95=5.1ms, p99=8.7ms, count=50 ← SLOW
```

**Optimization techniques**:
- **Debouncing**: Batch rapid events (mouse drag, resize) and process at frame boundaries
- **Event batching**: Process multiple queued events in one frame
- **Lazy rendering**: Skip frames when no visual changes occurred
- **Partial updates**: Only re-render changed regions (dirty rectangles)

### 7. Verify Regression

After optimization, re-run benchmarks:

```bash
zig build test-tui-bench
```

Ensure all benchmarks still pass (10% regression tolerance).

---

## Common Optimization Techniques

### Widget Caching

Cache expensive widget computations:

```zig
const WidgetCache = struct {
    tree_nodes: ?[]stui.widgets.TreeNode = null,
    last_node_count: usize = 0,

    pub fn getTreeNodes(
        self: *WidgetCache,
        allocator: std.mem.Allocator,
        nodes: []const GraphNode,
    ) ![]stui.widgets.TreeNode {
        // Cache hit: same node count, reuse cached tree
        if (self.tree_nodes != null and nodes.len == self.last_node_count) {
            return self.tree_nodes.?;
        }

        // Cache miss: rebuild tree
        if (self.tree_nodes) |old_nodes| {
            for (old_nodes) |*node| {
                freeTreeNode(allocator, node);
            }
            allocator.free(old_nodes);
        }

        self.tree_nodes = try buildTreeNodes(allocator, nodes);
        self.last_node_count = nodes.len;
        return self.tree_nodes.?;
    }
};
```

**When to use**:
- Widgets with expensive construction (tree nodes, complex layouts)
- Static or semi-static data (task list, graph structure)
- Invalidate cache on data change

### Arena Allocators for Frame-Scoped Work

Reduce allocation overhead for per-frame work:

```zig
pub fn render() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const frame_alloc = arena.allocator();

    // All frame-scoped allocations use arena
    const formatted_text = try std.fmt.allocPrint(frame_alloc, "Status: {s}", .{status});
    const widget_data = try frame_alloc.alloc(WidgetData, widget_count);

    // Render with frame allocations
    try renderWidgets(frame_alloc, widget_data);

    // Arena.deinit() frees all at once (no per-allocation tracking)
}
```

**When to use**:
- Short-lived allocations within a single frame
- High allocation churn (>1000 allocations per frame)
- Reduces allocator bookkeeping overhead

### Lazy Evaluation

Defer expensive computations until needed:

```zig
const LazyTaskList = struct {
    tasks: []const TaskConfig,
    filtered_tasks: ?[]TaskConfig = null,
    filter_text: []const u8 = "",

    pub fn getFiltered(self: *LazyTaskList, allocator: std.mem.Allocator, filter: []const u8) ![]TaskConfig {
        // Only recompute if filter changed
        if (self.filtered_tasks != null and std.mem.eql(u8, self.filter_text, filter)) {
            return self.filtered_tasks.?;
        }

        // Filter lazily
        if (self.filtered_tasks) |old| allocator.free(old);
        self.filtered_tasks = try filterTasks(allocator, self.tasks, filter);
        self.filter_text = filter;
        return self.filtered_tasks.?;
    }
};
```

**When to use**:
- Expensive transformations (filtering, sorting, layout calculation)
- User-triggered actions (search, filter changes)
- Invalidate cache on data change

### Event Batching & Debouncing

Reduce event processing overhead:

```zig
const EventBatcher = struct {
    pending_events: std.ArrayList(Event),
    last_process_time: i64 = 0,
    batch_interval_ms: u32 = 16, // ~60 FPS

    pub fn queueEvent(self: *EventBatcher, event: Event) !void {
        try self.pending_events.append(event);
    }

    pub fn shouldProcess(self: *EventBatcher) bool {
        const now = std.time.milliTimestamp();
        return now - self.last_process_time >= self.batch_interval_ms;
    }

    pub fn processBatch(self: *EventBatcher) !void {
        defer {
            self.pending_events.clearRetainingCapacity();
            self.last_process_time = std.time.milliTimestamp();
        }

        // Process all queued events in one frame
        for (self.pending_events.items) |event| {
            try handleEvent(event);
        }
    }
};
```

**When to use**:
- High-frequency events (mouse drag, scroll wheel)
- Network/I/O events (task output streaming)
- Window resize events

---

## Performance Budget Violation Response

| Violation Type | Threshold | Action |
|----------------|-----------|--------|
| **Frame time >16ms** | 1-3 frames | Log warning, continue |
|                      | >10 consecutive | Drop frames, show "lag" indicator |
|                      | >50 frames | Switch to degraded mode (fewer updates) |
| **Memory >50MB** | 1-10 seconds | Log warning, trigger GC if available |
|                  | >30 seconds | Show "low memory" warning, suggest smaller dataset |
|                  | >80MB | Emergency cleanup, discard old logs |
| **Event latency >10ms p99** | Single event | Log slow event details |
|                             | >10% of events | Show "input lag" warning, suggest disabling animations |

---

## Benchmarking

### Running Benchmarks

```bash
# Run all TUI benchmarks
zig build test-tui-bench

# Run all tests (includes TUI benchmarks)
zig build test-all
```

### Benchmark Output

TAP (Test Anything Protocol) format with performance metrics:

```
1/13 tui_bench.test.TUI benchmark: task picker - small dataset...ok - task picker small dataset frame time within budget
#   avg_frame_time_ms: 0.02
#   frame_time_budget_ms: 16.00
#   peak_memory_bytes: 24600
#   memory_budget_bytes: 52428800
OK
```

### Interpreting Results

- **All tests passing**: Performance within budgets, no action needed
- **Test failing**: Performance regression detected (>10% over budget)
  - Check `avg_frame_time_ms` vs `frame_time_budget_ms` (16ms)
  - Check `peak_memory_bytes` vs `memory_budget_bytes` (50MB)
  - Check `*_p99_latency_ms` vs `event_latency_budget_ms` (5ms)
- **Near budget**: Performance close to limit (>90% of budget)
  - Investigate with TuiProfiler for hot spots
  - Consider optimization before adding new features

---

## Optimization Checklist

Before starting optimization:

- [ ] Run `zig build test-tui-bench` to establish baseline
- [ ] Identify failing benchmarks or near-budget metrics
- [ ] Profile with `TuiProfiler` to find hot spots (high self time, high call count)
- [ ] Choose optimization technique (caching, arena allocators, lazy eval, event batching)
- [ ] Implement optimization in isolated scope
- [ ] Re-run benchmarks to verify improvement (target: 20%+ speedup, no regression)
- [ ] Check memory usage hasn't increased (profile with MemoryTracker)
- [ ] Update this guide if new technique discovered

---

## Tools Reference

### TuiProfiler API

```zig
const tui_profiler = @import("../util/tui_profiler.zig");

// Initialize profiler
var profiler = tui_profiler.TuiProfiler.init(allocator);
defer profiler.deinit();

// Custom thresholds (default: 16ms frame, 5ms event)
var profiler = tui_profiler.TuiProfiler.initWithThresholds(
    allocator,
    10, // render_threshold_ms
    3,  // event_threshold_ms
);

// Render profiling
profiler.beginScope("scope_name");
defer profiler.endScope();

// Memory profiling
profiler.trackMemory("allocation_site", size_bytes);
profiler.trackMemoryFree("allocation_site", size_bytes);

// Event profiling
var guard = profiler.trackEvent("event_type", queue_depth);
defer guard.end();

// Generate report
const report = try profiler.generateReport();
std.debug.print("Avg frame: {d:.2}ms\n", .{report.render_metrics.avg_frame_time_ms});
std.debug.print("Peak memory: {d}MB\n", .{report.memory_metrics.peak_usage_bytes / 1024 / 1024});
std.debug.print("Keyboard p99: {d:.2}ms\n", .{report.event_metrics.get("keyboard").?.p99});

// Export flame graph (JSON)
const json = try profiler.exportFlameGraph();
defer allocator.free(json);

// Control
profiler.reset();      // Clear all data
profiler.enable();     // Resume profiling
profiler.disable();    // Pause profiling
```

### Benchmark API

```zig
// tests/tui_bench.zig
test "my custom benchmark" {
    // Setup
    const allocator = std.testing.allocator;
    var profiler = tui_profiler.TuiProfiler.init(allocator);
    defer profiler.deinit();

    // Benchmark loop
    for (0..100) |_| {
        profiler.beginScope("frame");
        defer profiler.endScope();

        // Workload
        try myTuiMode();
    }

    // Verify
    const report = try profiler.generateReport();
    try std.testing.expect(report.render_metrics.avg_frame_time_ms < 16.0);
}
```

---

## Further Reading

- [sailor Profiling Tools](https://github.com/yusa-imit/sailor/blob/main/docs/optimization.md)
- [sailor Profiler Examples](https://github.com/yusa-imit/sailor/blob/main/examples/profile_demo.zig)
- [Speedscope Flame Graph Viewer](https://www.speedscope.app/)
- [Chrome DevTools Performance](https://developer.chrome.com/docs/devtools/performance/)

---

## Troubleshooting

### "Frame time exceeds budget" warning

**Symptoms**: TUI feels laggy, dropped frames, slow scrolling

**Diagnosis**:
```zig
const report = try profiler.generateReport();
for (report.render_metrics.scope_stats.items) |stat| {
    std.debug.print("{s}: self={d:.2}ms, calls={d}\n",
        .{stat.name, stat.self_time_ms, stat.call_count});
}
```

**Solutions**:
1. High self time → cache widget construction, use arena allocators
2. High call count → reduce render frequency, batch updates
3. Deep nesting → flatten widget hierarchy, avoid unnecessary wrappers

### "Memory usage exceeds budget" warning

**Symptoms**: OOM errors, system slowdown, swap thrashing

**Diagnosis**:
```zig
const hot_spots = try report.memory_metrics.getHotSpots(10);
for (hot_spots) |spot| {
    std.debug.print("{s}: {d}MB ({d} allocs)\n",
        .{spot.location, spot.total_bytes / 1024 / 1024, spot.allocation_count});
}
```

**Solutions**:
1. High allocation count → object pooling, arena allocators
2. Large single allocations → stream processing, windowed rendering
3. Leaks (peak >> current) → check defer/deinit pairing

### "Event latency exceeds budget" warning

**Symptoms**: Unresponsive input, delayed mouse tracking

**Diagnosis**:
```zig
for (report.event_metrics.items) |metric| {
    std.debug.print("{s}: p99={d:.2}ms, max={d:.2}ms\n",
        .{metric.event_type, metric.p99, metric.max_latency_ms});
}
```

**Solutions**:
1. High p99 → event batching, debouncing
2. Occasional spikes (max >> p99) → move heavy work to background thread
3. High queue depth → increase processing frequency, reduce work per event

---

**Last Updated**: 2026-04-03 (Cycle 78, TUI Performance Optimization milestone)
