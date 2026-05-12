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
- **Unit tests**: ✅ Passing (1638 passed, 8 skipped, 0 failed) — all memory leaks fixed (Cycle 224)
- **Integration tests**: Ready to run (unit tests passing)
- **CI**: ⚠️ In progress (recent push)
- **GitHub Issues**: 5 open (4 zuda migrations, 1 util migration), **0 panic bugs**, **0 memory leak bugs**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.8.0 (upgraded 2026-05-10, Cycle 220 STABILIZATION)
- **zuda version**: v2.0.4 (upgraded 2026-05-11, Cycle 223 FEATURE - fixes #23/#24)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-12, FEATURE Cycle 226)**: ✅ **zuda Graph Migration Assessment** — Evaluated Issue #37 (migrate graph algorithms to zuda). Current status: DAG data structure uses zuda.containers.graphs.AdjacencyList (✅ COMPLETE in Cycles 223-224), providing memory/cache benefits. Topological sort and cycle detection remain custom Kahn's algorithm implementations operating on zuda's graph (decision: keep custom for API compatibility, battle-tested code). Closed #37 with detailed status. Previous (Cycle 224): DAG memory leak fixes.

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
- **READY milestones**: 0 (all post-v1.0 milestones are DONE or BLOCKED per `docs/milestones.md`)
- **COMPLETED**: zuda Graph Migration (Cycle 226) — DAG uses zuda AdjacencyList, Issue #37 closed
- **BLOCKED milestones**: Multiple (zuda WorkStealingDeque, utility migrations) - awaiting upstream features
- **Current priority**: Monitor open issues for bug reports, implement new post-v1.0 features as milestones become READY
