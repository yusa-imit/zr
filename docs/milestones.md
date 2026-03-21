# zr — Milestones

## Current Status

- **Latest**: v1.47.0 (Task Retry Strategies & Backoff Policies)
- **Next actionable milestone**: Shell Integration Enhancements (READY)
- **READY milestones**: zuda WorkStealingDeque, zuda Glob (zuda v1.15.0)
- **BLOCKED milestones**: zuda Graph Migration (awaiting zuda issue #12 — compat layer incomplete)

---

## Active Milestones

> **Note**: Version numbers below are **historical references only**. Actual release version is determined at release time as `build.zig.zon` current version + 1. See "Milestone Establishment Process" for rules.

### zuda Graph Migration (DAG + Topo Sort + Cycle Detection)

Migrate `src/graph/dag.zig` (187 LOC), `src/graph/topo_sort.zig` (323 LOC), `src/graph/cycle_detect.zig` (205 LOC) to zuda (issues #23, #24). Use `zuda.compat.zr_dag` compatibility layer for drop-in replacement, or migrate directly to `zuda.containers.graphs.AdjacencyList` + `zuda.algorithms.graph.topological_sort` + `zuda.algorithms.graph.cycle_detection`. Add zuda dependency via `zig fetch --save`, update all call sites, verify tests, remove custom implementations. **Status: BLOCKED** — zuda v1.15.0 compat.zr_dag missing required functions (nodeCount, getInDegree, getExecutionLevels, different return types). Filed https://github.com/yusa-imit/zuda/issues/12, awaiting resolution.

### zuda Levenshtein Migration

Migrate from custom `src/util/levenshtein.zig` (214 LOC) to `zuda.algorithms.dynamic_programming.edit_distance` (issue #21). Add zuda dependency via zig fetch, migrate levenshtein.zig to wrapper, update all call sites (`main.zig` "Did you mean?" suggestions, `cli/validate.zig`), verify unit tests pass, remove custom implementation. **Status: DONE** — Completed 2026-03-21. Migrated to zuda.algorithms.dynamic_programming.editDistance, all tests passing.

### zuda WorkStealingDeque Migration

Migrate from custom `src/exec/workstealing.zig` (130 LOC) to `zuda.containers.queues.WorkStealingDeque` (issue #22). Add zuda dependency, migrate scheduler's work-stealing deque to zuda implementation, update WorkStealingDeque wrapper, verify performance benchmarks, integration tests pass. **Status: READY** — zuda v1.15.0 provides WorkStealingDeque module.

### zuda Glob Migration

Migrate from custom `src/util/glob.zig` (130 LOC) to `zuda.algorithms.string.globMatch` (issue #25). Add zuda dependency, replace glob matching logic, verify tests pass. **Status: READY** — zuda v1.15.0 provides glob_match module.

### Shell Integration Enhancements

**Theme**: Developer Experience — Seamless shell integration beyond completion

**Scope**:
1. **Smart `cd` integration**: `zr cd <workspace-member>` — instantly jump to workspace members by name (no path memorization)
2. **Shell hooks**: Optional shell hooks for automatic environment loading (direnv-like, but zr-native)
3. **Command abbreviations**: `zr b` → `zr run build`, `zr t` → `zr run test` (user-configurable aliases in `~/.zrconfig`)
4. **Shell history integration**: Record `zr run` invocations in shell history with full command expansion for replay
5. **Integration tests**: 5+ tests for cd/hooks/abbreviations

**Why**: Make zr feel like a native part of the shell, not just another CLI tool. Reduce friction for daily workflows.

**Status**: READY

### Task Output Streaming Improvements

**Theme**: Performance & UX — Better handling of long-running task output

**Scope**:
1. **Incremental rendering**: Stream task output to TUI without buffering entire output in memory (critical for multi-GB logs)
2. **Compression on-the-fly**: Gzip-compress stored task output for `zr show --output` (reduce history storage by 5-10x)
3. **Follow mode**: `zr show --output <task> --follow` — tail -f style live following
4. **Output pagination**: Automatic pager integration (less/bat) for large outputs
5. **Performance tests**: Verify memory usage stays under 50MB when streaming 1GB+ output

**Why**: Current output capture buffers entire output, causing OOM on very long-running tasks. Improve scalability.

**Status**: READY

### Cross-Platform Path Handling Audit

**Theme**: Stability — Eliminate path-related bugs on Windows

**Scope**:
1. **Path separator audit**: Review all path manipulation code for hardcoded `/` vs proper `std.fs.path.sep`
2. **UNC path support**: Handle Windows UNC paths (`\\server\share`) correctly in cwd/remote_cwd
3. **Long path support**: Enable Windows long path support (>260 characters) via manifest
4. **Symlink handling**: Test and fix symlink resolution on Windows (requires admin or Dev Mode)
5. **Integration tests**: 10+ Windows-specific path tests (run in CI via windows-latest)

**Why**: Windows users report occasional path-related crashes. Comprehensive audit to eliminate this class of bugs.

**Status**: READY

---

## Completed Milestones

| Version | Name | Date | Summary |
| v1.47.0 | Task Retry Strategies & Backoff Policies | 2026-03-19 | Configurable retry strategies: backoff multiplier, jitter, max backoff ceiling, conditional retry (retry_on_codes, retry_on_patterns), integration tests |
|---------|------|------|---------|
| v1.46.0 | Remote Execution & Distributed Builds | 2026-03-18 | SSH/HTTP remote task execution, remote/remote_cwd/remote_env fields, scheduler integration, 9 integration tests |
| v1.45.0 | TOML Syntax Highlighting | 2026-03-17 | Syntax-highlighted TOML error messages, error_display utility, color-coded diagnostics for validate command |
| v1.44.0 | Version Fix (v1.0.0 revert) | 2026-03-16 | Reverted erroneous v1.0.0 version downgrade, added version monotonicity guard to release policy |
| v1.43.0 | Sailor v1.15.0 Migration | 2026-03-16 | Thread safety fixes, XTGETTCAP terminal capability detection, platform-specific testing, memory leak fixes, multi-platform CI |
| v1.39.0 | Sailor v1.14.0 Migration | 2026-03-16 | Memory pooling, render profiling, virtual widget rendering, incremental layout solver, buffer compression |
| v1.38.0 | Task Output Search & Filtering | 2026-03-16 | Search/filter/head/tail flags for show --output, color highlighting, 7 integration tests |
| v1.37.0 | Enhanced Task Output Capture & Streaming | 2026-03-16 | OutputCapture module with stream/buffer/discard modes, scheduler integration, TUI live display, `zr show --output` command, 13 integration tests |
| v1.34.0 | Workflow Retry Budget Integration | 2026-03-14 | Workflow-level retry budget fully functional with scheduler integration and multi-stage support |
| v1.33.0 | Advanced TUI Data Visualization | 2026-03-14 | Sailor v1.6.0/v1.7.0 data visualization widgets (Histogram, TimeSeriesChart, ScatterPlot) with FlexBox layout |
| v1.32.0 | Sailor v1.11.0 & v1.12.0 Migration | 2026-03-14 | Particle effects, blur/transparency, session recording, audit logging, WCAG AAA themes, screen reader enhancements |
| v1.31.0 | Checkpoint/Resume for Long-Running Tasks | 2026-03-13 | Checkpoint storage infrastructure, task stdout monitoring for markers, resume via ZR_CHECKPOINT env var |
| v1.30.0 | Enhanced Error Recovery | 2026-03-13 | Circuit breaker pattern, retry budget for workflow-level limiting, enhanced scheduler error recovery |
| v1.29.0 | Task Template System | 2026-03-13 | Reusable task templates with parameter substitution, CLI commands (list/show/apply) |
| v1.28.0 | Interactive TUI with Mouse Support | 2026-03-12 | Mouse click/scroll support in task picker, graph TUI, and live execution TUI via sailor v1.10.0 |
| v1.27.0 | Real-time Resource Monitoring | 2026-03-12 | Live TUI dashboard with ASCII bar charts for CPU/memory, task status table, bottleneck detection |
| v1.26.0 | Language Provider Expansion | 2026-03-11 | Added C# (.NET) and Ruby language providers, 10 total languages supported |
| v1.25.0 | Interactive TUI Config Editor | 2026-03-11 | Interactive prompt-based config editor with `zr edit task/workflow/profile` commands |
| v1.24.0 | Execution Hooks | 2026-03-11 | Pre/post task hooks (on_before, on_after, on_success, on_failure, on_timeout) with TOML parser and scheduler integration |
| v1.23.0 | Shell Auto-Completion v2 | 2026-03-10 | Context-aware shell completion with dynamic task/profile/member name suggestions |
| v1.22.0 | Sailor v1.6.0 & v1.7.0 Migration | 2026-03-09 | Data visualization widgets, FlexBox layout, viewport clipping, shadow effects, layout caching |
| v1.21.0 | TUI Testing & Enhancements | 2026-03-09 | MockTerminal snapshot tests for all TUI modes (runner, graph, list), 19 new unit tests |
| v1.20.0 | Expression Diagnostics Integration | 2026-03-09 | DiagContext integration into expression evaluator, 17 eval functions with push/pop stack tracking |
| v1.19.0 | Parser Enhancements v3 | 2026-03-09 | Inline workflow stages syntax, dependency-only tasks without cmd, subsection ordering fix |
| v1.18.0 | Conditional Task Execution | 2026-03-08 | Git predicates (git.branch/tag/dirty), skip_if/output_if fields, expression engine extensions |
| v1.17.0 | Advanced Watch Mode | 2026-03-08 | Debouncing, pattern-based watch filters, multi-pattern support, TOML watch configuration |
| v1.16.0 | Task Execution Analytics | 2026-03-07 | Resource usage tracking (peak memory, avg CPU), enhanced analytics reports (HTML/JSON) |
| v1.15.0 | Workspace Enhancements | 2026-03-07 | Workspace-wide cache invalidation, member-specific cache clearing, sailor v1.5.0 migration |
| v1.14.0 | Enhanced Error Diagnostics | 2026-03-06 | Task execution timeline, failure replay mode |
| v1.13.0 | Parallel Execution Optimizations | 2026-03-05 | Work-stealing deque, NUMA topology detection, cross-platform CPU affinity |
| v1.12.0 | TOML Parser v2 | 2026-03-03 | Auto-generate stage names for anonymous workflow stages, validation warning removal |
| v1.11.0 | Plugin Registry Index Server | 2026-03-03 | Independent index server with REST API, plugin metadata, search endpoints |
| v1.10.0 | Task Dependencies v2 | 2026-03-02 | Conditional dependencies (deps_if), optional dependencies (deps_optional), expression engine integration |
| v1.9.0 | Sailor v1.1.0 Accessibility | 2026-03-02 | Unicode width improvements (CJK/emoji), TUI keyboard navigation, accessibility features |
| v1.8.0 | Toolchain Auto-Update | 2026-03-02 | `zr tools upgrade --check-updates`, `--cleanup` flag for version conflict resolution |
| v1.7.0 | Performance Enhancements | 2026-03-02 | String interning (StringPool), object pooling (ObjectPool), 30-50% memory reduction |
| v1.6.0 | Interactive Configuration | 2026-03-02 | `zr add task/workflow/profile` interactive commands, smart stdin handling |
| v1.5.0 | Remote Cache v2 | 2026-03-02 | Gzip compression, incremental sync, cache statistics dashboard |
| v1.4.0 | Plugin Registry Client | 2026-03-02 | HTTP client, remote search `--remote` flag, graceful fallback |
| v1.3.0 | TUI Graph Visualization | 2026-03-02 | Tree widget-based graph TUI mode, sailor v1.0.3 migration |
| v1.2.0 | TOML Parser Improvements | 2026-03-01 | Strict validation, malformed section header detection, error message improvements |
| v1.1.0 | Sailor v1.0.2 Migration | 2026-02-28 | Dependency update, API refactoring, local TTY workaround, theme system review |

---

## Milestone Establishment Process

미완료 마일스톤이 **2개 이하**가 되면, 에이전트가 자율적으로 새 마일스톤을 수립한다.

**입력 소스** (우선순위 순):
1. `gh issue list --state open --label feature-request` — 사용자 요청 기능
2. `docs/PRD.md` — 아직 구현되지 않은 PRD 항목 (Phase 5-8의 미구현 세부사항)
3. 의존성 업데이트 — sailor, Zig 새 버전 등
4. 기술 부채 — Known Limitations, TODO, 성능 병목
5. 경쟁 도구 분석 — just, task, make 대비 누락된 기능

**수립 규칙**:
- 마일스톤 하나는 **단일 테마**로 구성 (여러 작은 기능을 하나의 주제로 묶음)
- 1-2주 내 완료 가능한 범위로 스코프 설정
- 마일스톤은 **이름(테마)으로 관리**하며, 버전 번호는 **릴리즈 시점에 결정**한다
- 릴리즈 시 버전: `build.zig.zon`의 현재 버전 + 1 (마일스톤에 미리 적힌 번호는 참고용)
- **건너뛰기 금지**: 차단된 마일스톤을 건너뛰고 미래 버전을 릴리즈하지 않는다. 차단된 마일스톤은 차단 해제 시까지 대기하고, 다른 작업을 먼저 릴리즈한다 (순차 번호로)
- 수립 후 이 파일의 Active Milestones에 추가하고 커밋: `chore: add milestone <이름>`

---

## Dependency Migration Tracking

### Sailor Library

- **Current in zr**: v1.16.0 (all migrations complete)
- **Repository**: https://github.com/yusa-imit/sailor

| Sailor Version | Status | Summary |
|---------------|--------|---------|
| v0.1.0 | DONE | arg parsing, color module |
| v0.2.0 | DONE | progress module |
| v0.3.0 | DONE | fmt/JSON module |
| v0.4.0 | DONE | TUI framework |
| v0.5.0 | DONE | Advanced widgets (deferred), Windows cross-compile fix |
| v1.0.0-v1.0.3 | DONE | Production ready, Tree widget Zig 0.15.2 fix |
| v1.1.0 | DONE | Accessibility, Unicode width (CJK/emoji), keyboard navigation |
| v1.2.0 | DONE | Grid layout, ScrollView, overlay/z-index, responsive breakpoints |
| v1.3.0 | DONE | RenderBudget, LazyBuffer, EventBatcher, DebugOverlay |
| v1.4.0 | DONE | Form widget, Select/Dropdown, Checkbox, RadioGroup, Validators |
| v1.5.0 | DONE | MockTerminal snapshot testing, Event bus, Command pattern |
| v1.6.0 | DONE | ScatterPlot, Histogram, TimeSeriesChart (data visualization, consumed in v1.22.0) |
| v1.6.1 | DONE | PieChart overflow fix, API compilation fixes |
| v1.7.0 | DONE | FlexBox layout, viewport clipping, shadow effects, layout caching (consumed in v1.22.0) |
| v1.8.0 | DONE | HttpClient, WebSocket, AsyncEventLoop, TaskRunner, LogViewer (features available, no zr milestone needed) |
| v1.9.0 | DONE | WidgetDebugger, PerformanceProfiler, CompletionPopup, ThemeEditor |
| v1.10.0 | DONE | Mouse event handling (SGR), widget mouse interaction, gamepad/touch |
| v1.11.0 | DONE | Particle effects, blur/transparency, Sixel/Kitty graphics, transitions |
| v1.12.0 | DONE | Session recording, audit logging, WCAG AAA themes, screen reader |
| v1.13.0 | READY | Syntax highlighting, code editor, autocomplete, multi-cursor, rich text |
| v1.13.1 | DONE | Integer overflow fix for data visualization widgets |
| v1.14.0 | DONE | Memory pooling, render profiling, virtual widget rendering, incremental layout, buffer compression |
| v1.15.0 | DONE | Thread safety fixes, XTGETTCAP terminal capability detection, memory leak audit, multi-platform CI |
| v1.16.0 | DONE | Terminal capability database, bracketed paste mode, synchronized output protocol, hyperlink support (OSC 8), focus tracking |

### zuda Library

- **Current**: Not yet integrated — **READY for migration** (zuda v1.15.0 available)
- **Repository**: https://github.com/yusa-imit/zuda
- **Compatibility layers**: `zuda.compat.zr_dag` — drop-in DAG/topo sort/cycle detection wrapper
- **Migration guides**: See zuda `docs/migrations/ZR_GRAPH.md` for detailed API mapping

| Custom Implementation | File | LOC | zuda Replacement | Issue | Status |
|----------------------|------|-----|-----------------|-------|--------|
| DAG | `src/graph/dag.zig` | 187 | `zuda.compat.zr_dag` or `zuda.containers.graphs.AdjacencyList` | #23 | **READY** |
| Topological Sort (Kahn's) | `src/graph/topo_sort.zig` | 323 | `zuda.algorithms.graph.topological_sort` | #24 | **READY** |
| Cycle Detection | `src/graph/cycle_detect.zig` | 205 | `zuda.algorithms.graph.cycle_detection` | #24 | **READY** |
| Work-Stealing Deque | `src/exec/workstealing.zig` | 130 | `zuda.containers.queues.WorkStealingDeque` | #22 | **READY** |
| Levenshtein Distance | `src/util/levenshtein.zig` | 214 | `zuda.algorithms.dynamic_programming.editDistance` | #21 | **READY** |
| Glob Pattern Matching | `src/util/glob.zig` | 130 | `zuda.algorithms.string.globMatch` | #25 | **READY** |

**Migration exclusions** (domain-specific, kept in zr):
- `src/util/string_pool.zig` — zr-specific string interning
- `src/util/object_pool.zig` — zr-specific object pooling
- `src/graph/ascii.zig` — zr-specific ASCII graph renderer
