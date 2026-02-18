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

> **Status**: Phase 1 complete + Phase 2 complete + Phase 3 complete + Phase 4 started (task caching). 124/124 tests passing. Next: full plugin system (native .so/.dylib loading) or TUI.

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
