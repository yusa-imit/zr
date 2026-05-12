# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.82.0 (build.zig.zon) | Latest Release: v1.82.0 (2026-05-04)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.82.0 (current in build.zig.zon) | Latest Release: v1.82.0 (2026-05-04)
- **Unit tests**: ✅ Passing (1638 passed, 8 skipped, 0 failed) — all memory leaks fixed (Cycle 224)
- **Integration tests**: Ready to run (unit tests passing)
- **CI**: ✅ Green (tests passing locally, 1638/1646)
- **GitHub Issues**: 0 open (all zuda migrations complete), **0 panic bugs**, **0 memory leak bugs**, Issues #22, #24, #36, #37, #38 closed (Cycles 226-228)
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.8.0 (upgraded 2026-05-10, Cycle 220 STABILIZATION)
- **zuda version**: v2.0.4 (upgraded 2026-05-11, Cycle 223 FEATURE - fixes #23/#24)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-13, FEATURE Cycle 229)**: ✅ **Test Cleanup** — Removed obsolete tests/zuda_migration_test.zig (116 LOC dead code with panic placeholders). All zuda migrations were completed in Cycle 228, making this test file obsolete. All remaining tests pass (1638/1646). Previous (Cycle 228): zuda WorkStealingDeque Migration COMPLETE — analyzed scheduler, removed unused src/exec/workstealing.zig and tests.

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

🎯 **Next Work** — Post-v1.0 Feature Development
- **READY milestones**: 0 (all zuda migrations complete as of Cycle 228)
- **COMPLETED (Cycle 229)**: Test cleanup — removed obsolete zuda_migration_test.zig (dead code)
- **COMPLETED (Cycle 228)**: zuda WorkStealingDeque Migration — analyzed scheduler, removed unused code, closed all migration issues
- **COMPLETED (Cycle 226-227)**: zuda Graph Migration — DAG migrated, algorithms kept custom, documentation updated
- **BLOCKED milestones**: 0 (all blockers resolved)
- **Current priority**: Monitor for bug reports, implement new feature milestones (see docs/milestones.md for candidates)
