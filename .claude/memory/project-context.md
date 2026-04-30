# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.80.0 (current in build.zig.zon) | Latest Release: v1.80.0 (2026-04-30)
- **Unit tests**: 1487/1495 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 37 artifact management tests + existing tests
- **CI**: In progress (triggered by v1.80.0 release)
- **GitHub Issues**: 3 open (3 zuda migrations), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.4.0 (migrated 2026-04-30, Cycle 188)
- **Source**: ~75,600+ lines, 98 modules, 10 language providers
- **Latest work (2026-04-30, FEATURE Cycle 188)**: ✅ Sailor v2.3.0 & v2.4.0 Migration — Completed batch migration from sailor v2.1.0 → v2.4.0. Updated build.zig.zon dependency. All unit tests passing (1487/1495). Zero code changes required (backward compatible). Closed issues #55, #56. New features available for future use: v2.3.0 (scrollable widgets, state persistence, advanced styling, LazyBuffer/VirtualList), v2.4.0 (snapshot testing, property-based testing, visual regression, mock terminal, test utilities). Commits: 52c0ee9 (migration), 5ae25ec (milestones update). Previous work (Cycle 187): v1.80.0 RELEASE — Task Output Artifacts & Persistence milestone complete.

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

✅ **v1.80.0 Release** — COMPLETE (Cycles 182, 184, 186, 187 FEATURE session)
- Task Output Artifacts & Persistence milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.80.0
- Deliverables: ~560 LOC implementation + 37 integration tests
- All unit tests passing (1487/1495)
- 0 bug issues open

🎯 **Next Work** — Choose from READY milestones
- **READY milestones**: 3 (Task Result Caching, Enhanced Watch Mode, Dependency Resolution)
- **BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
- **Recommended**: Task Result Caching (3-4 cycles, ~1200 LOC) or Enhanced Watch Mode (2-3 cycles, ~1030 LOC)
