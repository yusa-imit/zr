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
- **Unit tests**: 1452/1460 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 1420 tests (some failures in add_interactive_test, not related to current work)
- **CI**: IN_PROGRESS (last check 2026-04-24)
- **GitHub Issues**: 6 open (5 zuda migrations, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~72,500+ lines, 95+ modules, 10 language providers
- **Latest work (2026-04-24, FEATURE Cycle 160)**: Task Conditional Dependencies Enhancement (Phase 1-2 COMPLETE). (1) Expression engine enhancements (commit 57ba56b): Added params.param_name, has_tag('tag'), ! negation operator. Total: ~674 LOC (234 impl + 440 tests). (2) Scheduler integration (commit 58f80af): Added evalConditionalDep() API, updated scheduler deps_if evaluation (+49 LOC). (3) Integration tests (commit 7c43d45): 15 comprehensive tests for env-based, tag-based, combined, and edge case conditions (~511 LOC). All 1452 unit tests passing.

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

🚧 **Task Conditional Dependencies Enhancement** (IN PROGRESS - Cycle 160)
- ✅ Phase 1: Expression engine enhancements (params, has_tag, negation) — COMPLETE
- ✅ Phase 2: Scheduler integration — COMPLETE
- ✅ Phase 3: Integration tests (15 tests) — COMPLETE
- ⏳ Phase 4: Dry-run preview for conditional deps — PENDING
- ⏳ Phase 5: Watch mode integration — PENDING
- ⏳ Phase 6: Comprehensive documentation guide — PENDING

Estimated completion: 1-2 more cycles for remaining phases

**Other READY milestone**:
- Enhanced Task Filtering & Selection Patterns (2-3 cycles)
