# zr v1.58.0 — Post-v1.0 Enhancements (Task Estimation, Validation, Visualization)

**Release Date**: 2026-03-30

This release delivers three major post-v1.0 enhancement milestones focused on workflow intelligence, configuration quality, and interactive visualization.

---

## 🎯 New Features

### Task Estimation & Time Tracking

Complete task duration estimation and time tracking system for predictive workflow planning.

**Core Components**:
- **Statistics Module** (`src/history/stats.zig`): Percentile calculations (p50/p90/p99), standard deviation, anomaly detection (2x p90 threshold)
- **Estimate Command**: Enhanced `zr estimate <task|workflow>` with per-task and workflow estimation
  - Critical path calculation for parallel workflow stages (MAX for parallel, SUM for sequential)
  - JSON export format with full statistical breakdown
  - P90/P99 percentiles and anomaly thresholds in text output
- **Duration Displays**:
  - `zr list`: Shows `[~8.2s (avg), 0.6-27.6s range]` estimates alongside task names
  - `zr run --dry-run`: Displays per-task estimates and total estimated workflow time
  - TUI Progress Bars: Live ETA display based on historical averages (dynamic updates, human-readable formatting)

**Use Cases**:
```bash
# Get task duration prediction
zr estimate build
# Output: Estimated duration: ~362ms (avg), 104-723ms range (p50: 315ms, p90: 650ms, p99: 700ms)

# Predict workflow completion time
zr estimate test-workflow --format=json
# Output: {"stages": [...], "total_ms": 972, "critical_path": [...]}

# Preview workflow with time estimates
zr run test-workflow --dry-run
# Shows: build [~362ms] → test [~8.2s] → Total: ~9s
```

**Technical Details**:
- Reads execution history from `.zr_history` (last 1000 records)
- Handles missing history gracefully (no estimates shown, warning in estimate command)
- Anomaly detection warns when task exceeds 2x p90 threshold
- Integration: 7 new tests (estimate command, list/dry-run integration, workflow estimation)
- Coverage: 9 new unit tests for ETA calculations and formatting

---

### Configuration Validation Enhancements

Advanced configuration validation with expression syntax checking, performance warnings, and plugin schema validation.

**New Validation Rules**:
1. **Expression Syntax Validation**: Uses `expr.evalConditionWithDiag` to validate all task conditions and `deps_if` expressions
   - Reports parse errors with diagnostic context and stack traces
   - Validates before execution to catch syntax errors early
2. **Performance Warnings**:
   - Warns when task count >100 (potential execution complexity)
   - Detects deep dependency chains (>10 levels via recursive depth calculation)
   - Helps identify performance bottlenecks before execution
3. **Plugin Schema Validation**:
   - Checks required `source` field presence in plugin configurations
   - Validates source format (protocol or path)
   - Warns about malformed plugin sources
4. **Import Collision Detection**: Warns about namespace collisions with multiple imports

**Strict Mode Enhancement**:
- `zr validate --strict` now treats warnings as errors (exit code 1)
- Critical for CI pipelines requiring zero-warning configurations

**Examples**:
```bash
# Validate with warnings as errors (CI mode)
zr validate --strict
# Exits with code 1 if any warnings detected

# Check for performance issues
zr validate
# Warns: "Deep dependency chain detected: task 'build' has depth 12 (>10 levels)"
```

**Technical Details**:
- Enhanced `src/cli/validate.zig` with comprehensive error reporting
- Expression validation integrated with existing expression engine
- Recursive depth calculation for dependency chain analysis
- Integration: 7 new tests (expression validation, performance warnings, plugin validation, import collisions)
- All 1223 unit tests passing

---

### Interactive Workflow Visualizer

Interactive HTML/SVG-based workflow visualization with D3.js for modern web-based task graph analysis.

**Interactive Features**:
- **Task Details Panel**: Click nodes to view full metadata
  - Shows: cmd, description, dependencies, environment variables, tags, duration
  - Formatted output with labeled fields and code-style backgrounds
  - Duration from execution history (formatted as ms/s/m)
- **Status Color Coding**: Loads `.zr_history` for task status
  - Success (green), Failed (red), Pending (blue), Unknown (gray)
  - Finds most recent execution record per task (backward search for efficiency)
- **Critical Path Highlighting**: Recursive BFS depth calculation on DAG
  - Builds temporary DAG from node dependencies
  - Calculates max depth for each node from entry points
  - Marks nodes at `max_depth` as critical path (golden border)
  - Links between critical nodes also highlighted
- **Filter Controls**:
  - Regex search: filter nodes by name pattern
  - Status dropdown: show only success/failed/pending/unknown tasks
  - Tag dropdown: auto-populated from all task tags
  - Reset zoom button to restore view
- **Export Functionality**:
  - SVG export: direct outerHTML blob download
  - PNG export: converts SVG to canvas with 2x scaling for quality
  - Downloads named `zr-task-graph.svg` or `.png`

**Visual Design**:
- D3.js v7 force-directed graph with zoom/pan/drag behaviors
- Standalone HTML output with embedded JSON data (no external dependencies)
- Dark theme UI matching zr's aesthetic
- Fixed sidebar for task details, bottom-left legend
- Curved links with arrow markers, responsive layout

**Usage**:
```bash
# Generate interactive visualization
zr graph --interactive > workflow.html
# Or: zr graph --type=tasks --interactive > workflow.html

# Open in browser
open workflow.html
```

**Technical Details**:
- Implementation: `src/cli/graph_interactive.zig` (core renderer), `src/cli/graph.zig` (command integration)
- Added `GraphType` enum (workspace, tasks), `GraphFormat.interactive`
- `--interactive` flag implies `--type=tasks`
- Loads `history_store.Store` and passes records to renderer
- Backward compatible: workspace graphs unchanged
- Integration: 10 tests in `tests/graph_interactive_test.zig` (3907-3916)
  - HTML structure validation, task details inclusion, critical path presence
  - Filter controls, export buttons, empty config handling
  - Complex multi-level dependency graphs

**Deferred**:
- `--watch` flag (requires scheduler integration, future enhancement)

---

## 📊 Statistics

- **Commits since v1.57.0**: 47 commits
- **Test Coverage**: 1224/1232 unit tests passing (100% pass rate), 8 skipped
- **Integration Tests**: 24 new integration tests (7 validation, 7 estimation, 10 interactive graph)
- **Lines of Code**: +1,500 LOC (stats module, validation enhancements, interactive renderer)

---

## 🔧 Technical Improvements

- **Refactored Estimate Command**: Reduced from 249 LOC to 53 LOC (-196 LOC) by extracting shared statistics module
- **Expression Diagnostics**: Integrated `evalConditionWithDiag` for detailed parse error reporting
- **Recursive Depth Calculation**: Efficient BFS-based dependency chain analysis
- **D3.js Integration**: Modern web-based visualization without external build dependencies

---

## 🧪 Testing

All features comprehensively tested:
- Task Estimation: 7 integration tests + 9 unit tests (workflow estimation, ETA calculations, format helpers)
- Configuration Validation: 7 integration tests (expression syntax, performance warnings, plugin schema, strict mode)
- Interactive Visualizer: 10 integration tests (HTML structure, task details, critical path, filters, export)

---

## 🚀 Migration Guide

### From v1.57.0 to v1.58.0

**No Breaking Changes** — All features are additive enhancements.

1. **Task Estimation**: Automatically works if `.zr_history` exists. No configuration needed.
2. **Validation Enhancements**: Existing configs validated with new rules. Use `--strict` in CI for zero-warning enforcement.
3. **Interactive Visualizer**: New command option, doesn't affect existing `zr graph` usage.

**New Commands**:
```bash
zr estimate <task|workflow>         # Predict duration
zr estimate <task> --format=json    # JSON export
zr validate --strict                # Treat warnings as errors (CI)
zr graph --interactive > out.html   # Generate interactive viz
```

---

## 🎉 What's Next

All READY milestones from the post-v1.0 roadmap are now complete. Future development will focus on:
- Unblocking zuda migrations (graph algorithms, work-stealing deque)
- New milestone establishment based on user feedback
- Performance optimizations and polish

---

## 📝 Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for complete commit history.

---

**Credits**: Developed by Yusa × Claude Sonnet 4.5 (autonomous development workflow)
