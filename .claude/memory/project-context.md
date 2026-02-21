# zr (zig-runner) - Project Context

## Overview

- **Name**: zr (zig-runner)
- **Language**: Zig
- **Type**: Universal task runner & workflow manager CLI
- **Goal**: Language/ecosystem-agnostic, single binary, C-level performance, user-friendly CLI
- **Config format**: TOML + built-in expression engine (Option D from PRD)

## Current Phase

### Phase 1 - Foundation (MVP) — **COMPLETE**
- [x] Project bootstrap (build.zig, build.zig.zon, src/main.zig)
- [x] TOML config parser (tasks with cmd, cwd, description, deps, env, retry, timeout, etc.)
- [x] Task execution engine (process spawning, env vars, retry with backoff)
- [x] Dependency graph (DAG) construction & cycle detection (Kahn's Algorithm)
- [x] Parallel execution engine (worker pool with semaphores)
- [x] Basic CLI (run, list, graph) with color output, error formatting
- [x] Cross-compile CI pipeline (6 targets)
- [x] Execution history module + `zr history` CLI command
- [x] Task fields: timeout, allow_failure, deps_serial, env, retry, condition, cache, max_concurrent, matrix

### Phase 2 - Workflows & Expressions — **COMPLETE (100%)**
- [x] Workflow system (`[workflows.X]` + `[[workflows.X.stages]]`, fail_fast)
- [x] Profile system (`--profile`, `ZR_PROFILE`, per-task overrides)
- [x] **Watch mode** — **NATIVE (inotify/kqueue/ReadDirectoryChangesW)** with polling fallback (8ef87a4)
- [x] Matrix task execution (Cartesian product, `${matrix.KEY}` interpolation)
- [x] Task output caching (Wyhash64 fingerprint, `~/.zr/cache/`)
- [x] **Expression engine** — **100% of PRD §5.6 implemented**
  - [x] Logical operators: `&&`, `||` with short-circuit evaluation
  - [x] Platform checks: `platform == "linux" | "darwin" | "windows"`
  - [x] Architecture checks: `arch == "x86_64" | "aarch64"`
  - [x] `file.exists(path)` — filesystem check via fs.access
  - [x] `file.changed(glob)` — git diff-based change detection
  - [x] `file.newer(target, source)` — mtime comparison (dirs walk full tree)
  - [x] `file.hash(path)` — Wyhash content fingerprint
  - [x] `shell(cmd)` — command execution success check
  - [x] `semver.gte(v1, v2)` — semantic version comparison
  - [x] Environment variables: `env.VAR == "val"`, `env.VAR != "val"`, truthy checks
  - [x] **Runtime state refs**: `stages['name'].success`, `tasks['name'].duration` with all comparison operators

### Phase 3 - UX & Resources — **COMPLETE (100%)** ✓
- [x] `--dry-run` / `-n` flag (execution plan without running)
- [x] `zr init` command (scaffold starter zr.toml)
- [x] `zr validate` command (config validation with --strict and --schema modes) (29d771a)
- [x] Shell completion (bash/zsh/fish)
- [x] Global CLI flags: `--jobs`, `--no-color`, `--quiet`, `--verbose`, `--config`, `--format json`
- [x] `max_concurrent` per-task resource limit
- [x] Workspace/monorepo support (`[workspace] members`, glob discovery)
- [x] Progress bar output module
- [x] Interactive TUI — **COMPLETE with cancel/retry** (58a59ac)
  - [x] Task picker (arrow keys + Enter)
  - [x] **Live log streaming** — `zr live <task> [task...]` with real-time stdout/stderr display (430fe98)
  - [x] **Multi-task live mode** — `zr live` now accepts multiple tasks, runs sequentially with TUI (9fd6cf9)
  - [x] **Cancel/pause/resume controls** — `zr interactive-run <task>` with keyboard controls (58a59ac)
  - [x] Automatic retry prompt on task failure
  - Missing: dependency graph ASCII visualization (PRD §5.3.3) — low priority
- [x] **Resource limits (CPU/Memory)** — **COMPLETE (100%)** (PRD §5.4)
  - [x] `max_cpu`, `max_memory` config fields + TOML parsing (e276a26)
  - [x] `GlobalResourceConfig` (max_total_memory, max_cpu_percent) (e276a26)
  - [x] `src/exec/resource.zig` — ResourceMonitor with cross-platform implementation
  - [x] getProcessUsage() Linux implementation (/proc/[pid]/status, /proc/[pid]/stat) (f1f7cd3)
  - [x] getProcessUsage() macOS implementation (proc_pidinfo) (3560668)
  - [x] getProcessUsage() Windows implementation (GetProcessMemoryInfo, GetProcessTimes) (21df9dc)
  - [x] Integration with process spawning (resource watcher thread, memory limit kill) (f1f7cd3)
  - [x] cgroups v2 / Job Objects hard limit enforcement (Linux/Windows kernel-level limits)
  - [x] ResourceMonitor soft limit enforcement (process killing on memory limit violation) (d99de2d)
  - [x] `--monitor` CLI flag for live resource display (dd1a9fd)

### Phase 4 - Extensibility — **COMPLETE (~90%)**
- [x] Native plugin system (.so/.dylib via DynLib, C-ABI hooks)
- [x] Plugin management CLI (install/remove/update/info/search from local/git/registry)
- [x] Plugin scaffolding (`zr plugin create`)
- [x] Built-in plugins: env (.env loading), git (branch/changes), notify (webhooks), cache (lifecycle hooks)
- [x] Plugin documentation (README, PLUGIN_GUIDE, PLUGIN_DEV_GUIDE)
- [x] **Docker built-in plugin** — COMPLETE with build/push/tag/prune, BuildKit cache, multi-platform support (c07e0aa)
- [x] **WASM plugin sandbox** — **COMPLETE** (2b0c89a, e432538, 7926633) — Full MVP implementation: binary format parser (magic/version/sections), stack-based interpreter (35+ opcodes), memory isolation, host callbacks, lifecycle hooks
- [ ] **Plugin registry index server** — NOT implemented (uses GitHub as backend only)
- [ ] **Remote cache** — NOT implemented (local cache only; PRD §9)

### Phase 5 - Toolchain Management (PRD v2.0) — **COMPLETE (100%)** ✓
- [x] **Toolchain types & config** (85a7a0e) — ToolKind enum (node/python/zig/go/rust/deno/bun/java), ToolVersion parser (major.minor.patch with optional patch), ToolSpec
- [x] **Config [tools] section** (85a7a0e) — TOML parser integration, toolchains field in Config struct
- [x] **Installer infrastructure** (85a7a0e) — getToolDir, isInstalled, listInstalled, install/uninstall stubs (directory creation only)
- [x] **Actual downloaders** (6298ae1) — Download tarballs from official sources (Node.js, Python, Zig, Go, Rust, Deno, Bun, Java), curl-based HTTP download, archive extraction (tar/unzip/PowerShell)
- [x] **PATH manipulation** (8c52f7c, e0030b4) — Inject toolchain bin paths into task execution environment, JAVA_HOME/GOROOT env vars, integrated with scheduler
- [x] **CLI commands** (be3b994) — `zr tools list`, `zr tools install`, `zr tools outdated` (stub) with full help, error handling, and 7 unit tests
- [x] **Auto-install on task run** (1db7ecb) — Per-task toolchain requirements ([tasks.X.toolchain]), auto-detection and installation before execution, "tool@version" parsing, ensureToolchainsInstalled() in scheduler

### Phase 6 - Monorepo Intelligence (PRD §9 Phase 5) — **IN PROGRESS (~70%)**
- [x] **Affected detection** (9bccfef) — Git diff-based change detection for workspace members
  - `util/affected.zig` — detectAffected(), getChangedFiles(), findProjectForFile()
  - `--affected <ref>` CLI flag — Filter workspace members based on git changes
  - `zr --affected origin/main workspace run test` — Run tasks only on changed projects
  - 5 unit tests for file-to-project mapping
- [x] **Dependency graph expansion** (d503d7b) — expandWithDependents() to include projects that depend on affected ones
  - Transitive dependency expansion with BFS traversal
  - Circular dependency handling to prevent infinite loops
  - 6 comprehensive tests (single-level, transitive, multi-initial, edge cases, cycles)
- [ ] **Content hash caching** — Already implemented in Phase 2, documented here for completeness
- [x] **Project graph visualization** (d8f4316) — ASCII/DOT/JSON/HTML output formats (PRD §5.7.4)
  - `cli/graph.zig` — `zr graph` command with 4 output formats
  - ASCII: Terminal tree view with affected highlighting
  - DOT: Graphviz format for visual diagrams
  - JSON: Programmatic access to dependency structure
  - HTML: Interactive D3.js force-directed graph
  - `--affected <ref>` integration for highlighting changed projects
- [x] **Architecture constraints** (6e5f826) — `[[constraints]]` section, `zr lint` command (PRD §5.7.6)
  - `config/constraints.zig` — Constraint validation engine
  - `cli/lint.zig` — `zr lint` command with verbose mode
  - 3 constraint types: no-circular, tag-based, banned-dependency
  - Tag-based dependency control (app→lib, feature→feature rules)
  - 4 unit tests for validation logic
- [ ] **Module boundary rules** — Extended tag-based constraints with module metadata

### Missing Utility Modules (PRD §7.2)
- [x] `util/glob.zig` — **ENHANCED** (f439225) — glob pattern matching with recursive directory support (*/? wildcards, nested patterns like `packages/*/src`, absolute path handling)
- [x] `util/semver.zig` — semantic version parsing and comparison (gte/gt/lt/lte/eql)
- [x] `util/hash.zig` — file and string hashing with Wyhash (hashFile/hashString/hashStrings)
- [x] `util/platform.zig` — cross-platform POSIX wrappers
- [x] `util/affected.zig` — git diff-based affected detection for monorepo workflows

## Status Summary

> **Reality**: Phase 1-5 complete, Phase 6 ~60% (MVP → Plugins → Toolchains → Monorepo). **Production-ready with full toolchain management + monorepo intelligence** — 8 supported toolchains (Node/Python/Zig/Go/Rust/Deno/Bun/Java), auto-install on task run, PATH injection, git-based affected detection (`--affected origin/main`), transitive dependency graph expansion, multi-format graph visualization (ASCII/DOT/JSON/HTML), event-driven watch mode, kernel-level resource limits, full Docker integration, complete WASM plugin execution (parser + interpreter), and interactive TUI with task controls.

- **Tests**: 425 total (421 passing, 8 skipped, 4 constraint validation tests) — includes 29 toolchain tests + 7 CLI tests + 1 auto-install test + 11 affected detection tests + 2 graph visualization tests
- **Binary**: ~3MB, ~0ms cold start, ~2MB RSS
- **CI**: 6 cross-compile targets working

## Architecture (High-Level)

```
CLI Interface -> Config Engine -> Task Graph Engine -> Execution Engine -> Plugin System
```

### Key Modules (src/)
- `main.zig` - Entry point + CLI commands (run, list, graph, interactive-run, tools) + color output
- `cli/` - Argument parsing, help, completion, TUI (picker, live streaming, interactive controls), **tools (list/install/outdated)**, **graph (workspace visualization)**
- `config/` - TOML loader, schema validation, expression engine, profiles, **toolchain config**
- `graph/` - DAG, topological sort, cycle detection, visualization
- `exec/` - Scheduler, worker pool, process management, task control (atomic signals)
- `plugin/` - Dynamic loading (.so/.dylib), git/registry install, built-ins (Docker, env, git, cache), **WASM runtime**
- `watch/` - Native filesystem watchers (inotify/kqueue/ReadDirectoryChangesW)
- `output/` - Terminal rendering, color, progress bars
- `util/` - glob, semver, hash, platform wrappers, **affected (git diff-based change detection)**
- `toolchain/` - **Phase 5**: types (ToolKind, ToolVersion, ToolSpec), installer (version management, directory structure), downloader (URL resolution, HTTP download, archive extraction), path (PATH injection, env var building)

## Config File

- Filename: `zr.toml`
- Format: TOML with limited expression engine for conditions
- Supports: tasks, workflows, env vars, profiles, watch rules, plugins, workspaces

## Performance Targets

- Cold start: < 10ms (achieved: ~0ms)
- 100-task graph resolution: < 5ms
- Memory (core): < 10MB (achieved: ~2MB RSS)
- Binary size: < 5MB (achieved: 2.9MB)
- Cross-compile: 6 targets (linux/macos/windows x x86_64/aarch64)

## Priority Backlog (by impact)

1. ~~**Expression engine (runtime refs)**~~ — **COMPLETE** ✓ (c1db626)
2. ~~**Resource monitoring (Linux/macOS/Windows)**~~ — **COMPLETE** ✓ (21df9dc)
3. ~~**Resource limit enforcement**~~ — **COMPLETE** ✓ (cgroups v2 / Job Objects)
4. ~~**Watch mode upgrade**~~ — **COMPLETE** ✓ (native inotify/kqueue/ReadDirectoryChangesW) (8ef87a4)
5. ~~**Docker built-in plugin**~~ — **COMPLETE** ✓ (build/push/tag/prune with BuildKit cache) (c07e0aa)
6. ~~**TUI live log streaming**~~ — **COMPLETE** ✓ (430fe98)
7. ~~**TUI cancel/retry/pause**~~ — **COMPLETE** ✓ (interactive controls with atomic signals) (58a59ac)
8. ~~**WASM plugin sandbox (MVP)**~~ — **COMPLETE** ✓ (interpreter runtime, memory isolation, host callbacks) (2b0c89a)
9. ~~**WASM module parser + interpreter**~~ — **COMPLETE** ✓ (full MVP spec parser + stack-based bytecode executor) (e432538, 7926633)
10. ~~**Toolchain foundation**~~ — **COMPLETE** ✓ (types, config parsing, installer stubs) (85a7a0e)
11. ~~**Toolchain downloaders**~~ — **COMPLETE** ✓ (URL resolution, download, extraction for all 8 toolchains) (6298ae1)
12. ~~**Toolchain PATH injection**~~ — **COMPLETE** ✓ (PATH prepending, JAVA_HOME/GOROOT, scheduler integration) (8c52f7c, e0030b4)
13. ~~**`zr tools` CLI**~~ — **COMPLETE** ✓ (list/install/outdated commands) (be3b994)
14. ~~**Auto-install**~~ — **COMPLETE** ✓ (per-task toolchain field, auto-detection and installation) (1db7ecb)
15. ~~**Affected detection**~~ — **COMPLETE** ✓ (git diff-based change detection, --affected flag) (9bccfef)
16. ~~**Dependency graph expansion**~~ — **COMPLETE** ✓ (expandWithDependents() for transitive affected projects) (d503d7b)
17. ~~**Project graph visualization**~~ — **COMPLETE** ✓ (ASCII/DOT/JSON/HTML formats, `zr graph` command) (d8f4316)
18. ~~**Architecture constraints**~~ — **COMPLETE** ✓ (`[[constraints]]` + `zr lint` with 3 rule types) (6e5f826)
19. **Module boundary rules** — Tag metadata + extended constraint validation
20. **Remote cache** — shared cache for CI pipelines (future enhancement)
