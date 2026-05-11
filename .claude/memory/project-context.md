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
- **Unit tests**: ⚠️ Failing (runtime crash during test suite - zuda migration in progress)
- **Integration tests**: Not run (blocked by unit test failures)
- **CI**: Pending (awaiting test fixes for commit aa8ee7e)
- **GitHub Issues**: 5 open (5 zuda migrations - #23/#24 FIXED in v2.0.4), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.8.0 (upgraded 2026-05-10, Cycle 220 STABILIZATION)
- **zuda version**: v2.0.4 (upgraded 2026-05-11, Cycle 223 FEATURE - fixes #23/#24)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-11, FEATURE Cycle 223)**: ⚙️ **zuda Graph Migration (IN PROGRESS)** — Migrating DAG/topological sort/cycle detection to zuda v2.0.4. Upgraded zuda dependency (fixes #23/#24 blocking issues). Replaced custom DAG implementation (187 LOC) with zuda.containers.graphs.AdjacencyList wrapper. Updated cycle_detect.zig and topo_sort.zig to use new DAG API. Compiles successfully, runtime tests failing (debugging needed). Previous (Cycle 222): Lock File Timestamp Fix.

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
