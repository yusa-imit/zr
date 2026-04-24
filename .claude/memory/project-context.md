# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.76.0 (current in build.zig.zon) | Latest Release: v1.76.0 (2026-04-24)
- **Unit tests**: 1452/1460 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 1420 tests (some failures in add_interactive_test, not related to current work)
- **CI**: IN_PROGRESS (last check 2026-04-24)
- **GitHub Issues**: 6 open (5 zuda migrations, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~72,500+ lines, 95+ modules, 10 language providers
- **Latest work (2026-04-24, FEATURE Cycle 162)**: v1.76.0 Release (Task Conditional Dependencies Enhancement). Completed all 6 phases: (1) Expression engine enhancements (params.X, has_tag(), negation) ~234 LOC impl + 440 LOC tests. (2) Scheduler integration ~49 LOC impl. (3) 15 integration tests for runtime behavior ~511 LOC. (4) 18 integration tests for dry-run preview ~577 LOC. (5) Watch mode integration (already complete). (6) Comprehensive documentation guide ~680 LOC. Total deliverable: ~2051 LOC (283 impl + 1088 tests + 680 docs). Released v1.76.0 with GitHub release notes. All 1452 unit tests passing.

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

✅ **Task Conditional Dependencies Enhancement** — COMPLETE (v1.76.0 released 2026-04-24)

🚧 **Enhanced Task Filtering & Selection Patterns** (READY - Next priority)
- Advanced glob patterns for task selection
- Multi-criteria filtering (tags, aliases, execution state)
- Inverse selection patterns
- Estimated: 2-3 cycles

**READY milestones**: 1 remaining (Enhanced Task Filtering & Selection Patterns)
**BLOCKED milestones**: 2 (zuda Graph Migration, zuda WorkStealingDeque)
