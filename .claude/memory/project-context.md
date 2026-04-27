# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.78.0 (current in build.zig.zon) | Latest Release: v1.78.0 (2026-04-26)
- **Unit tests**: 1483/1491 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 1551/1565 passing (14 skipped, 0 failed) — fixed TTY-requiring tests
- **CI**: Was in_progress for 30+ min (2026-04-27), new CI triggered by fix
- **GitHub Issues**: 6 open (5 zuda migrations, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~75,030+ lines, 97 modules (added help.zig), 10 language providers
- **Latest work (2026-04-27, FEATURE Cycle 177)**: ✅ Implemented `--verbose` flag for list command. Added flag parsing in main.zig, updated cmdList signature in list.zig with verbose parameter, and fixed call site in mcp/handlers.zig. Flag is currently backward-compatible (descriptions shown by default) and reserved for future use. All unit tests passing (1483/1491). Commits: 8d9489d (session counter), a2686e4 (--verbose implementation), b01636e (agent log). Previous work (2026-04-27, STABILIZATION Cycle 175): Fixed 15 failing TTY-requiring interactive tests. Previous work (2026-04-26, FEATURE Cycle 172-174): Task Documentation Phase 1 + parser TOML support complete with 34 parser integration tests.

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

✅ **v1.78.0 Release** — COMPLETE (Cycle 171, FEATURE session)
- Enhanced Environment Variable Management milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.78.0
- Deliverables: ~1413 LOC (268 impl + 495 tests + 650 docs)
- All unit tests passing (1483/1491)
- 0 bug issues open

🎯 **Current Work** — Task Documentation & Rich Help System (v1.79.0) — IN PROGRESS
- Status: Phase 1 COMPLETE, Phase 2 COMPLETE, Phase 3 PENDING
- **Phase 1 DONE** (Cycle 172):
  - ✅ Schema: TaskDescription union, examples/outputs/see_also fields
  - ✅ Help command: zr help <task> with formatted display
  - ✅ Tests: 29 integration tests (~967 LOC)
  - ✅ Backward compat: old string descriptions still work
  - Commits: 3e92791 (implementation), 6d752eb (tests)
- **Phase 2 DONE** (Cycles 173-174, 177):
  - ✅ Parse description.short and description.long tables
  - ✅ Parse examples array
  - ✅ Parse outputs table
  - ✅ Parse see_also array
  - ✅ List --verbose flag implementation (Cycle 177)
  - Commits: e28c8cf (parser), 394fce5 (34 parser tests), a2686e4 (--verbose flag)
- **Phase 3 NEEDED** (documentation):
  - ⏳ docs/guides/task-documentation.md (~400 LOC)
- Estimate remaining: 1 cycle (~400 LOC docs)

**READY milestones**: 2 (Task Documentation & Rich Help System, Task Output Artifacts & Persistence)
**BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
