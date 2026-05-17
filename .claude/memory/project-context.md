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
- **Unit tests**: ✅ Passing (1647 passed, 8 skipped, 0 failed) — fixed FileTooBig test failure Cycle 246
- **Integration tests**: 107 test files (added help_test.zig in Cycle 245)
- **Test coverage**: 97.6% (201/206 files) — exceeds 80% threshold
- **CI**: ⏳ In progress (checking latest run)
- **GitHub Issues**: 0 open, **0 panic bugs**, **0 memory leak bugs**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.10.1 (upgraded 2026-05-17, Cycle 245 STABILIZATION — zero functional changes, test reliability patch)
- **zuda version**: v2.0.4 (upgraded 2026-05-11, Cycle 223 FEATURE)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-18, FEATURE Cycle 246)**: 🐛 **Bug Fix** — Fixed pre-existing test failure: cmdHistory FileTooBig error caused by 1MB history file exceeding read limit. Increased history file size limit from 1MB→10MB (store.zig), increased test buffer sizes 4KB→64KB (run.zig), fixed cmdHistory test to use /dev/null writer. All tests now passing (1647/1647). Commits: 3b49d43 (counter→246), 0625379 (fix).

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
- **ACTIVE milestones**: 1 (Code Quality & Documentation Polish — continuous improvement, Cycle 243)
- **READY milestones**: 0 (all zuda migrations complete as of Cycle 228)
- **COMPLETED (Cycle 229)**: Test cleanup — removed obsolete zuda_migration_test.zig (dead code)
- **COMPLETED (Cycle 228)**: zuda WorkStealingDeque Migration — analyzed scheduler, removed unused code, closed all migration issues
- **COMPLETED (Cycle 226-227, 232)**: zuda Graph Migration — DAG migrated to zuda AdjacencyList, levenshtein→editDistance, glob→globMatch. Topo sort kept custom (edge semantics incompatibility), documented in #62
- **BLOCKED milestones**: 0 (all blockers resolved)
- **Current priority**: Code Quality & Documentation Polish milestone work items (incremental improvements to comments, docs, error messages)
