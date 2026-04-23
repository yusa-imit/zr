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
- **Latest work (2026-04-23, FEATURE Cycle 158)**: Dual release v1.74.0 + v1.75.0. Completed Task Parameters documentation (f554cb6, 620 LOC). Released v1.74.0 (Up-to-Date Detection) and v1.75.0 (Task Parameters) — total ~3400 LOC across 8 commits, cycles 148-158. Both releases published to GitHub with comprehensive release notes. 0 READY milestones remaining (only 2 BLOCKED).

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

✅ Releases complete: v1.74.0 + v1.75.0 (2026-04-23)
Next priority: **Milestone Establishment Process** — 0 READY milestones remaining
- Review BLOCKED milestones (zuda Graph, zuda WorkStealingDeque)
- Identify new feature/enhancement opportunities
- Create 2-3 new READY milestones for next cycles
- Update docs/milestones.md with proposals
