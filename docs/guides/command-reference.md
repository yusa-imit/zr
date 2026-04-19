# Command Reference

Complete reference for all `zr` CLI commands.

## Table of Contents

- [Core Commands](#core-commands)
  - [run](#run) — Execute tasks
  - [watch](#watch) — Auto-run on file changes
  - [workflow](#workflow) — Execute workflows
  - [list](#list) — List tasks
  - [graph](#graph) — Visualize dependencies
  - [history](#history) — View execution history
- [Project Commands](#project-commands)
  - [init](#init) — Initialize configuration
  - [add](#add) — Add tasks/workflows/profiles
  - [edit](#edit) — Interactive editor
  - [validate](#validate) — Validate configuration
  - [setup](#setup) — Project setup
- [Workspace Commands](#workspace-commands)
  - [workspace list](#workspace-list) — List members
  - [workspace run](#workspace-run) — Run across members
  - [workspace sync](#workspace-sync) — Build synthetic workspace
  - [affected](#affected) — Run on affected members
- [Cache Commands](#cache-commands)
  - [cache clear](#cache-clear) — Clear cache
  - [cache status](#cache-status) — Cache statistics
  - [clean](#clean) — Clean all data
- [Toolchain Commands](#toolchain-commands)
  - [tools list](#tools-list) — List installed tools
  - [tools install](#tools-install) — Install toolchains
  - [tools outdated](#tools-outdated) — Check for updates
  - [setup](#setup) — Install project tools
- [Plugin Commands](#plugin-commands)
  - [plugin list](#plugin-list) — List plugins
  - [plugin install](#plugin-install) — Install plugin
  - [plugin remove](#plugin-remove) — Remove plugin
  - [plugin update](#plugin-update) — Update plugin
  - [plugin info](#plugin-info) — Show plugin details
  - [plugin create](#plugin-create) — Scaffold plugin
- [Interactive Commands](#interactive-commands)
  - [interactive](#interactive) — Task picker TUI
  - [live](#live) — Live log streaming
  - [monitor](#monitor) — Resource dashboard
  - [interactive-run](#interactive-run) — Run with controls
- [Integration Commands](#integration-commands)
  - [mcp serve](#mcp-serve) — MCP server for AI agents
  - [lsp](#lsp) — LSP server for editors
- [Utility Commands](#utility-commands)
  - [show](#show) — Show task details
  - [which](#which) — Show task location
  - [env](#env) — Display environment
  - [export](#export) — Export shell variables
  - [cd](#cd) — Workspace member path
  - [bench](#bench) — Benchmark tasks
  - [analytics](#analytics) — Build analysis
  - [context](#context) — AI-friendly metadata
  - [doctor](#doctor) — Diagnose environment
  - [estimate](#estimate) — Duration estimation
  - [failures](#failures) — View failure reports
  - [version](#version) — Version management
  - [upgrade](#upgrade) — Upgrade zr
  - [completion](#completion) — Shell completion

---

## Core Commands

### run

Execute one or more tasks with dependency resolution.

**Syntax**:
```bash
zr run <task> [task2...] [options]
```

**Examples**:
```bash
# Run single task
zr run build

# Run multiple tasks (in parallel if independent)
zr run build test lint

# Run with dry-run
zr run deploy --dry-run

# Run with specific profile
zr run build --profile production

# Run with custom parallelism
zr run test --jobs 4

# Run with monitoring
zr run build --monitor
```

**Options**:
- `--dry-run, -n` — Show execution plan without running
- `--profile, -p <name>` — Activate profile
- `--jobs, -j <N>` — Max parallel tasks
- `--monitor, -m` — Live resource monitoring
- `--grep <pattern>` — Filter output lines matching pattern
- `--grep-v <pattern>` — Exclude output lines matching pattern
- `--highlight <pattern>` — Highlight matching lines
- `-C, --context <N>` — Show N lines of context around matches
- `--quiet, -q` — Suppress non-error output
- `--verbose, -v` — Verbose output

**Shortcuts**:
```bash
# Re-run last task
zr !!

# Run Nth-to-last task
zr !-2

# Smart no-args behavior
zr          # Runs default task, or shows picker, or auto-runs if single task
```

**See also**: [workflow](#workflow), [watch](#watch), [interactive](#interactive)

---

### watch

Watch files for changes and automatically re-run a task.

**Syntax**:
```bash
zr watch <task> [paths...] [options]
```

**Examples**:
```bash
# Watch all files (uses task 'watch_paths' from config)
zr watch dev

# Watch specific paths
zr watch test src/ tests/

# Watch with pattern
zr watch build "**/*.ts"
```

**Notes**:
- Uses native file watchers (inotify on Linux, kqueue on macOS, ReadDirectoryChangesW on Windows)
- Debounces changes (waits for file system to stabilize before re-running)
- Press `Ctrl+C` to stop watching

**See also**: Task configuration field `watch_paths`

---

### workflow

Execute a named workflow (sequence of task stages).

**Syntax**:
```bash
zr workflow <name> [options]
```

**Examples**:
```bash
# Run workflow
zr workflow ci

# Run with dry-run
zr workflow deploy --dry-run

# Run with profile
zr workflow release --profile production

# Shorthand syntax
zr w/ci
```

**Workflow definition** (in `zr.toml`):
```toml
[workflows.ci]
description = "Continuous integration pipeline"
stages = [
  { tasks = ["lint", "fmt"] },           # Stage 1: parallel
  { tasks = ["test"] },                  # Stage 2: serial (waits for stage 1)
  { tasks = ["build-frontend", "build-backend"] }  # Stage 3: parallel
]
```

**See also**: [Configuration guide on workflows](configuration.md#workflows)

---

### list

List available tasks with filtering and formatting options.

**Syntax**:
```bash
zr list [pattern] [options]
```

**Examples**:
```bash
# List all tasks
zr list

# Show as dependency tree
zr list --tree

# Filter by pattern
zr list build

# Filter by tags (AND logic)
zr list --tags ci,test

# Exclude tags (OR logic)
zr list --exclude-tags slow,flaky

# Show frequently used tasks
zr list --frequent=10

# Show slow tasks (avg time > 30s)
zr list --slow=30000

# Search full-text (name, description, command)
zr list --search "docker build"

# Combined filters
zr list --tags ci --exclude-tags flaky --frequent=10

# JSON output
zr list --format json

# With unique abbreviation hints
zr list
# Output:
# [b]   build        Build the application
# [tea] teardown     Clean up resources
# [tes] test         Run test suite
```

**Options**:
- `--tree` — Show as dependency tree
- `--tags <tags>` — Filter by tags (comma-separated, ALL must match)
- `--exclude-tags <tags>` — Exclude tags (comma-separated, ANY match)
- `--search <query>` — Full-text search
- `--frequent[=N]` — Show top N most executed tasks (default 10)
- `--slow[=THRESHOLD]` — Show tasks slower than threshold (ms, default 30000)
- `--format, -f <fmt>` — Output format (text or json)

**See also**: [show](#show), [which](#which), [graph](#graph)

---

### graph

Visualize task dependency graph.

**Syntax**:
```bash
zr graph [options]
```

**Examples**:
```bash
# ASCII tree view (default)
zr graph

# DOT format for graphviz
zr graph --format dot > graph.dot
dot -Tpng graph.dot -o graph.png

# Mermaid format
zr graph --format mermaid > graph.mmd
```

**Output formats**:
- `text` — ASCII tree (default)
- `dot` — Graphviz DOT format
- `mermaid` — Mermaid diagram

**See also**: [list --tree](#list)

---

### history

Show recent task execution history.

**Syntax**:
```bash
zr history [options]
```

**Examples**:
```bash
# Show recent runs
zr history

# Show last 50 entries
zr history --limit 50

# Show only failures
zr history --failures

# JSON output
zr history --format json
```

**History format**:
```
2026-04-19 12:34:56  build         SUCCESS  1.2s
2026-04-19 12:35:12  test          SUCCESS  3.4s
2026-04-19 12:36:01  deploy        FAILURE  0.5s
```

**See also**: [failures](#failures), [estimate](#estimate)

---

## Project Commands

### init

Initialize a new `zr.toml` configuration file.

**Syntax**:
```bash
zr init [options]
```

**Examples**:
```bash
# Create basic template
zr init

# Auto-detect project and generate tasks
zr init --detect

# Migrate from npm scripts
zr init --from-npm

# Migrate from Makefile
zr init --from-make

# Migrate from justfile
zr init --from-just

# Migrate from Taskfile.yml
zr init --from-task

# Preview without creating file
zr init --from-npm --dry-run
```

**Migration options**:
- `--detect` — Auto-detect language and generate tasks
- `--from-npm` — Migrate from `package.json` scripts
- `--from-make` — Migrate from `Makefile`
- `--from-just` — Migrate from `justfile`
- `--from-task` — Migrate from `Taskfile.yml`
- `--dry-run` — Preview generated config without writing

**See also**: [Migration guide](migration.md), [add](#add)

---

### add

Interactively add tasks, workflows, or profiles.

**Syntax**:
```bash
zr add <type> [name] [options]
```

**Examples**:
```bash
# Interactive task creation
zr add task

# Add task with name
zr add task build

# Add workflow
zr add workflow ci

# Add profile
zr add profile production
```

**Types**:
- `task` — Add a task
- `workflow` — Add a workflow
- `profile` — Add a profile

**See also**: [edit](#edit), [init](#init)

---

### edit

Launch TUI editor for tasks, workflows, or profiles.

**Syntax**:
```bash
zr edit <type> [options]
```

**Examples**:
```bash
# Edit tasks
zr edit task

# Edit workflows
zr edit workflow

# Edit profiles
zr edit profile
```

**See also**: [add](#add)

---

### validate

Validate `zr.toml` configuration file.

**Syntax**:
```bash
zr validate [options]
```

**Examples**:
```bash
# Validate current config
zr validate

# Validate specific file
zr validate --config ./path/to/zr.toml
```

**Checks**:
- TOML syntax errors
- Dependency cycles
- Invalid task references
- Required field validation
- Expression syntax

**See also**: [lint](#lint), [doctor](#doctor)

---

### setup

Install project toolchains and run setup tasks.

**Syntax**:
```bash
zr setup [options]
```

**Examples**:
```bash
# Install all toolchains and run setup tasks
zr setup

# Dry-run (show what would be installed)
zr setup --dry-run
```

**What it does**:
1. Parses `[toolchains]` section
2. Installs missing toolchains (Node, Python, Zig, etc.)
3. Runs tasks tagged with `setup = true`

**Configuration** (in `zr.toml`):
```toml
[toolchains]
node = "20.11.1"
python = "3.12.1"

[tasks.install-deps]
cmd = "npm install"
tags = ["setup"]
```

**See also**: [tools install](#tools-install)

---

## Workspace Commands

### workspace list

List all workspace members.

**Syntax**:
```bash
zr workspace list [options]
```

**Examples**:
```bash
# List members
zr workspace list

# JSON output
zr workspace list --format json
```

**See also**: [workspace run](#workspace-run)

---

### workspace run

Run a task across all workspace members.

**Syntax**:
```bash
zr workspace run <task> [options]
```

**Examples**:
```bash
# Run task on all members
zr workspace run test

# Run on specific members
zr workspace run build --members frontend,backend

# Parallel execution
zr workspace run lint --jobs 4

# Filter by affected members
zr workspace run test --affected origin/main
```

**Options**:
- `--members <list>` — Comma-separated member names
- `--affected <ref>` — Only affected members (git diff)
- `--jobs, -j <N>` — Max parallel members

**See also**: [affected](#affected)

---

### workspace sync

Build synthetic workspace from multi-repo configuration.

**Syntax**:
```bash
zr workspace sync [options]
```

**Examples**:
```bash
# Sync multi-repo workspace
zr workspace sync
```

**Configuration** (in `zr.toml`):
```toml
[workspace]
multi_repo = true

[[workspace.repositories]]
name = "frontend"
url = "https://github.com/org/frontend.git"
path = "repos/frontend"

[[workspace.repositories]]
name = "backend"
url = "https://github.com/org/backend.git"
path = "repos/backend"
```

**See also**: [repo sync](#repo-sync)

---

### affected

Run task on workspace members affected by git changes.

**Syntax**:
```bash
zr affected <task> [options]
```

**Examples**:
```bash
# Run on affected members (vs origin/main)
zr affected test

# Custom base ref
zr affected build --base develop

# Dry-run
zr affected deploy --dry-run
```

**Options**:
- `--base <ref>` — Base git ref for comparison (default: origin/main)
- `--dry-run, -n` — Show affected members without running

**See also**: [workspace run](#workspace-run)

---

## Cache Commands

### cache clear

Clear cached task results.

**Syntax**:
```bash
zr cache clear [options]
```

**Examples**:
```bash
# Clear all cache
zr cache clear

# Clear specific task
zr cache clear build

# Clear remote cache (S3/GCS/HTTP)
zr cache clear --remote
```

**See also**: [cache status](#cache-status), [clean](#clean)

---

### cache status

Show cache statistics and storage usage.

**Syntax**:
```bash
zr cache status [options]
```

**Examples**:
```bash
# Show cache stats
zr cache status

# JSON output
zr cache status --format json
```

**Output**:
```
Cache Statistics:
  Entries: 127
  Total size: 2.3 GB
  Hit rate: 67.4%
  Remote cache: enabled (S3)
```

**See also**: [Configuration guide on caching](configuration.md#caching)

---

### clean

Clean zr data directories.

**Syntax**:
```bash
zr clean [options]
```

**Examples**:
```bash
# Clean cache only
zr clean --cache

# Clean history
zr clean --history

# Clean toolchains
zr clean --toolchains

# Clean plugins
zr clean --plugins

# Clean everything
zr clean --all
```

**Options**:
- `--cache` — Clear cache
- `--history` — Clear history
- `--toolchains` — Remove toolchains
- `--plugins` — Remove plugins
- `--all` — Clean everything

**See also**: [cache clear](#cache-clear)

---

## Toolchain Commands

### tools list

List installed toolchain versions.

**Syntax**:
```bash
zr tools list [kind] [options]
```

**Examples**:
```bash
# List all toolchains
zr tools list

# List specific toolchain
zr tools list node

# JSON output
zr tools list --format json
```

**Supported toolchains**:
- `node` — Node.js
- `python` — Python
- `zig` — Zig
- `go` — Go
- `rust` — Rust
- `ruby` — Ruby
- `java` — Java
- `dotnet` — .NET Core

**See also**: [tools install](#tools-install), [tools outdated](#tools-outdated)

---

### tools install

Install a specific toolchain version.

**Syntax**:
```bash
zr tools install <kind>@<version> [options]
```

**Examples**:
```bash
# Install Node.js 20.11.1
zr tools install node@20.11.1

# Install latest Python 3.12
zr tools install python@3.12

# Install Zig 0.15.2
zr tools install zig@0.15.2
```

**See also**: [setup](#setup), [tools list](#tools-list)

---

### tools outdated

Check for outdated toolchains.

**Syntax**:
```bash
zr tools outdated [kind] [options]
```

**Examples**:
```bash
# Check all toolchains
zr tools outdated

# Check specific toolchain
zr tools outdated node
```

**Output**:
```
node     20.11.1 → 20.12.0 (latest)
python   3.11.7  → 3.12.1  (latest)
```

**See also**: [tools install](#tools-install), [upgrade](#upgrade)

---

## Plugin Commands

### plugin list

List plugins declared in `zr.toml`.

**Syntax**:
```bash
zr plugin list [options]
```

**Examples**:
```bash
# List installed plugins
zr plugin list

# JSON output
zr plugin list --format json
```

**See also**: [plugin install](#plugin-install)

---

### plugin install

Install a plugin from local path or git URL.

**Syntax**:
```bash
zr plugin install <path|url> [options]
```

**Examples**:
```bash
# Install from local path
zr plugin install ./plugins/my-plugin

# Install from git URL
zr plugin install https://github.com/user/zr-plugin-name.git

# Install with specific name
zr plugin install ./plugin --name custom-name
```

**See also**: [plugin remove](#plugin-remove), [plugin update](#plugin-update)

---

### plugin remove

Remove an installed plugin.

**Syntax**:
```bash
zr plugin remove <name> [options]
```

**Examples**:
```bash
# Remove plugin
zr plugin remove my-plugin
```

**See also**: [plugin install](#plugin-install)

---

### plugin update

Update a plugin.

**Syntax**:
```bash
zr plugin update <name> [path] [options]
```

**Examples**:
```bash
# Update from git (git pull)
zr plugin update my-plugin

# Update from new path
zr plugin update my-plugin ./new-path
```

**See also**: [plugin install](#plugin-install)

---

### plugin info

Show metadata for an installed plugin.

**Syntax**:
```bash
zr plugin info <name> [options]
```

**Examples**:
```bash
# Show plugin info
zr plugin info my-plugin

# JSON output
zr plugin info my-plugin --format json
```

**See also**: [plugin list](#plugin-list)

---

### plugin create

Scaffold a new plugin template directory.

**Syntax**:
```bash
zr plugin create <name> [options]
```

**Examples**:
```bash
# Create native plugin (Zig)
zr plugin create my-plugin --type native

# Create WASM plugin
zr plugin create my-plugin --type wasm
```

**See also**: [Plugin development guide](../PLUGIN_DEV_GUIDE.md)

---

## Interactive Commands

### interactive

Launch interactive TUI task picker.

**Syntax**:
```bash
zr interactive [options]
# or
zr i
```

**Examples**:
```bash
# Launch task picker
zr interactive

# Shorthand
zr i
```

**Features**:
- Arrow keys to navigate
- Enter to select/run
- Space to multi-select
- `/` to search
- `q` to quit

**See also**: [list](#list), [run](#run)

---

### live

Run task with live TUI log streaming.

**Syntax**:
```bash
zr live <task> [options]
```

**Examples**:
```bash
# Run with live logs
zr live build

# Live logs for workflow
zr live workflow ci
```

**Features**:
- Real-time log streaming
- Color-coded output
- Task progress indicators

**See also**: [monitor](#monitor), [interactive-run](#interactive-run)

---

### monitor

Execute workflow with real-time resource monitoring dashboard.

**Syntax**:
```bash
zr monitor <workflow> [options]
```

**Examples**:
```bash
# Monitor workflow execution
zr monitor ci

# Monitor with custom refresh
zr monitor deploy --refresh 500
```

**Dashboard metrics**:
- CPU usage per task
- Memory usage per task
- Task execution timeline
- Resource graphs

**See also**: [workflow](#workflow), [analytics](#analytics)

---

### interactive-run

Run task with interactive cancel/retry controls.

**Syntax**:
```bash
zr interactive-run <task> [options]
# or
zr irun <task>
```

**Examples**:
```bash
# Run with controls
zr interactive-run test

# Shorthand
zr irun test
```

**Controls**:
- `Ctrl+C` — Cancel task
- `r` — Retry failed task
- `s` — Skip current task

**See also**: [run](#run), [live](#live)

---

## Integration Commands

### mcp serve

Start MCP (Model Context Protocol) server for AI agent integration.

**Syntax**:
```bash
zr mcp serve [options]
```

**Examples**:
```bash
# Start MCP server
zr mcp serve

# Custom port
zr mcp serve --port 8080

# Enable debug logging
zr mcp serve --verbose
```

**Usage with Claude Code**:
```json
{
  "mcpServers": {
    "zr": {
      "command": "zr",
      "args": ["mcp", "serve"]
    }
  }
}
```

**See also**: [MCP integration guide](mcp-integration.md)

---

### lsp

Start LSP (Language Server Protocol) server for editor integration.

**Syntax**:
```bash
zr lsp [options]
```

**Examples**:
```bash
# Start LSP server (stdio)
zr lsp

# Start with debug logging
zr lsp --verbose
```

**Features**:
- Autocomplete for task names, fields
- Hover documentation
- Go-to-definition for task references
- Diagnostics for syntax errors

**See also**: [LSP setup guide](lsp-setup.md)

---

## Utility Commands

### show

Display detailed information about a task.

**Syntax**:
```bash
zr show <task> [options]
```

**Examples**:
```bash
# Show task details
zr show build

# JSON output
zr show build --format json
```

**Output**:
```
Task: build
Description: Build the application
Command: npm run build
Dependencies: install, lint
Environment: NODE_ENV=production
Directory: ./frontend
Tags: ci, release
Cache: enabled (content-based)
```

**See also**: [list](#list), [which](#which)

---

### which

Show where a task is defined (file path and line number).

**Syntax**:
```bash
zr which <task> [options]
```

**Examples**:
```bash
# Show task location
zr which build
# Output: zr.toml:42
```

**See also**: [show](#show)

---

### env

Display environment variables for tasks.

**Syntax**:
```bash
zr env [options]
```

**Examples**:
```bash
# Show all env vars
zr env

# Show for specific task
zr env --task build

# Export format (shell-sourceable)
zr env --export

# Shell-specific format
zr env --export --shell bash
zr env --export --shell fish
```

**Options**:
- `--task <name>` — Show task-specific env
- `--export` — Shell-sourceable format
- `--shell <type>` — Shell type (bash/zsh/fish)

**See also**: [export](#export), [Shell setup guide](shell-setup.md)

---

### export

Export environment variables in shell-sourceable format.

**Syntax**:
```bash
zr export [options]
```

**Examples**:
```bash
# Export all task env vars
eval $(zr export)

# Export specific task
eval $(zr export --task build)

# Generate shell functions
eval $(zr export --functions)
```

**Generated functions**:
```bash
zr_build() { zr run build "$@"; }
zr_test() { zr run test "$@"; }
```

**See also**: [env](#env), [Shell setup guide](shell-setup.md)

---

### cd

Print path to workspace member (for shell integration).

**Syntax**:
```bash
zr cd <member> [options]
```

**Examples**:
```bash
# Print member path
zr cd frontend
# Output: /path/to/workspace/packages/frontend

# Shell integration
cd $(zr cd frontend)
```

**Shell function**:
```bash
zrcd() { cd $(zr cd "$1"); }
```

**See also**: [workspace list](#workspace-list)

---

### bench

Benchmark task performance with statistics.

**Syntax**:
```bash
zr bench <task> [options]
```

**Examples**:
```bash
# Benchmark task (10 runs)
zr bench build

# Custom iterations
zr bench test --iterations 50

# Warmup runs
zr bench deploy --warmup 5 --iterations 20
```

**Output**:
```
Benchmark: build (20 runs, 5 warmup)
  Min:    1.234s
  Max:    1.567s
  Mean:   1.401s
  Median: 1.398s
  Stddev: 0.089s
```

**See also**: [analytics](#analytics), [Benchmarks guide](benchmarks.md)

---

### analytics

Generate build analysis reports.

**Syntax**:
```bash
zr analytics [options]
```

**Examples**:
```bash
# Generate analytics report
zr analytics

# Export to JSON
zr analytics --format json > report.json

# Interactive TUI
zr analytics --tui
```

**Metrics**:
- Task execution times
- Dependency graph complexity
- Cache hit rates
- Resource usage

**See also**: [monitor](#monitor), [bench](#bench)

---

### context

Generate AI-friendly project metadata.

**Syntax**:
```bash
zr context [options]
```

**Examples**:
```bash
# Generate context
zr context

# JSON output
zr context --format json

# Include file tree
zr context --include-tree
```

**Output**:
```markdown
# Project Context

## Tasks
- build: Build the application
- test: Run test suite
- deploy: Deploy to production

## Dependencies
build → install
test → build
deploy → test, build

## Technologies
- Node.js 20.11.1
- TypeScript
- Docker
```

**See also**: [mcp serve](#mcp-serve)

---

### doctor

Diagnose environment and toolchain setup.

**Syntax**:
```bash
zr doctor [options]
```

**Examples**:
```bash
# Run diagnostics
zr doctor
```

**Checks**:
- zr version
- Config file validity
- Toolchain installations
- Git repository status
- System dependencies

**Output**:
```
✓ zr v1.71.0
✓ Config: zr.toml (valid)
✓ Node.js 20.11.1 (required: 20.11.1)
✓ Git repository
✗ Python not found (required: 3.12.1)
```

**See also**: [validate](#validate), [tools list](#tools-list)

---

### estimate

Estimate task or workflow duration based on execution history.

**Syntax**:
```bash
zr estimate <task|workflow> [options]
```

**Examples**:
```bash
# Estimate task duration
zr estimate build

# Estimate workflow duration
zr estimate ci
```

**Output**:
```
Estimate for 'build':
  Predicted: 1.4s (±0.2s)
  Based on: 127 runs
  Confidence: 95%
```

**See also**: [history](#history), [bench](#bench)

---

### failures

View or clear captured task failure reports.

**Syntax**:
```bash
zr failures [list|clear] [options]
```

**Examples**:
```bash
# List failures
zr failures list

# Clear failures
zr failures clear

# Show specific failure
zr failures list --task build
```

**See also**: [history](#history)

---

### version

Show or bump package version.

**Syntax**:
```bash
zr version [--bump=TYPE] [options]
```

**Examples**:
```bash
# Show current version
zr version

# Bump patch version
zr version --bump=patch

# Bump minor version
zr version --bump=minor

# Bump major version
zr version --bump=major
```

**See also**: [publish](#publish)

---

### upgrade

Upgrade zr to the latest version.

**Syntax**:
```bash
zr upgrade [options]
```

**Examples**:
```bash
# Upgrade to latest
zr upgrade

# Check for updates without installing
zr upgrade --check

# Upgrade to specific version
zr upgrade --version 1.71.0
```

**See also**: [version](#version)

---

### completion

Print shell completion script.

**Syntax**:
```bash
zr completion <shell> [options]
```

**Examples**:
```bash
# Bash
zr completion bash > /etc/bash_completion.d/zr
source /etc/bash_completion.d/zr

# Zsh
zr completion zsh > ~/.zsh/completion/_zr
source ~/.zsh/completion/_zr

# Fish
zr completion fish > ~/.config/fish/completions/zr.fish

# PowerShell
zr completion powershell > zr.ps1
```

**Supported shells**:
- `bash`
- `zsh`
- `fish`
- `powershell`

---

## Global Options

These options apply to all commands:

- `--help, -h` — Show help message
- `--version` — Show version information
- `--config <path>` — Config file path (default: `zr.toml`)
- `--profile, -p <name>` — Activate named profile
- `--format, -f <fmt>` — Output format (text or json)
- `--no-color` — Disable color output
- `--quiet, -q` — Suppress non-error output
- `--verbose, -v` — Verbose output
- `--jobs, -j <N>` — Max parallel tasks (default: CPU count)
- `--dry-run, -n` — Show what would run without executing

**Environment variables**:
- `ZR_PROFILE=<name>` — Alternative to `--profile`
- `ZR_CONFIG=<path>` — Alternative to `--config`
- `NO_COLOR=1` — Disable color output

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Task execution failure |
| 2 | Configuration error |
| 3 | Dependency cycle |
| 4 | Task not found |
| 5 | Validation error |
| 6 | Toolchain error |
| 7 | Cache error |
| 8 | Workspace error |

**See also**: [Error codes reference](error-codes.md)

---

## Aliases

You can define custom command aliases in `zr.toml`:

```toml
[aliases]
dev = "run server --profile dev"
ci = "workflow ci --jobs 4"
deploy = "workflow deploy --profile production"
```

Usage:
```bash
zr dev      # Runs: zr run server --profile dev
zr ci       # Runs: zr workflow ci --jobs 4
zr deploy   # Runs: zr workflow deploy --profile production
```

**See also**: [Configuration guide on aliases](configuration.md#aliases)
