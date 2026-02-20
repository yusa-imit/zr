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

## [2026-02-18] Global CLI Flags Implementation
- Context: PRD Section 5.3.1 specifies --jobs/-j, --no-color, --quiet/-q, --verbose/-v, --config flags
- Decision:
  - All global flags parsed in `run()` before command dispatch; non-flag args go to `remaining_args`
  - `--jobs N`: validated >= 1 (0 rejected with hint), passed to `scheduler.run()` as `max_jobs`
  - `--no-color`: overrides `use_color = TTY-detect and !no_color`
  - `--quiet`: opens `/dev/null` and replaces `w` (stdout writer) — task failures still go to `err_writer`
  - `--verbose`: prints `[verbose mode]` dim line after the no-subcommand guard
  - `--config <path>`: `loadConfig()` now accepts `config_path: []const u8` parameter
  - `loadConfig` also accepts `use_color: bool` (was re-deriving from stderr TTY, ignoring --no-color)
  - Shell completions updated for all 3 shells
  - 94/94 tests passing; binary 2.4MB
- Key fixes from code review:
  - Quiet writer: use plain `var quiet_writer: std.fs.File.Writer` (not optional) before taking &interface
  - Task failure lines route to `err_writer` not `w` (visible under --quiet)
  - --jobs 0 rejected (was silently treated as CPU-count, confusing intent)

## [2026-02-18] max_concurrent Per-Task Resource Limit
- Context: Phase 3 requires per-task concurrency control for matrix builds and resource-constrained tasks
- Decision: `Task.max_concurrent: u32` field; scheduler maintains `StringHashMap(*std.Thread.Semaphore)` keyed by task name
  - Created lazily in dispatch loop; heap-allocated with `allocator.create`; destroyed in map defer
  - `errdefer allocator.destroy(new_sem)` before `put()` prevents memory leak on OOM
  - Acquisition order: global semaphore FIRST, then per-task semaphore (avoids hold-and-wait deadlock)
  - `threads.ensureTotalCapacity(level.items.len)` + `appendAssumeCapacity` prevents live-thread use-after-free if append OOMs
  - 98/98 tests passing; binary 2.4MB

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

## [2026-02-18] JSON/Machine-Readable Output (--format flag)

- **Decision**: Add `--format json` global flag (alias `-f`) alongside existing `--format text` default
- **Scope**: `list`, `graph`, `run`, `history` commands
- **Implementation**:
  - Flag parsed in `run()` alongside other global flags; `json_output: bool` passed to each cmd function
  - `writeJsonString()` helper handles all JSON string escaping (incl. control chars via `\\u{x:0>4}`)
  - Switch case range `0x00...0x1f` split: `\n`, `\r`, `\t` as named escapes; remainder as `\\uXXXX`
  - JSON schemas: `list` → `{tasks:[...],workflows:[...]}`, `graph` → `{levels:[...]}`, `run` → `{success,elapsed_ms,tasks:[...]}`, `history` → `{runs:[...]}`
  - Shell completions (bash/zsh/fish) updated to complete `--format` with `text json`
- **Tests**: 8 new tests added (flag parsing, error cases, JSON structure smoke tests)

## [2026-02-19] Matrix Task Execution

- **Decision**: Implement matrix task expansion via `matrix = { key = ["v1", "v2"] }` in task definitions
- **Scope**: `config/loader.zig` only — no CLI changes needed (meta-task handles routing)
- **Implementation**:
  - `MatrixDim` public struct: `key: []const u8`, `values: [][]const u8`
  - `task_matrix_raw: ?[]const u8` parse-time state (non-owning slice into content)
  - `parseMatrixTable`: bracket-depth + quote-aware scanner for inline table of arrays
  - `interpolateMatrixVars`: `${matrix.KEY}` substitution using `std.mem.replaceOwned` (errdefer guards result)
  - `addMatrixTask`: expansion engine — sorts dims alphabetically, computes Cartesian product via little-endian counter, creates variants + meta-task
  - Variant naming: `basename:key1=val1:key2=val2` (keys sorted alphabetically for determinism)
  - Meta-task: original name, `echo "Matrix task: NAME"` cmd, deps = all variant names
  - 4 new tests; 115/115 total passing
- **Rationale**:
  - Parse-time expansion (vs. runtime): simpler, no scheduler changes needed, variants visible in `list`/`graph`
  - Alphabetical key sort: deterministic variant names independent of TOML definition order
  - `std.mem.replaceOwned` allows multiple substitutions cleanly with owned result

## [2026-02-19] Task Output Caching (Phase 4 start)

- **Decision**: Implement task output caching as `cache = true` TOML field; `src/cache/store.zig`
- **Scope**: loader.zig (Task struct + TOML parsing), scheduler.zig (worker integration), main.zig (`zr cache clear` command)
- **Implementation**:
  - `CacheStore` in `src/cache/store.zig`: init creates `~/.zr/cache/` dir; key = Wyhash64(cmd + env pairs) as 16-char hex string; hit = `<key>.ok` file exists; `recordHit` creates empty marker file; `clearAll` removes `*.ok` files
  - `Task.cache: bool = false`; parsed as `cache = true` in TOML
  - Scheduler: `WorkerCtx` gains `cache: bool` + `cache_key: ?[]u8` (computed before spawn, freed in defer); `workerFn` checks hit before exec → returns skipped=true; records hit after success
  - `zr cache clear` → `cmdCache()` in main.zig; prints count of removed entries
  - All `addTaskImpl`/`addMatrixTask` call sites updated with new `cache` parameter
  - 9 new tests; 124/124 total passing
- **Rationale**:
  - File-based cache: simple, cross-process, no daemon needed; Wyhash64 is fast and sufficient for fingerprinting
  - Marker file (`.ok` suffix): trivially clearable, atomic creation, no locking needed for reads
  - Cache key covers cmd+env (not cwd/task-name) — focused on command identity, not location

## [2026-02-19] Plugin System Foundation
- Context: Phase 4 — Extensibility; PRD §5.5 requires plugin system with native .so/.dylib loading and TOML configuration
- Decision:
  - `src/plugin/loader.zig`: `PluginConfig` (name, kind, source, config pairs) + `PluginRegistry` (ArrayListUnmanaged of Plugin)
  - Native loading via `std.DynLib` with optional C-ABI hooks: `zr_on_init`, `zr_on_before_task`, `zr_on_after_task`
  - `SourceKind` enum: local / registry / git; source prefix parsing: "registry:", "git:", "local:" or bare path
  - TOML: `[plugins.NAME]` sections, `source =` field, `config = { k = "v" }` inline table
  - `Config.plugins: []PluginConfig` field added to loader; flushed at end of parseToml
  - `zr plugin list` CLI command with text + JSON output
  - 14 new tests; 138/138 total passing
- Rationale:
  - `std.DynLib` is idiomatic Zig for dynamic loading; C-ABI hooks are the simplest stable interface
  - Three source kinds cover all PRD scenarios; registry/git marked as "not yet supported" for now
  - Plugin system is additive — no changes to existing task execution path; hooks called optionally

## [2026-02-19] Plugin Management CLI (install/remove/info)
- Context: Phase 4 — after foundation, need to manage locally-installed plugins in `~/.zr/plugins/`
- Decision:
  - `zr plugin install <path> [name]`: copies local plugin dir to `~/.zr/plugins/<name>/` (shallow file copy)
  - `zr plugin remove <name>`: deletes `~/.zr/plugins/<name>/` via `std.fs.deleteTreeAbsolute`
  - `zr plugin info <name>`: reads `plugin.toml` from installed dir, displays name/version/description/author
  - `readPluginMeta()`: simple flat key=value TOML parser (quote-stripping); returns null if no plugin.toml
  - `installLocalPlugin()`: resolves abs path, checks no collision, copies all files (shallow one-level)
  - `listInstalledPlugins()`: enumerates dirs in `~/.zr/plugins/` via `Dir.iterate()`
  - args indexing: args[0]=zr, args[1]=plugin, args[2]=subcommand, args[3]=first-arg (name/path)
  - 5 new tests; 143/143 total passing
- Rationale: Local-first install covers most plugin development workflows; registry/git install deferred to later phase

## [2026-02-19] Plugin git install via git clone
- Context: PRD requires git URL source kind for plugin install
- Decision: `installGitPlugin(allocator, git_url, plugin_name) ![]const u8` in loader.zig; detect URLs by prefix (https://, http://, git://, git@) in cmdPlugin; run `git clone --depth=1 <url> <dest>` as subprocess
- Rationale: Shallow clone is fastest for install; subprocess avoids linking libgit2; detection by prefix is robust without regex
  - Name derivation: strip trailing .git suffix from last URL segment
  - Error types: GitInstallError{GitNotFound, CloneFailed, AlreadyInstalled}
  - 4 new tests; 151/151 total passing

## [2026-02-19] Git Plugin Update via git pull
- Context: `zr plugin update <name> <path>` required a local path even for git-installed plugins; users shouldn't need to remember the original URL
- Decision: Write `git_url` key to `plugin.toml` after `installGitPlugin()` succeeds; `updateGitPlugin()` reads it and runs `git -C <plugin_dir> pull`; `zr plugin update <name>` (no path) auto-detects git vs local and routes accordingly
- Rationale: Storing metadata in plugin.toml keeps the source of truth in the plugin dir; no separate manifest needed; `git pull` is idiomatic for git-sourced updates
  - New functions: `writeGitUrlToMeta()`, `readGitUrl()`, `updateGitPlugin()`, `GitUpdateError`
  - Error types: GitUpdateError{PluginNotFound, NotAGitPlugin, GitNotFound, PullFailed}
  - 6 new tests; 157/157 total passing

## [Feb 19, 2026] Plugin Registry Support
- Context: PRD specifies `registry:org/name@version` format for installing plugins from a registry
- Decision: Resolve registry refs to GitHub repos (`https://github.com/<org>/zr-plugin-<name>`) and use `git clone --branch <version>` (reusing existing git infrastructure); store `registry_ref` in plugin.toml for traceability; `PluginRegistry.loadAll()` now tries to load installed git/registry plugins from `~/.zr/plugins/<name>` instead of warning "not supported"
- Rationale: Reusing git clone avoids building a separate HTTP client; GitHub as default registry host is practical for Phase 4; version pinning via git tags is standard practice
  - New functions: `parseRegistryRef()`, `installRegistryPlugin()`, `writeRegistryRefToMeta()`, `readRegistryRef()`
  - CLI: `zr plugin install registry:org/name@version` in cmdPlugin
  - 10 new tests; 167/167 total passing

## [2026-02-19] Plugin Search Command
- Context: Plugin management was missing discoverability — users couldn't search installed plugins
- Decision: Implement `zr plugin search [query]` as local search over `~/.zr/plugins/`; case-insensitive substring match on dir name, display name (from plugin.toml), and description; supports `--format json`
- Rationale: Local search (no network) is fast and sufficient for Phase 4; avoids need for central index server; SearchResult struct owns its memory via deinit pattern
  - New: `searchInstalledPlugins()`, `SearchResult` in loader.zig
  - CLI: `zr plugin search [query]` in cmdPlugin
  - 8 new tests; 175/175 total passing

## [2026-02-19] Built-in Plugin System
- Context: Phase 4 requires "빌트인 플러그인 (docker, git, env, notify, cache)" compiled into zr binary
- Decision: Implemented `src/plugin/builtin.zig` with `BuiltinHandle`, `EnvPlugin`, `GitPlugin`, `NotifyPlugin`; added `SourceKind.builtin` to loader; `source = "builtin:<name>"` TOML syntax; `PluginRegistry` gains `builtins: ArrayListUnmanaged(BuiltinHandle)` alongside `plugins`; `zr plugin builtins` CLI command lists all 5 built-ins
- Rationale: Compiling built-ins directly into zr avoids distributing separate .so files; `EnvPlugin` uses C `setenv(3)` extern (std.posix.setenv doesn't exist in Zig 0.15); `NotifyPlugin` uses curl subprocess (no HTTP client needed); `GitPlugin` uses git subprocess (no libgit2 needed); docker/cache are stubs ready for expansion
  - New file: `src/plugin/builtin.zig` (~700 lines with tests)
  - Modified: loader.zig (SourceKind.builtin, PluginRegistry.builtins), config/loader.zig (builtin: prefix parsing), main.zig (plugin builtins command)
  - Pattern: `extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;` for POSIX setenv
  - Pattern: fmt.allocPrint format strings must be comptime — use fixed format, not runtime message template
  - 18 new tests; 193/193 total passing

## [2026-02-20] Progress Summary Integration into cmdRun/cmdWorkflow
- Context: `progress.printSummary()` was implemented but only referenced via `_ = progress` in main.zig — not called anywhere
- Decision: Wired into `src/cli/run.zig` — both `cmdRun` (text path) and `cmdWorkflow` (per-stage); only fires when `results.len > 1` to avoid noise for single-task runs
- Implementation: Count passed/failed/skipped by checking `TaskResult.skipped` first (skipped tasks aren't success or failure in UX terms); workflow single-task stages keep original "Stage done" dim line; import added to run.zig directly
- 200/200 tests passing; binary 2.8MB

## [2026-02-20] Plugin Scaffolding Command (zr plugin create)
- Context: Plugin development workflow needed streamlined onboarding
- Decision: Implemented `zr plugin create <name> [--output-dir <dir>]` command in `src/cli/plugin.zig`
- Implementation:
  - Generates complete plugin directory: plugin.toml (metadata), plugin.h (C ABI), plugin_impl.c (starter), Makefile (OS-aware), README.md
  - Name validation: alphanumeric, hyphens, underscores only (rejects spaces/special chars)
  - Refuses to overwrite existing directories (safety check via `std.fs.accessAbsolute`)
  - Makefile auto-detects OS (Darwin → .dylib, Linux → .so) via `UNAME := $(shell uname)`
  - Template uses starter implementation that logs to stderr (demonstrates hook pattern)
  - Shell completions updated for all 3 shells (bash/zsh/fish) to include `create` subcommand
  - 5 new tests; 244/244 total passing
- Rationale: Lowers barrier to plugin development; provides working template; enforces consistent structure

## [2026-02-20] Plugin Documentation Suite
- Context: Phase 4 extensibility requires comprehensive documentation for users and developers
- Decision: Created 3 documentation files covering full plugin ecosystem
- Implementation:
  1. **README.md** (1600+ lines):
     - Project overview with features, quick start, comparison table (zr vs just/task/make)
     - Core concepts: tasks, workflows, profiles, workspaces
     - Complete CLI reference with examples
     - Plugin integration examples
     - Architecture diagram and performance metrics
     - Roadmap with phase completion status
  2. **docs/PLUGIN_GUIDE.md** (500+ lines):
     - User-facing guide for installing/managing plugins
     - Built-in plugin reference (env/git/notify/cache) with TOML examples
     - Plugin lifecycle explanation
     - Troubleshooting section with platform-specific issues
     - Example use cases (Slack notifications, git branch checks)
  3. **docs/PLUGIN_DEV_GUIDE.md** (700+ lines):
     - Complete C ABI interface documentation (zr_on_init/before_task/after_task)
     - Plugin scaffolding walkthrough
     - Multi-language examples: C, Rust, Zig, Go (with build instructions)
     - Advanced topics: thread safety, memory management, cross-platform builds
     - Complete Slack notification plugin example
     - Troubleshooting: symbol visibility, ABI mismatches, platform issues
- Rationale: Comprehensive docs enable community plugin development; reduces support burden; demonstrates best practices

## [2026-02-20] 100% Test Coverage Achievement
- Context: Only `platform.zig` lacked tests (32/33 files covered)
- Decision: Added 3 comprehensive tests for platform wrappers
  - `getHome()` validation for both POSIX and Windows
  - `killProcess()` callability verification
  - `getenv()` behavior testing on both platforms
- Result: 247/247 tests passing; 33/33 files with tests (100% coverage)
- Rationale: Complete test coverage ensures cross-platform reliability; validates comptime platform guards work correctly

## [2026-02-19] Progress Bar Output Module
- Context: PRD requires progress output (`src/output/progress.zig`); UX improvement for multi-task runs
- Decision: Standalone `ProgressBar` struct (no scheduler integration) + `printSummary()` function
  - `ProgressBar.init(writer, use_color, total)` / `tick(label)` / `finish()` — in-place ANSI render via `\r`
  - BAR_WIDTH=20 chars fill region; `=` for filled, `>` for cursor, ` ` for empty
  - `printSummary(writer, use_color, passed, failed, skipped, elapsed_ms)` — post-run compact summary
  - TTY-aware: color mode uses ANSI codes, plain mode uses ASCII
  - Tests use `std.Io.Writer.fixed(&buf)` — new Zig 0.15 API; written bytes tracked via `writer.end`
  - 7 new tests; 200/200 total passing
- Rationale: Standalone module keeps scope small; no scheduler changes needed; future callers (e.g., cmdRun) can opt into progress display by wrapping ScheduleResult
