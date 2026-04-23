# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.75.0 (current in build.zig.zon) | Latest Release: v1.75.0 (2026-04-23)
- **Unit tests**: 1434/1442 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: Passing
- **CI**: IN_PROGRESS (last check 2026-04-23)
- **GitHub Issues**: 7 open (5 zuda migrations, 1 sailor v2.1.0, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v1.38.0 (all migrations complete through v1.38.0)
- **Source**: ~71,000+ lines, 95+ modules, 10 language providers
- **Latest work (2026-04-24, FEATURE Cycle 159)**: Milestone Establishment Process executed. Created 3 new READY milestones: (1) Sailor v2.1.0 Migration (drop-in upgrade, issue #54, 1 cycle), (2) Task Conditional Dependencies Enhancement (robust expr eval, 2-3 cycles), (3) Enhanced Task Filtering & Selection Patterns (glob/tag-based selection, 2-3 cycles). Updated docs/milestones.md with detailed scope, implementation plan, testing strategy. Next: Begin Sailor v2.1.0 migration.

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

✅ Milestone Establishment: 3 new READY milestones created (Cycle 159)
Next priority: **Sailor v2.1.0 Migration** (highest priority, 1 cycle estimate)
- Drop-in dependency upgrade (issue #54)
- Zero code changes required (backward compatible)
- +38% buffer diff, +34% buffer fill, +33% buffer set performance
- Steps: zig fetch, run tests, close issue, commit

**Other READY milestones** (2-3 cycle estimates each):
- Task Conditional Dependencies Enhancement
- Enhanced Task Filtering & Selection Patterns
