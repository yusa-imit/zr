# Decision Log

Decisions are logged chronologically. Format:
```
## [Date] Decision Title
- Context: why
- Decision: what
- Rationale: why this option
```

---

## [2026-02-16] Project Setup for AI-Driven Development
- Context: Setting up repository for fully autonomous Claude Code development
- Decision: Created comprehensive .claude/ directory with agents, commands, and memory system
- Rationale: Enables Claude Code to self-organize teams, maintain context across sessions, and follow consistent workflows

## [2026-02-16] Agent Model Assignment (Team Review)
- Context: Agent definitions used `model: inherit`, lacking static model assignment
- Decision: Assigned static models based on task complexity:
  - **opus**: architect (complex reasoning, design decisions)
  - **sonnet**: zig-developer, code-reviewer, test-writer (balanced implementation/analysis)
  - **haiku**: git-manager, ci-cd (fast, rule-following operations)
- Rationale: Static model assignment ensures consistent performance and cost optimization per agent role. Voted 4/4 by review team.

## [2026-02-16] Document Review & Cleanup (Team Review)
- Context: 18 changes proposed by 4-agent expert team (zig-expert, arch-reviewer, devops-expert, doc-specialist)
- Decision: Applied 18 changes with 75%+ approval: model assignments, CLAUDE.md restructure, CI artifact upload, checksum compatibility, settings cleanup, .gitignore simplification, validate command addition
- Rationale: Voting-based review ensures quality through multi-perspective consensus

## [2026-02-17] Color Output & Env Vars Implementation
- Context: Phase 1 requires color output for UX and env var support for real-world tasks
- Decision: Implemented:
  - `output/color.zig`: TTY-aware ANSI color module with semantic helpers
  - `process.zig`: env var overrides via merged EnvMap + `inherit_stdio` flag
  - `main.zig`: all CLI output now uses color module
- Rationale:
  - TTY detection prevents ANSI codes in pipes/CI
  - `inherit_stdio` flag solves test deadlock: production inherits stdio, tests use .Pipe
  - Semantic helpers (printSuccess/printError/printInfo) enforce consistent UX

## [2026-02-17] Parallel Execution Engine
- Context: Phase 1 requires parallel task execution for performance
- Decision: Implemented thread-based parallel execution in scheduler.zig:
  - `WorkerCtx` struct carries task context to worker threads
  - `std.Thread.Semaphore` caps concurrency to `max_jobs` (default = CPU count)
  - `std.atomic.Value(bool)` tracks failure across threads
  - `std.Thread.Mutex` protects shared results list
  - Levels run sequentially; tasks within a level run in parallel
  - `SchedulerConfig.inherit_stdio` flag (default: true) for test safety
- Also fixed: `getExecutionLevels` now returns `error.CycleDetected` instead of silently returning empty levels
- Also added: `Config.addTask()` public method for programmatic config construction

## [2026-02-17] Execution History Module
- Context: Phase 2 requires execution history for traceability and UX
- Decision: Implemented `history/store.zig` with line-delimited text file backend
  - Format: `<timestamp>\t<task>\t<ok|fail>\t<duration_ms>\t<task_count>`
  - `Store.append()` uses `fmt.bufPrint` + `file.writeAll` (not buffered File.writer — caused partial writes)
  - `Store.loadLast(limit)` returns last N records efficiently
  - `zr history` CLI command shows last 20 runs
  - History recording in `cmdRun` is best-effort (errors silently ignored)
  - History file: `.zr_history` in CWD
- Key fix: `File.writer(&buf)` with flush was unreliable for file appending; use `fmt.bufPrint` + `file.writeAll` for direct unbuffered writes

## [2026-02-17] Graph Module Implementation
- Context: Phase 1 requires DAG construction, cycle detection, and topological sort
- Decision: Implemented three modules:
  - `graph/dag.zig`: Core DAG structure with StringHashMap for nodes
  - `graph/cycle_detect.zig`: Kahn's Algorithm for cycle detection
  - `graph/topo_sort.zig`: Topological sort + execution level calculation
- Rationale:
  - Kahn's Algorithm chosen for both cycle detection and topo sort (single-pass, O(V+E))
  - Execution levels enable parallel execution planning by grouping independent tasks
  - StringHashMap provides O(1) node lookup for large graphs
  - Each module is independently testable with comprehensive test coverage
