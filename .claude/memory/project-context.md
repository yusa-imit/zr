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
- **Integration tests**: 1420+ tests (16 new task filtering tests added, integration-test still running)
- **CI**: IN_PROGRESS (last check 2026-04-25)
- **GitHub Issues**: 6 open (5 zuda migrations, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~73,200+ lines, 96 modules, 10 language providers
- **Latest work (2026-04-25, FEATURE Cycle 164)**: Enhanced Task Filtering & Selection Patterns COMPLETE. Documentation phase: Created comprehensive docs/guides/task-selection.md (~635 LOC) covering glob patterns, tag filters, combinations, real-world examples, comparison with Bazel/Nx/Task/Just, best practices, troubleshooting. Updated docs/milestones.md to DONE status. Implementation from Cycle 163: task_selector.zig module (~124 LOC), CLI integration in main.zig (~95 LOC), 16 integration tests (~379 LOC). Total deliverable: ~1233 LOC (219 impl + 379 tests + 635 docs) across 3 commits. Ready for v1.77.0 release. All unit tests passing (1452/1460).

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

✅ **Enhanced Task Filtering & Selection Patterns** — COMPLETE (Cycle 163-164, ready for v1.77.0)

🎯 **v1.77.0 Release** (READY - Next priority)
- All release criteria met:
  - ✅ Milestone complete (Enhanced Task Filtering & Selection Patterns)
  - ✅ Tests passing (1452/1460 unit tests, 16 new integration tests)
  - ✅ Documentation complete (docs/guides/task-selection.md)
  - ✅ 0 bug issues open
- Release checklist:
  - [ ] Verify integration tests pass (zig build integration-test)
  - [ ] Bump version in build.zig.zon (v1.76.0 → v1.77.0)
  - [ ] Update CHANGELOG.md with v1.77.0 entry
  - [ ] Create git tag and GitHub release
  - [ ] Send Discord notification

**READY milestones**: 0 (all complete, ready for release)
**BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
