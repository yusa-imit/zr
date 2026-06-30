# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.113.0 (build.zig.zon) | Latest Release: v1.113.0 (2026-06-30)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.113.0 (current in build.zig.zon) | Latest Release: v1.113.0 (2026-06-30)
- **Unit tests**: ✅ Passing (1779 passed, 8 skipped, 0 failed)
- **Integration tests**: 118 test files — comprehensive coverage (41000-41005 for zr status)
- **Test coverage**: ~98% file coverage — exceeds 80% threshold
- **CI**: Was FAILED (test 991 timing regression from sailor v2.69.0 cycle) — FIXED in v1.113.0
- **GitHub Issues**: 0 open bugs; #115 (sailor v2.70.0) closed
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.70.0 (upgraded in v1.113.0 cycle — MatrixView widget, no breaking changes)
- **zuda version**: main@4ff2325 (upgraded 2026-05-21, Cycle 259 FEATURE — includes detectCycle fix)
- **Source**: ~78,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-06-30, FEATURE Cycle 382)**: ✅ **v1.113.0 RELEASED** — `zr status` command (config path, task count, last-run failures, --json support), sailor v2.70.0 migration, CI timing fix (test 991: 1000ms→5000ms bound). 6 integration tests (41000-41005). GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.113.0
- **Previous work (2026-06-29, FEATURE Cycle 378)**: ✅ **v1.111.0 RELEASED** — `--env-file <path>` flag for `zr run`. GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.111.0

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
