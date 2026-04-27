# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.79.0 (current in build.zig.zon) | Latest Release: v1.79.0 (2026-04-28)
- **Unit tests**: 1484/1492 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 1551/1565 passing (14 skipped, 0 failed)
- **CI**: In progress (triggered by v1.79.0 release)
- **GitHub Issues**: 7 open (5 zuda migrations, 1 sailor v2.3.0, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~75,030+ lines, 97 modules, 10 language providers
- **Latest work (2026-04-28, FEATURE Cycle 179)**: ✅ Completed Task Documentation & Rich Help System milestone (v1.79.0 RELEASED). Phase 3: Created comprehensive docs/guides/task-documentation.md (704 LOC) with rich descriptions, examples, parameter docs, output documentation, see_also, help command, real-world examples, best practices, migration guides, troubleshooting. Updated milestones.md: Task Documentation → DONE. Total milestone: ~3042 LOC (254 impl + 2084 tests + 704 docs) across 5 cycles (172-174, 177, 179). All tests passing (1484/1492). Commits: e047b66 (documentation + milestone), aa946e1 (version bump). GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.79.0. Previous work (Cycle 177): --verbose flag implementation. Previous work (Cycle 175): Fixed TTY-requiring tests. Previous work (Cycles 172-174): Schema + parser + 63 integration tests.

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

✅ **v1.79.0 Release** — COMPLETE (Cycles 172-174, 177, 179, FEATURE session)
- Task Documentation & Rich Help System milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.79.0
- Deliverables: ~3042 LOC (254 impl + 2084 tests + 704 docs)
- All unit tests passing (1484/1492)
- 0 bug issues open

🎯 **Next Work** — Choose from READY milestones or establish new milestones
- **READY milestones**: 1 (Task Output Artifacts & Persistence)
- **BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
- **Note**: Only 1 READY milestone remaining — should establish 2-3 new milestones for future work
