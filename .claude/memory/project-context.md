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

### Phase 2 - Workflows & Expressions — **COMPLETE (100%)**
- [x] Workflow system (`[workflows.X]` + `[[workflows.X.stages]]`, fail_fast)
- [x] Profile system (`--profile`, `ZR_PROFILE`, per-task overrides)
- [x] **Watch mode** — **NATIVE (inotify/kqueue/ReadDirectoryChangesW)** with polling fallback (8ef87a4)
- [x] Matrix task execution (Cartesian product, `${matrix.KEY}` interpolation)
- [x] Task output caching (Wyhash64 fingerprint, `~/.zr/cache/`)
- [x] **Expression engine** — **100% of PRD §5.6 implemented**
  - [x] Logical operators: `&&`, `||` with short-circuit evaluation
  - [x] Platform checks: `platform == "linux" | "darwin" | "windows"`
  - [x] Architecture checks: `arch == "x86_64" | "aarch64"`
  - [x] `file.exists(path)` — filesystem check via fs.access
  - [x] `file.changed(glob)` — git diff-based change detection
  - [x] `file.newer(target, source)` — mtime comparison (dirs walk full tree)
  - [x] `file.hash(path)` — Wyhash content fingerprint
  - [x] `shell(cmd)` — command execution success check
  - [x] `semver.gte(v1, v2)` — semantic version comparison
  - [x] Environment variables: `env.VAR == "val"`, `env.VAR != "val"`, truthy checks
  - [x] **Runtime state refs**: `stages['name'].success`, `tasks['name'].duration` with all comparison operators

### Phase 3 - UX & Resources — **NEARLY COMPLETE (~95%)**
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
- [x] **Resource limits (CPU/Memory)** — **COMPLETE (100%)** (PRD §5.4)
  - [x] `max_cpu`, `max_memory` config fields + TOML parsing (e276a26)
  - [x] `GlobalResourceConfig` (max_total_memory, max_cpu_percent) (e276a26)
  - [x] `src/exec/resource.zig` — ResourceMonitor with cross-platform implementation
  - [x] getProcessUsage() Linux implementation (/proc/[pid]/status, /proc/[pid]/stat) (f1f7cd3)
  - [x] getProcessUsage() macOS implementation (proc_pidinfo) (3560668)
  - [x] getProcessUsage() Windows implementation (GetProcessMemoryInfo, GetProcessTimes) (21df9dc)
  - [x] Integration with process spawning (resource watcher thread, memory limit kill) (f1f7cd3)
  - [x] cgroups v2 / Job Objects hard limit enforcement (Linux/Windows kernel-level limits)
  - [ ] `--monitor` CLI flag for live resource display (future enhancement)

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

> **Reality**: Phase 1 complete. Phase 2 **100% complete** (native filesystem watchers + full expression engine). Phase 3 **~95% complete** (resource limits with kernel-level enforcement complete). Phase 4 ~60% (no WASM, docker stub). **Strong MVP with event-driven watch mode and production-ready resource management.**

- **Tests**: 267 passing (5 skipped platform-specific) — resource monitoring cross-platform
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

1. ~~**Expression engine (runtime refs)**~~ — **COMPLETE** ✓ (c1db626)
2. ~~**Resource monitoring (Linux/macOS/Windows)**~~ — **COMPLETE** ✓ (21df9dc)
3. ~~**Resource limit enforcement**~~ — **COMPLETE** ✓ (cgroups v2 / Job Objects)
4. ~~**Watch mode upgrade**~~ — **COMPLETE** ✓ (native inotify/kqueue/ReadDirectoryChangesW) (8ef87a4)
5. **TUI enhancements** — live log streaming, cancel/retry
6. **WASM plugin sandbox** — sandboxed third-party plugins
7. **Docker built-in plugin** — implement or remove from enum
8. **Remote cache** — shared cache for CI pipelines
