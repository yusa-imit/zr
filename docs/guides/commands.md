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

Run a task and its dependencies. If no task is specified, launches an interactive task picker.

```bash
zr run [task]
```

**Interactive Task Picker:**

When `zr run` is called without a task name, an interactive TUI picker is launched (requires TTY):

```bash
zr run  # launches interactive picker
```

**Picker Features:**
- **Real-time fuzzy search** — Filter tasks as you type using substring matching and Levenshtein distance (max distance: 3)
- **Keyboard navigation** — Arrow keys, `j`/`k` (vim-style), `g` (top), `G` (bottom)
- **Metadata preview** — Shows selected task's command, description, dependencies, tags
- **Task and workflow support** — Unified picker for both tasks and workflows
- **Search mode** — Press `/` to enter search, `Esc`/`Enter` to exit search
- **Execute or quit** — Press `Enter` to run selected task, `q`/`Esc` to cancel

**Examples:**
```bash
zr run  # interactive picker
zr run build  # run specific task
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

List available tasks, profiles, or workspace members with optional filtering.

```bash
zr list [pattern] [OPTIONS]
```

**Examples:**
```bash
zr list  # all tasks and workflows
zr list test  # tasks matching "test"
zr list --tree  # show dependency tree
zr list --tags ci  # filter by tags
zr list --tags ci,build  # multiple tags
zr list --profiles  # list all profile names (v1.23.0+)
zr list --members  # list all workspace members (v1.23.0+)
```

**Options:**
- `--tree` — Show tasks as a dependency tree
- `--tags <tags>` — Filter by comma-separated tags
- `--profiles` — List only profile names (useful for shell completion)
- `--members` — List only workspace member paths (useful for shell completion)

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
zr graph --format tui  # Interactive TUI with mouse support
zr graph --format json  # JSON output
zr graph --format html > graph.html  # HTML visualization
```

**Options:**
- `--ascii` — ASCII tree view
- `--format <fmt>` — Output format: `dot`, `ascii`, `tui`, `json`, `html`
- `--format tui` — Interactive TUI with tree navigation (use `j/k` or click to navigate, mouse scroll to move, `q` to quit)

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

### `add`

Interactively add a task, workflow, or profile.

```bash
zr add <type> [name]
```

**Examples:**
```bash
# Interactive task creation
zr add task
# Prompts for: name, command, description, dependencies

# Add task with predefined name
zr add task build
# Prompts for: command, description, dependencies

# Interactive workflow creation
zr add workflow ci
# Prompts for: description, multi-stage task lists

# Interactive profile creation
zr add profile production
# Prompts for: environment variables (KEY=VALUE format)
```

**Interactive Prompts:**

For **tasks**:
- Task name (if not provided)
- Add command? (y/n) → Command line
- Add description? (y/n) → Description text
- Add dependencies? (y/n) → Comma-separated task names

For **workflows**:
- Workflow name (if not provided)
- Add description? (y/n) → Description text
- Add stages (one per line, empty to finish)
  - Stage 1 tasks (comma-separated)
  - Stage 2 tasks (comma-separated)
  - ... (continues until empty input)

For **profiles**:
- Profile name (if not provided)
- Add environment variables? (y/n)
  - Environment variable (KEY=VALUE format)
  - ... (continues until empty input)

**Notes:**
- Appends to existing `zr.toml` file
- Validates input format (e.g., KEY=VALUE for env vars)
- Escapes special characters in TOML strings
- Gracefully handles EOF (cancelled by user)

---

### `edit` (v1.25.0)

Interactively edit and create tasks, workflows, or profiles with guided prompts and live TOML preview.

```bash
zr edit <type>
```

**Examples:**
```bash
# Edit/create a task with interactive prompts
zr edit task

# Edit/create a workflow
zr edit workflow

# Edit/create a profile
zr edit profile
```

**Interactive Prompts:**

For **tasks**:
- Task name (required)
- Command (required)
- Description (optional)
- Dependencies (optional, comma-separated)

For **workflows**:
- Workflow name (required)

For **profiles**:
- Profile name (required)

**Features:**

- **Field Validation:** Required fields are enforced, optional fields can be skipped
- **Context-Sensitive Help:** Each prompt shows helpful hints below the input
- **Live TOML Preview:** Preview the generated TOML before confirming
- **Automatic Appending:** Appends to existing `zr.toml` or creates a new one
- **Graceful Cancellation:** Handles EOF and user cancellation cleanly

**Example Session:**

```bash
$ zr edit task

=== Create New Task ===

Task name: build
  💡 Unique task identifier
> build

Command: npm run build
  💡 Shell command to execute
> npm run build

Description (optional): Build the application
  💡 Human-readable description
> Build the application

Dependencies (optional): lint,test
  💡 Comma-separated list of task names
> lint,test

--- Generated TOML ---
[tasks.build]
cmd = "npm run build"
description = "Build the application"
deps = ["lint", "test"]


Add to zr.toml? [Y/n]: y
✓ Configuration appended to zr.toml
```

**Notes:**
- Validates task name uniqueness (warns if task already exists)
- Properly escapes TOML strings
- Supports cancellation at any prompt (Ctrl+D or EOF)
- Shows live preview before writing to file

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

**Options:**
- `--workspace` - Clear cache for all workspace members
- `--member <path>` - Clear cache for a specific workspace member

**Examples:**

```bash
# Clear cache for the current project
zr cache clear

# Clear cache for all workspace members
zr cache clear --workspace

# Clear cache for a specific workspace member
zr cache clear --member packages/api
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

Search installed plugins or the remote plugin registry.

```bash
# Search installed plugins:
zr plugin search [query]

# Search remote registry:
zr plugin search --remote [query]
```

**Options:**
- `--remote` — Search the plugin registry instead of local installations
- `--format json` — Output results as JSON

**Examples:**
```bash
# Search installed plugins:
zr plugin search docker

# Search remote registry:
zr plugin search --remote docker

# List all plugins in registry:
zr plugin search --remote

# Get JSON output:
zr plugin search --remote ci --format json
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

**Navigation:**
- `j/k` or `↑/↓` arrow keys: Move selection
- Mouse click: Select task directly
- `Enter`: Execute selected task
- `g/G`: Jump to top/bottom
- `q`: Quit

---

### `live`

Run task with live TUI log streaming.

```bash
zr live <task>
```

Shows real-time task output in a TUI interface with scroll support.

**Navigation:**
- `j/k` or `↑/↓` arrow keys: Switch between tasks
- Mouse click: Select task in task list
- Mouse scroll: Scroll through task logs
- `PgUp/PgDn`: Page up/down in logs
- `q`: Quit

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

Generate build analysis reports with detailed metrics.

```bash
zr analytics [OPTIONS]
```

**Examples:**
```bash
zr analytics                         # Open interactive HTML report
zr analytics --format json          # JSON output to stdout
zr analytics -o report.html         # Save HTML to file
zr analytics --limit 100            # Analyze last 100 executions
zr analytics --no-open              # Generate without opening browser
```

**Options:**
- `--format <fmt>` — Output format: `html` (default), `json`
- `-o, --output <path>` — Save report to file instead of temp
- `--limit <n>` — Analyze last N executions (default: 1000)
- `--no-open` — Don't open HTML report in browser

**Report Contents:**
- **Task execution metrics** — Per-task timing, success rates, retry counts
- **Resource usage** — Peak memory (MB), average CPU (%), per task
- **Failure analysis** — Failure rates, patterns, trends over time
- **Critical path** — Slowest tasks (bottlenecks)
- **Parallelization efficiency** — CPU utilization, speedup metrics
- **Time series charts** — Duration trends, cache hit rates (HTML only)

**Resource Tracking (v1.16.0+):**

Resource usage is automatically captured during task execution:
- **Peak Memory**: Maximum RSS (resident set size) in bytes
- **Average CPU**: CPU percentage averaged over execution (0-100% per core)

Resource data is stored in `.zr_history` and included in all analytics reports.

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

### `failures`

View and manage captured task failure reports.

```bash
zr failures [subcommand] [OPTIONS]
```

**Subcommands:**
- `list` (default) — View all captured failure reports
- `clear` — Remove all failure reports

**Examples:**
```bash
# View all failure reports
zr failures
zr failures list

# Filter by task name
zr failures --task build

# Clear all failure reports
zr failures clear

# Custom storage directory
zr failures --storage-dir /path/to/failures
```

**Options:**
- `--task <name>` — Filter failures by task name
- `--storage-dir <path>` — Custom storage directory (default: `.zr/failures`)

**Failure Report Contents:**
Each failure report includes:
- Task name and execution timestamp
- Exit code and command that was run
- Working directory and environment variables
- Timeline events (queued, started, completed)
- Duration and retry information (if applicable)

**Note:** Failure reports are automatically captured when tasks fail and stored in `.zr/failures/` as JSON files. Use this command to review failures for debugging or post-mortem analysis.

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

Print shell completion script with context-aware suggestions.

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

**Completion Features (v1.23.0+):**
- **Dynamic task names**: Completes task names from `zr.toml` when typing `zr run <TAB>`
- **Workflow names**: Completes workflow names for `zr workflow <TAB>`
- **Profile names**: Completes profile names for `--profile <TAB>` or `-p <TAB>`
- **Workspace members**: Completes member paths for workspace commands
- **Flag values**: Context-aware completion for `--format`, `--config`, and other flags
- **Subcommands**: Intelligent completion for multi-level commands like `zr workspace run <TAB>`

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
