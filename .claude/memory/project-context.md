# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.49.0 (build.zig.zon) | Latest Release: v1.49.0 (2026-03-22)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.56.0 (current in build.zig.zon) | Latest Release: v1.56.0 (2026-03-26)
- **Unit tests**: 1151/1159 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: Passing (includes Windows platform tests)
- **CI**: IN_PROGRESS (last check 2026-03-26)
- **GitHub Issues**: 3 open (#22-24, zuda migrations)
- **Binary**: ~1.2MB ReleaseSmall, ~9.5MB debug, ~4-8ms cold start
- **Sailor version**: v1.22.0 (all migrations complete through v1.22.0)
- **Source**: ~70,000+ lines, 95+ modules, 10 language providers
- **Latest work (2026-03-26, FEATURE Cycle 18)**: Phase 12C Benchmark Dashboard complete. Removed incorrect "Natural Language AI Command (Phase 10C)" milestone (doesn't exist in PRD). Added Phase 12C and 13B milestones. Created comprehensive benchmarks/RESULTS.md with performance analysis vs Make/Just/Task. Commit: 142bff3.

## PRD Phase Status

| Phase | Name | Status |
|-------|------|--------|
| 1–11 | MVP through LSP Server | ✅ COMPLETE |
| 12A | Binary Optimization | ✅ COMPLETE |
| 12B | Fuzz Testing | ✅ COMPLETE |
| 12C | Benchmark Dashboard | ✅ COMPLETE (scripts + RESULTS.md) |
| 13A | Documentation Site | ✅ COMPLETE (7 guides) |
| 13B | Migration Tools | ❌ PENDING (next priority) |
| 13C | v1.0 Release | ⏸️ PENDING (awaits 13B) |

## Architecture (High-Level)

```
CLI Interface → Config Engine → Task Graph Engine → Execution Engine → Plugin System
                     ↓                                      ↓
              Expression Engine                    Toolchain Manager (10 langs)
                     ↓                                      ↓
              LanguageProvider                    Remote Cache (S3/GCS/Azure/HTTP)
```

### Key Modules (src/)
- `main.zig` (~550 lines) — Entry point + CLI dispatcher (34+ commands)
- `cli/` (34 modules) — Command handlers (run, list, graph, watch, plugins, etc.)
- `config/` (5 modules) — TOML loader, parser, expression engine, matrix expansion
- `exec/` (9 modules) — Scheduler, worker pool, resource monitoring, hooks, timeline, remote execution (SSH/HTTP)
- `graph/` — DAG, topological sort, cycle detection, visualization
- `plugin/` (8 modules) — Dynamic loading, registry client, built-ins, WASM runtime
- `watch/` — Native filesystem watchers (inotify/kqueue/ReadDirectoryChangesW)
- `toolchain/` — Installer, downloader, PATH injection (10 languages)
- `cache/` — Local + remote backends (S3/GCS/Azure/HTTP)
- `multirepo/` — Sync, status, graph, workspace orchestration
- `output/` — Terminal rendering (sailor.color, sailor.progress)
- `util/` — Glob, platform wrappers, affected detection, semver, hash

## Sailor Library

- **Current in zr**: v1.16.0 ✅
- **Status**: All migrations complete (v1.1.0 → v1.16.0)
- **Latest available**: v1.18.0 (hot reload, widget inspector, benchmarks)
- **Key features**: Terminal capability database, bracketed paste mode, synchronized output, hyperlink support (OSC 8), focus tracking, syntax highlighting, session recording, accessibility (WCAG AAA), mouse input, particle effects, data visualization, hot reload for themes, widget inspector, benchmark suite

## Post-v1.0 Milestones

**Completed**: v1.1.0 – v1.43.0 (see CHANGELOG.md for details)

**Blocked** (waiting for zuda releases):
- v1.35.0, v1.36.0 — zuda WorkStealingDeque, TaskPool migrations

**Active/Ready**:
- v1.40.0 — Syntax highlighting via sailor v1.13.0 features (already in v1.15.0)
- v1.41.0, v1.42.0 — Post-release enhancements

## Documentation

- `docs/PRD.md` — Complete product spec (13 phases)
- `docs/guides/` — 6 user guides (getting-started, configuration, commands, MCP, LSP, language-provider)
- `docs/milestones.md` — Active milestones, roadmap, dependency tracking
- `CHANGELOG.md` — Complete version history (v1.0.0 → v1.43.0)
- `CONTRIBUTING.md` — Contributor onboarding
- `examples/` — 19 example projects (15 language providers, plugin, Docker/K8s)

## Performance Targets (All Met)

| Metric | Target | Actual |
|--------|--------|--------|
| Cold start | < 10ms | ~4ms |
| 100-task graph | < 5ms | < 5ms |
| Memory (core) | < 10MB | ~2-3MB RSS |
| Binary size | < 5MB | ~1.2MB |
| Cross-compile | 6 targets | 6/6 passing |

## Next Action

Check `docs/milestones.md` for v1.40.0+ priorities. Current blockers: zuda library releases.
