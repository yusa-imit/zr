# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.73.0 (current in build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Unit tests**: 1434/1442 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: Passing
- **CI**: IN_PROGRESS (last check 2026-04-23)
- **GitHub Issues**: 7 open (5 zuda migrations, 1 sailor v2.1.0, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v1.38.0 (all migrations complete through v1.38.0)
- **Source**: ~71,000+ lines, 95+ modules, 10 language providers
- **Latest work (2026-04-23, FEATURE Cycle 158)**: Task Parameters & Dynamic Task Generation milestone (COMPLETE 100%). All 5 phases done: (1) Schema (ca49ef2, 134 LOC), (2-3) Implementation+CLI (16d01eb, 234 LOC), (4) Tests (d3f0148, 776 LOC), (5) Documentation (f554cb6, 620 LOC). Milestone marked DONE (7f70db3). Total: ~1764 LOC across 4 commits. Ready for v1.75.0 release.

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

Task Parameters milestone complete (v1.75.0). Ready for release:
1. Verify integration tests pass (22 task_params tests)
2. Check release conditions (0 bugs ✅, tests pass, milestone DONE ✅)
3. Execute v1.75.0 release (MINOR - milestone complete)
4. After release: Milestone Establishment Process (need new READY milestones)
