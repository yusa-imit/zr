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

> **Status**: Phase 1 complete + Phase 2 partial. 48/48 tests passing. Next: expression engine, watch mode, workflow system, retry logic.

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
