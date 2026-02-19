# zr — Universal Task Runner

**zr** (zig-runner) is a fast, language-agnostic task runner and workflow manager built with Zig. It combines the simplicity of `make` with modern features like dependency graphs, parallel execution, caching, and an extensible plugin system.

[![CI](https://github.com/yourorg/zr/workflows/CI/badge.svg)](https://github.com/yourorg/zr/actions)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Features

- ✨ **Single Binary** — No runtime dependencies (Node.js, Python, etc.)
- ⚡ **Fast** — Native performance, < 10ms cold start
- 🔗 **Dependency Graphs** — Automatic task ordering with cycle detection
- 🚀 **Parallel Execution** — Multi-core task execution with configurable limits
- 🎯 **Cross-Platform** — Linux, macOS, Windows (x86_64, aarch64)
- 📦 **Caching** — Skip unchanged tasks with content-based fingerprinting
- 🔌 **Plugin System** — Extend with native plugins (C/C++/Rust/Zig/Go)
- 🎨 **Beautiful Output** — Color-coded, progress bars, interactive TUI
- 🧪 **Monorepo Support** — Run tasks across workspace members
- 🔄 **Watch Mode** — Re-run tasks on file changes
- 🌊 **Workflows** — Multi-stage pipelines with conditional execution
- 📝 **TOML Config** — Simple, readable configuration format

---

## Quick Start

### Installation

**macOS / Linux** (prebuilt binaries):

```bash
curl -fsSL https://zr.dev/install.sh | sh
```

**From source** (requires Zig 0.15.2):

```bash
git clone https://github.com/yourorg/zr.git
cd zr
zig build -Doptimize=ReleaseSafe
# Binary at ./zig-out/bin/zr
```

**Windows**:

Download from [Releases](https://github.com/yourorg/zr/releases) and add to PATH.

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

---

## Example `zr.toml`

```toml
# Simple task
[tasks.build]
cmd = "cargo build"
description = "Build the project"

# Task with dependencies
[tasks.test]
cmd = "cargo test"
deps = ["build"]  # Runs build first

# Parallel dependencies
[tasks.ci]
deps = ["lint", "test", "docs"]  # All run in parallel
description = "Run all checks"

# Task with environment vars
[tasks.deploy]
cmd = "deploy.sh"
cwd = "./scripts"
env = { ENV = "production", REGION = "us-west-2" }
deps = ["test"]

# Conditional execution
[tasks.deploy-staging]
cmd = "deploy.sh"
condition = "env.BRANCH == 'staging'"
env = { ENV = "staging" }

# Cache expensive tasks
[tasks.build-wasm]
cmd = "wasm-pack build"
cache = true  # Skip if unchanged

# Matrix builds
[tasks.test-matrix]
cmd = "cargo test --target ${matrix.target}"
matrix = { target = ["x86_64-unknown-linux-gnu", "aarch64-apple-darwin"] }
```

---

## Core Concepts

### Tasks

Tasks are the building blocks. Each task has:

- **cmd**: Command to execute (string or array)
- **deps**: Tasks that must run first (parallel by default)
- **deps_serial**: Tasks that run sequentially before this task
- **env**: Environment variables (key-value pairs)
- **cwd**: Working directory
- **timeout**: Max execution time (`"5m"`, `"30s"`)
- **retry**: Retry on failure (`{ max = 3, delay = "5s", backoff = "exponential" }`)
- **condition**: Expression to control execution (`"env.VAR == 'value'"`)
- **cache**: Enable output caching (`true`/`false`)

### Workflows

Multi-stage pipelines for complex build/deploy processes:

```toml
[workflows.release]

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
tasks = ["upload-artifacts", "publish-release"]
```

Run with:

```bash
zr workflow release
```

### Profiles

Environment-specific overrides:

```toml
# Base task
[tasks.deploy]
cmd = "deploy.sh"

# Production profile
[profiles.prod]
env = { ENV = "production" }

[profiles.prod.tasks.deploy]
cmd = "deploy.sh --region us-west-2"
```

Use with:

```bash
zr --profile prod run deploy
```

### Workspaces (Monorepo)

```toml
[workspace]
members = ["packages/*", "apps/*"]
```

Run task in all members:

```bash
zr workspace run build
# Runs `zr run build` in each member with zr.toml
```

---

## CLI Usage

```bash
# Run a task
zr run <task>

# Run a workflow
zr workflow <name>

# List all tasks and workflows
zr list

# Show dependency graph
zr graph <task>

# Watch mode (re-run on file changes)
zr watch <task> [paths...]

# Interactive mode (task picker TUI)
zr interactive

# Dry run (show execution plan)
zr --dry-run run <task>

# Parallel execution (max 8 jobs)
zr --jobs 8 run <task>

# Show execution history
zr history

# Scaffold new config
zr init

# Shell completions
zr completion bash > /etc/bash_completion.d/zr
```

### Global Flags

```bash
--profile <name>    # Use profile (or ZR_PROFILE env var)
--jobs, -j <N>      # Max parallel tasks (default: CPU cores)
--dry-run, -n       # Show plan without executing
--no-color          # Disable color output
--quiet, -q         # Suppress task output
--verbose, -v       # Show debug info
--config <path>     # Use custom config file
--format json       # JSON output (for list/graph/run/history)
```

---

## Plugins

Extend zr with plugins for notifications, metrics, integrations, and more.

### Built-in Plugins

```toml
# Load .env files
[plugins.env]
source = "builtin:env"

# Git integration
[plugins.git]
source = "builtin:git"

# Webhook notifications (Slack, Discord)
[plugins.notify]
source = "builtin:notify"
config = { webhook = "https://hooks.slack.com/..." }

# Advanced caching with expiration
[plugins.cache]
source = "builtin:cache"
config = { max_age_seconds = 3600 }
```

### Custom Plugins

Create your own plugins in C/C++/Rust/Zig/Go:

```bash
# Scaffold a new plugin
zr plugin create my-plugin

# Build and install
cd my-plugin/
make
zr plugin install . my-plugin
```

See **[Plugin Guide](docs/PLUGIN_GUIDE.md)** for usage and **[Plugin Development Guide](docs/PLUGIN_DEV_GUIDE.md)** for creating plugins.

---

## Documentation

- **[Product Requirements](docs/PRD.md)** — Full specification and design
- **[Plugin Guide](docs/PLUGIN_GUIDE.md)** — Using and managing plugins
- **[Plugin Development Guide](docs/PLUGIN_DEV_GUIDE.md)** — Creating custom plugins
- **[CLAUDE.md](CLAUDE.md)** — Development orchestration (for contributors)

---

## Performance

| Metric | Target | Actual |
|--------|--------|--------|
| Cold start | < 10ms | ~8ms |
| 100-task graph | < 5ms | ~3ms |
| Memory (core) | < 10MB | ~8MB |
| Binary size | < 5MB | ~2.8MB |

*Benchmarked on M1 MacBook Pro (2021)*

---

## Comparison

| Feature | zr | just | task (go-task) | make |
|---------|----|----|----------------|------|
| Single binary | ✅ | ✅ | ✅ | ❌ (usually installed) |
| Cross-platform | ✅ | ✅ | ✅ | ⚠️ (GNU vs BSD) |
| Config format | TOML | Justfile | YAML | Makefile |
| Parallel execution | ✅ | ✅ | ✅ | ✅ |
| Dependency graph | ✅ | ✅ | ✅ | ✅ |
| Caching | ✅ | ❌ | ⚠️ (limited) | ⚠️ (file-based) |
| Watch mode | ✅ | ⚠️ (external) | ✅ | ❌ |
| Plugins | ✅ | ❌ | ❌ | ❌ |
| Workflows | ✅ | ❌ | ❌ | ❌ |
| Matrix builds | ✅ | ❌ | ⚠️ (via templates) | ❌ |
| Interactive TUI | ✅ | ❌ | ❌ | ❌ |
| Monorepo support | ✅ | ❌ | ❌ | ❌ |

---

## Architecture

```
CLI Interface → Config Engine → Task Graph Engine → Execution Engine → Plugin System
                     ↓              ↓                      ↓
                  TOML Parser    DAG + Topo Sort      Worker Pool
                  Schema Val     Cycle Detection      Process Mgmt
                  Expr Engine    Level Calculation    Resource Limits
```

**Key modules**:

- **Config** (`src/config/`) — TOML parsing, schema validation, expression engine
- **Graph** (`src/graph/`) — DAG, topological sort, cycle detection
- **Exec** (`src/exec/`) — Scheduler, worker pool, process management
- **Plugin** (`src/plugin/`) — Dynamic loading, builtin plugins, registry
- **CLI** (`src/cli/`) — Argument parsing, commands, TUI, completions
- **Output** (`src/output/`) — Terminal rendering, colors, progress bars

---

## Development

### Building

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseSafe

# Run tests
zig build test

# Integration tests
zig build integration-test

# Cross-compile (example)
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
```

### Testing

```bash
# Unit tests (239 tests across 33 files)
zig build test

# Integration tests (black-box CLI tests)
zig build integration-test
```

### Contributing

See **[CLAUDE.md](CLAUDE.md)** for:

- Development workflow
- Coding standards
- Commit conventions
- PR process

**TL;DR**: We use Claude Code for autonomous development with AI-assisted teams. All changes require tests and follow Zig conventions.

---

## Roadmap

### ✅ Phase 1 — Foundation (Complete)

- TOML config parser
- Task execution engine
- Dependency graph (DAG)
- Parallel execution
- Cross-platform CI

### ✅ Phase 2 — Workflows (Complete)

- Workflows with stages
- Watch mode
- Execution history
- Profiles
- Expression engine

### ✅ Phase 3 — UX (Complete)

- Interactive TUI
- Shell completions
- Resource limits (`max_concurrent`)
- JSON output format
- Workspace/monorepo support
- Matrix builds
- Task caching

### 🚧 Phase 4 — Extensibility (In Progress)

- ✅ Plugin system (native .so/.dylib)
- ✅ Built-in plugins (env, git, notify, cache)
- ✅ Plugin management CLI
- ✅ Plugin scaffolding (`zr plugin create`)
- ✅ Plugin documentation
- ⏳ WASM plugin sandbox
- ⏳ Plugin registry index
- ⏳ Remote cache

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

Built with:

- **Zig** — https://ziglang.org
- **TOML** — https://toml.io
- **Claude Code** — https://claude.com/claude-code (AI-assisted development)

Inspired by:
- **just** (command runner)
- **task** (go-task)
- **make** (classic build tool)

---

## Contact

- **GitHub Issues**: https://github.com/yourorg/zr/issues
- **Discussions**: https://github.com/yourorg/zr/discussions
- **X (Twitter)**: [@zr_cli](https://twitter.com/zr_cli)

---

**⚡ zr — Run tasks, not runtimes.**
