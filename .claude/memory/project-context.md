# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.81.0 (current in build.zig.zon) | Latest Release: v1.81.0 (2026-05-01)
- **Unit tests**: 1516/1524 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 5 watch mode tests + 37 artifact management tests + existing tests
- **CI**: Green (no failures on main)
- **GitHub Issues**: 6 open (6 zuda migrations), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.4.0 (migrated 2026-04-30, Cycle 188)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-01, FEATURE Cycle 193)**: ✅ v1.81.0 RELEASE — Enhanced Watch Mode & Live Reload milestone complete. Intelligent file watching with adaptive debouncing (burst detection, sporadic detection, smooth ramping 300ms-3000ms) and browser auto-refresh via WebSocket server (port 35729, LiveReload protocol). Implementation: ~1328 LOC (debounce.zig, livereload.zig, CLI integration). Testing: ~165 LOC (unit + integration). Documentation: ~605 LOC guide. Total: ~2098 LOC across Cycles 189-192. GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.81.0. Commits: 269188a (version bump), da10ff6 (docs), 0048975 (milestone update). Previous work (Cycle 188): Sailor v2.3.0 & v2.4.0 Migration.

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
