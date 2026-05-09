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
- **Unit tests**: 1634/1642 passing (8 skipped), 0 failed (+7 net tests from quality improvements)
- **Integration tests**: 46 cache tests + 5 watch mode tests + 37 artifact management tests + existing tests
- **CI**: Pending (awaiting build completion for commit 3d1daa7)
- **GitHub Issues**: 5 open (5 zuda migrations - all BLOCKED awaiting zuda fixes), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.7.0 (upgraded 2026-05-08, Cycle 214)
- **zuda version**: v2.0.3 (upgraded 2026-05-07, Cycle 211)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-05-10, FEATURE Cycle 219)**: ✅ **Documentation & Code Quality** — Updated README version badge from v1.68.1 to v1.82.0. Fixed 2 TODO comments in src/cli/deps.zig: replaced hardcoded timestamp with std.time.timestamp(), replaced hardcoded version "1.82.0" with build_options.version for consistency. All 1634 tests passing (96.6% coverage, 200/207 files tested). Previous (Cycle 217): Test Quality Audit. Next: Continue polishing tasks.

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

🎯 **Next Work** — Polishing & Maintenance
- **READY milestones**: 0 (all current milestones BLOCKED)
- **BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.4+ fixes for issues #23/#24, zuda WorkStealingDeque depends on Graph)
- **Current priority**: Wait for zuda fixes, perform polishing tasks (test quality audit, documentation improvements, code cleanup, performance optimizations)
