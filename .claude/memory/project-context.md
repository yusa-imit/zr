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
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~71,000+ lines, 95+ modules, 10 language providers
- **Latest work (2026-04-24, FEATURE Cycle 159)**: Milestone Establishment + Sailor v2.1.0 Migration. (1) Established 3 new READY milestones (commit 320fc43). (2) Completed Sailor v2.1.0 migration (commit a485dee): updated build.zig.zon, fixed 4 Rect.new() call sites, all unit tests passing (1434/1442), closed issue #54. Performance: +38% buffer diff, +34% fill, +33% set. 2 READY milestones remaining.

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

✅ Sailor v2.1.0 Migration: COMPLETE (Cycle 159, commit a485dee)
Next priority: **Task Conditional Dependencies Enhancement** (2-3 cycle estimate)
- Enhance expression engine for robust conditional operator support
- Add env var, param, platform, tag-based condition functions
- Integrate with watch mode and dry-run
- Comprehensive integration tests + documentation

**Other READY milestone**:
- Enhanced Task Filtering & Selection Patterns (2-3 cycles)
