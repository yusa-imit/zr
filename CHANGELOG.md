# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.43.0] - 2026-03-16

### Changed
- **Sailor v1.15.0 Migration**
  - Upgraded sailor dependency from v1.14.0 to v1.15.0
  - Fixed async_loop.zig dangling pointer and race conditions (thread safety)
  - Implemented XTGETTCAP terminal capability querying
  - Replaced environment variable detection with proper capability negotiation
  - Enhanced Sixel and Kitty graphics protocol detection
  - Added 13 new edge case tests for Windows, Linux, macOS
  - Improved terminal size detection on all platforms
  - Better handling of non-TTY environments
  - Fixed 6 memory leaks in repl.zig and editor.zig
  - Multi-platform native testing in CI (not just cross-compilation)
  - Tests run on real VMs: ubuntu-latest, macos-13, macos-latest, windows-latest
  - All optimization modes tested (Debug, ReleaseSafe, ReleaseSmall, ReleaseFast)
  - No breaking changes — drop-in replacement for v1.14.0

### Developer Notes
- Total unit tests: 845/853 (8 skipped, 0 leaks)
- Total integration tests: 957/958 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)
- Sailor library: 1243 tests passing, 6 cross-compile targets verified

## [1.39.0] - 2026-03-16

### Changed
- **Sailor v1.14.0 Migration**
  - Upgraded sailor dependency from v1.13.1 to v1.14.0
  - Memory pooling system reduces allocations for frequently created objects
  - Render profiling tools identify slow widgets and detect bottlenecks
  - Virtual widget rendering only renders widgets in viewport, skips off-screen
  - Incremental layout solver caches layout results, only recomputes on changes
  - Buffer compression reduces memory footprint for large TUI applications
  - All features are opt-in and backward compatible

### Developer Notes
- Total unit tests: 845/853 (8 skipped, 0 leaks)
- Total integration tests: 967/968 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)
- No breaking changes from sailor v1.14.0

## [1.34.0] - 2026-03-14

### Added
- **Workflow Retry Budget Integration** (v1.34.0)
  - Added `retry_budget` field to `SchedulerConfig` struct for workflow-level retry limiting
  - Initialize `RetryBudgetTracker` from workflow config when executing stages
  - Updated `cmdWorkflow` to extract and pass workflow `retry_budget` to scheduler
  - Retry budget is now shared across all stages in multi-stage workflows
  - 3 new integration tests (941-943) covering workflow retry scenarios
  - Documentation updated with multi-stage workflow examples

### Changed
- Workflow retry budget (from v1.30.0 infrastructure) is now fully functional
- Multi-stage workflows can limit total retries across all stages with a single `retry_budget` value

### Developer Notes
- Total unit tests: 820/828 (8 skipped, 0 leaks)
- Total integration tests: 942/943 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)

## [1.33.0] - 2026-03-14

### Added
- **Advanced TUI Data Visualization** (v1.33.0)
  - Created `src/cli/analytics_tui.zig` with three data visualization widgets
  - Histogram for task duration distribution (5 bins)
  - TimeSeriesChart for build time trends (last 50 executions)
  - ScatterPlot for cache hit rate vs build time correlation
  - FlexBox layout for responsive three-panel dashboard
  - Viewport clipping for efficient large graph rendering
  - Added `--tui` flag to `zr analytics` command

### Changed
- Graph rendering now uses viewport clipping for better performance with large graphs
- Virtual buffer (2x terminal height) reduces memory usage

### Developer Notes
- Total unit tests: 820/828 (8 skipped, 0 leaks)
- Total integration tests: 939/940 (1 skipped, 0 leaks)
- Uses sailor v1.6.0/v1.7.0 data visualization widgets

## [1.32.0] - 2026-03-14

### Changed
- **Sailor Library Migration** (v1.10.0 → v1.12.0)
  - Upgraded sailor dependency from v1.10.0 to v1.12.0
  - v1.11.0 features (terminal graphics & effects):
    - Particle effects system (confetti, sparkles for celebrations)
    - Blur/transparency effects for visual depth
    - Sixel/Kitty graphics protocol support for inline images
    - Animated widget transitions
  - v1.12.0 features (enterprise & accessibility):
    - Session recording & playback for debugging TUI interactions
    - Audit logging infrastructure for compliance tracking
    - High contrast WCAG AAA themes (dark, light, amber, green)
    - Screen reader enhancements (OSC8 hyperlinks, ARIA attributes, JSON modes)
    - Keyboard-only navigation improvements (skip links, focus indicators)

### Developer Notes
- All features are opt-in and non-breaking
- Total unit tests: 819/827 (8 skipped, 0 leaks)
- Total integration tests: 939/940 (1 skipped, 0 leaks)
- CI status: GREEN (all cross-compile targets passing)

## [1.31.0] - 2026-03-13

### Added
- **Checkpoint/Resume for Long-Running Tasks** (`src/exec/checkpoint.zig`)
  - CheckpointStorage interface with vtable for pluggable backends
  - FileSystemStorage backend with JSON format
  - Task stdout monitoring for "CHECKPOINT: <data>" markers
  - Automatic checkpoint save (respecting interval_ms config)
  - Resume protocol via ZR_CHECKPOINT environment variable
  - Scheduler integration with worker thread support
  - 3 new integration tests (938-940)
  - Comprehensive documentation in configuration.md

### Developer Notes
- Total unit tests: 819/827 (8 skipped, 0 leaks)
- Total integration tests: 939/940 (1 skipped, 0 leaks)
- Checkpoint monitoring only works when inherit_stdio=false
- Interactive tasks cannot emit checkpoints (limitation documented)

## [1.30.0] - 2026-03-13

### Added
- **Enhanced Error Recovery** (`src/exec/scheduler.zig`)
  - Circuit breaker pattern with failure threshold tracking
  - Circuit states: closed → open (threshold exceeded) → half-open (reset timeout)
  - Workflow-level retry budget for limiting total retry attempts
  - Per-task circuit breaker state isolation
  - 9 new unit tests for circuit breaker and retry budget
  - 5 new integration tests (933-937)
  - Comprehensive documentation in configuration.md

### Developer Notes
- Total unit tests: 816/824 (8 skipped, 0 leaks)
- Total integration tests: 937/937 (936 passed, 1 skipped, 0 leaks)
- Circuit breaker state resets between zr run invocations

## [1.29.0] - 2026-03-13

### Added
- **Task Template System** (`src/cli/template.zig`)
  - Reusable task templates with parameter substitution
  - template and params fields in Task struct
  - Automatic template application with field merging
  - CLI commands: zr template list/show/apply
  - 12 new integration tests (921-932)
  - Comprehensive documentation in configuration.md

### Developer Notes
- Total unit tests: 807/815 (8 skipped, 0 leaks)
- Total integration tests: 931/932 (1 skipped, 0 leaks)

## [1.28.0] - 2026-03-12

### Added
- **Interactive TUI with Mouse Support** (`src/cli/tui_mouse.zig`)
  - Mouse input integration module with InputEvent union
  - SGR mouse event parsing (click/drag/scroll)
  - Interactive task picker mouse support (left-click to select)
  - Graph TUI mouse support (click nodes, scroll to navigate)
  - Live execution TUI mouse support (click tasks, scroll logs)
  - Thread-safe mouse tracking in background inputThread
  - 5 new unit tests for mouse input handling
  - Updated documentation with navigation instructions

### Developer Notes
- Total unit tests: 801/809 (8 skipped, 0 leaks)
- Total integration tests: 919/920 (1 skipped, 0 leaks)
- Leveraged sailor v1.10.0 mouse input features

## [1.27.0] - 2026-03-12

### Added
- **Live Resource Monitoring Dashboard** (`src/cli/monitor.zig`)
  - MonitorDashboard component for real-time task execution monitoring
  - ASCII bar charts for CPU usage (10 rows × 60 columns)
  - ASCII bar charts for memory usage (8 rows × 60 columns)
  - Task status table with color-coded status (running/completed/failed)
  - Bottleneck detection algorithm (CPU > 80%, memory > 500MB)
  - Circular buffer history (60 data points at 1Hz update interval)
  - Foundation for future live TUI monitoring features

### Developer Notes
- Total unit tests: 796/804 (8 skipped, 0 leaks) — +4 new tests
- Total integration tests: 919/920 (1 skipped, 0 leaks)
- New tests: MonitorDashboard init/deinit, addTask, formatBytes, estimateBytesLen
- Existing `--monitor` flag integration tests (916-920) continue to pass
- Remote monitoring server (WebSocket) deferred to v1.31.0

## [1.22.0] - 2026-03-09

### Changed
- **Sailor Library Upgrade**: Updated from v1.5.0 to v1.7.0
  - **v1.6.0 features**: Data visualization widgets (ScatterPlot, Histogram, TimeSeriesChart, Heatmap, PieChart)
  - **v1.7.0 features**: Advanced layout and rendering
    - FlexBox layout: CSS flexbox-inspired with justify/align support
    - Viewport clipping: Efficient rendering of large virtual buffers
    - Shadow & 3D border effects: Visual depth for widgets
    - Custom widget traits: Extensible widget protocol
    - Layout caching: LRU cache for constraint computation
  - All new features are opt-in and non-breaking
  - Enables future TUI enhancements with advanced data visualization and layout capabilities

### Developer Notes
- Total unit tests: 769/777 (8 skipped, 0 leaks)
- Total integration tests: 894/894 (100% pass rate)
- No breaking changes, seamless upgrade from v1.5.0

## [1.21.0] - 2026-03-09

### Added
- **TUI Testing Framework**: Comprehensive test coverage for all TUI modes using sailor v1.5.0 MockTerminal
  - **MockTerminal snapshot tests**: 19 new unit tests for pixel-perfect TUI rendering verification
  - **TUI Runner tests**: 5 tests covering empty runner, single task, multiple states, resize events, char/style access
  - **Graph TUI tests**: 8 tests including buildTreeNodes unit tests and MockTerminal snapshot tests
  - **List TUI tests**: 6 tests for empty items, single task, multiple items, navigation, truncation, and helper functions
  - All tests verify proper rendering, selection highlighting, and layout consistency
- **Documentation**: Added TUI testing guide to CONTRIBUTING.md with MockTerminal usage examples

### Developer Notes
- Total unit tests: 769 (up from 763), all integration tests pass (894/894)
- Event bus and command pattern integration deferred to future versions as optional enhancements
- All TUI modes (runner, graph, list) now have comprehensive snapshot test coverage

## [1.18.0] - 2026-03-08

### Added
- **Conditional Task Execution**: Control task execution with powerful conditional expressions
  - **Git predicates**: Check repository state in task conditions
    - `git.branch`: Current branch name (e.g., `skip_if = "git.branch != 'main'"`)
    - `git.tag`: Current tag if HEAD is tagged (e.g., `skip_if = "git.tag == 'v1.0.0'"`)
    - `git.dirty`: Boolean indicating uncommitted changes (e.g., `skip_if = "git.dirty"`)
    - Supports `==` and `!=` operators for branch/tag comparisons
  - **skip_if**: Skip task execution when condition evaluates to true
    - Evaluated before task execution
    - Failed conditions default to `false` (task runs)
    - Skipped tasks report success with zero exit code
    - Example: `skip_if = "env.CI != 'true'"` (skip unless in CI)
  - **output_if**: Control task output visibility based on conditions
    - Evaluated at task execution time
    - Failed conditions default to `true` (show output)
    - Example: `output_if = "env.DEBUG == 'true'"` (hide output unless debugging)
  - **Integration tests**: 9 comprehensive tests covering all predicates and conditions

### Fixed
- Parser state bleed between TOML sections (caused incorrect task field assignments)
- Missing `!=` operator support in git predicate expressions
- CI test failures due to inconsistent git default branch naming

### Developer Notes
- All 746 unit tests pass (8 skipped), all 890 integration tests pass
- Comprehensive error diagnostics for condition failures deferred to v1.20.0

## [1.17.0] - 2026-03-08

### Added
- **Advanced Watch Mode**: Enhanced file watching with debouncing and pattern filtering
  - **Debouncing**: Configurable delay (`debounce_ms`) to coalesce rapid file changes
    - Default: 300ms delay before triggering task execution
    - Set to 0 to disable debouncing (execute immediately on each change)
    - Prevents excessive rebuilds during rapid editing sessions
  - **Pattern-based filtering**: Glob patterns for precise control over watched files
    - `patterns`: Include only specific file types (e.g., `["**/*.zig", "*.toml"]`)
    - `exclude_patterns`: Exclude directories/files (e.g., `["**/node_modules/**", "**/.git/**"]`)
    - Exclude patterns take precedence over include patterns
    - Empty include list watches all files (unless excluded)
  - **Watch configuration in TOML**: `[tasks.*.watch]` section for task-specific settings
    - `debounce_ms`: Delay in milliseconds (default: 300)
    - `patterns`: Array of glob patterns for inclusion
    - `exclude_patterns`: Array of glob patterns for exclusion
    - `mode`: "native" or "polling" (auto-selects if null)
  - **Enhanced watcher implementation**: Updated `src/watch/watcher.zig` with filtering logic
    - New `WatcherOptions` struct for configuration
    - `matchesPatterns()` method for glob-based filtering
    - Debouncing logic with timestamp tracking and event coalescing
    - Backwards compatible: existing code works without changes
  - **CLI integration**: Watch mode automatically applies task configuration
    - Shows active settings in output: "(using native mode, debounce: 500ms, patterns: 2)"
    - Pattern and debounce info displayed when configured
  - **Tests**: 3 new unit tests for pattern filtering (include, exclude, combined)
  - **Documentation**: Comprehensive guide in `docs/guides/configuration.md`
    - Complete field reference with examples
    - Usage patterns and best practices
    - Pattern matching rules and debouncing behavior

### Changed
- Watcher initialization now requires `WatcherOptions` parameter (backwards compatible with `.{}`)
- Watch mode output shows configuration details when debouncing or patterns are active

### Developer Notes
- All 746 unit tests pass (8 skipped), all 881 integration tests pass
- Existing watch_test.zig integration tests verify TOML parsing of watch config

## [1.16.0] - 2026-03-07

### Added
- **Task Execution Analytics**: Resource usage tracking and enhanced reporting
  - **Resource tracking**: Peak memory and average CPU monitoring
    - Sampled at 100ms intervals during task execution
    - Peak memory recorded in bytes (max RSS usage)
    - Average CPU calculated from samples (percentage)
  - **Analytics collector**: Extended TaskStats with resource metrics
    - Integrated into scheduler's result tracking
    - Zero configuration required
  - **Enhanced reports**: HTML/JSON output includes resource columns
    - Peak memory displayed in human-readable format (MB/GB)
    - Average CPU shown as percentage
    - Sortable columns in HTML reports
  - **Tests**: 2 new integration tests (874-875) verifying resource tracking
  - **Documentation**: Updated commands.md with resource tracking examples

### Changed
- Analytics reports now include peak_memory_bytes and avg_cpu_percent columns
- HTML report tables extended with resource usage metrics

## [1.15.0] - 2026-03-07

### Added
- **Workspace-wide cache invalidation**: Clear cache for all workspace members at once
  - `zr cache clear --workspace` clears cache for root and all member projects
  - `zr cache clear --member <path>` clears cache for specific workspace member
  - Enables efficient cache management in multi-project workspaces
  - Integration tests: 4 new tests (870-873) verifying workspace cache features
  - Documentation: Updated commands.md with examples and flag descriptions
- **Sailor v1.5.0 migration**: Testing utilities and state management
  - Widget snapshot testing: `assertSnapshot()` method for pixel-perfect TUI verification
  - EventSimulator and MockTerminal available for TUI testing
  - Event bus and Command pattern for future TUI features
  - Non-breaking upgrade: all tests pass (743/751 unit, 873/873 integration)

### Changed
- Workspace cache commands now support targeting specific members
- Cache clearing operations provide better feedback for workspace scenarios

### Developer Notes
- Expression diagnostics integration deferred to future milestone (requires refactoring ~15 functions)
- Future enhancements planned: dependency visualization improvements, cross-workspace tasks

## [1.14.0] - 2026-03-07

### Added
- **Enhanced Error Diagnostics**: Comprehensive diagnostic framework for debugging task failures
  - **Timeline tracking**: Records all task execution events (started, completed, retry_started, skipped, cancelled, timeout, memory_limit)
    - Automatic duration analysis and execution analytics
    - Longest task identification, retry/skip/cancel/timeout counts
    - Integrated directly into scheduler (zero configuration)
  - **Failure replay mode**: Captures full context for failed tasks
    - Records cmd, cwd, env, exit code, timeline events
    - Automatic storage to `.zr/failures` directory
    - Full diagnostic information for post-mortem analysis
  - **CLI command**: `zr failures [list|clear]` to view and manage captured failure reports
    - `--task=<name>` to filter by specific task
    - `--storage-dir=<path>` to customize storage location (default: `.zr/failures`)
    - Color-coded output with detailed failure context
  - **Expression diagnostics module**: Foundation for stack traces in expression evaluation
    - `src/config/expr_diagnostics.zig` with StackFrame, DiagContext, DiagnosticError types
    - Integration into expression evaluator deferred to v1.15.0
- **Integration**: Timeline and replay managers automatically initialized in scheduler (commit a7218f0)
  - Zero configuration - works out of the box for all task executions
  - Failure contexts captured on task failure with full diagnostic information
  - Worker threads track events through shared timeline
- **Tests**: 10 new unit tests (743/751 total, 8 skipped), 3 new integration tests (865 total, 100% pass rate)
  - All integration tests pass (865/865)
  - Known issue: Minor memory leak in unit tests (non-blocking)

### Fixed
- **Memory leaks in failures integration tests**: Fixed tests 863-864 by properly freeing writeTmpConfig() return value (commit 972f627)

## [1.13.0] - 2026-03-03

### Added
- **Parallel Execution Optimizations**: CPU affinity and NUMA awareness for performance-critical tasks
  - `cpu_affinity` field: Pin tasks to specific CPU cores (array of core IDs)
  - `numa_node` field: Bind tasks to specific NUMA nodes
  - Work-stealing deque (Chase-Lev algorithm) for future scheduler improvements
  - NUMA topology detection (Linux + fallback for other platforms)
  - Cross-platform CPU affinity support (Linux, Windows, macOS)
  - Best-effort implementation: silently ignored if platform doesn't support affinity
  - Use cases: Cache locality, avoiding CPU migration, reducing memory latency
- **Documentation**: Comprehensive CPU affinity and NUMA guide in configuration.md
  - Platform support matrix (Linux: full, Windows: full, macOS: advisory)
  - Example configurations for database, web server, ML training
  - Performance tuning guidance
- **Integration tests**: 5 new tests for cpu_affinity/numa_node TOML parsing (tests 853-857)
- **Partial version resolution**: `zr tools install` now supports partial version specifications
  - `node@20` resolves to latest 20.x.x version
  - `node@20.11` resolves to latest 20.11.x version
  - Currently supports Node.js (other toolchains coming soon)
  - Provides helpful error messages for unsupported toolchains

### Changed
- Scheduler WorkerCtx now includes cpu_affinity and numa_node fields
- Worker threads set CPU affinity at start (if specified in task)

### Fixed
- **Linux cross-compilation**: Replaced CPU_ZERO/CPU_SET macros with direct bit manipulation
  - Fixes build failures on x86_64-linux-gnu and aarch64-linux-gnu targets
  - CPU_ZERO/CPU_SET macros from sched.h cannot be translated by Zig's @cImport
  - Uses @memset and manual bitset operations for cpu_set_t manipulation
- **Child.Term handling**: Use switch statement for proper tagged union access in toolchain downloader
  - Fixes Zig 0.15.2 compatibility issue with `result.term.Exited` access pattern
  - Properly handles all exit status cases (Exited, Signaled, Stopped, Unknown)

## [1.12.0] - 2026-03-03

### Added
- **Auto-generated stage names for anonymous workflow stages**: TOML array-of-tables syntax `[[workflows.X.stages]]` without explicit `name =` field now works correctly
  - Parser auto-generates names like "stage-1", "stage-2", etc. for anonymous stages
  - Works seamlessly with mixed named/anonymous stages
  - All example configs (docker-kubernetes, github-actions-ci) now parse correctly
- **Unit tests**: 3 new parser tests for anonymous stage handling (730/738 total)
- **Integration tests**: 3 new workflow tests for anonymous stages (852/852 total)

### Fixed
- **Anonymous workflow stages no longer discarded**: Previously, stages without `name =` were silently dropped during parsing
  - Fixes "0 stages" validation warnings in example configs
  - Resolves Known Limitation documented in debugging.md
- **flushPendingStage() helper**: Refactored 5 stage flush points to use unified helper function
  - Ensures consistent behavior across all section transitions
  - Proper memory management with auto-generated names

### Changed
- Enhanced TOML parser with anonymous stage name generation logic
- Improved workflow stage handling for better ergonomics

## [1.10.1] - 2026-03-02

### Fixed
- **Windows stdin buffering**: Fixed prompt display issue in `zr add` command on Windows
  - Added explicit stdout flush before reading stdin
  - Ensures prompts appear correctly before user input
  - Fixes issue where prompts appeared after entering input

## [1.10.0] - 2026-03-02

### Added
- **Conditional dependencies (`deps_if`)**: Run dependencies only when a condition evaluates to true
  - Syntax: `deps_if = [{ task = "lint", condition = "env.CI == 'true'" }]`
  - Supports full expression engine (env vars, platform checks, boolean logic)
  - Useful for environment-specific workflows (CI-only linting, platform-specific builds)
- **Optional dependencies (`deps_optional`)**: Silently skip dependencies if they don't exist
  - Syntax: `deps_optional = ["format", "optional-task"]`
  - Runs the dependency if defined, skips without error if not found
  - Useful for conditional features or plugin-based workflows
- **Integration tests**: 5 new tests for conditional/optional dependency execution (837/837 total)
- **Unit tests**: 16 new tests for deps v2 parser, graph builder, validation, and helper functions (716/724 total)

### Changed
- Enhanced dependency traversal in scheduler to support conditional and optional deps
- Updated configuration documentation with `deps_if` and `deps_optional` examples

### Fixed
- Execution logic now correctly evaluates conditional dependencies during graph building

## [1.9.0] - 2026-03-02

### Added
- **Accessibility features**: Enhanced TUI with screen reader support and better visual feedback
  - Position indicator in header showing current selection (e.g., "selected: 3/10")
  - Item count display for context awareness
  - Distinctive [T]/[W] symbols for task/workflow type differentiation
  - Footer showing currently selected item details
  - Improved semantic labels for better screen reader compatibility
- **Unicode width calculation**: Proper display width for CJK characters and emoji in TUI
  - Fixes alignment issues with multibyte characters
  - Supports full Unicode width calculation (combining characters, zero-width, etc.)
- **Enhanced keyboard navigation**: Extended TUI navigation shortcuts
  - `g/G`: Jump to top/bottom of list (Vim-style)
  - `Home/End`: Navigate to first/last item
  - `PgUp/PgDn`: Page up/down through lists
  - Arrow key support (↑/↓) in addition to j/k

### Changed
- Upgraded sailor library to v1.2.0 (layout & composition features)
- Improved TUI layout with dedicated footer area
- Better visual hierarchy with semantic type indicators

## [1.8.0] - 2026-03-02

### Added
- **Toolchain auto-update**: `zr tools upgrade` command for managing installed toolchains
  - `zr tools upgrade`: Dry-run mode shows available updates for all installed tools
  - `zr tools upgrade --check-updates`: Auto-install latest versions
  - `zr tools upgrade --cleanup`: Remove old versions after upgrade
  - Kind filtering support (e.g., `zr tools upgrade node`)
  - Version conflict resolution strategy (keeps only latest version)
- **Integration tests**: 7 new tests for `zr tools upgrade` command (826/831 total integration tests)
- **Unit tests**: 4 new tests for upgrade logic (689/697 total unit tests)

### Changed
- Enhanced toolchain management with automated upgrade workflow
- Improved version conflict detection and resolution

## [1.7.0] - 2026-03-02

### Added
- **String interning (StringPool)**: Memory-efficient string deduplication
  - Reduces heap allocations for repeated strings (task names, file paths, etc.)
  - 30-50% memory reduction in typical workloads
- **Object pooling (ObjectPool(T))**: Reusable object allocation
  - Eliminates allocation churn for frequently created/destroyed objects
  - Improves performance for hot paths (task execution, graph traversal)
- **Automated benchmark suite**: Hyperfine-based performance testing
  - `scripts/bench.sh`: Automated benchmark runner comparing against Make, Just, Task
  - Cold start benchmarks (empty task, 10 tasks, 100 tasks)
  - Parallel execution benchmarks (2/4/8 workers)
  - Results: 17% faster cold start, 28% lower RSS memory

### Changed
- Optimized task graph construction with string interning
- Reduced memory footprint with object pooling
- Updated benchmark documentation with Quick Start guide

### Performance
- Cold start: ~5ms → ~4.2ms (17% improvement)
- Memory (RSS): ~2.5MB → ~1.8MB (28% reduction)
- Binary size: Maintained at ~1.2MB

## [1.6.0] - 2026-03-02

### Added
- **Interactive configuration builder**: `zr add` command for creating tasks, workflows, and profiles interactively
  - `zr add task [name]`: Interactive task creation with prompts for cmd, description, dependencies
  - `zr add workflow [name]`: Interactive workflow creation with multi-stage support (each stage accepts comma-separated task lists)
  - `zr add profile [name]`: Interactive profile creation with environment variables (KEY=VALUE format)
  - Smart stdin handling with byte-by-byte reading (Zig 0.15 compatible)
  - Yes/no prompts for optional fields
  - Graceful error handling (missing config file, EOF, empty input)
  - Appends to existing `zr.toml` file without overwriting
- **Integration tests**: 6 new tests for `zr add` command (819/819 total, 100% pass rate)
- **Documentation**: Updated getting-started.md and commands.md with comprehensive examples and usage notes

### Fixed
- stdin error handling: Added `NotOpenForReading` to catch closed stdin in tests
- ArrayList API: Updated to Zig 0.15.2 unmanaged API (`.{}` initialization, allocator parameters for `.append`, `.deinit`, `.writer`)

### Closed Issues
- Closes #11 (need interactive add feature)

## [1.5.0] - 2026-03-02

### Added
- **Remote cache compression**: gzip compression for remote cache entries (reduces network transfer and storage costs)
  - New `compression` field in `RemoteCacheConfig` (default: true)
  - Auto-compress on push, auto-decompress on pull
  - Cross-platform using gzip CLI
- **Incremental sync**: Chunked upload/download for remote cache with deduplication
  - Split large cache entries into 1MB chunks
  - Track chunks via SHA256 hashes in manifest
  - Upload only missing chunks (deduplication across entries)
  - New `incremental_sync` field in `RemoteCacheConfig` (default: false)
  - Works with all backends (HTTP, S3, GCS, Azure)
- **Enhanced cache stats dashboard**: Improved `zr cache status` command
  - Human-readable size formatting (B, KB, MB, GB)
  - Average entry size calculation
  - Enhanced visual layout with separator line

### Changed
- Updated cache statistics display from "Cache Status" to "Cache Statistics" with better formatting

## [1.4.0] - 2026-03-02

### Added
- **Plugin registry client**: HTTP client for `registry.zr.dev` API with search, list, and getPlugin endpoints
- **Remote plugin search**: `zr plugin search --remote <query>` to browse the central plugin registry
- **Registry documentation**: Complete API specification in `docs/plugin-registry-api.md`
- **Graceful fallback**: CLI continues to work when registry is unreachable (returns empty results)
- **Integration tests**: 3 new tests (811-813) for remote search functionality

### Changed
- Updated `zr plugin search` help text to document `--remote` flag
- Enhanced PLUGIN_GUIDE.md with registry usage examples and API information
- Updated commands.md with remote search options and examples

## [1.3.0] - 2026-03-02

### Added
- **Interactive graph TUI mode**: `zr graph --format=tui` with sailor Tree widget for dependency visualization
- **Sailor v1.0.3 migration**: Updated to latest sailor library with Zig 0.15.2 compatibility fixes

### Fixed
- Re-enabled graph TUI mode (was temporarily disabled pending sailor#8 fix)
- Tree widget ArrayList API compatibility with Zig 0.15.2

### Changed
- Updated sailor dependency from v1.0.2 to v1.0.3

## [1.0.2] - 2026-03-01

### Fixed
- Windows terminal ANSI color code bleeding
- Windows console codepage UTF-8 setup for proper ANSI escape sequence handling

## [1.0.1] - 2026-02-28

### Fixed
- Minor post-release documentation improvements

## [1.0.0] - 2026-02-28

### Added

#### Phase 13 - v1.0 Release
- **Comprehensive documentation site**: 6 user guides (getting-started, configuration, commands, mcp-integration, lsp-setup, adding-language)
- **Migration guides**: `zr init --from-make`, `--from-just`, `--from-task` automatic conversion
- **README overhaul**: Complete rewrite with feature matrix, quick start, and comparison tables
- **Installation scripts**: `install.sh` (macOS/Linux) and `install.ps1` (Windows) for automated binary deployment
- **Contributor guide**: CONTRIBUTING.md with development setup, coding standards, and workflow

#### Phase 12 - Performance & Stability
- **Binary optimization**: ReleaseSmall + strip options (~1.2MB binary)
- **Fuzz testing**: TOML parser, expression engine, JSON-RPC parser (10min+ crash-free)
- **Benchmark dashboard**: Performance comparison vs Make, Just, Task(go-task)

#### Phase 11 - LSP Server
- **LSP core + diagnostics**: Full LSP server with document management and TOML parse error diagnostics
- **Auto-completion**: Context-aware completion for task names, field names, deps, expression keywords
- **Hover documentation**: Field hover docs and go-to-definition for deps → task definitions

#### Phase 10 - MCP Server
- **MCP Server core**: JSON-RPC based MCP server with 9 tools (run_task, list_tasks, show_task, validate_config, show_graph, run_workflow, task_history, estimate_duration, generate_config)
- **Auto-detection**: `zr init --detect` generates zr.toml from detected language providers

#### Phase 9 - Infrastructure + DX Quick Wins
- **LanguageProvider interface**: 8 languages (Node, Python, Zig, Go, Rust, Deno, Bun, Java) with single-file addition pattern
- **JSON-RPC shared infrastructure**: Content-Length + newline-delimited transport for MCP/LSP
- **"Did you mean?" suggestions**: Levenshtein distance-based typo suggestions for commands and task names
- **Error message improvements**: Line/column numbers in parse errors, similar name suggestions for missing deps

#### Additional Improvements
- **Version display**: Binary version derived from build.zig.zon as single source of truth
- **15 example projects**: Docker/Kubernetes, Make migration, all 8 language providers, plugin examples
- **Sailor library integration**: v0.5.1 for arg parsing, color, progress, JSON formatting, TUI widgets

### Changed
- Upgraded from development (v0.0.5) to production-ready (v1.0.0)
- All 13 PRD phases complete with comprehensive test coverage

### Performance
- Binary size: ~1.2MB (ReleaseSmall)
- Cold start: < 10ms (~4ms measured)
- Memory usage: ~2-3MB RSS
- Unit tests: 670/678 (8 skipped, 0 memory leaks)
- Integration tests: 805/805 (100% pass rate)
- Cross-compilation: 6 targets (linux/macos/windows x x86_64/aarch64)

## [0.0.5] - 2026-02-23

### Added
- **Shell-sourceable environment export**: `zr export` command generates shell-compatible env variable exports
  - Supports bash, zsh, fish shell formats with `--shell` flag
  - Automatic shell detection from `$SHELL` environment variable
  - Toolchain PATH injection - automatically includes toolchain bin directories in exported PATH
  - Profile-aware exports with `--profile` flag
  - Task-specific environment merging with `--task` flag
- **Task-specific environment layering**: Enhanced `zr env` command with task context
  - Display merged environment for specific tasks with `--task` flag
  - Visual layer breakdown showing system vs task-specific variables
  - Task environment overrides system environment (proper layering semantics)

### Changed
- Enhanced validation with whitespace-only command detection and duplicate task detection in workflow stages

## [0.0.4] - 2026-02-23

### Added

#### Phase 8 - Enterprise & Community Features
- **CODEOWNERS auto-generation**: `zr codeowners generate` command for workspace-based ownership files
- **Publishing & versioning automation**: `zr version` and `zr publish` commands with conventional commits support
  - Auto-detect version bump type from commit history (major/minor/patch)
  - CHANGELOG.md generation with categorized sections
  - Git tag creation and staged commit guidance
- **Build analytics reports**: `zr analytics` command with HTML/JSON output
  - Task execution time trends
  - Failure rates tracking
  - Critical path analysis (slowest tasks)
  - Parallelization efficiency metrics
- **AI-friendly metadata generation**: `zr context` command outputs structured project info (JSON/YAML)
  - Project dependency graph
  - Task catalog per package
  - File ownership mapping (CODEOWNERS)
  - Recent changes summary (git commits)
  - Toolchain information
- **Conformance rules engine**: `zr conformance` command with file-level governance
  - 5 rule types: import_pattern, file_naming, file_size, directory_depth, file_extension
  - Auto-fix support with `--fix` flag (removes banned imports)
  - Severity levels (error/warning/info)
  - Custom ignore patterns
- **Performance benchmarking**: `zr bench <task>` command with statistical analysis
  - Mean, median, standard deviation, coefficient of variation
  - Profile and quiet mode support
  - Configurable iteration count
- **Environment diagnostics**: `zr doctor` command verifies toolchain and environment setup
  - Checks for git, docker, curl, and installed toolchains
  - Color-coded status output
  - Exit code 1 on issues

#### Phase 7 - Multi-repo & Remote Cache
- **Remote cache backends**: Full support for 4 major cloud providers
  - HTTP backend with curl-based client
  - S3 backend with AWS Signature v4 authentication (compatible with MinIO, R2, etc.)
  - GCS backend with OAuth2 service account and RS256 JWT assertion
  - Azure Blob backend with Shared Key HMAC-SHA256 authentication
- **Multi-repo orchestration**: Complete multi-repository support
  - `zr repo sync`: Clone and pull all repositories from zr-repos.toml
  - `zr repo status`: Show git status across all repos
  - `zr repo graph`: Visualize cross-repo dependencies (ASCII/DOT/JSON)
  - `zr repo run <task>`: Execute tasks across repos in topological order
- **Synthetic workspace**: `zr workspace sync` unifies multi-repo into monorepo view
  - Builds unified member list and dependency map
  - Caches metadata to `~/.zr/synthetic-workspace/metadata.json`
  - Full integration with graph/workspace commands

#### Phase 6 - Monorepo Intelligence
- **Affected detection**: Git diff-based change detection for workspace members
  - `--affected <ref>` CLI flag filters tasks to changed projects
  - `zr affected <task>` standalone command with advanced filtering
  - `--include-dependents`: Run on projects that depend on affected ones
  - `--exclude-self`: Only run on dependents, not directly affected
  - `--include-dependencies`: Run on dependencies of affected projects
  - `--list`: Only list affected projects without running
- **Dependency graph expansion**: Transitive dependency expansion with BFS traversal
- **Project graph visualization**: `zr graph` command with 4 output formats
  - ASCII: Terminal tree view with affected highlighting
  - DOT: Graphviz format for visual diagrams
  - JSON: Programmatic access to dependency structure
  - HTML: Interactive D3.js force-directed graph
- **Architecture constraints**: `zr lint` command validates architectural rules
  - 3 constraint types: no-circular, tag-based, banned-dependency
  - Tag-based dependency control (app→lib, feature→feature rules)
  - Module boundary enforcement with [metadata] section parsing

#### Phase 5 - Toolchain Management
- **Multi-language toolchain support**: 8 toolchain types supported
  - Node.js, Python, Zig, Go, Rust, Deno, Bun, Java
  - Official source downloads with version resolution
  - Archive extraction (tar/unzip/PowerShell)
- **Toolchain CLI commands**:
  - `zr tools list [kind]`: List installed toolchain versions
  - `zr tools install <kind>@<version>`: Install specific version
  - `zr tools outdated [kind]`: Check for updates against official registries
- **Auto-install on task run**: Per-task toolchain requirements with automatic installation
- **PATH manipulation**: Inject toolchain bin paths into task execution environment
  - JAVA_HOME and GOROOT environment variables
  - Full scheduler integration

#### Additional Commands & Features
- **Self-update system**: `zr upgrade` command with version checking and binary replacement
- **Comprehensive cleanup**: `zr clean` command for cache/history/toolchains/plugins
- **Environment commands**:
  - `zr env` displays environment variables for tasks
  - `zr export` outputs shell-sourceable env vars with toolchain PATH injection
  - `zr cache status` shows cache statistics
  - `zr setup` one-command project onboarding (install tools + run setup tasks)
- **Enhanced shell completions**: All Phase 5-8 commands included in bash/zsh/fish completions
- **Validation improvements**: Edge case detection for whitespace-only commands and duplicate workflow tasks

## [0.0.3] - 2026-02-20

### Added

#### Phase 4 - Extensibility
- Native plugin system with .so/.dylib dynamic loading and C-ABI hooks
- Plugin management CLI: install/remove/update/info/search from local/git/registry
- Plugin scaffolding with `zr plugin create <name>`
- Built-in plugins: env (.env loading), git (branch/changes), notify (webhooks), cache (lifecycle hooks)
- **Docker built-in plugin**: Complete with build/push/tag/prune, BuildKit cache, multi-platform support
- **WASM plugin sandbox**: Full MVP implementation
  - Binary format parser (magic/version/sections)
  - Stack-based interpreter (35+ opcodes)
  - Memory isolation with host callbacks
  - Lifecycle hooks (init/pre_task/post_task)
- Plugin documentation (PLUGIN_GUIDE.md, PLUGIN_DEV_GUIDE.md)

#### Phase 3 - UX & Resources
- **Interactive TUI**:
  - Task picker with arrow keys + Enter
  - `zr live <task>` for real-time log streaming
  - Multi-task live mode support
  - `zr interactive-run <task>` with cancel/pause/resume controls
  - Automatic retry prompt on task failure
- **Resource limits**:
  - CPU and memory limits (`max_cpu`, `max_memory` config fields)
  - Cross-platform monitoring (Linux/macOS/Windows)
  - Kernel-level enforcement (cgroups v2 / Job Objects)
  - `--monitor` CLI flag for live resource display
- **Workspace/monorepo support**:
  - `[workspace] members` with glob discovery
  - `zr workspace list` and `zr workspace run <task>`
- CLI enhancements:
  - `--dry-run` / `-n` flag for execution plans
  - `zr init` scaffolds starter zr.toml
  - `zr validate` with --strict and --schema modes
  - Shell completion (bash/zsh/fish)
  - Global flags: --jobs, --no-color, --quiet, --verbose, --config, --format json
- Progress bar output module

#### Phase 2 - Workflows & Expressions
- **Workflow system**: `[workflows.X]` with `[[workflows.X.stages]]` and fail_fast
- **Profile system**: `--profile` flag, `ZR_PROFILE` env var, per-task overrides
- **Watch mode**: Native filesystem watchers (inotify/kqueue/ReadDirectoryChangesW) with polling fallback
- **Matrix execution**: Cartesian product with `${matrix.KEY}` interpolation
- **Task caching**: Wyhash64 fingerprint with `~/.zr/cache/` storage
- **Expression engine**: 100% of PRD §5.6 implemented
  - Logical operators: `&&`, `||` with short-circuit evaluation
  - Platform checks: `platform == "linux" | "darwin" | "windows"`
  - Architecture checks: `arch == "x86_64" | "aarch64"`
  - File operations: `file.exists()`, `file.changed()`, `file.newer()`, `file.hash()`
  - Shell execution: `shell(cmd)` for command success checks
  - Version comparison: `semver.gte(v1, v2)`
  - Environment variables: `env.VAR == "val"` with truthy checks
  - Runtime state refs: `stages['name'].success`, `tasks['name'].duration`

## [0.0.2] - 2026-02-17

### Added

#### Phase 1 - Foundation (MVP)
- Project bootstrap (build.zig, build.zig.zon, src/main.zig)
- TOML config parser with schema validation
- Task execution engine:
  - Process spawning with environment variables
  - Retry with exponential backoff
  - Timeout handling
- Dependency graph (DAG):
  - Graph construction with Kahn's Algorithm
  - Cycle detection
  - Topological sorting
- Parallel execution engine with worker pool and semaphores
- Basic CLI commands:
  - `zr run <task>`: Execute tasks with dependencies
  - `zr list`: Show available tasks
  - `zr graph`: Display dependency graph
- Execution history module with `zr history` command
- Cross-compilation CI pipeline (6 targets: linux/macos/windows × x86_64/aarch64)
- Task configuration fields:
  - timeout, allow_failure, deps_serial
  - env, retry, condition, cache
  - max_concurrent, matrix
- Color output and error formatting
- Integration test suite (15+ black-box CLI tests)

### Performance
- Binary size: ~2.9MB
- Cold start: ~0ms
- Memory usage: ~2MB RSS
- Test coverage: 472+ unit tests (8 platform-specific skipped)

## [0.0.1] - 2026-02-16

### Added
- Initial project structure
- Basic task runner implementation
- Version support

---

## Version Comparison

| Version | Release Date | Phases | Key Features |
|---------|--------------|--------|--------------|
| **1.0.0** | 2026-02-28 | 9-13 | MCP/LSP servers, LanguageProvider, DX improvements, binary optimization, documentation |
| **0.0.5** | 2026-02-23 | - | Shell environment export, task-specific env layering |
| **0.0.4** | 2026-02-23 | 5-8 | Enterprise features, Multi-repo, Toolchain management, Remote cache |
| **0.0.3** | 2026-02-20 | 3-4 | Interactive TUI, Resource limits, WASM plugins, Docker plugin |
| **0.0.2** | 2026-02-17 | 1-2 | MVP task runner, Workflows, Expression engine, Watch mode |
| **0.0.1** | 2026-02-16 | - | Initial release |

---

## Migration Guides

### Upgrading to 0.0.4

No breaking changes. New features are opt-in through:
- Toolchain management: Add `[tools]` section to zr.toml
- Remote cache: Add `[cache.remote]` section (HTTP/S3/GCS/Azure)
- Multi-repo: Create zr-repos.toml for cross-repo orchestration
- Conformance: Add `[[conformance.rules]]` for code governance

### Upgrading to 0.0.3

No breaking changes. New features:
- Interactive mode: Use `zr interactive` or `zr live <task>`
- Resource limits: Add `max_cpu` and `max_memory` to tasks
- Plugins: Add `[plugins]` section to zr.toml

### Upgrading to 0.0.2

No breaking changes. New features:
- Workflows: Add `[workflows.X]` sections
- Profiles: Use `--profile <name>` or `ZR_PROFILE` env var
- Watch mode: Use `zr watch <task> [paths...]`
- Expression engine: Use conditions in task `condition` fields

---

## Links

- [GitHub Repository](https://github.com/yusa-imit/zr)
- [Documentation](./docs/)
- [PRD (Product Requirements)](./docs/PRD.md)
- [Plugin Development Guide](./docs/PLUGIN_DEV_GUIDE.md)
- [Plugin User Guide](./docs/PLUGIN_GUIDE.md)

[Unreleased]: https://github.com/yusa-imit/zr/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yusa-imit/zr/compare/v0.0.5...v1.0.0
[0.0.5]: https://github.com/yusa-imit/zr/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/yusa-imit/zr/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/yusa-imit/zr/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/yusa-imit/zr/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/yusa-imit/zr/releases/tag/v0.0.1
