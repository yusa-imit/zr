# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.44.0 (build.zig.zon) | Latest Release: v1.43.0 (2026-03-16)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.44.0 (fixup release)
- **Unit tests**: 845/853 (8 skipped, 0 failed, 0 memory leaks)
- **Integration tests**: 957/958 (1 skipped, 0 failed, 0 memory leaks)
- **CI**: GREEN — all 6 cross-compile targets passing
- **GitHub Issues**: 5 open (#21-25, all zuda migration enhancements, blocked on zuda releases)
- **Binary**: ~1.2MB ReleaseSmall, ~9.5MB debug, ~4ms cold start
- **Sailor version**: v1.16.0 (all migrations complete)
- **Source**: ~63,645 lines, 90+ modules, 10 language providers

## All PRD Phases COMPLETE ✅

13 phases fully implemented. See `docs/PRD.md` for detailed requirements.

| Phase | Name | Status |
|-------|------|--------|
| 1–13 | MVP through v1.0 Release | ✅ COMPLETE |

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
- `exec/` (7 modules) — Scheduler, worker pool, resource monitoring, hooks, timeline
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
- **Latest available**: v1.16.0 (terminal capabilities release)
- **Key features**: Terminal capability database, bracketed paste mode, synchronized output, hyperlink support (OSC 8), focus tracking, syntax highlighting, session recording, accessibility (WCAG AAA), mouse input, particle effects, data visualization

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
