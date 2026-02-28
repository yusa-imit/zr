# Commands Reference

Complete reference for all `zr` CLI commands.

## Table of Contents

- [Core Commands](#core-commands)
- [Workflow Commands](#workflow-commands)
- [Workspace Commands](#workspace-commands)
- [Cache Commands](#cache-commands)
- [Plugin Commands](#plugin-commands)
- [Interactive Commands](#interactive-commands)
- [Toolchain Commands](#toolchain-commands)
- [Repository Commands](#repository-commands)
- [Publishing Commands](#publishing-commands)
- [Development Commands](#development-commands)
- [MCP & LSP Commands](#mcp--lsp-commands)
- [Global Options](#global-options)

---

## Core Commands

### `run`

Run a task and its dependencies.

```bash
zr run <task>
```

**Examples:**
```bash
zr run build
zr run test build lint  # run multiple tasks
zr run --dry-run deploy  # show execution plan without running
zr run --profile prod build  # use a profile
zr run --monitor test  # show live resource usage
```

**Options:**
- `--dry-run, -n` — Show what would run without executing
- `--profile, -p <name>` — Use a named profile
- `--monitor, -m` — Display live resource usage (CPU/memory)
- `--jobs, -j <N>` — Max parallel tasks

---

### `list`

List available tasks with optional filtering.

```bash
zr list [pattern] [OPTIONS]
```

**Examples:**
```bash
zr list  # all tasks
zr list test  # tasks matching "test"
zr list --tree  # show dependency tree
zr list --tags ci  # filter by tags
zr list --tags ci,build  # multiple tags
```

**Options:**
- `--tree` — Show tasks as a dependency tree
- `--tags <tags>` — Filter by comma-separated tags

---

### `show`

Display detailed information about a task.

```bash
zr show <task>
```

**Example:**
```bash
zr show build
# Output:
# Task: build
# Description: Build the application
# Command: npm run build
# Dependencies: install
# Tags: ci, build
# Timeout: 300000ms
# Cache: enabled
```

---

### `graph`

Visualize task dependency graph.

```bash
zr graph [OPTIONS]
```

**Examples:**
```bash
zr graph  # DOT format
zr graph --ascii  # ASCII art tree
zr graph --format json  # JSON output
zr graph --format html > graph.html  # HTML visualization
```

**Options:**
- `--ascii` — ASCII tree view
- `--format <fmt>` — Output format: `dot`, `json`, `html`

---

### `history`

Show recent task execution history.

```bash
zr history [OPTIONS]
```

**Examples:**
```bash
zr history
zr history --status failed  # only failed runs
zr history --since 1d  # last 24 hours
zr history --task build  # specific task
```

**Options:**
- `--status <status>` — Filter by status: `success`, `failed`, `running`
- `--since <duration>` — Time filter: `1h`, `1d`, `1w`
- `--task <name>` — Filter by task name

---

### `init`

Initialize a new `zr.toml` configuration.

```bash
zr init [OPTIONS]
```

**Examples:**
```bash
zr init  # create basic template
zr init --detect  # auto-detect from package.json, Makefile, etc.
zr init --from-make  # convert from Makefile (Phase 13B)
zr init --from-just  # convert from Justfile (Phase 13B)
zr init --from-task  # convert from Taskfile.yml (Phase 13B)
```

**Options:**
- `--detect` — Auto-detect project language and extract tasks
- `--from-make` — Convert from Makefile (Phase 13B)
- `--from-just` — Convert from Justfile (Phase 13B)
- `--from-task` — Convert from Taskfile.yml (Phase 13B)

---

### `validate`

Validate `zr.toml` configuration.

```bash
zr validate
```

Checks for:
- TOML syntax errors
- Missing dependencies
- Circular dependencies
- Invalid expressions
- Schema violations

**Example:**
```bash
zr validate
# ✓ Configuration is valid
# ✓ 15 tasks defined
# ✓ No circular dependencies
# ✓ All dependencies resolved
```

---

### `clean`

Clean zr data (cache, history, toolchains, plugins).

```bash
zr clean [OPTIONS]
```

**Examples:**
```bash
zr clean  # interactive selection
zr clean --cache  # clear cache only
zr clean --history  # clear history only
zr clean --toolchains  # remove installed toolchains
zr clean --plugins  # remove installed plugins
zr clean --all  # remove everything
```

**Options:**
- `--cache` — Clear task cache
- `--history` — Clear execution history
- `--toolchains` — Remove toolchains
- `--plugins` — Remove plugins
- `--all` — Remove all data

---

## Workflow Commands

### `workflow`

Run a workflow by name.

```bash
zr workflow <name>
```

**Example:**
```bash
zr workflow ci
# Runs all stages in the 'ci' workflow sequentially
```

---

### `watch`

Watch files and auto-run task on changes.

```bash
zr watch <task> [paths...]
```

**Examples:**
```bash
zr watch build  # watch all files
zr watch test src/ tests/  # watch specific paths
zr watch build "**/*.ts"  # watch TypeScript files
```

Uses native filesystem watchers (inotify/kqueue/ReadDirectoryChangesW).

---

## Workspace Commands

### `workspace list`

List all workspace member directories.

```bash
zr workspace list
```

**Example:**
```bash
zr workspace list
# packages/core
# packages/utils
# apps/frontend
# apps/backend
```

---

### `workspace run`

Run a task across all workspace members.

```bash
zr workspace run <task>
```

**Example:**
```bash
zr workspace run test
# Runs 'test' task in each workspace member in parallel
```

---

### `workspace sync`

Build synthetic workspace from multi-repo configuration.

```bash
zr workspace sync
```

Syncs repositories defined in `zr-repos.toml` and creates a synthetic workspace.

---

### `affected`

Run task on affected workspace members only.

```bash
zr affected <task> [--affected <ref>]
```

**Examples:**
```bash
zr affected test --affected origin/main
zr affected build --affected HEAD~1
zr run test --affected origin/main  # also works with run command
```

Uses git-based change detection to identify affected workspace members.

---

## Cache Commands

### `cache status`

Show cache statistics.

```bash
zr cache status
```

**Example:**
```bash
zr cache status
# Cache directory: ~/.zr/cache
# Total size: 1.2 GB
# Entries: 342
# Hit rate: 78%
```

---

### `cache clear`

Clear all cached task results.

```bash
zr cache clear
```

---

## Plugin Commands

### `plugin list`

List plugins declared in `zr.toml`.

```bash
zr plugin list
```

---

### `plugin builtins`

List available built-in plugins.

```bash
zr plugin builtins
```

Built-in plugins: `env`, `git`, `cache`, `docker`, `http`.

---

### `plugin search`

Search installed plugins.

```bash
zr plugin search [query]
```

**Example:**
```bash
zr plugin search docker
```

---

### `plugin install`

Install a plugin from a local path or git URL.

```bash
zr plugin install <path|url>
```

**Examples:**
```bash
zr plugin install ./my-plugin.wasm
zr plugin install https://github.com/user/plugin/releases/download/v1.0/plugin.wasm
```

---

### `plugin remove`

Remove an installed plugin.

```bash
zr plugin remove <name>
```

---

### `plugin update`

Update a plugin.

```bash
zr plugin update <name> [path]
```

---

### `plugin info`

Show metadata for an installed plugin.

```bash
zr plugin info <name>
```

---

### `plugin create`

Scaffold a new plugin template.

```bash
zr plugin create <name>
```

---

## Interactive Commands

### `interactive` (alias: `i`)

Launch interactive TUI task picker.

```bash
zr interactive
# or
zr i
```

Shows a full-screen TUI with task selection, filtering, and execution.

---

### `live`

Run task with live TUI log streaming.

```bash
zr live <task>
```

Shows real-time task output in a TUI interface with scroll support.

---

### `interactive-run` (alias: `irun`)

Run task with cancel/retry controls.

```bash
zr interactive-run <task>
# or
zr irun <task>
```

Interactive mode with cancel and retry buttons.

---

## Toolchain Commands

### `tools list`

List installed toolchain versions.

```bash
zr tools list [kind]
```

**Examples:**
```bash
zr tools list  # all toolchains
zr tools list node  # Node.js versions only
```

---

### `tools install`

Install a toolchain.

```bash
zr tools install <kind>@<version>
```

**Examples:**
```bash
zr tools install node@20.11.1
zr tools install python@3.12.0
zr tools install zig@0.15.2
```

Supported toolchains: `node`, `python`, `zig`, `go`, `rust`, `deno`, `bun`, `java`.

---

### `tools outdated`

Check for outdated toolchains.

```bash
zr tools outdated [kind]
```

**Example:**
```bash
zr tools outdated
# node: 20.11.0 → 20.11.1 available
# python: 3.11.5 → 3.12.0 available
```

---

### `setup`

Set up project (install tools, run setup tasks).

```bash
zr setup
```

Automatically installs required toolchains and runs initialization tasks.

---

### `doctor`

Diagnose environment and toolchain setup.

```bash
zr doctor
```

**Example output:**
```
✓ zr version: 3.0.0
✓ Configuration: valid
✓ Node.js: 20.11.1 (required: 20.x)
✗ Python: not found (required: 3.12)
✓ Git: 2.42.0
```

---

## Repository Commands

For multi-repository projects (defined in `zr-repos.toml`).

### `repo sync`

Sync all repositories.

```bash
zr repo sync
```

---

### `repo status`

Show git status of all repositories.

```bash
zr repo status
```

**Example output:**
```
packages/core: clean (main)
packages/utils: 2 modified files (develop)
apps/frontend: clean (main)
```

---

## Publishing Commands

### `version`

Show or bump package version.

```bash
zr version [--bump=<type>]
```

**Examples:**
```bash
zr version  # show current version
zr version --bump=patch  # 1.0.0 → 1.0.1
zr version --bump=minor  # 1.0.1 → 1.1.0
zr version --bump=major  # 1.1.0 → 2.0.0
```

---

### `publish`

Publish a new version.

```bash
zr publish [OPTIONS]
```

**Examples:**
```bash
zr publish  # auto-detect version bump from conventional commits
zr publish --manual  # prompt for version
zr publish --tag  # create git tag
```

**Options:**
- `--manual` — Manual version selection
- `--tag` — Create git tag
- `--push` — Push to remote

---

### `codeowners generate`

Generate `CODEOWNERS` file from workspace.

```bash
zr codeowners generate
```

Uses workspace structure and git history to generate CODEOWNERS.

---

### `analytics`

Generate build analysis reports.

```bash
zr analytics [OPTIONS]
```

**Examples:**
```bash
zr analytics  # text summary
zr analytics --format html > report.html
zr analytics --format json > report.json
```

**Options:**
- `--format <fmt>` — Output format: `text`, `html`, `json`

---

### `context`

Generate AI-friendly project metadata.

```bash
zr context [OPTIONS]
```

**Examples:**
```bash
zr context  # YAML output
zr context --format json  # JSON output
```

Generates metadata for AI agents (Claude Code, Cursor) with task descriptions, dependencies, and execution history.

---

## Development Commands

### `bench`

Benchmark task performance.

```bash
zr bench <task> [OPTIONS]
```

**Examples:**
```bash
zr bench build  # run 10 iterations
zr bench build --iterations 100
zr bench build --warmup 5
```

**Options:**
- `--iterations <N>` — Number of runs (default: 10)
- `--warmup <N>` — Warmup runs (default: 3)

---

### `estimate`

Estimate task duration based on execution history.

```bash
zr estimate <task>
```

**Example:**
```bash
zr estimate build
# Estimated duration: 45s (based on 23 previous runs)
# Min: 38s, Max: 52s, Median: 44s
```

---

### `lint`

Validate architecture constraints.

```bash
zr lint
```

Checks conformance rules defined in `[conformance]` section.

**Example:**
```bash
zr lint
# ✓ No circular dependencies
# ✓ Tag-based dependencies valid
# ✗ Banned dependency: apps/frontend → packages/legacy
```

---

### `conformance`

Check code conformance against rules.

```bash
zr conformance [OPTIONS]
```

**Examples:**
```bash
zr conformance  # check all rules
zr conformance --fix  # auto-fix violations
zr conformance --rule no-circular  # specific rule
```

**Options:**
- `--fix` — Auto-fix violations
- `--rule <name>` — Check specific rule

---

### `env`

Display environment variables for tasks.

```bash
zr env [OPTIONS]
```

**Examples:**
```bash
zr env  # all env vars
zr env --task build  # env for specific task
```

---

### `export`

Export env vars in shell-sourceable format.

```bash
zr export [OPTIONS]
```

**Example:**
```bash
eval "$(zr export)"
# or
source <(zr export)
```

---

### `completion`

Print shell completion script.

```bash
zr completion <shell>
```

**Examples:**
```bash
zr completion bash > /etc/bash_completion.d/zr
zr completion zsh > ~/.zsh/completions/_zr
zr completion fish > ~/.config/fish/completions/zr.fish
```

Supported shells: `bash`, `zsh`, `fish`.

---

### `upgrade`

Upgrade zr to the latest version.

```bash
zr upgrade [OPTIONS]
```

**Examples:**
```bash
zr upgrade  # latest stable
zr upgrade --check  # check for updates without installing
```

**Options:**
- `--check` — Check for updates only

---

### `alias`

Manage command aliases.

```bash
zr alias <subcommand>
```

**Subcommands:**
- `add <name> <expansion>` — Add an alias
- `list` — List all aliases
- `remove <name>` — Remove an alias
- `show <name>` — Show alias expansion

**Examples:**
```bash
zr alias add ci "run build test lint"
zr alias list
zr alias show ci
zr alias remove ci
```

---

### `schedule`

Schedule tasks to run at specific times.

```bash
zr schedule <subcommand>
```

**Subcommands:**
- `add <task> <cron>` — Schedule a task
- `list` — List scheduled tasks
- `remove <id>` — Remove a schedule
- `show <id>` — Show schedule details

**Examples:**
```bash
zr schedule add test "0 2 * * *"  # 2 AM daily
zr schedule list
zr schedule remove 1
```

---

## MCP & LSP Commands

### `mcp serve`

Start MCP (Model Context Protocol) server for AI agent integration.

```bash
zr mcp serve
```

Starts an MCP server on stdio for integration with:
- Claude Code (Anthropic)
- Cursor (AI code editor)

Provides 9 MCP tools:
- `run_task`
- `list_tasks`
- `show_task`
- `validate_config`
- `show_graph`
- `run_workflow`
- `task_history`
- `estimate_duration`
- `generate_config`

See [MCP Integration Guide](mcp-integration.md) for setup.

---

### `lsp`

Start LSP (Language Server Protocol) server for editor integration.

```bash
zr lsp
```

Starts an LSP server on stdio for integration with:
- VS Code
- Neovim
- Emacs
- Any LSP-compatible editor

Features:
- Real-time diagnostics (TOML parse errors)
- Autocomplete (task names, fields, expressions)
- Hover documentation
- Go-to-definition for task references

See [LSP Setup Guide](lsp-setup.md) for configuration.

---

## Global Options

These options work with all commands:

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--version` | | Show version information |
| `--profile <name>` | `-p` | Activate a named profile |
| `--dry-run` | `-n` | Show plan without executing (run/workflow) |
| `--jobs <N>` | `-j` | Max parallel tasks (default: CPU count) |
| `--no-color` | | Disable color output |
| `--quiet` | `-q` | Suppress non-error output |
| `--verbose` | `-v` | Verbose output |
| `--config <path>` | | Config file path (default: `zr.toml`) |
| `--format <fmt>` | `-f` | Output format: `text` or `json` |
| `--monitor` | `-m` | Display live resource usage (CPU/memory) |
| `--affected <ref>` | | Run only affected members (e.g., `origin/main`) |

---

## Examples

### Run Multiple Tasks

```bash
zr run build test lint
# Runs all three tasks in parallel after resolving dependencies
```

### Profile-Specific Build

```bash
zr run --profile prod build
# Uses production profile settings
```

### Dry Run

```bash
zr run --dry-run deploy
# Shows execution plan without running
```

### Workspace Build

```bash
zr workspace run build
# Builds all workspace members in parallel
```

### Affected Testing

```bash
zr affected test --affected origin/main
# Tests only workspace members changed since origin/main
```

### Watch and Rebuild

```bash
zr watch build src/ include/
# Watches src/ and include/ directories, rebuilds on changes
```

---

## See Also

- [Configuration Reference](configuration.md) — `zr.toml` schema
- [Getting Started](getting-started.md) — quick start guide
- [MCP Integration](mcp-integration.md) — AI agent integration
- [LSP Setup](lsp-setup.md) — editor integration
