# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig
- **Type**: Universal task runner & workflow manager CLI
- **Goal**: Language/ecosystem-agnostic, single binary, C-level performance, user-friendly CLI
- **Config format**: TOML + built-in expression engine (Option D from PRD)

## Current Phase

**Phase 1 - Foundation (MVP)** — 구현 시작
- [x] Project bootstrap (build.zig, build.zig.zon, src/main.zig)
- [x] Basic TOML config parser (supports tasks with cmd, cwd, description, deps)
- [ ] Task execution engine (process spawning, env vars)
- [ ] Dependency graph (DAG) construction & cycle detection
- [ ] Parallel execution engine (worker pool)
- [ ] Basic CLI (run, list, graph)
- [ ] Color output, error formatting
- [x] Cross-compile CI pipeline (ci.yml, release.yml 준비됨)
- [x] 문서/설정/에이전트 인프라 구축 완료

> **Status**: Project successfully bootstrapped with Zig 0.15.2. Basic TOML parser implemented and tested.

## Architecture (High-Level)

```
CLI Interface -> Config Engine -> Task Graph Engine -> Execution Engine -> Plugin System
```

### Key Modules (src/)
- `main.zig` - Entry point
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
