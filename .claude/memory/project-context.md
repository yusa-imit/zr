# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.88.0 (build.zig.zon) | Latest Release: v1.88.0 (2026-06-06)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.88.0 (current in build.zig.zon) | Latest Release: v1.88.0 (2026-06-06)
- **Unit tests**: ✅ Passing (1750 passed, 8 skipped, 0 failed)
- **Integration tests**: 110 test files — comprehensive coverage (18000-18012 for input_prompt)
- **Test coverage**: ~98% file coverage — exceeds 80% threshold
- **CI**: Running (pushed v1.88.0)
- **GitHub Issues**: 0 open, **0 bugs**, **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.13.0 (upgraded in v1.84.0 cycle)
- **zuda version**: main@4ff2325 (upgraded 2026-05-21, Cycle 259 FEATURE — includes detectCycle fix)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-06-06, FEATURE Cycle 323)**: ✅ **v1.88.0 Released** — Interactive Task Input Prompting: input_prompt field, --input/--non-interactive CLI flags, type+choices validation, resolved_params integration, zr explain integration. 13 integration tests (18000-18012). IMPORTANT: input_prompt arrays must be single-line in TOML (parser limitation). GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.88.0

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
