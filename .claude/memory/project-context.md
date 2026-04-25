# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig 0.15.2
- **Type**: Universal task runner & workflow manager CLI → developer platform
- **Version**: v1.73.0 (build.zig.zon) | Latest Release: v1.73.0 (2026-04-21)
- **Config format**: TOML + built-in expression engine
- **Repository**: https://github.com/yusa-imit/zr

## Current Status

- **Build version**: v1.77.0 (current in build.zig.zon) | Latest Release: v1.77.0 (2026-04-25)
- **Unit tests**: 1457/1465 passing (8 skipped), 0 failed, 0 memory leaks
- **Integration tests**: 1420+ tests (13 new env_file tests added)
- **CI**: GREEN (last check 2026-04-25)
- **GitHub Issues**: 6 open (5 zuda migrations, 1 zuda DAG), **0 bug reports**
- **Binary**: ~1.2MB ReleaseSmall, ~12MB debug, ~4-8ms cold start
- **Sailor version**: v2.1.0 (migrated 2026-04-24, Cycle 159)
- **Source**: ~73,350+ lines, 96 modules, 10 language providers
- **Latest work (2026-04-25, FEATURE Cycle 168)**: Runtime .env file loading implemented in scheduler.zig. Added loadAndMergeEnvFiles() function (~100 LOC) that loads multiple .env files with override semantics (later files override earlier), merges with priority order (task env > env_file > base_env), integrated into workerFn before buildEnvWithToolchains. Added env_file and task_cwd fields to WorkerCtx. Fixed env_loader.zig Zig 0.15.2 API compatibility (writeFile, fetchPut). Commit ece498a. All 1457 unit tests passing. Part of Enhanced Environment Variable Management milestone (v1.78.0, ~30% complete). Next: verify integration tests pass, implement CLI --show-env flag for list/run commands.

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

✅ **v1.77.0 Release** — COMPLETE (Cycle 165, STABILIZATION session)
- Enhanced Task Filtering & Selection Patterns milestone RELEASED
- GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.77.0
- Deliverables: ~1233 LOC (219 impl + 379 tests + 635 docs)
- All unit tests passing (1452/1460)
- 0 bug issues open

🎯 **Next Priority** — Enhanced Environment Variable Management (v1.78.0)
- Status: READY, ~30% complete (schema + loader + runtime integration done, CLI flags + docs pending)
- Completed:
  - env_file schema (types.zig), .env file loader module (env_loader.zig), parser integration
  - Runtime .env loading in scheduler.zig (loadAndMergeEnvFiles, workerFn integration, WorkerCtx fields)
  - 13 integration tests in tests/env_file_test.zig (ready to verify)
- Next:
  - Verify integration tests pass (zig build integration-test)
  - Implement CLI --show-env flag for list/run commands (show resolved env vars)
  - Variable interpolation in env values: ${VAR} expansion
  - Documentation: docs/guides/environment-management.md (~500 LOC)
- Estimate: 1-2 more cycles to complete (CLI flags + interpolation + docs)

**READY milestones**: 0 (need new milestone establishment)
**BLOCKED milestones**: 2 (zuda Graph Migration awaiting zuda v2.0.1+, zuda WorkStealingDeque depends on Graph)
