# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.113.1 (build.zig.zon) | Latest Release: v1.113.1 (2026-09-01)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.113.1 (released 2026-09-01, Cycle 439)
- **Unit tests**: ✅ Passing (1797 passed, 8 skipped, 0 failed as of Cycle 444)
- **Integration tests**: ✅ Passing (2081 passed, 44 skipped, 0 failed as of Cycle 444)
- **CI**: Green (issue #124 CI-red saga fully resolved and closed as of Cycle 439)
- **GitHub Issues**: 0 open bug-label issues as of Cycle 444; only routine sailor migration issues appear
- **Sailor version**: v2.98.0 (migrated 2026-09-02 Cycle 444, issue #151, no breaking changes — new tooltip.zig auto-dismiss/fade-in and splitpane.zig drag-resize APIs, all opt-in)
- **Latest work (2026-09-02, Cycle 444)**: FEATURE mode session; found no active bug/feature-blocking issues, so per issue-priority protocol handled the sole open issue (#151, sailor v2.98.0 migration label) — build.zig.zon was already bumped by a prior uncommitted session state, verified full test suite green, committed, closed issue. No active PRD phase work remains (all 13 phases complete); only continuous "Code Quality & Documentation Polish" milestone is active.

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
