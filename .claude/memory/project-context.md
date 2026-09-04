# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.114.0 (build.zig.zon) | Latest Release: v1.114.0 (2026-09-05)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.114.0 (released 2026-09-05, Cycle 451)
- **Unit tests**: ✅ Passing (1798 passed, 8 skipped, 0 failed as of Cycle 451)
- **Integration tests**: ✅ Passing (2087 passed, 44 skipped, 0 failed as of Cycle 451)
- **CI**: Green
- **GitHub Issues**: 0 open issues as of Cycle 451
- **Sailor version**: v2.99.0 (no breaking changes)
- **Latest work (2026-09-05, Cycle 451)**: FEATURE mode session; found a prior session's finished-but-uncommitted work implementing Task Argument Passthrough (`zr run <task> -- <args...>` → shell-quoted `ZR_ARGS` env var), plus a new `tests/42000_task_args_test.zig` (6 tests). Verified full suite green, added help text for `--`, documented the milestone in `docs/milestones.md`, and released as v1.114.0 (minor release — new feature milestone completed with tests, 0 bug issues open).

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
