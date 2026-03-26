# zr — Developer Platform

**zr** (zig-runner) is a universal developer platform built with Zig. It replaces nvm/pyenv/asdf (toolchain managers), make/just/task (task runners), and Nx/Turborepo (monorepo tools) with a single ~1.2MB binary.

[![CI](https://github.com/yusa-imit/zr/workflows/CI/badge.svg)](https://github.com/yusa-imit/zr/actions)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.57.0-blue.svg)](https://github.com/yusa-imit/zr/releases/tag/v1.57.0)

---

## ⚡ What is zr?

zr combines **four core capabilities** in one tool:

| Capability | What it does | Replaces |
|------------|--------------|----------|
| **Run** | Execute tasks with dependency graphs, parallel execution, workflows | `make`, `just`, `task`, npm scripts |
| **Manage** | Install & manage toolchains (Node, Python, Zig, Go, Rust, etc.) | `nvm`, `pyenv`, `rbenv`, `asdf`, `mise` |
| **Scale** | Monorepo/multi-repo intelligence with affected detection, caching | `Nx`, `Turborepo`, `Lerna`, `Rush` |
| **Integrate** | MCP Server for AI agents, LSP Server for editors | (No equivalent) |

**Key differentiators**:
- **No runtime dependencies** — Single binary, no Node.js/Python/JVM required
- **~1.2MB binary** — 10-100x smaller than alternatives
- **< 10ms cold start** — Instant execution, C-level performance
- **Language-agnostic** — Works with any language, any build system
- **No vendor lock-in** — Self-hosted remote cache (S3/GCS/HTTP), open TOML config

---

## 🚀 Quick Start

### Installation

**macOS / Linux**:
```bash
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
```

**Windows** (PowerShell):
```powershell
irm https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1 | iex
```

**From source** (requires Zig 0.15.2):
```bash
git clone https://github.com/yusa-imit/zr.git
cd zr
zig build -Doptimize=ReleaseSmall
# Binary at ./zig-out/bin/zr
```

### Your First Task

Create `zr.toml`:
```toml
[tasks.hello]
cmd = "echo Hello, World!"
description = "Print a greeting"
```

Run it:
```bash
$ zr run hello
✓ hello completed (0.01s)
Hello, World!
```

### Auto-generate from Existing Project

Already have a Makefile, Justfile, or Taskfile.yml?
```bash
# Detect languages and generate zr.toml from package.json, setup.py, etc.
zr init --detect

# Or migrate from existing task runner
zr init --from-make   # Convert Makefile → zr.toml
zr init --from-just   # Convert Justfile → zr.toml
zr init --from-task   # Convert Taskfile.yml → zr.toml
```

📖 **See the [Migration Guide](docs/guides/migration.md) for detailed instructions and troubleshooting.**

---

## 🖥️ Supported Platforms

zr is cross-compiled for **6 platforms**:

| Platform | Architecture | Status | Notes |
|----------|-------------|--------|-------|
| **Linux** | x86_64 | ✅ Fully Supported | Tested on Ubuntu 20.04+ |
| **Linux** | aarch64 (ARM64) | ✅ Fully Supported | Tested on ARM servers |
| **macOS** | x86_64 (Intel) | ✅ Fully Supported | macOS 11.0+ |
| **macOS** | aarch64 (Apple Silicon) | ✅ Fully Supported | M1/M2/M3 Macs |
| **Windows** | x86_64 | ✅ Fully Supported | Windows 10+ |
| **WASM** | wasm32-wasi | ❌ Not Supported | Threading not available |

**System Requirements**:
- **Memory**: Minimum 4GB RAM (8GB recommended for large monorepos)
- **Disk**: ~5MB for binary + toolchains (varies by language)
- **Network**: Required for toolchain downloads and remote cache (optional)

**Limitations**:
- **WASM**: zr uses native threads for parallel execution, which is not supported in WASM environments. Use native builds for CLI usage.
- **Single-threaded CPUs**: zr will run but parallelization benefits are limited.

---

## 🎯 Core Features

### Task Runner (Phase 1-3)

```toml
# Task with dependencies
[tasks.test]
cmd = "cargo test"
deps = ["build"]  # Runs build first

# Parallel dependencies
[tasks.ci]
deps = ["lint", "test", "docs"]  # All run in parallel

# Conditional dependencies (v1.10.0+)
[tasks.build]
cmd = "cargo build"
deps_if = [
  { task = "lint", condition = "env.CI == 'true'" },
  { task = "type-check", condition = "env.STRICT == 'true'" }
]
deps_optional = ["format"]  # Run if exists, skip if not

# Conditional execution
[tasks.deploy]
cmd = "deploy.sh"
condition = "env.BRANCH == 'main'"

# Cache expensive tasks
[tasks.build-wasm]
cmd = "wasm-pack build"
cache = true  # Skip if unchanged

# Matrix builds
[tasks.test-matrix]
cmd = "cargo test --target ${matrix.target}"
matrix = { target = ["x86_64-linux", "aarch64-darwin"] }

# Retry on failure
[tasks.flaky-api-test]
cmd = "curl https://api.example.com/health"
retry = { max = 3, delay = "5s", backoff = "exponential" }
```

**Commands**:
```bash
zr run <task>              # Execute a task
zr list                    # Show all tasks
zr graph <task>            # Visualize dependency graph
zr watch <task> [paths]    # Re-run on file changes
zr interactive             # TUI task picker
zr failures [list|clear]   # View/clear task failure reports (v1.14.0+)
zr --dry-run run <task>    # Preview execution plan
```

### Workflows (Phase 2)

Multi-stage pipelines with conditional execution, approvals, and error handling:

```toml
[workflows.release]
description = "Build, test, and deploy"

[[workflows.release.stages]]
name = "build"
tasks = ["build-linux", "build-macos", "build-windows"]
parallel = true

[[workflows.release.stages]]
name = "test"
tasks = ["test-unit", "test-integration"]
fail_fast = true  # Stop if any test fails

[[workflows.release.stages]]
name = "deploy"
tasks = ["upload-artifacts"]
requires_approval = true  # Manual approval before deploy
on_failure = ["rollback", "notify-slack"]
```

**Commands**:
```bash
zr workflow <name>         # Run a workflow
zr workflow list           # List all workflows
```

### Toolchain Management (Phase 5)

Install and manage language runtimes automatically:

```toml
# Install specific versions per-project
[toolchain.node]
version = "20.11.0"

[toolchain.python]
version = "3.12.1"

[toolchain.go]
version = "1.22.0"
```

**Commands**:
```bash
zr tools install           # Install all toolchains in zr.toml
zr tools list              # Show installed toolchains
zr tools outdated          # Check for updates
zr doctor                  # Diagnose environment issues
zr run build               # Runs with correct Node/Python/etc. versions
```

**Supported toolchains** (8): Node, Python, Zig, Go, Rust, Deno, Bun, Java

### Monorepo Intelligence (Phase 6)

```toml
[workspace]
members = ["packages/*", "apps/*"]
```

**Affected detection** (Git-based):
```bash
# Only run tasks in projects with changes since last commit
zr --affected run test

# Compare against specific branch
zr affected --base=main --head=feature-branch
```

**Architecture governance**:
```toml
# Define module boundaries
[conformance.rules.no-ui-in-backend]
source = "apps/backend/**"
forbidden = "libs/ui/**"
message = "Backend cannot depend on UI libraries"
```

```bash
zr lint  # Enforce architecture rules
```

**Commands**:
```bash
zr workspace run <task>    # Run task in all workspace members
zr workspace status        # Show workspace structure
zr workspace graph         # Visualize package dependencies
zr codeowners generate     # Generate CODEOWNERS from workspace
```

### Multi-repo Orchestration (Phase 7)

Manage multiple repositories as a unified workspace:

```toml
# zr-repos.toml
[repos.api]
url = "https://github.com/org/api.git"
branch = "main"

[repos.frontend]
url = "https://github.com/org/frontend.git"
depends_on = ["api"]  # Cross-repo dependency
```

**Commands**:
```bash
zr repos sync              # Clone/pull all repositories
zr repos status            # Show sync status
zr repos graph             # Visualize cross-repo dependencies
zr repos run test          # Run task across all repos
```

### AI & Editor Integration (Phase 10-11)

**MCP Server** — Let AI agents (Claude Code, Cursor) execute tasks directly:

```bash
# Add to Claude Code MCP config
zr mcp serve
```

Available tools: `run_task`, `list_tasks`, `show_task`, `validate_config`, `show_graph`, `run_workflow`, `task_history`, `estimate_duration`, `generate_config`

**LSP Server** — Real-time autocomplete, diagnostics, hover docs in any editor:

```bash
# VS Code, Neovim, Helix, Emacs, Sublime
zr lsp
```

Features:
- TOML syntax errors with line/column precision
- Autocomplete for task names, fields, expressions, toolchains
- Hover documentation for fields and expressions
- Go-to-definition for task dependencies

### Performance & Enterprise (Phase 8, 12)

**Benchmarking**:
```bash
zr bench run <task>        # Measure execution time
zr bench compare           # Compare against other runners
```

**Analytics**:
```bash
zr analytics report        # HTML/JSON execution analytics
zr context                 # Generate AI-friendly project metadata
```

**Publishing** (semantic versioning):
```bash
zr publish                 # Bump version, create changelog, tag
```

**Remote caching**:
```toml
[cache.remote]
type = "s3"
bucket = "my-build-cache"
region = "us-west-2"
```

---

## 📚 Documentation

Comprehensive guides in `docs/guides/`:

| Guide | What it covers |
|-------|----------------|
| [Getting Started](docs/guides/getting-started.md) | Installation, first task, basic config |
| [Configuration](docs/guides/configuration.md) | Complete TOML schema reference |
| [Commands](docs/guides/commands.md) | All 50+ CLI commands with examples |
| [MCP Integration](docs/guides/mcp-integration.md) | Setting up MCP server for Claude Code/Cursor |
| [LSP Setup](docs/guides/lsp-setup.md) | Configuring LSP for VS Code/Neovim/etc. |
| [Adding Language](docs/guides/adding-language.md) | How to add a new toolchain |

**Architecture docs**:
- [Product Requirements](docs/PRD.md) — Full specification and design
- [CLAUDE.md](CLAUDE.md) — Development orchestration

---

## 🏎️ Performance

zr achieves **Make-level performance** with **10x more features** in a single binary.

| Metric | zr | make | just | task (go-task) | Nx | Turborepo |
|--------|----|----|------|---------------|-------|-----------|
| **Binary size** | **1.2MB** | 200KB* | 4-6MB | 10-15MB | 200MB+ | 50MB+ |
| **Cold start** | **~4-8ms** | 3-5ms | 15-20ms | 20-30ms | 500ms+ | 300ms+ |
| **Memory (idle)** | **~2-3MB** | ~1MB | ~5MB | ~8MB | ~50MB+ | ~30MB+ |
| **Parallel execution** | **4x speedup** (default) | 1x (serial) | 1x (serial) | 4x (-p flag) | 4x+ | 4x+ |
| **Runtime deps** | **None** | None | None | None | Node.js | Node.js |

*make is usually pre-installed

**Key Benchmarks** (Phase 12C):
- **Cold start**: 4-8ms → Competitive with Make despite TOML parsing + DAG construction
- **Config parsing**: <10ms for 100 tasks → Faster than execution overhead
- **Memory**: 2-3MB RSS → 30-50% reduction via string interning & arena allocators
- **Parallel**: Native worker pool → 4x speedup on multi-core systems (no `-j` flag needed)

**Comprehensive benchmark results**: [benchmarks/RESULTS.md](benchmarks/RESULTS.md)

---

## 🔄 Migration

Already using make, just, or task? Migrate in seconds:

```bash
# Makefile → zr.toml
zr init --from-make
# ✓ Converted 12 targets to tasks

# Justfile → zr.toml
zr init --from-just
# ✓ Converted 8 recipes to tasks

# Taskfile.yml → zr.toml
zr init --from-task
# ✓ Converted 15 tasks
```

Conversion handles:
- Dependencies between targets/recipes/tasks
- Multi-line commands
- Variables and interpolation
- Comments and descriptions

---

## 🆚 Comparison

### vs Make
- ✅ TOML instead of tab-sensitive Makefile syntax
- ✅ Built-in parallel execution with worker pool
- ✅ Content-based caching (not just file timestamps)
- ✅ Workflows, retries, conditional execution
- ✅ Beautiful, color-coded output with progress bars

### vs just/task
- ✅ Toolchain management built-in
- ✅ Monorepo/multi-repo support
- ✅ Remote caching
- ✅ MCP/LSP integration
- ✅ Affected detection
- ✅ 2-10x faster cold start

### vs Nx/Turborepo
- ✅ No runtime dependencies (works without Node.js)
- ✅ Language-agnostic (not JS/TS-centric)
- ✅ No vendor lock-in (self-hosted cache)
- ✅ 100x smaller binary
- ✅ 10x faster startup
- ✅ Simpler config (TOML vs complex JSON/JS)

### vs asdf/mise
- ✅ Task runner built-in (not just toolchain management)
- ✅ Full dependency graphs and workflows
- ✅ Monorepo intelligence
- ✅ MCP/LSP integration

**See full comparison**: [docs/PRD.md § 12](docs/PRD.md)

---

## 🛠️ Development

### Building

```bash
# Debug build
zig build

# Release build (optimized for size)
zig build release

# Run tests
zig build test

# Integration tests (black-box CLI tests)
zig build integration-test

# Fuzz testing
zig build fuzz-toml
zig build fuzz-expr

# Cross-compile (example)
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
```

### Test Status

- **Unit tests**: 845/853 passing (8 skipped, 0 failures)
- **Integration tests**: 957/958 passing (1 skipped, 0 failures)
- **CI targets**: 6 (x86_64/aarch64 × linux-gnu/macos-none/windows-msvc)
- **Memory leaks**: 0

### Contributing

We use Claude Code for autonomous development with AI-assisted teams. See [CLAUDE.md](CLAUDE.md) for:

- Development workflow
- Coding standards (Zig conventions)
- Commit conventions (conventional commits)
- PR process

**Quick guidelines**:
- Always write tests for new features
- Run `zig build test && zig build integration-test` before committing
- Follow Zig naming conventions (camelCase for functions, PascalCase for types)
- Use explicit error handling (no `catch unreachable` in production code)
- Prefer arena allocators for request-scoped work

---

## 🗺️ Roadmap

All phases complete! zr v1.0 is production-ready.

### ✅ Phase 1-4 — Task Runner & Extensibility
- TOML config, dependency graphs, parallel execution
- Workflows, watch mode, profiles, expression engine
- Interactive TUI, shell completions, resource limits
- Plugin system (native + WASM), built-in plugins

### ✅ Phase 5-8 — Developer Platform
- Toolchain management (Node/Python/Zig/Go/Rust/Deno/Bun/Java)
- Monorepo intelligence (affected detection, architecture governance)
- Multi-repo orchestration (cross-repo dependencies, sync)
- Enterprise features (analytics, publishing, CODEOWNERS)

### ✅ Phase 9-13 — AI Integration & v1.0 Release (COMPLETED)
**Foundation** (Phase 9):
- LanguageProvider interface — extensible language support for 8+ toolchains
- JSON-RPC shared infrastructure for MCP & LSP
- Levenshtein "Did you mean?" suggestions for typos
- Enhanced error messages with line/column numbers

**AI Integration** (Phase 10):
- **MCP Server** — 9 tools for AI agents (Claude Code, Cursor, Windsurf)
  - `run_task`, `list_tasks`, `validate_config`, `show_history`, `graph_tasks`, etc.
  - Real-time task execution with streaming output
- **Auto-generate** — `zr init --detect` detects languages & creates zr.toml
- **Natural language** — `zr ai "run tests in parallel"` keyword matching

**Editor Integration** (Phase 11):
- **LSP Server** — Language Server Protocol for zr.toml files
  - Autocomplete for task names, fields, dependencies, expressions
  - Hover documentation with Big-O complexity
  - Go-to-definition for task references
  - Real-time diagnostics for syntax errors, missing deps
  - Supports VS Code, Neovim, Helix, Emacs, Zed

**Performance & Quality** (Phase 12):
- Binary optimization — 1.2MB (ReleaseSmall + strip)
- Fuzz testing — TOML parser, expression engine, JSON-RPC (10min+ no crashes)
- **Benchmarks** — Performance comparison vs Make, Just, Task (see benchmarks/RESULTS.md)
  - Cold start: ~4-8ms (competitive with Make)
  - Memory: ~2-3MB RSS (minimal overhead)
  - Parallel execution: 4x speedup on multi-core systems

**Migration & Documentation** (Phase 13):
- **Migration tools** — `zr init --from-make/just/task` auto-converts configs
- **8 comprehensive guides** — getting-started, configuration, commands, benchmarks, MCP, LSP, migration, adding-language
- **README overhaul** — Feature matrix, performance benchmarks, comparison tables

### 🔮 Future (v2.0+)
- Web dashboard for execution visualization
- Distributed task execution (Kubernetes/Docker Swarm)
- GitHub App for PR previews
- Plugin marketplace

---

## 🐛 Known Issues

If you encounter any problems, please [open an issue](https://github.com/yusa-imit/zr/issues).

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

**Built with**:
- [Zig](https://ziglang.org) — Fast, safe, simple systems programming
- [TOML](https://toml.io) — Human-readable config format
- [Claude Code](https://claude.com/claude-code) — AI-assisted development

**Inspired by**:
- make, just, task (task runners)
- Nx, Turborepo (monorepo tools)
- asdf, mise (toolchain managers)
- Bazel, Buck2 (build systems)

---

## 📞 Contact

- **Issues**: [github.com/yusa-imit/zr/issues](https://github.com/yusa-imit/zr/issues)
- **Discussions**: [github.com/yusa-imit/zr/discussions](https://github.com/yusa-imit/zr/discussions)

---

**⚡ zr — Run tasks, not runtimes.**
