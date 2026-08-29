# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.113.0 (build.zig.zon) | Latest Release: v1.113.0 (2026-06-30)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.113.0 (still current in build.zig.zon — no minor release since; sailor jumped ahead independently)
- **Unit tests**: ✅ Passing (1779 passed, 8 skipped, 0 failed)
- **Integration tests**: ✅ Passing (2076 passed, 44 skipped, 0 failed as of Cycle 428)
- **CI**: Was red since v1.113.0 (issue #124) for ~2 months across many sessions — RESOLVED 2026-08-28 Cycle 428. Final root cause was 23 tests leaking `ZrResult`/allocated-path memory in 3 test files (see debugging.md). Push 830a5e2 should be the first fully-green `main` CI run in a long time — verify next session.
- **GitHub Issues**: bug-label issues should be 0 after #124's fix lands; re-check `gh issue list --label bug` next session
- **Sailor version**: v2.96.0 (migrated 2026-08-28 Cycle 428, closing #119-#148 in one batch — was stuck at v2.70.0 for ~2 months while ~30 migration issues piled up unaddressed)
- **Next sailor migration issue**: #149 (v2.96.1)
- **Latest work (2026-08-28, Cycle 428)**: Finished a prior uncommitted session's fix for leaked test allocations (28000_includes_test.zig, integration_imports.zig), extended the same fix to integration_path_separator.zig, committed the already-fetched sailor v2.96.0 bump, closed 30 stale migration issues (#119-#148). No new feature/version release this cycle — was entirely a stabilization catch-up.

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
