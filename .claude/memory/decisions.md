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

## [2026-02-17] Timeout and allow_failure Implementation
- Context: Phase 2 requires timeout enforcement and fault tolerance per PRD Section 5.1.1
- Decision:
  - `Task` struct gains `timeout_ms: ?u64` and `allow_failure: bool`
  - `parseDurationMs()` in loader.zig parses "5m", "30s", "1h", "500ms"
  - `process.zig`: after spawn, optionally start `timeoutWatcher` thread (50ms poll loop). On expiry, `posix.kill(pid, SIGKILL)`. After child.wait(), join watcher and check `timed_out` flag.
  - `scheduler.zig`: `allow_failure` prevents setting global `failed` flag. Task result still records actual exit code.
  - `std.Thread.sleep(ns)` is the correct API in Zig 0.15 (not `std.time.sleep`)
  - 45/45 tests passing
- Rationale: poll-based timeout watcher is simpler than timer syscalls, cross-platform, and 50ms granularity is sufficient for CI-level timeouts

## [2026-02-18] Retry Logic Implementation
- Context: Phase 2 requires retry on failure per PRD Section 5.1.1 (`retry = { max = 3, delay = "5s", backoff = "exponential" }`)
- Decision:
  - `Task` struct gains `retry_max: u32`, `retry_delay_ms: u64`, `retry_backoff: bool`
  - TOML parser handles `retry = { ... }` inline table (same pattern as `env`)
  - `workerFn` (parallel) and `runTaskSync` (serial) both loop up to `retry_max` times on failure
  - Delay between retries via `std.Thread.sleep(delay_ms * ns_per_ms)`; doubles if `retry_backoff`
  - `delay_ms = 0` means no delay (safe for tests)
  - 55/55 tests passing; binary 1.8MB
- Rationale: inline loop retry is simple and sufficient; no separate thread needed

## [2026-02-18] deps_serial Implementation
- Context: Phase 2 requires sequential dependency execution (PRD Section 5.2.2)
- Decision: `deps_serial` tasks run inline (not via DAG) using `runSerialChain` helper
  - `collectDeps` only traverses `deps` (not `deps_serial`) — serial tasks excluded from DAG
  - `runSerialChain` executes serial deps one-at-a-time, recursing into nested serial chains
  - Cycle detection via false sentinel inserted before recursion (prevents stack overflow)
  - `runTaskSync` holds `results_mutex` to prevent data race with parallel worker threads
  - Partial inner-string allocation leak fixed using duped-count tracking in errdefer
- 48/48 tests passing; binary 1.88MB

## [2026-02-18] Condition Expression Engine
- Context: Phase 2 requires conditional task execution (PRD Section 5.1.1: `condition = "expr"`)
- Decision: Implemented `config/expr.zig` — standalone expression evaluator
  - Supports: `true`/`false` literals, `env.VAR` truthy check, `env.VAR == "val"`, `env.VAR != "val"`
  - Fail-open: unknown/unparseable expressions return `true` (task runs)
  - Task env pairs checked before process environment (allows test isolation)
  - `Task.condition: ?[]const u8` field added; duped on store, freed in `Task.deinit`
  - Scheduler evaluates condition before spawning worker thread; false → skipped result (success=true, skipped=true)
  - `EvalError = error{OutOfMemory}` only — no parse errors propagate
  - 68/68 tests passing; binary 1.86MB
- Rationale: Fail-open prevents misconfigured conditions from silently breaking pipelines. Per-task env lookup enables environment-specific skipping without polluting process env.

## [2026-02-18] Workflow System Implementation
- Context: Phase 2 requires workflow system with stages (PRD Section 5.2.3)
- Decision: Implemented `Workflow` + `Stage` structs in `config/loader.zig`; `zr workflow <name>` in `main.zig`
  - TOML format: `[workflows.X]` for header, `[[workflows.X.stages]]` for each stage
  - Stage fields: `name`, `tasks = [...]`, `parallel = true`, `fail_fast = false`, `condition`
  - parseToml state machine: flush stage → flush workflow on any new section header
  - `addWorkflow()` dupes all strings (same pattern as addTaskImpl)
  - Key insight: `Config.deinit` must NOT free key separately — Workflow.deinit frees `.name` = same allocation as key
  - `zr workflow <name>` runs stages sequentially; each stage's tasks via scheduler.run
  - fail_fast: stops workflow immediately on stage failure
  - `zr list` shows workflows section below tasks
  - 74/74 tests passing
- Rationale: Stage-based sequential execution is the natural model for CI-style pipelines; reusing scheduler.run for stage tasks avoids duplication

## [2026-02-18] Dry-Run Implementation
- Context: Phase 2 / UX requires showing execution plan without running tasks
- Decision: Added `dry_run: bool` to `SchedulerConfig` + separate `planDryRun()` function
  - `SchedulerConfig.dry_run = true`: existing `run()` skips process execution, records skipped=true results
  - `planDryRun()`: standalone function returning `DryRunPlan` with `[]DryRunLevel` (task names per level)
  - `DryRunPlan.deinit()` and `DryRunLevel.deinit()` follow standard owned-slice cleanup pattern
  - `printDryRunPlan()` in main.zig formats levels: single task = inline, multiple = [parallel] with indented list
  - `--dry-run` / `-n` global flag parsed alongside `--profile` in args scan loop
  - `cmdWorkflow` dry-run: calls `planDryRun` per stage and prints each stage's plan
  - 86/86 tests passing; binary 2.1MB
- Rationale: Separate planDryRun() is cleaner than threading a writer through scheduler; dry_run in SchedulerConfig handles the "skip but track" case in existing tests

## [2026-02-18] zr init & zr completion Implementation
- Context: Phase 2 UX improvements — scaffolding and shell integration
- Decision:
  - `zr init`: creates starter `zr.toml` with 4 example tasks (hello, build, test, clean)
  - `cmdInit(dir: std.fs.Dir, ...)` accepts a Dir param for testability; call site passes `std.fs.cwd()`
  - On write failure: close file, delete partial artifact, then return error (user can safely retry)
  - Control flow: explicit `exists: bool` local using labeled block — readable, not buried in `catch`
  - `zr completion <bash|zsh|fish>`: embeds static completion scripts as Zig string literals
  - Scripts complete: subcommands, task names (via `zr list` awk parse), workflow names, shell names
  - 88/88 tests passing; binary 2.3MB
- Rationale: Static string literal scripts avoid runtime generation complexity; `zr list` awk parsing
  is a pragmatic tradeoff (coupled to output format, but simple and works without JSON output)

## [2026-02-18] Profile System Implementation
- Context: Phase 2 requires named profiles for environment-specific config overrides
- Decision: Implemented `Profile` + `ProfileTaskOverride` structs in `config/loader.zig`
  - TOML format: `[profiles.X]` for profile header with global env; `[profiles.X.tasks.Y]` for per-task overrides
  - Profile fields: `name`, `env: [][2][]const u8`, `task_overrides: StringHashMap(ProfileTaskOverride)`
  - Task override fields: `cmd`, `cwd`, `env` (all optional)
  - `Config.applyProfile(name)` mutates task env/cmd/cwd in-place; returns `error.ProfileNotFound`
  - CLI: `zr --profile <name>` or `zr -p <name>`; env: `ZR_PROFILE=<name>` (flag takes precedence)
  - Profile resolution: flag > ZR_PROFILE env var; done inside `loadConfig` after file parse
  - flushProfile() helper transfers ownership of accumulated `profile_task_overrides` StringHashMap
  - Key insight: profile_task_overrides map keys must be cleared without freeing after transfer
  - 80/80 tests passing; binary 2.1MB
- Rationale: Profiles enable CI/dev/prod environment differentiation without separate config files. In-place mutation keeps the rest of the pipeline unchanged.

## [2026-02-18] Watch Mode Implementation
- Context: Phase 2 requires watch mode for automatic task re-run on file changes
- Decision: Polling-based watcher (500ms interval) in `src/watch/watcher.zig`
  - `Watcher.init(allocator, paths, poll_ms)` → snapshot initial mtimes
  - `Watcher.waitForChange()` → blocks, returns changed path
  - Uses `std.fs.Dir.walk()` for recursive directory scanning
  - Skips .git, node_modules, zig-out, .zig-cache
  - `cmdWatch` in main.zig: run immediately, then loop on `waitForChange`
  - Reloads config each iteration (picks up zr.toml edits mid-session)
  - Records each run to history (consistent with `cmdRun`)
  - errdefer on `owned_path` before `mtimes.put` prevents OOM leak
  - 72/72 tests passing; binary 1.9MB
- Rationale: Polling is cross-platform (no inotify/kqueue), simple, and 500ms granularity is sufficient for dev workflows

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
