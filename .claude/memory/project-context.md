# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.84.0 (build.zig.zon) | Latest Release: v1.84.0 (2026-06-01)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.84.0 (current in build.zig.zon) | Latest Release: v1.84.0 (2026-06-01)
- **Unit tests**: ✅ Passing (1717 passed, 8 skipped, 0 failed)
- **Integration tests**: 109 test files - comprehensive coverage (added vars regression tests 14009-14011)
- **Test coverage**: ~98% (202/207 files) — exceeds 80% threshold
- **CI**: Running (pushed v1.84.0 tag + fixes)
- **GitHub Issues**: 0 open, **0 bugs**, **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.13.0 (upgraded in v1.84.0 cycle)
- **zuda version**: main@4ff2325 (upgraded 2026-05-21, Cycle 259 FEATURE — includes detectCycle fix)
- **Source**: ~77,000+ lines, 100+ modules, 10 language providers
- **Latest work (2026-06-01, FEATURE Cycle 303)**: ✅ **v1.84.0 Released** — --only flag (run without deps), required_env task field, --sort flag for list, [vars] section for static substitutions. Parser fix: in_vars now reset when entering workspace/templates/mixins sections. Fixed test 874 (wrong cache subcommand "clean"→"clear").

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

✅ **v1.84.0 Release** — COMPLETE (Cycle 303 FEATURE session)
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.84.0
- Features: --only flag, required_env, --sort for list, [vars] section, parser fixes, test 874 fix
- All unit tests passing (1717/1725)
- 0 bug issues open

✅ **v1.83.0 Release** — COMPLETE (Cycle 283 FEATURE session)
- Enhanced Task Control & Developer Experience milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.83.0

🎯 **Next Work** — Post-v1.0 Feature Development
- **ACTIVE milestones**: 1 (Code Quality & Documentation Polish — continuous improvement)
- **READY milestones**: 0
- **BLOCKED milestones**: 0
- **COMPLETED (Cycle 303)**: v1.84.0 Release — --only, required_env, --sort, [vars], parser fixes
- **COMPLETED (Cycle 283)**: Enhanced Task Control & Developer Experience (v1.83.0)
- **COMPLETED (Cycle 229)**: Test cleanup — removed obsolete zuda_migration_test.zig (dead code)
- **COMPLETED (Cycle 228)**: zuda WorkStealingDeque Migration — analyzed scheduler, removed unused code
- **COMPLETED (Cycle 226-227, 232)**: zuda Graph Migration — DAG migrated to zuda AdjacencyList
- **Current priority**: Continue Code Quality & Documentation Polish milestone (continuous improvement).
