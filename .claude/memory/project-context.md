# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.82.0 (current in build.zig.zon) | Latest Release: v1.82.0 (2026-05-04)
- **Unit tests**: 1527/1535 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 46 cache tests + 5 watch mode tests + 37 artifact management tests + existing tests
- **CI**: Green (all tests passing on main)
- **GitHub Issues**: 5 open (5 zuda migrations), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.6.0 (migrated 2026-05-06, Cycle 209)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-07, STABILIZATION Cycle 210)**: ✅ **Test Coverage & Documentation** — Added documentation for help.zig unit tests (integration tests already exist). Unit tests pass (1629/1637, 8 skipped). Test coverage: 96.6% (200/207 files, 7 untested CLI files). CI was cancelled but tests pass locally. Commits: 2c7acf7 (counter), e814abc (help.zig docs). Previous: Sailor v2.5.0 & v2.6.0 Migration (Cycle 209). Next: Continue stabilization (integrate tests, check CI, polishing).

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

✅ **v1.81.0 Release** — COMPLETE (Cycles 189-193 FEATURE session)
- Enhanced Watch Mode & Live Reload milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.81.0
- Deliverables: ~2098 LOC (1328 impl + 165 tests + 605 docs)
- All unit tests passing (1516/1524)
- 0 bug issues open

🎯 **Next Work** — Choose from READY milestones
- **READY milestones**: 2 (Task Result Caching & Memoization, Dependency Resolution & Version Constraints)
- **BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
- **Recommended**: Task Result Caching (3-4 cycles, ~1200 LOC) — content-based caching with local/remote backends for intelligent task output memoization similar to Nx/Turborepo
