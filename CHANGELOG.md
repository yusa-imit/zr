# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.5] - 2026-02-23

### Added
- **Shell-sourceable environment export**: `zr export` command generates shell-compatible env variable exports
  - Supports bash, zsh, fish shell formats with `--shell` flag
  - Automatic shell detection from `$SHELL` environment variable
  - Toolchain PATH injection - automatically includes toolchain bin directories in exported PATH
  - Profile-aware exports with `--profile` flag
  - Task-specific environment merging with `--task` flag
- **Task-specific environment layering**: Enhanced `zr env` command with task context
  - Display merged environment for specific tasks with `--task` flag
  - Visual layer breakdown showing system vs task-specific variables
  - Task environment overrides system environment (proper layering semantics)

### Changed
- Enhanced validation with whitespace-only command detection and duplicate task detection in workflow stages

## [0.0.4] - 2026-02-23

### Added

#### Phase 8 - Enterprise & Community Features
- **CODEOWNERS auto-generation**: `zr codeowners generate` command for workspace-based ownership files
- **Publishing & versioning automation**: `zr version` and `zr publish` commands with conventional commits support
  - Auto-detect version bump type from commit history (major/minor/patch)
  - CHANGELOG.md generation with categorized sections
  - Git tag creation and staged commit guidance
- **Build analytics reports**: `zr analytics` command with HTML/JSON output
  - Task execution time trends
  - Failure rates tracking
  - Critical path analysis (slowest tasks)
  - Parallelization efficiency metrics
- **AI-friendly metadata generation**: `zr context` command outputs structured project info (JSON/YAML)
  - Project dependency graph
  - Task catalog per package
  - File ownership mapping (CODEOWNERS)
  - Recent changes summary (git commits)
  - Toolchain information
- **Conformance rules engine**: `zr conformance` command with file-level governance
  - 5 rule types: import_pattern, file_naming, file_size, directory_depth, file_extension
  - Auto-fix support with `--fix` flag (removes banned imports)
  - Severity levels (error/warning/info)
  - Custom ignore patterns
- **Performance benchmarking**: `zr bench <task>` command with statistical analysis
  - Mean, median, standard deviation, coefficient of variation
  - Profile and quiet mode support
  - Configurable iteration count
- **Environment diagnostics**: `zr doctor` command verifies toolchain and environment setup
  - Checks for git, docker, curl, and installed toolchains
  - Color-coded status output
  - Exit code 1 on issues

#### Phase 7 - Multi-repo & Remote Cache
- **Remote cache backends**: Full support for 4 major cloud providers
  - HTTP backend with curl-based client
  - S3 backend with AWS Signature v4 authentication (compatible with MinIO, R2, etc.)
  - GCS backend with OAuth2 service account and RS256 JWT assertion
  - Azure Blob backend with Shared Key HMAC-SHA256 authentication
- **Multi-repo orchestration**: Complete multi-repository support
  - `zr repo sync`: Clone and pull all repositories from zr-repos.toml
  - `zr repo status`: Show git status across all repos
  - `zr repo graph`: Visualize cross-repo dependencies (ASCII/DOT/JSON)
  - `zr repo run <task>`: Execute tasks across repos in topological order
- **Synthetic workspace**: `zr workspace sync` unifies multi-repo into monorepo view
  - Builds unified member list and dependency map
  - Caches metadata to `~/.zr/synthetic-workspace/metadata.json`
  - Full integration with graph/workspace commands

#### Phase 6 - Monorepo Intelligence
- **Affected detection**: Git diff-based change detection for workspace members
  - `--affected <ref>` CLI flag filters tasks to changed projects
  - `zr affected <task>` standalone command with advanced filtering
  - `--include-dependents`: Run on projects that depend on affected ones
  - `--exclude-self`: Only run on dependents, not directly affected
  - `--include-dependencies`: Run on dependencies of affected projects
  - `--list`: Only list affected projects without running
- **Dependency graph expansion**: Transitive dependency expansion with BFS traversal
- **Project graph visualization**: `zr graph` command with 4 output formats
  - ASCII: Terminal tree view with affected highlighting
  - DOT: Graphviz format for visual diagrams
  - JSON: Programmatic access to dependency structure
  - HTML: Interactive D3.js force-directed graph
- **Architecture constraints**: `zr lint` command validates architectural rules
  - 3 constraint types: no-circular, tag-based, banned-dependency
  - Tag-based dependency control (app→lib, feature→feature rules)
  - Module boundary enforcement with [metadata] section parsing

#### Phase 5 - Toolchain Management
- **Multi-language toolchain support**: 8 toolchain types supported
  - Node.js, Python, Zig, Go, Rust, Deno, Bun, Java
  - Official source downloads with version resolution
  - Archive extraction (tar/unzip/PowerShell)
- **Toolchain CLI commands**:
  - `zr tools list [kind]`: List installed toolchain versions
  - `zr tools install <kind>@<version>`: Install specific version
  - `zr tools outdated [kind]`: Check for updates against official registries
- **Auto-install on task run**: Per-task toolchain requirements with automatic installation
- **PATH manipulation**: Inject toolchain bin paths into task execution environment
  - JAVA_HOME and GOROOT environment variables
  - Full scheduler integration

#### Additional Commands & Features
- **Self-update system**: `zr upgrade` command with version checking and binary replacement
- **Comprehensive cleanup**: `zr clean` command for cache/history/toolchains/plugins
- **Environment commands**:
  - `zr env` displays environment variables for tasks
  - `zr export` outputs shell-sourceable env vars with toolchain PATH injection
  - `zr cache status` shows cache statistics
  - `zr setup` one-command project onboarding (install tools + run setup tasks)
- **Enhanced shell completions**: All Phase 5-8 commands included in bash/zsh/fish completions
- **Validation improvements**: Edge case detection for whitespace-only commands and duplicate workflow tasks

## [0.0.3] - 2026-02-20

### Added

#### Phase 4 - Extensibility
- Native plugin system with .so/.dylib dynamic loading and C-ABI hooks
- Plugin management CLI: install/remove/update/info/search from local/git/registry
- Plugin scaffolding with `zr plugin create <name>`
- Built-in plugins: env (.env loading), git (branch/changes), notify (webhooks), cache (lifecycle hooks)
- **Docker built-in plugin**: Complete with build/push/tag/prune, BuildKit cache, multi-platform support
- **WASM plugin sandbox**: Full MVP implementation
  - Binary format parser (magic/version/sections)
  - Stack-based interpreter (35+ opcodes)
  - Memory isolation with host callbacks
  - Lifecycle hooks (init/pre_task/post_task)
- Plugin documentation (PLUGIN_GUIDE.md, PLUGIN_DEV_GUIDE.md)

#### Phase 3 - UX & Resources
- **Interactive TUI**:
  - Task picker with arrow keys + Enter
  - `zr live <task>` for real-time log streaming
  - Multi-task live mode support
  - `zr interactive-run <task>` with cancel/pause/resume controls
  - Automatic retry prompt on task failure
- **Resource limits**:
  - CPU and memory limits (`max_cpu`, `max_memory` config fields)
  - Cross-platform monitoring (Linux/macOS/Windows)
  - Kernel-level enforcement (cgroups v2 / Job Objects)
  - `--monitor` CLI flag for live resource display
- **Workspace/monorepo support**:
  - `[workspace] members` with glob discovery
  - `zr workspace list` and `zr workspace run <task>`
- CLI enhancements:
  - `--dry-run` / `-n` flag for execution plans
  - `zr init` scaffolds starter zr.toml
  - `zr validate` with --strict and --schema modes
  - Shell completion (bash/zsh/fish)
  - Global flags: --jobs, --no-color, --quiet, --verbose, --config, --format json
- Progress bar output module

#### Phase 2 - Workflows & Expressions
- **Workflow system**: `[workflows.X]` with `[[workflows.X.stages]]` and fail_fast
- **Profile system**: `--profile` flag, `ZR_PROFILE` env var, per-task overrides
- **Watch mode**: Native filesystem watchers (inotify/kqueue/ReadDirectoryChangesW) with polling fallback
- **Matrix execution**: Cartesian product with `${matrix.KEY}` interpolation
- **Task caching**: Wyhash64 fingerprint with `~/.zr/cache/` storage
- **Expression engine**: 100% of PRD §5.6 implemented
  - Logical operators: `&&`, `||` with short-circuit evaluation
  - Platform checks: `platform == "linux" | "darwin" | "windows"`
  - Architecture checks: `arch == "x86_64" | "aarch64"`
  - File operations: `file.exists()`, `file.changed()`, `file.newer()`, `file.hash()`
  - Shell execution: `shell(cmd)` for command success checks
  - Version comparison: `semver.gte(v1, v2)`
  - Environment variables: `env.VAR == "val"` with truthy checks
  - Runtime state refs: `stages['name'].success`, `tasks['name'].duration`

## [0.0.2] - 2026-02-17

### Added

#### Phase 1 - Foundation (MVP)
- Project bootstrap (build.zig, build.zig.zon, src/main.zig)
- TOML config parser with schema validation
- Task execution engine:
  - Process spawning with environment variables
  - Retry with exponential backoff
  - Timeout handling
- Dependency graph (DAG):
  - Graph construction with Kahn's Algorithm
  - Cycle detection
  - Topological sorting
- Parallel execution engine with worker pool and semaphores
- Basic CLI commands:
  - `zr run <task>`: Execute tasks with dependencies
  - `zr list`: Show available tasks
  - `zr graph`: Display dependency graph
- Execution history module with `zr history` command
- Cross-compilation CI pipeline (6 targets: linux/macos/windows × x86_64/aarch64)
- Task configuration fields:
  - timeout, allow_failure, deps_serial
  - env, retry, condition, cache
  - max_concurrent, matrix
- Color output and error formatting
- Integration test suite (15+ black-box CLI tests)

### Performance
- Binary size: ~2.9MB
- Cold start: ~0ms
- Memory usage: ~2MB RSS
- Test coverage: 472+ unit tests (8 platform-specific skipped)

## [0.0.1] - 2026-02-16

### Added
- Initial project structure
- Basic task runner implementation
- Version support

---

## Version Comparison

| Version | Release Date | Phases | Key Features |
|---------|--------------|--------|--------------|
| **0.0.4** | 2026-02-23 | 5-8 | Enterprise features (CODEOWNERS, analytics, conformance, benchmarks), Multi-repo orchestration, Toolchain management, Remote cache (4 backends) |
| **0.0.3** | 2026-02-20 | 3-4 | Interactive TUI, Resource limits, WASM plugins, Docker plugin, Workspace support |
| **0.0.2** | 2026-02-17 | 1-2 | MVP task runner, Workflows, Expression engine, Watch mode, Caching |
| **0.0.1** | 2026-02-16 | - | Initial release |

---

## Migration Guides

### Upgrading to 0.0.4

No breaking changes. New features are opt-in through:
- Toolchain management: Add `[tools]` section to zr.toml
- Remote cache: Add `[cache.remote]` section (HTTP/S3/GCS/Azure)
- Multi-repo: Create zr-repos.toml for cross-repo orchestration
- Conformance: Add `[[conformance.rules]]` for code governance

### Upgrading to 0.0.3

No breaking changes. New features:
- Interactive mode: Use `zr interactive` or `zr live <task>`
- Resource limits: Add `max_cpu` and `max_memory` to tasks
- Plugins: Add `[plugins]` section to zr.toml

### Upgrading to 0.0.2

No breaking changes. New features:
- Workflows: Add `[workflows.X]` sections
- Profiles: Use `--profile <name>` or `ZR_PROFILE` env var
- Watch mode: Use `zr watch <task> [paths...]`
- Expression engine: Use conditions in task `condition` fields

---

## Links

- [GitHub Repository](https://github.com/yourusername/zr)
- [Documentation](./docs/)
- [PRD (Product Requirements)](./docs/PRD.md)
- [Plugin Development Guide](./docs/PLUGIN_DEV_GUIDE.md)
- [Plugin User Guide](./docs/PLUGIN_GUIDE.md)

[Unreleased]: https://github.com/yourusername/zr/compare/v0.0.4...HEAD
[0.0.4]: https://github.com/yourusername/zr/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/yourusername/zr/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/yourusername/zr/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/yourusername/zr/releases/tag/v0.0.1
