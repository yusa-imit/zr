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
- **Unit tests**: ✅ Passing (1640 passed, 6 skipped, 0 failed) — ⚠️ 58 tests leak memory (Issue #61)
- **Integration tests**: Ready to run (unit tests passing)
- **CI**: ⚠️ Failing due to memory leaks (tests pass but exit code 1 from allocator)
- **GitHub Issues**: 6 open (5 zuda migrations + 1 memory leak bug), **0 panic bugs**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.8.0 (upgraded 2026-05-10, Cycle 220 STABILIZATION)
- **zuda version**: v2.0.4 (upgraded 2026-05-11, Cycle 223 FEATURE - fixes #23/#24)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-12, FEATURE Cycle 224)**: ✅ **DAG.getNode() Fix (COMPLETE)** — Fixed CI-blocking null pointer panic in buildDag tests. Implemented DAG.getNode() to allocate Node from zuda graph data. Updated all test call sites to deinit returned nodes. All buildDag tests passing. Filed Issue #61 for memory leaks (separate concern). Previous (Cycle 223): zuda v2.0.4 Graph Migration (partial).

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

🎯 **Next Work** — zuda Graph Migration
- **READY milestones**: 1 (zuda Graph Migration - UNBLOCKED with v2.0.4 release)
- **IN PROGRESS**: zuda Graph Migration (Cycle 223) — compiles, tests failing, needs runtime debugging
- **BLOCKED milestones**: 1 (zuda WorkStealingDeque depends on Graph completion)
- **Current priority**: Fix DAG migration test failures, complete Graph Migration, then WorkStealingDeque
