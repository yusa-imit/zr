# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.0.0 (released 2026-02-28)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status (2026-03-07)

- **Version**: v1.14.0 (released - Enhanced Error Diagnostics)
- **Unit tests**: 743/751 (8 skipped, 0 failed, 0 memory leaks)
- **Integration tests**: 869/869 (100% pass rate)
- **CI**: GREEN — all 6 cross-compile targets passing
- **GitHub Issues**: 2 open (enhancement requests: #19 inline stages, #20 cmd-less tasks)
- **Binary**: ~1.2MB ReleaseSmall, ~4ms cold start, ~1.8MB RSS

## All Phases COMPLETE

| Phase | Name | Key Deliverables |
|-------|------|------------------|
| 1 | Foundation (MVP) | TOML parser, DAG, parallel execution, CLI (run/list/graph) |
| 2 | Workflow & Control | Workflows, expressions, watch mode, matrix, profiles, caching |
| 3 | Resource & UX | TUI, resource limits (cgroups/Job Objects), shell completion, dry-run |
| 4 | Extensibility | Plugins (native + WASM), Docker plugin, remote cache |
| 5 | Toolchain Management | 8 languages, auto-install, PATH injection, `zr tools` CLI |
| 6 | Monorepo Intelligence | Affected detection, graph viz (ASCII/DOT/JSON/HTML), constraints |
| 7 | Multi-repo & Remote Cache | S3/GCS/Azure/HTTP backends, cross-repo tasks, synthetic workspace |
| 8 | Enterprise & Community | CODEOWNERS, versioning, analytics, conformance, benchmarks |
| 9 | Infrastructure + DX | LanguageProvider (8 langs), JSON-RPC, "Did you mean?", error improvements |
| 10 | MCP Server | 9 MCP tools, `zr init --detect` auto-generation |
| 11 | LSP Server | Diagnostics, completion, hover/go-to-definition |
| 12 | Performance & Stability | Binary optimization, fuzz testing, benchmark dashboard |
| 13 | v1.0 Release | 6 user guides, migration tools, README overhaul, install scripts |

## Architecture (High-Level)

```
CLI Interface → Config Engine → Task Graph Engine → Execution Engine → Plugin System
                     ↓                                      ↓
              Expression Engine                    Toolchain Manager
                     ↓                                      ↓
              LanguageProvider                    Remote Cache (S3/GCS/Azure/HTTP)
```

### Key Modules (src/)
- `main.zig` (~550 lines) — Entry point + CLI dispatcher (34+ commands)
- `cli/` (34 modules) — Command handlers for all features
- `config/` (5 modules) — TOML loader, parser, types, matrix, expression engine
- `graph/` — DAG, topological sort, cycle detection, visualization
- `exec/` — Scheduler, worker pool, process management, resource monitoring
- `plugin/` (7 modules) — Dynamic loading, git/registry install, built-ins (Docker, env, git, cache), WASM runtime
- `watch/` — Native filesystem watchers (inotify/kqueue/ReadDirectoryChangesW)
- `toolchain/` — Types, installer, downloader, PATH injection
- `cache/` — Local store + remote backends (S3/GCS/Azure/HTTP)
- `multirepo/` — Sync, status, graph, run, synthetic workspace
- `output/` — Terminal rendering, color (sailor.color), progress (sailor.progress)
- `util/` — Glob, semver, hash, platform wrappers, affected detection

## Sailor Library Integration

- **Current version**: v0.5.1 (in build.zig.zon)
- **Latest available**: v1.0.2 (released 2026-02-28)
- **Migration pending**: Update to v1.0.2 for theme system, animations, local TTY workaround removal
- Modules using sailor: arg parsing (main.zig), color (color.zig), progress (progress.zig), JSON formatting (cli/), TUI widgets (tui.zig, tui_runner.zig)

## Post-v1.0 Development (In Progress)

### Completed Milestones
- v1.1.0 - v1.8.0: See CHANGELOG.md

### Current Work (v1.9.0)
- **Sailor v1.1.0 Accessibility Features**
  - ✅ Unicode width calculation (CJK/emoji support)
  - ✅ Enhanced keyboard navigation (Home/End/PgUp/PgDn/g/G)
  - 🔄 Accessibility metadata (screen reader hints) - in progress
  - 🔄 Focus management for TUI widgets - planned

### Next Priorities
1. Complete v1.9.0 accessibility features
2. v1.10.0 — Task Dependencies v2 (conditional deps, optional deps)
3. v1.11.0 — Plugin Registry Index Server
4. v1.12.0 — TOML Workflow Parser Fix

## Documentation

- `docs/PRD.md` — Product Requirements Document (v3.0, 2085 lines)
- `docs/guides/` — 6 user guides (getting-started, configuration, commands, mcp-integration, lsp-setup, adding-language)
- `docs/PLUGIN_GUIDE.md` — Plugin user guide
- `docs/PLUGIN_DEV_GUIDE.md` — Plugin developer guide
- `CONTRIBUTING.md` — Contributor onboarding guide
- `CHANGELOG.md` — Complete version history
- `examples/` — 15 example projects (Docker/K8s, Make migration, 8 language providers, plugin)

## Performance Targets (All Met)

| Metric | Target | Actual |
|--------|--------|--------|
| Cold start | < 10ms | ~4ms |
| 100-task graph | < 5ms | < 5ms |
| Memory (core) | < 10MB | ~2-3MB RSS |
| Binary size | < 5MB | ~1.2MB |
| Cross-compile | 6 targets | 6/6 passing |
