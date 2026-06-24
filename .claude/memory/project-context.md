# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.105.0 (build.zig.zon) | Latest Release: v1.105.0 (2026-06-22)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.105.0 (current in build.zig.zon) | Latest Release: v1.105.0 (2026-06-22)
- **Unit tests**: ✅ Passing (1766 passed, 8 skipped, 0 failed)
- **Integration tests**: 112 test files — comprehensive coverage (34000-34005 for task priority)
- **Test coverage**: ~98% file coverage — exceeds 80% threshold
- **CI**: Green (all cancelled = no failures)
- **GitHub Issues**: 1 open (#100 — intermittent argv parsing, no fix yet), **0 actionable bugs**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.55.0 (upgraded in v1.105.0 cycle)
- **zuda version**: main@4ff2325 (upgraded 2026-05-21, Cycle 259 FEATURE — includes detectCycle fix)
- **Source**: ~78,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-06-25, FEATURE Cycle 363)**: Bug fixes for 8 open issues — #93 (template list FileNotFound crash), #95 (task CWD path resolution), #96 (validate builtin: source prefix), #99 (ci 'github' alias for 'github-actions'), #92 (cache key includes source file content), #94 (init --detect dedup), #98 (spinner overwrite on TTY), #90+#91 (MCP memory leak + protocol conformance). Added diagnostic hint for #100 (intermittent argv joining on macOS arm64). 1768 unit tests pass.
- **Previous work (2026-06-22, FEATURE Cycle 361)**: ✅ **v1.105.0 Released** — Task Priority Scheduling: priority = N field (i32), [p:N] badge in list, --sort=priority, priority-based sorting in scheduler within topological levels. 6 integration tests (34000-34005). sailor v2.55.0 (FlowText widget). GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.105.0

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
