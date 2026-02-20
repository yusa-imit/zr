# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig
- **Type**: Universal task runner & workflow manager CLI
- **Goal**: Language/ecosystem-agnostic, single binary, C-level performance, user-friendly CLI
- **Config format**: TOML + built-in expression engine (Option D from PRD)

## Current Phase

### Phase 1 - Foundation (MVP) — **COMPLETE**
- [x] Project bootstrap (build.zig, build.zig.zon, src/main.zig)
- [x] TOML config parser (tasks with cmd, cwd, description, deps, env, retry, timeout, etc.)
- [x] Task execution engine (process spawning, env vars, retry with backoff)
- [x] Dependency graph (DAG) construction & cycle detection (Kahn's Algorithm)
- [x] Parallel execution engine (worker pool with semaphores)
- [x] Basic CLI (run, list, graph) with color output, error formatting
- [x] Cross-compile CI pipeline (6 targets)
- [x] Execution history module + `zr history` CLI command
- [x] Task fields: timeout, allow_failure, deps_serial, env, retry, condition, cache, max_concurrent, matrix

### Phase 2 - Workflows & Expressions — **MOSTLY COMPLETE (~85%)**
- [x] Workflow system (`[workflows.X]` + `[[workflows.X.stages]]`, fail_fast)
- [x] Profile system (`--profile`, `ZR_PROFILE`, per-task overrides)
- [x] Watch mode — **polling-based (500ms)**, NOT native inotify/kqueue as PRD specifies
- [x] Matrix task execution (Cartesian product, `${matrix.KEY}` interpolation)
- [x] Task output caching (Wyhash64 fingerprint, `~/.zr/cache/`)
- [ ] **Expression engine** — only `env.VAR == "val"` supported (PRD §5.6 의 ~10% 구현)
  - Missing: `file.exists()`, `file.changed()`, `file.hash()`, `file.newer()`
  - Missing: `shell(cmd)`, `semver.gte()`, `platform == "linux"`
  - Missing: logical operators (`&&`, `||`)
  - Missing: `stages['name'].success`, `tasks['name'].duration`

### Phase 3 - UX & Resources — **PARTIAL (~70%)**
- [x] `--dry-run` / `-n` flag (execution plan without running)
- [x] `zr init` command (scaffold starter zr.toml)
- [x] Shell completion (bash/zsh/fish)
- [x] Global CLI flags: `--jobs`, `--no-color`, `--quiet`, `--verbose`, `--config`, `--format json`
- [x] `max_concurrent` per-task resource limit
- [x] Workspace/monorepo support (`[workspace] members`, glob discovery)
- [x] Progress bar output module
- [x] Interactive TUI — **basic picker only** (arrow keys + Enter)
  - Missing: real-time log streaming (PRD §5.3.3)
  - Missing: task cancel/retry (PRD §5.3.3)
  - Missing: dependency graph ASCII visualization (PRD §5.3.3)
- [ ] **Resource limits (CPU/Memory)** — NOT implemented (PRD §5.4)
  - Missing: `max_cpu`, `max_memory` per-task (PRD §5.4.1)
  - Missing: `max_total_memory`, `max_cpu_percent` global (PRD §5.4.2)
  - Missing: cgroups v2 / Job Objects integration (PRD §5.4.3)
  - Missing: `--monitor` resource monitoring flag

### Phase 4 - Extensibility — **PARTIAL (~60%)**
- [x] Native plugin system (.so/.dylib via DynLib, C-ABI hooks)
- [x] Plugin management CLI (install/remove/update/info/search from local/git/registry)
- [x] Plugin scaffolding (`zr plugin create`)
- [x] Built-in plugins: env (.env loading), git (branch/changes), notify (webhooks), cache (lifecycle hooks)
- [x] Plugin documentation (README, PLUGIN_GUIDE, PLUGIN_DEV_GUIDE)
- [ ] **Docker built-in plugin** — enum placeholder only, zero implementation
- [ ] **WASM plugin sandbox** — NOT implemented (zero code; PRD §5.5.1 core component)
- [ ] **Plugin registry index server** — NOT implemented (uses GitHub as backend only)
- [ ] **Remote cache** — NOT implemented (local cache only; PRD §9)

### Missing Utility Modules (PRD §7.2)
- [ ] `util/glob.zig` — no general glob API (workspace uses ad-hoc `dir/*` resolution)
- [ ] `util/semver.zig` — no semver comparison
- [ ] `util/hash.zig` — no general file hashing (cache uses Wyhash on task name only)
- [x] `util/platform.zig` — cross-platform POSIX wrappers

## Status Summary

> **Reality**: Phase 1 complete. Phase 2 ~85% (expression engine stub). Phase 3 ~70% (no resource limits). Phase 4 ~60% (no WASM, docker stub). **Strong MVP, not feature-complete.**

- **Tests**: 246 passing across 33 files
- **Binary**: 2.9MB, ~0ms cold start, ~2MB RSS
- **CI**: 6 cross-compile targets working

## Architecture (High-Level)

```
CLI Interface -> Config Engine -> Task Graph Engine -> Execution Engine -> Plugin System
```

### Key Modules (src/)
- `main.zig` - Entry point + CLI commands (run, list, graph) + color output
- `cli/` - Argument parsing, help, completion, TUI (basic)
- `config/` - TOML loader, schema validation, expression engine (limited), profiles
- `graph/` - DAG, topological sort, cycle detection, visualization
- `exec/` - Scheduler, worker pool, process management, max_concurrent only
- `plugin/` - Dynamic loading (.so/.dylib), git/registry install, built-ins (4/5)
- `watch/` - Polling-based filesystem watcher (NOT native inotify/kqueue)
- `output/` - Terminal rendering, color, progress bars

## Config File

- Filename: `zr.toml`
- Format: TOML with limited expression engine for conditions
- Supports: tasks, workflows, env vars, profiles, watch rules, plugins, workspaces

## Performance Targets

- Cold start: < 10ms (achieved: ~0ms)
- 100-task graph resolution: < 5ms
- Memory (core): < 10MB (achieved: ~2MB RSS)
- Binary size: < 5MB (achieved: 2.9MB)
- Cross-compile: 6 targets (linux/macos/windows x x86_64/aarch64)

## Priority Backlog (by impact)

1. **Expression engine** — `file.exists()`, `file.changed()`, `shell()`, `&&`/`||` (CI/CD use cases blocked)
2. **Resource limits** — `max_cpu`, `max_memory`, cgroups v2 (production workload isolation)
3. **Watch mode upgrade** — inotify/kqueue native (performance, scalability)
4. **TUI enhancements** — live log streaming, cancel/retry
5. **WASM plugin sandbox** — sandboxed third-party plugins
6. **Docker built-in plugin** — implement or remove from enum
7. **Remote cache** — shared cache for CI pipelines
