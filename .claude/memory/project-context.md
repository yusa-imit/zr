# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.77.0 (current in build.zig.zon) | Latest Release: v1.77.0 (2026-04-25)
- **Unit tests**: 1452/1460 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 1420+ tests (16 new task filtering tests added)
- **CI**: GREEN (last check 2026-04-25)
- **GitHub Issues**: 6 open (5 zuda migrations, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~73,200+ lines, 96 modules, 10 language providers
- **Latest work (2026-04-25, STABILIZATION Cycle 165)**: v1.77.0 RELEASED. Enhanced Task Filtering & Selection Patterns milestone complete. GitHub release published with comprehensive notes. Features: glob patterns (*, **, ?), tag filtering (--tag, --exclude-tag), combined filters, dry-run preview, multiple task execution with dependency ordering. Total: ~1233 LOC (219 impl + 379 tests + 635 docs) across 3 commits (83566b4, 5d4a47a, c29df67). Release commits: 64885d3 (version bump), df13a16 (milestone update). All tests passing.

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

✅ **v1.77.0 Release** — COMPLETE (Cycle 165, STABILIZATION session)
- Enhanced Task Filtering & Selection Patterns milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.77.0
- Deliverables: ~1233 LOC (219 impl + 379 tests + 635 docs)
- All unit tests passing (1452/1460)
- 0 bug issues open

🎯 **Next Priority** — Milestone Establishment
- Current status: 0 READY milestones, 2 BLOCKED (zuda migrations)
- Action: Establish 2-3 new READY milestones for upcoming work
- Candidates: Performance profiling, error message enhancements, advanced caching strategies
- Timeline: Cycle 166+

**READY milestones**: 0 (need new milestone establishment)
**BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
