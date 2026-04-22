# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.73.0 (current in build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Unit tests**: 1434/1442 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: Passing
- **CI**: IN_PROGRESS (last check 2026-04-22)
- **GitHub Issues**: 7 open (5 zuda migrations, 1 sailor v2.1.0, 1 zuda DAG)
- **Binary**: ~1.2MB ReleaseSmall, ~9.5MB debug, ~4-8ms cold start
- **Sailor version**: v1.38.0 (all migrations complete through v1.38.0)
- **Source**: ~70,000+ lines, 95+ modules, 10 language providers
- **Latest work (2026-04-22, FEATURE Cycle 154)**: Task Parameters & Dynamic Task Generation milestone (IN PROGRESS 0% → 30%). Phase 1 complete: schema changes (TaskParam struct, task_params field, TOML parser). Integration tests written (22 tests, 776 LOC). Commits: d3f0148 (tests), ca49ef2 (schema), e35030e (agent log).

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

Continue Task Parameters milestone: Implement Phase 2 (parameter interpolation {{param}} in cmd/env fields), Phase 3 (CLI parsing key=value syntax), Phase 4 (validation).
