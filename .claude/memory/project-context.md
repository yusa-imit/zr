# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.109.0 (build.zig.zon) | Latest Release: v1.109.0 (2026-06-28)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.109.0 (current in build.zig.zon) | Latest Release: v1.109.0 (2026-06-28)
- **Unit tests**: ✅ Passing (1771 passed, 8 skipped, 0 failed)
- **Integration tests**: 116 test files — comprehensive coverage (39000-39005 for --summary run table)
- **Test coverage**: ~98% file coverage — exceeds 80% threshold
- **CI**: Green (all cancelled = no failures)
- **GitHub Issues**: 0 open bugs
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.63.0 (upgraded in v1.109.0 cycle — ActivityFeed widget, no breaking changes)
- **zuda version**: main@4ff2325 (upgraded 2026-05-21, Cycle 259 FEATURE — includes detectCycle fix)
- **Source**: ~78,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-06-28, FEATURE Cycle 374)**: ✅ **v1.109.0 RELEASED** — Run Summary Table (--summary, formatted per-task table after all tasks complete), sailor v2.63.0 migration (ActivityFeed). 6 integration tests (39000-39005). GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.109.0
- **Previous work (2026-06-28, FEATURE Cycle 373)**: ✅ **v1.108.0 Released** — Output-On-Failure (--output-on-failure, buffers task output and shows only for failed tasks), sailor v2.62.0 migration (BracketViewer). 6 integration tests (38000-38005). GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.108.0

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

✅ **v1.85.0 Release** — COMPLETE (Cycle 309 FEATURE session)
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.85.0
- Features: zr explain (--tree/--json/--multi), zr run --explain, history-based duration estimates
- Integration tests: 21 tests (15000-15020)

✅ **v1.84.0 Release** — COMPLETE (Cycle 303 FEATURE session)
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.84.0
- Features: --only flag, required_env, --sort for list, [vars] section, parser fixes, test 874 fix

✅ **v1.88.0 Release** — COMPLETE (Cycle 323 FEATURE session)
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.88.0
- Features: input_prompt field, --input/--non-interactive, type+choices validation, explain integration
- Integration tests: 13 tests (18000-18012)

🎯 **Next Work** — Post-v1.0 Feature Development
- **ACTIVE milestones**: 1 (Code Quality & Documentation Polish — continuous improvement)
- **READY milestones**: 0
- **Current priority**: Establish new milestone for next feature (v1.89.0).
