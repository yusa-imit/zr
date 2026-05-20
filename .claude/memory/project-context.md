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
- **Unit tests**: ✅ Passing (1647 passed, 8 skipped, 0 failed)
- **Integration tests**: 107 test files - comprehensive coverage
- **Test coverage**: 97.6% (201/206 files) — exceeds 80% threshold
- **CI**: Recent runs cancelled (not failed) - likely manual intervention
- **GitHub Issues**: 1 open (zuda migration #65 - **BLOCKED** yusa-imit/zuda#28), **0 panic bugs**, **0 memory leak bugs**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.10.1 (upgraded 2026-05-17, Cycle 245 STABILIZATION — zero functional changes, test reliability patch)
- **zuda version**: v2.0.4+f95785b (upgraded 2026-05-20, Cycle 257 FEATURE — commit with Zig 0.15 toOwnedSlice fix, awaiting v2.0.5 release)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-21, FEATURE Cycle 258)**: ⏸️ **zuda Migration BLOCKED** — Attempted migration to zuda.compat.zr_dag but discovered compilation error in detectCycle() return type mismatch (!?[][]const u8 vs ![][]const u8). Filed upstream issue yusa-imit/zuda#28. Tested both commit f95785b and latest 5eb27dc — bug exists in both. Per CLAUDE.md policy (no local workarounds), migration work paused until upstream fix. Code quality audit completed: tests have meaningful assertions (no always-true tests), deinit tests verify state, error messages follow ✗ + Hint pattern, README/docs up-to-date (v1.82.0). Unit tests: 1647/1655 passing (8 skipped). 1 commit (session counter).

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
- **READY milestones**: 0
- **BLOCKED milestones**: 1 (Issue #65 zuda Graph Migration - yusa-imit/zuda#28 detectCycle type bug, ETA 1-2 days)
- **COMPLETED (Cycle 229)**: Test cleanup — removed obsolete zuda_migration_test.zig (dead code)
- **COMPLETED (Cycle 228)**: zuda WorkStealingDeque Migration — analyzed scheduler, removed unused code, closed all migration issues
- **COMPLETED (Cycle 226-227, 232)**: zuda Graph Migration — DAG migrated to zuda AdjacencyList, levenshtein→editDistance, glob→globMatch. Topo sort kept custom (edge semantics incompatibility), documented in #62
- **Current priority**: Wait for zuda#28 fix, then resume #65 migration. Meanwhile, Code Quality milestone (continuous).
