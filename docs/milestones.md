# zr — Milestones

## Current Status

- **Latest**: v1.34.0 (Workflow Retry Budget Integration)
- **Next**: v1.35.0 — zuda Levenshtein Migration (blocked on zuda release)
- **Blockers**: v1.35.0 and v1.36.0 blocked on zuda releases

---

## Active Milestones

### v1.35.0 — zuda Levenshtein Migration

Migrate from custom `src/util/levenshtein.zig` to `zuda.algorithms.dynamic_programming.edit_distance` (issue #21). Add zuda dependency via zig fetch, migrate levenshtein.zig to wrapper, update all call sites (`main.zig` "Did you mean?" suggestions, `cli/validate.zig`), verify unit tests pass, remove custom implementation. **Blocked until zuda releases edit_distance module.**

### v1.36.0 — zuda WorkStealingDeque Migration

Migrate from custom `src/exec/workstealing.zig` to `zuda.containers.queues.StealingQueue` (issue #22). Add zuda dependency, migrate scheduler's work-stealing deque to zuda implementation, update WorkStealingDeque wrapper, verify performance benchmarks, integration tests pass. **Blocked until zuda releases StealingQueue module.**

### v1.37.0 — Enhanced Task Output Capture & Streaming

Implement real-time task output capture and streaming. Address TODOs in scheduler.zig for stdout/stderr capture. Features: (1) Stream task output to file (`output_file` field), (2) Real-time output display in TUI (`--live` flag enhancement), (3) Output buffer management with configurable size limits, (4) Post-execution output retrieval via `zr show <task> --output`, (5) Output filtering and search. Implementation: Create `src/exec/output_capture.zig` with OutputCapture struct, integrate with scheduler worker threads, add TOML fields (`output_file`, `output_mode`: stream|buffer|discard), update TUI runner to display live output, add integration tests (5-8 tests). Tests: Unit tests for OutputCapture, integration tests for file output and TUI streaming.

---

## Completed Milestones

| Version | Name | Date | Summary |
|---------|------|------|---------|
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
- 버전 번호는 마지막 마일스톤의 다음 번호로 자동 부여
- 수립 후 이 파일의 Active Milestones에 추가하고 커밋: `chore: add milestone v1.X.0`

---

## Dependency Migration Tracking

### Sailor Library

- **Current in zr**: v1.13.1 (all migrations complete)
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
| v1.6.0 | READY | ScatterPlot, Histogram, TimeSeriesChart (data visualization) |
| v1.6.1 | DONE | PieChart overflow fix, API compilation fixes |
| v1.7.0 | READY | FlexBox layout, viewport clipping, shadow effects, layout caching |
| v1.8.0 | READY | HttpClient, WebSocket, AsyncEventLoop, TaskRunner, LogViewer |
| v1.9.0 | DONE | WidgetDebugger, PerformanceProfiler, CompletionPopup, ThemeEditor |
| v1.10.0 | DONE | Mouse event handling (SGR), widget mouse interaction, gamepad/touch |
| v1.11.0 | DONE | Particle effects, blur/transparency, Sixel/Kitty graphics, transitions |
| v1.12.0 | DONE | Session recording, audit logging, WCAG AAA themes, screen reader |
| v1.13.0 | READY | Syntax highlighting, code editor, autocomplete, multi-cursor, rich text |
| v1.13.1 | DONE | Integer overflow fix for data visualization widgets |

### zuda Library

- **Current**: Not yet integrated (blocked on zuda releases)
- **Repository**: https://github.com/yusa-imit/zuda

| Custom Implementation | File | zuda Replacement | Status |
|----------------------|------|-----------------|--------|
| DAG | `src/graph/dag.zig` | `zuda.containers.graphs.AdjacencyList` | PENDING |
| Topological Sort (Kahn's) | `src/graph/topo_sort.zig` | `zuda.algorithms.graph.topological_sort` | PENDING |
| Cycle Detection | `src/graph/cycle_detect.zig` | `zuda.algorithms.graph.cycle_detection` | PENDING |
| Work-Stealing Deque | `src/exec/workstealing.zig` | `zuda.containers.queues.StealingQueue` | PENDING |
| Levenshtein Distance | `src/util/levenshtein.zig` | `zuda.algorithms.dynamic_programming.edit_distance` | PENDING |
| Glob Pattern Matching | `src/util/glob.zig` | `zuda.algorithms.string.glob_match` | PENDING |

**Migration exclusions** (domain-specific, kept in zr):
- `src/util/string_pool.zig` — zr-specific string interning
- `src/util/object_pool.zig` — zr-specific object pooling
- `src/graph/ascii.zig` — zr-specific ASCII graph renderer
