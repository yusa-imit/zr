# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.84.0 (build.zig.zon) | Latest Release: v1.84.0 (2026-06-01)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.85.0 (current in build.zig.zon) | Latest Release: v1.85.0 (2026-06-02)
- **Unit tests**: ✅ Passing (1729 passed, 8 skipped, 0 failed)
- **Integration tests**: 109 test files + explain tests 15015-15020 — comprehensive coverage
- **Test coverage**: ~98% (202/207 files) — exceeds 80% threshold
- **CI**: Running (pushed v1.85.0 version bump)
- **GitHub Issues**: 0 open, **0 bugs**, **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.13.0 (upgraded in v1.84.0 cycle)
- **zuda version**: main@4ff2325 (upgraded 2026-05-21, Cycle 259 FEATURE — includes detectCycle fix)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-06-02, FEATURE Cycle 309)**: ✅ **v1.85.0 Released** — Task Explain & Execution Preview milestone complete. Added history-based duration estimates (~Xs per task, total), integration tests 15015-15020 (timeout/env/required_env/skip_if/cache/sources display). GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.85.0

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

🎯 **Next Work** — Post-v1.0 Feature Development
- **ACTIVE milestones**: 1 (Code Quality & Documentation Polish — continuous improvement)
- **READY milestones**: 0
- **Current priority**: Establish new milestone for next feature (v1.86.0).
