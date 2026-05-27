# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.83.0 (build.zig.zon) | Latest Release: v1.83.0 (2026-05-27)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.83.0 (current in build.zig.zon) | Latest Release: v1.83.0 (2026-05-27)
- **Unit tests**: ✅ Passing (1705 passed, 8 skipped, 0 failed)
- **Integration tests**: 108 test files - comprehensive coverage (added notification_test.zig)
- **Test coverage**: ~98% (202/207 files) — exceeds 80% threshold
- **CI**: In progress (most recent pushes auto-cancelled due to rapid commits)
- **GitHub Issues**: 0 open, **0 bugs**, **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.10.1 (upgraded 2026-05-17, Cycle 245 STABILIZATION)
- **zuda version**: main@4ff2325 (upgraded 2026-05-21, Cycle 259 FEATURE — includes detectCycle fix)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-27, FEATURE Cycle 283)**: ✅ **v1.83.0 Released** — Desktop notifications (notify/notify_on/notify_title + --notify flag), --dir directory filter, --skip flag, error message standardization, bug fixes. Added src/exec/notification.zig, tests/notification_test.zig. Added *.a to .gitignore.

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

✅ **v1.83.0 Release** — COMPLETE (Cycle 283 FEATURE session)
- Enhanced Task Control & Developer Experience milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.83.0
- Features: Desktop notifications, --dir filter, --skip flag, error standardization, bug fixes
- All unit tests passing (1705/1713)
- 0 bug issues open

🎯 **Next Work** — Post-v1.0 Feature Development
- **ACTIVE milestones**: 1 (Code Quality & Documentation Polish — continuous improvement)
- **READY milestones**: 0
- **BLOCKED milestones**: 0
- **COMPLETED (Cycle 283)**: Enhanced Task Control & Developer Experience (v1.83.0)
- **COMPLETED (Cycle 229)**: Test cleanup — removed obsolete zuda_migration_test.zig (dead code)
- **COMPLETED (Cycle 228)**: zuda WorkStealingDeque Migration — analyzed scheduler, removed unused code
- **COMPLETED (Cycle 226-227, 232)**: zuda Graph Migration — DAG migrated to zuda AdjacencyList
- **Current priority**: Continue Code Quality & Documentation Polish milestone (continuous improvement).
