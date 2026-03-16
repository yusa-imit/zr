# Decision Log

Keep decisions that affect future development. Format:
```
## [Date] Decision Title
- Context: why
- Decision: what
- Rationale: why this choice matters
```

---

## Architecture & Core Systems

## [2026-02-17] Parallel Execution Model
- Decision: Thread-based with `std.Thread.Semaphore` per global + per-task (`max_concurrent`)
- Rationale: CPU-bound tasks parallelize; levels run sequentially, tasks within level parallel; per-task semaphore prevents thundering herd

## [2026-02-18] Execution Levels for DAG
- Decision: Kahn's Algorithm for topo sort; execution levels group independent tasks
- Rationale: Enables deterministic parallel scheduling without external scheduler

## [2026-02-17] Fail-Open Condition Evaluator
- Decision: `config/expr.zig` returns `true` on parse error; per-task env checked before process env
- Rationale: Prevents misconfigured conditions from silently breaking pipelines; test isolation via per-task env

## [2026-02-18] Polling-Based File Watcher
- Decision: 500ms interval in `src/watch/watcher.zig`; cross-platform via `std.fs.Dir.walk()`; skips .git/node_modules/zig-out/.zig-cache
- Rationale: Cross-platform (no inotify/kqueue); 500ms sufficient for dev workflows; avoids external daemon

## [2026-02-19] Task Output Caching
- Decision: File-based cache (`~/.zr/cache/`); key = Wyhash64(cmd+env); hit = `.ok` marker file
- Rationale: Cross-process, simple, no locking; marker file trivially clearable

## [2026-02-19] TOML Parser State Machine
- Decision: Section flags (in_task_matrix/env/toolchain, pending_* buffers); reset ALL on new section header
- Rationale: Prevents subsection state leakage; explicit state tracking prevents subtle bugs

## Parser & Config

## [2026-02-19] Matrix Task Expansion (Parse-Time)
- Decision: Cartesian product via little-endian counter; variant naming `basename:key1=val1:key2=val2` (alphabetical keys); meta-task = original name with echo cmd
- Rationale: Parse-time expansion simpler than runtime; deterministic names; meta-task visible in list/graph

## [2026-02-18] Profile System (In-Place Mutation)
- Decision: `Config.applyProfile(name)` mutates task env/cmd/cwd in-place; flag > `ZR_PROFILE` env
- Rationale: Profiles enable CI/dev/prod without separate configs; mutation keeps rest of pipeline unchanged

## [2026-02-19] Inline Table Parsing (env, retry, hooks, etc)
- Decision: Bracket-depth aware scanner for nested structures; quote-aware to avoid false delimiters
- Rationale: Avoids external TOML parser; Zig comptime constraints prefer explicit parsing

## Plugin System

## [2026-02-19] Plugin Source Kinds
- Decision: Three kinds (local path, `git:URL`, `registry:org/name@version`); registry resolves to GitHub (`https://github.com/org/zr-plugin-name`) with version = git tag
- Rationale: GitHub as de-facto registry; git tags for version pinning; local path covers dev workflows

## [2026-02-19] Built-In Plugins (Compiled Into Binary)
- Decision: `src/plugin/builtin.zig` with EnvPlugin, GitPlugin, NotifyPlugin, CachePlugin, DockerPlugin; uses C `setenv()` extern, curl/git subprocesses
- Rationale: No separate .so distribution; avoids libgit2/libcurl; subprocesses pragmatic for external tools

## [2026-02-19] Plugin Metadata Storage
- Decision: `plugin.toml` flat key=value in plugin root; stores `git_url` / `registry_ref` after install for auto-update
- Rationale: Metadata in plugin dir keeps source of truth local; no separate manifest needed

## Execution

## [2026-02-17] Retry with Exponential Backoff
- Decision: `retry_max`, `retry_delay_ms`, `retry_backoff` in Task; inline loop in workerFn/runTaskSync; delay doubles if backoff=true
- Rationale: Inline loop simpler than separate retry thread; exponential backoff standard for fault tolerance

## [2026-02-18] Circuit Breaker for Error Recovery (v1.30)
- Decision: Per-task `CircuitBreakerConfig`; state machine (closed→open→half-open); failure_threshold, window_ms, min_attempts, reset_timeout_ms
- Rationale: Prevents cascading failures; per-task isolation avoids affecting unrelated tasks

## [2026-02-18] Workflow Retry Budget (v1.34)
- Decision: Optional `retry_budget` on Workflow; shared across all stages via `RetryBudgetTracker`
- Rationale: Workflow-level limit prevents unbounded retries; multi-stage workflows share budget naturally

## [2026-03-14] Checkpoint/Resume with Stdout Markers
- Decision: Task emits "CHECKPOINT: <data>" markers to stdout; scheduler detects marker, saves state to `~/.zr/checkpoints/`, provides via `ZR_CHECKPOINT` env to resumed run
- Rationale: Markers are lightweight, human-readable; stdout is canonical IPC; fits asyncio patterns (Python asyncio.pause/resume)

## [2026-03-16] Output Capture (Stream/Buffer/Discard)
- Decision: Three modes via OutputCapture struct; key = task name + run ID; streaming saves to file, buffering keeps in memory (FIFO eviction at limit)
- Rationale: Flexible output handling (logs, test failure inspection, remote submission); FIFO eviction bounds memory

## CLI & Output

## [2026-02-18] Global Flags in Dispatcher
- Decision: Parsed in `run()` before command dispatch; `--jobs`/`--config`/`--no-color`/`--quiet`/`--verbose` validated and passed to loaders/schedulers
- Rationale: Centralized parsing ensures consistency; flags available to all commands; validation at parse time catches errors early

## [2026-02-18] JSON Output (--format flag)
- Decision: Separate JSON output path per command; schemas defined for list/graph/run/history; control char escaping via `\\uXXXX`
- Rationale: Machine-readable output enables tool integration; separate code path avoids format entanglement with text logic

## [2026-02-17] TTY-Aware Color Output
- Decision: `output/color.zig` module; TTY detection via `std.fs.File.isTty()`; overridable via `--no-color` and `output: false` task field
- Rationale: Colors improve UX in terminals; TTY check prevents ANSI codes in CI logs; task-level override enables piping

## [2026-02-18] Dry-Run Model
- Decision: `dry_run: bool` in SchedulerConfig skips execution but tracks results as skipped=true; separate `planDryRun()` returns DryRunPlan structure
- Rationale: Existing scheduler supports dry-run via flag; separate plan function cleaner than threading writer through scheduler

---

## Cross-Cutting

## [2026-02-16] Agent Model Assignment
- Decision: opus→architect, sonnet→{zig-developer, code-reviewer, test-writer}, haiku→{git-manager, ci-cd}
- Rationale: Model complexity matched to task; cost optimization via haiku for fast rule-following ops

## [2026-02-17] String Ownership Pattern
- Decision: Allocator.dupe() at parse time; Task.deinit() frees all owned slices; no partial frees inside functions
- Rationale: Clear ownership prevents use-after-free; central deinit covers all variants

## [2026-02-18] Error Handling (No @panic in Library)
- Decision: Explicit error sets; fail-open for non-critical paths (expressions, history, output)
- Rationale: Library code must propagate errors; user-facing commands can choose silent failure

## [2026-03-14] Zig 0.15 ArrayList Unmanaged
- Decision: Use `ArrayList(T){}` not `.init(allocator)`; pass allocator to every mutation (`.append()`, `.deinit()`)
- Rationale: Zig 0.15 breaking change; unmanaged API enforces explicit allocator threading
