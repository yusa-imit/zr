# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig
- **Type**: Universal task runner & workflow manager CLI
- **Goal**: Language/ecosystem-agnostic, single binary, C-level performance, user-friendly CLI
- **Config format**: TOML + built-in expression engine (Option D from PRD)

## Current Phase

**Phase 1 - Foundation (MVP)** — 구현 진행 중
- [x] Project bootstrap (build.zig, build.zig.zon, src/main.zig)
- [x] Basic TOML config parser (supports tasks with cmd, cwd, description, deps)
- [x] Task execution engine (process spawning, env vars)
- [x] Dependency graph (DAG) construction & cycle detection
- [x] Topological sort with Kahn's Algorithm
- [x] Execution level calculation for parallel planning
- [x] Parallel execution engine (worker pool)
- [x] Basic CLI (run, list, graph)
- [x] Color output, error formatting
- [x] Cross-compile CI pipeline (ci.yml, release.yml 준비됨)
- [x] 문서/설정/에이전트 인프라 구축 완료
- [x] Execution history module (history/store.zig) + `zr history` CLI command
- [x] Task `timeout` field (parse "5m"/"30s"/"1h"/"500ms", kill child on expiry)
- [x] Task `allow_failure` field (non-zero exit doesn't fail pipeline)
- [x] Task `deps_serial` field (sequential pre-dependencies, run in array order)
- [x] Task `env` field (per-task env vars, TOML inline table: `env = { KEY = "value" }`)
- [x] Task `retry` field (retry_max, retry_delay_ms, retry_backoff — inline table: `retry = { max = 3, delay = "5s", backoff = "exponential" }`)
- [x] Task `condition` field (expression engine: `true`/`false`, `env.VAR`, `env.VAR == "val"`, `env.VAR != "val"`) — `src/config/expr.zig`
- [x] Watch mode (`zr watch <task> [path...]`) — `src/watch/watcher.zig` — polling-based, 500ms, skips .git/node_modules/zig-out/.zig-cache, records to history
- [x] Workflow system (`zr workflow <name>`) — `[workflows.X]` + `[[workflows.X.stages]]` TOML parsing; stage-sequential execution with fail_fast; `zr list` shows workflows
- [x] Profile system (`zr --profile <name>` or `ZR_PROFILE=<name>`) — `[profiles.X]` global env overrides + `[profiles.X.tasks.Y]` per-task cmd/cwd/env overrides; `Config.applyProfile()` merges at load time
- [x] `--dry-run` / `-n` flag — `zr --dry-run run <task>` and `zr --dry-run workflow <name>` show execution plan (levels, parallelism) without running; `planDryRun()` in scheduler returns `DryRunPlan`
- [x] `zr init` command — scaffolds starter `zr.toml` in current dir; accepts `std.fs.Dir` param for testability; deletes partial file on write failure; refuses to overwrite
- [x] `zr completion <bash|zsh|fish>` — prints shell completion scripts that complete subcommands, task names (from `zr list`), and workflow names
- [x] Global CLI flags: `--jobs/-j <N>` (max parallel), `--no-color`, `--quiet/-q`, `--verbose/-v`, `--config <path>` — all parsed in `run()` flag-scan loop; `--jobs` propagated to `scheduler.run()` as `max_jobs`; `--config` replaces hardcoded `CONFIG_FILE` via `loadConfig(config_path)` param; `--quiet` redirects `w` to `/dev/null`; `--no-color` overrides TTY detection
- [x] `max_concurrent` per-task resource limit — `Task.max_concurrent: u32` (0=unlimited); scheduler uses `StringHashMap(*Semaphore)` keyed by task name; global semaphore acquired first (avoids hold-and-wait), then per-task; heap semaphores destroyed after all threads joined; threads list pre-reserved to avoid live-thread leak on OOM
- [x] `--format json` / `-f json` global flag — machine-readable JSON output for `list`, `graph`, `run`, `history`; `writeJsonString()` helper in main.zig handles escaping; completions updated for all 3 shells
- [x] Workspace/monorepo support — `[workspace] members = ["packages/*"]`; `zr workspace list` discovers member dirs; `zr workspace run <task>` runs task across all members with `zr.toml`; `resolveWorkspaceMembers()` handles `dir/*` glob; supports `--format json`, `--dry-run`; 109/109 tests passing
- [x] Matrix task execution — `matrix = { arch = ["x86_64", "aarch64"], os = ["linux", "macos"] }` in task def; Cartesian product expansion generates variants like `test:arch=x86_64:os=linux`; meta-task deps on all variants; `${matrix.KEY}` interpolation in cmd/cwd/description/env; 115/115 tests passing
- [x] Task output caching — `cache = true` field in TOML; `src/cache/store.zig` stores Wyhash64 fingerprints as `~/.zr/cache/<key>.ok` marker files; scheduler checks cache pre-run and records hit on success; cache hit produces skipped=true result; `zr cache clear` removes all entries; 124/124 tests passing
- [x] Plugin system foundation — `src/plugin/loader.zig`: `PluginConfig` + `PluginRegistry` (native .so/.dylib via `std.DynLib`); `PluginSourceKind` (local/registry/git); `zr_on_init`, `zr_on_before_task`, `zr_on_after_task` C-ABI hooks; `[plugins.NAME]` TOML sections parsed into `Config.plugins: []PluginConfig`; `zr plugin list` CLI command with JSON support; 138/138 tests passing
- [x] Plugin management CLI — `zr plugin install <path> [name]` copies local plugin dir to `~/.zr/plugins/<name>/`; `zr plugin remove <name>` deletes it; `zr plugin info <name>` reads `plugin.toml` metadata; `readPluginMeta()` parses flat key=value TOML; `installLocalPlugin()` shallow-copies all files; `listInstalledPlugins()` enumerates dirs; 143/143 tests passing
- [x] Plugin update CLI — `zr plugin update <name> <path>` re-installs a plugin from a new source dir (delete-then-reinstall); `updateLocalPlugin()` in loader.zig; 147/147 tests passing
- [x] Plugin git install — `zr plugin install <git-url> [name]` clones from https://, http://, git://, git@ URLs using `git clone --depth=1`; `installGitPlugin()` in loader.zig; auto-strips .git suffix for name derivation; 151/151 tests passing
- [x] Plugin git update — `zr plugin update <name>` (no path) runs `git pull` in plugin dir for git-installed plugins; `installGitPlugin` writes `git_url` to plugin.toml after clone; `updateGitPlugin()`, `writeGitUrlToMeta()`, `readGitUrl()` in loader.zig; graceful errors for NotAGitPlugin/PluginNotFound/PullFailed; 157/157 tests passing
- [x] Plugin registry support — `zr plugin install registry:org/name@version`; `parseRegistryRef()` parses org/name@version format; `installRegistryPlugin()` resolves to `https://github.com/<org>/zr-plugin-<name>` and uses `git clone --branch <version>`; `writeRegistryRefToMeta()` / `readRegistryRef()` persist registry_ref in plugin.toml; `PluginRegistry.loadAll()` now loads git/registry plugins if already installed; 167/167 tests passing
- [x] Plugin search — `zr plugin search [query]`; `searchInstalledPlugins()` + `SearchResult` in loader.zig; case-insensitive substring search across dir name, display name, description; supports `--format json`; 175/175 tests passing
- [x] Built-in plugins — `src/plugin/builtin.zig`: `BuiltinHandle` with `BuiltinKind` (env/git/notify/cache/docker); `EnvPlugin.loadDotEnv()` via C `setenv(3)`, `EnvPlugin.readDotEnv()` for .env file parsing; `GitPlugin.currentBranch/changedFiles/lastCommitMessage/fileHasChanges` via git subprocess; `NotifyPlugin.sendWebhook()` via curl for Slack/Discord/generic webhooks; `loadBuiltin()` factory; `PluginRegistry` now has `builtins` list alongside `plugins`; `SourceKind.builtin` added; `source = "builtin:<name>"` syntax in TOML; `zr plugin builtins` CLI command; 193/193 tests passing
- [x] Progress bar output module — `src/output/progress.zig`: `ProgressBar` struct with in-place ANSI rendering (\r carriage return); `tick(label)` / `finish()` API; `printSummary()` for post-run passed/failed/skipped count summary line; TTY-aware via `use_color` flag; `std.Io.Writer.fixed(&buf)` used for tests; 7 new tests; 200/200 tests passing
- [x] Progress summary wired into CLI — `cmdRun` and `cmdWorkflow` in `src/cli/run.zig` now call `progress.printSummary()` after multi-task runs; tallies passed/failed/skipped from `TaskResult.skipped` flag; only shown when >1 task ran; 200/200 tests passing
- [x] Interactive TUI mode — `src/cli/tui.zig`: `zr interactive` / `zr i` command; arrow-key navigable task/workflow picker; raw terminal mode via POSIX `tcgetattr`/`tcsetattr`; `IS_POSIX` comptime guard for Windows safety; Enter runs selected task via `cmdRun`, q quits, r refreshes; non-TTY fallback prints guidance; 3 new tests; 235/235 tests passing
- [x] Cache built-in plugin hooks — `BuiltinHandle.onInit` initializes `CacheStore`, reads `max_age_seconds`/`clear_on_start` config; `onBeforeTask` evicts stale entries via `evictStaleEntries()` (mtime check); `BuiltinState` union holds kind-specific runtime state; `deinit` properly cleans up CacheStore; 4 new tests; 239/239 tests passing
- [x] Plugin scaffolding command — `zr plugin create <name> [--output-dir <dir>]` generates complete plugin template with plugin.toml, plugin.h (C ABI), plugin_impl.c (starter), Makefile (OS-aware), README.md; validates name (alphanumeric/hyphens/underscores), refuses to overwrite; updates shell completions; 5 new tests; 244/244 tests passing
- [x] Plugin documentation — Comprehensive guides for users and developers:
  - README.md: Full project overview with features, quick start, examples, architecture, performance metrics, comparison table vs just/task/make
  - docs/PLUGIN_GUIDE.md: User-facing guide for installing/managing/using plugins; built-in plugin reference; config examples; troubleshooting
  - docs/PLUGIN_DEV_GUIDE.md: Developer guide with C ABI reference, multi-language examples (C/Rust/Zig/Go), lifecycle explanation, best practices, advanced topics

> **Status**: Phase 1 complete + Phase 2 complete + Phase 3 complete (including interactive TUI) + Phase 4 nearly complete. 244/244 tests passing. Remaining: WASM runtime sandbox (optional), plugin registry index (optional).

## Architecture (High-Level)

```
CLI Interface -> Config Engine -> Task Graph Engine -> Execution Engine -> Plugin System
```

### Key Modules (src/)
- `main.zig` - Entry point + CLI commands (run, list, graph) + color output
- `cli/` - Argument parsing, help, completion, TUI
- `config/` - TOML loader, schema validation, expression engine, profiles
- `graph/` - DAG, topological sort, cycle detection, visualization
- `exec/` - Scheduler, worker pool, process management, resource limits
- `plugin/` - Dynamic loading (.so/.dylib), WASM sandbox, registry
- `watch/` - Filesystem watcher, debounce
- `output/` - Terminal rendering, color, progress bars, tables

## Config File

- Filename: `zr.toml`
- Format: TOML with embedded expression engine for conditions
- Supports: tasks, workflows, env vars, profiles, watch rules, plugins, workspaces

## Performance Targets

- Cold start: < 10ms
- 100-task graph resolution: < 5ms
- Memory (core): < 10MB
- Binary size: < 5MB
- Cross-compile: 6 targets (linux/macos/windows x x86_64/aarch64)

## Future Phases

- Phase 2: Workflows, expressions, watch mode, history
- Phase 3: Resource limits, TUI, shell completion, monorepo support
- Phase 4: Plugin system (native + WASM), plugin registry
