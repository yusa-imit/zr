# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.77.0 (current in build.zig.zon) | Latest Release: v1.77.0 (2026-04-25)
- **Unit tests**: 1452/1460 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 1420+ tests (16 new task filtering tests added)
- **CI**: GREEN (last check 2026-04-25)
- **GitHub Issues**: 6 open (5 zuda migrations, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~73,200+ lines, 96 modules, 10 language providers
- **Latest work (2026-04-25, FEATURE Cycle 167)**: env_file parser integration complete. Added env_file parameter to addTaskImpl signature (46th param), updated 13 call sites across parser.zig/types.zig/matrix.zig, parser supports both single string and array syntax for env_file field. Commit 50da7cf completes schema integration after env_loader.zig module (commit 5a126dd). All 1452 unit tests passing. Part of Enhanced Environment Variable Management milestone (v1.78.0, ~10% complete). Next: runtime loading of .env files in scheduler.zig.

## PRD Phase Status

| Phase | Name | Status |
|-------|------|--------|
| 1–11 | MVP through LSP Server | ✅ COMPLETE |
| 12A | Binary Optimization | ✅ COMPLETE |
| 12B | Fuzz Testing | ✅ COMPLETE |
| 12C | Benchmark Dashboard | ✅ COMPLETE (scripts + RESULTS.md) |
| 13A | Documentation Site | ✅ COMPLETE (7 guides) |
| 13B | Migration Tools | ✅ COMPLETE |
| 13C | v1.0 Release | ✅ COMPLETE |

## Next Action

✅ **v1.77.0 Release** — COMPLETE (Cycle 165, STABILIZATION session)
- Enhanced Task Filtering & Selection Patterns milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.77.0
- Deliverables: ~1233 LOC (219 impl + 379 tests + 635 docs)
- All unit tests passing (1452/1460)
- 0 bug issues open

🎯 **Next Priority** — Enhanced Environment Variable Management (v1.78.0)
- Status: READY, ~10% complete (schema + loader done, runtime integration pending)
- Completed: env_file schema (types.zig), .env file loader module (env_loader.zig), parser integration
- Next: Runtime .env loading in scheduler.zig (load files before task execution, merge with task env)
- Estimate: 2-3 more cycles to complete (runtime integration + CLI flags + tests + docs)

**READY milestones**: 0 (need new milestone establishment)
**BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
