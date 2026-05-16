# zr — Milestones

## Current Status

- **Latest**: v1.82.0 (Task Result Caching & Memoization) — RELEASED 2026-05-04
- **Active milestones**: 0 (zuda WorkStealingDeque completed Cycle 228, zuda Graph Migration closed as DONE in Cycle 226)
- **READY milestones**: 0 (all zuda migrations complete)
- **BLOCKED milestones**: 0 (all blockers resolved)
- **DONE**: Sailor v2.5.0 & v2.6.0 Migration (Cycle 209), Dependency Resolution & Version Constraints (Cycles 204, 206, 208), Task Result Caching & Memoization (Cycles 193-199, v1.82.0 RELEASED), Enhanced Watch Mode & Live Reload (Cycles 189-192, v1.81.0 RELEASED), Sailor v2.3.0 & v2.4.0 Migration (Cycle 188), Task Output Artifacts & Persistence (Cycles 182, 184, 186, 187, v1.80.0 RELEASED), Task Documentation & Rich Help System (Cycles 172-174, 177, 179, v1.79.0 RELEASED), Enhanced Environment Variable Management (Cycle 171, v1.78.0 RELEASED), Enhanced Task Filtering & Selection Patterns (Cycles 163-164, v1.77.0), Task Conditional Dependencies Enhancement (Cycles 160-161, v1.76.0), Sailor v2.1.0 Migration (Cycle 159), Task Parameters & Dynamic Task Generation (Cycles 154-158, v1.75.0), Task Up-to-Date Detection & Incremental Builds (Cycles 148-152, v1.74.0), Task Aliases & Silent Mode (Cycles 144-147, v1.73.0), Documentation Site & Onboarding Experience (Cycle 141, v1.72.0), Performance Benchmarking & Competitive Analysis (Cycle 139, no release), Migration Tool Enhancement (Cycle 138, v1.71.0), Real-Time Task Output Filtering & Grep (Cycle 131, v1.70.0), Task Name Abbreviation & Fuzzy Matching (Cycle 124, v1.69.0), Shell Integration & Developer Ergonomics (Cycle 114, v1.68.0), Advanced Task Composition & Mixins (Cycle 113, v1.67.0), Enhanced Task Retry & Error Recovery (Cycle 109, v1.66.0), Sailor v1.37.0 Migration (Cycle 108, v1.65.0), Enhanced Task Discovery & Search (Cycle 107, v1.64.0), Workspace-Level Task Inheritance (Cycle 106, v1.63.0), Task Parallel Execution Groups (Cycle 103, v1.62.0), Sailor v1.35.0-v1.36.0 Migration (Cycle 101, v1.68.1), CLI Command Unit Test Coverage Enhancement (Cycle 99), Task Templates & Scaffolding (Cycle 94, v1.61.0), CI/CD Integration Templates (Cycle 93), Sailor v1.32.0-v1.34.0 Batch Migration (Cycle 88), Resource Affinity & NUMA Enhancements (Cycle 87), Interactive Task Picker UX (Cycle 82), TUI Performance Optimization (Cycle 79), Sailor v1.31.0 Migration (Cycle 77), Error Message UX Enhancement (Cycle 76), Sailor v1.26.0-v1.30.2 Batch Migration (Cycle 75)
- **DONE**: zuda WorkStealingDeque Migration (Cycle 228, no release - WONTFIX), Test Infrastructure & Quality Enhancements (v1.60.0), Workflow Matrix Execution (v1.59.0), Task Fuzzy Search & Enhanced Discovery (no release), NUMA Memory Information (no release), Graph Format Enhancements (no release), Interactive Workflow Visualizer (v1.58.0), Configuration Validation Enhancements (v1.58.0), Task Estimation & Time Tracking (v1.58.0), TOML Parser Enhancement (no release), Interactive Task Builder TUI (no release), Enhanced Performance Monitoring (no release), Phase 13C v1.0 Release Preparation (v1.57.0), Phase 13A Documentation Review (no release), Phase 12C Benchmark Dashboard (no release), Phase 13B Migration Tools (no release), Sailor v1.21.0 & v1.22.0 Migration (no release), Windows Platform Enhancements (v1.56.0), Enhanced Configuration System (v1.55.0), TUI Mouse Interaction Enhancements (v1.54.0), Platform-Specific Resource Monitoring (v1.53.0), Output Enhancement & Pager Integration (v1.52.0), Sailor v1.19.0 & v1.20.0 Migration (v1.51.0), Cross-Platform Path Handling Audit (v1.50.0), Task Output Streaming Improvements (v1.49.0), Shell Integration Enhancements (v1.48.0), zuda Glob Migration, zuda Levenshtein Migration

---

## Active Milestones

> **Note**: Version numbers below are **historical references only**. Actual release version is determined at release time as `build.zig.zon` current version + 1. See "Milestone Establishment Process" for rules.

> **ALL PHASE 1-13 MILESTONES COMPLETE** — v1.57.0 marks feature-complete v1.0-equivalent status. Remaining milestones are post-v1.0 enhancements.


### Code Quality & Documentation Polish

Polish code quality, improve documentation, and enhance user experience with small but impactful improvements. Focus on developer experience, code maintainability, and documentation accuracy. This milestone addresses technical debt and ensures the codebase is ready for long-term maintenance. Includes:
- **Code comment accuracy**: Review and update comments that reference old version numbers or outdated behavior
- **Error message clarity**: Review all user-facing error messages for consistency and helpfulness
- **Documentation updates**: Update README and guides to reflect current feature set and version (v1.82.0)
- **Example improvements**: Ensure all examples in `examples/` are tested and up-to-date
- **Test documentation**: Add test docstrings to clarify what each test validates
- **Performance annotations**: Add performance characteristics comments to hot-path functions
- **Memory safety audit**: Review allocator usage patterns and ensure consistent error handling
- **CLI help text**: Ensure all commands have consistent, helpful --help output
**Status: ACTIVE** — Started 2026-05-17 (Cycle 243 FEATURE). This is a continuous improvement milestone with no fixed end date. Work items completed incrementally as time permits.

### Enhanced Environment Variable Management

Improve environment variable handling with .env file support, variable interpolation, and flexible merging strategies. Currently tasks can only specify env vars in TOML, requiring duplication for shared environments. This milestone adds .env file loading, variable expansion, and inheritance patterns similar to docker-compose and direnv. Includes:
- **.env file loading**: `env_file = ".env"` or `env_file = [".env.local", ".env"]` — load env vars from files
- **Variable interpolation**: `env = { PATH = "$PATH:/custom/bin", API_URL = "${BASE_URL}/api" }` — expand existing vars
- **Priority order**: CLI args > task env > workspace env > env_file > system env (clear precedence)
- **Multiple env files**: Load multiple files with override semantics (later files override earlier)
- **Conditional env vars**: `env_if = { "CI" = { CACHE_DIR = "/ci-cache" } }` — env vars based on conditions
- **Env var validation**: Required vars with `required_env = ["DATABASE_URL", "API_KEY"]` fail if missing
- **List integration**: `zr list --show-env` displays effective environment for each task
- **Dry-run preview**: `zr run --dry-run --show-env` shows resolved env vars before execution
- **Workspace inheritance**: Child tasks inherit parent workspace env_file and merge env vars
- **Documentation**: Comprehensive guide at docs/guides/environment-management.md with .env patterns, merging rules, security best practices
**Status: DONE** — Completed 2026-04-26 (Cycle 171). Implementation: ~268 LOC (env_file schema in types.zig, .env file loader in config/env_loader.zig with parseEnvFile(), variable interpolation engine interpolateEnvValue() with ${VAR}, $VAR, $$, recursive expansion, circular reference detection, scheduler.zig integration with loadAndMergeEnvFiles(), CLI --show-env flag in main.zig/run.zig/list.zig). Testing: ~495 LOC (27 integration tests covering .env loading, multiple files, priority order, workspace inheritance, interpolation patterns, circular refs, undefined vars, cross-file expansion). Documentation: ~650 LOC comprehensive guide at docs/guides/environment-management.md with .env format, interpolation syntax, priority system, real-world examples, best practices, troubleshooting, comparison with dotenv/docker-compose/make, migration guides. All tests passing (1483 unit tests). Total: ~1413 LOC across 5 commits (Cycles 168-171). Ready for v1.78.0 release.

### Task Documentation & Rich Help System

Add comprehensive task documentation capabilities with rich help formatting, examples, and metadata. Currently tasks have minimal description field, making complex tasks hard to understand. This milestone adds structured documentation with examples, parameters, outputs, and formatted help similar to CLI tools like docker and git. Includes:
- **Rich descriptions**: `description = { short = "Build project", long = """Builds the project...""" }` — short + detailed text
- **Task examples**: `examples = ["zr run build", "zr run build --release"]` — usage examples in help
- **Parameter docs**: Enhanced param descriptions with types, constraints, default values in help output
- **Output documentation**: `outputs = { "dist/" = "Compiled binaries", "logs/" = "Build logs" }` — what task produces
- **Related tasks**: `see_also = ["test", "deploy"]` — cross-reference related tasks
- **Help command**: `zr help <task>` shows formatted help with all metadata (description, params, examples, deps, outputs)
- **Man page generation**: `zr man <task>` generates man page format for task documentation
- **Markdown export**: `zr docs --markdown` exports all task docs to markdown for project wikis
- **List enhancements**: `zr list --verbose` shows short descriptions, `zr list --format detailed` shows full metadata
- **Interactive help**: `zr irun` shows task help when selecting tasks in picker
- **Documentation validation**: Warn on missing descriptions for public tasks, suggest improvements
**Status: DONE** — Completed 2026-04-28 (Cycles 172-174, 177, 179). Implementation: ~254 LOC (schema changes in types.zig with TaskDescription union, parser.zig for parsing description.short/long, examples array, outputs table, see_also array, list.zig --verbose flag integration). Testing: ~2084 LOC (63 integration tests: 29 tests in task_documentation_test.zig covering help command, list verbose, edge cases, feature integration; 34 tests in task_documentation_parser_test.zig covering rich description parsing, examples, outputs, see_also, combined parsing, error cases). Documentation: ~704 LOC comprehensive guide at docs/guides/task-documentation.md with rich descriptions, examples, parameter docs, output documentation, see_also, help command, man page generation, markdown export, real-world examples, best practices, comparison with make/just/task, migration guides, troubleshooting. All tests passing (1483 unit tests). Total: ~3042 LOC across 5 commits (Cycles 172-177, 179). Ready for v1.79.0 release.

### Task Output Artifacts & Persistence

Add artifact management to save, retrieve, and share task outputs across runs and environments. Currently task outputs are ephemeral (only visible in history), making it hard to preserve build artifacts, logs, or test reports. This milestone adds artifact storage, retrieval, and metadata tracking similar to GitHub Actions artifacts and CI systems. Includes:
- **Artifact declaration**: `artifacts = ["dist/*.wasm", "coverage/*.html", "logs/*.log"]` — files to preserve
- **Automatic collection**: After task success, collect matching artifacts and store with metadata
- **Artifact storage**: Local `.zr/artifacts/<task>/<timestamp>/` directory structure with manifest
- **Artifact retrieval**: `zr artifacts get <task>` lists artifacts, `zr artifacts get <task> --latest` downloads most recent
- **Artifact metadata**: Store timestamp, task params, git commit, exit code, duration in manifest.json
- **Expiration policy**: `artifact_retention = "7d"` or `artifact_retention = { count = 10 }` — auto-cleanup old artifacts
- **List integration**: `zr list --show-artifacts` displays tasks with preserved artifacts and counts
- **Artifact cleanup**: `zr artifacts clean --older-than 30d` or `zr artifacts clean --task build` manual cleanup
- **Compression**: Automatically compress artifacts with gzip for space efficiency (configurable)
- **Remote sync**: `artifact_remote = "s3://bucket/artifacts"` optional remote storage integration (future: cloud backends)
- **CI/CD integration**: Artifacts automatically tagged with CI environment metadata (GitHub Actions, GitLab CI, etc.)
- **Documentation**: Comprehensive guide at docs/guides/artifact-management.md with CI patterns, retention strategies, storage formats
**Status: DONE** — Completed 2026-04-30 (Cycles 182, 184, 186). Implementation: ~560 LOC (Phase 1: schema + CLI skeleton ~140 LOC in types.zig, artifacts.zig CLI; Phase 2: collection logic ~220 LOC in artifacts.zig with collectArtifacts(), manifest generation, scheduler integration; Phase 3: compression + retention ~200 LOC with compressFile() using gzip CLI, enforceRetentionPolicy() for time_based/count_based, enhanced CLI get/clean). Testing: ~37 integration tests (33 baseline + 4 compression/retention tests). All unit tests passing (1487/1495). Total: ~560 LOC implementation across 3 phases. Ready for v1.80.0 release.

### Task Up-to-Date Detection & Incremental Builds

Enable smart task execution by skipping tasks whose outputs are already up-to-date, similar to make's file timestamp checking and task's sources/generates pattern. Currently zr always re-runs tasks regardless of whether inputs have changed or outputs exist. This milestone adds incremental build support to dramatically speed up repeated task executions. Includes:
- **Sources pattern**: `sources = ["src/**/*.ts", "package.json"]` — files that affect task output
- **Generates pattern**: `generates = ["dist/**/*.js", "dist/bundle.min.js"]` — files created by task
- **Up-to-date logic**: Skip task if all generates exist and are newer than all sources (mtime comparison)
- **Manual invalidation**: `zr run <task> --force` always runs, ignoring up-to-date check
- **Cache integration**: Up-to-date detection works with content-based caching (hash vs mtime)
- **Watch mode optimization**: File watcher uses sources pattern to filter relevant changes
- **Status display**: `zr list --status` shows task states (up-to-date, stale, never-run)
- **Dry-run preview**: `zr run --dry-run` shows which tasks would run vs skip
- **Dependencies**: Tasks with up-to-date dependencies skip if all deps are up-to-date and outputs exist
- **Glob expansion**: Support globs with `**`, `*`, `?` for flexible source/generate patterns
**Status: DONE** — Completed 2026-04-22 (Cycles 148-152). Implementation: ~448 LOC (schema changes in types.zig/parser.zig, uptodate.zig checker module with mtime comparison and glob expansion, scheduler.zig integration with force_run flag, CLI --force/--status flags in main.zig/run.zig/list.zig, dependency propagation with executed_tasks HashMap). Testing: ~666 LOC (12 integration tests covering mtime comparison, glob patterns, --force flag, dependency propagation, backward compatibility). Documentation: ~522 LOC comprehensive guide at docs/guides/incremental-builds.md with usage examples, glob patterns, dependency propagation, migration from make/task/just, best practices, troubleshooting. All tests passing (1434 unit tests). Ready for v1.74.0 release.

### Task Parameters & Dynamic Task Generation

Add parameterized tasks with default values to enable flexible, reusable task definitions similar to just's recipe parameters. Currently tasks are static — to deploy to multiple environments you must copy-paste the task definition. This milestone enables tasks that accept arguments at runtime, reducing duplication and improving maintainability. Includes:
- **Task parameters**: `params = [{ name = "env", default = "dev", description = "Target environment" }]` in task definition
- **Parameter interpolation**: Use `{{env}}` in cmd/env fields, resolved at runtime
- **CLI invocation**: `zr run deploy env=prod` or `zr run deploy --param env=prod` (both syntaxes supported)
- **Validation**: Type checking (string, bool, number), required params without defaults fail if not provided
- **Multiple params**: `params = [{ name = "env" }, { name = "region", default = "us-east-1" }]` — positional or named args
- **Help integration**: `zr run deploy --help` shows available params, defaults, descriptions
- **List display**: `zr list` shows tasks with params as `deploy(env="dev", region="us-east-1")`
- **History tracking**: Execution history records actual param values used
- **Workflow integration**: Workflows can pass params to tasks: `tasks = [{ name = "deploy", params = { env = "staging" } }]`
- **Interactive mode**: `zr irun` prompts for required params if not provided
- **Task dependencies**: Dependent tasks inherit params from parent or use own defaults
**Status: DONE** — Completed 2026-04-23 (Cycles 154-158). Implementation: ~368 LOC (schema changes in types.zig/parser.zig, CLI param parsing in main.zig with 3 syntaxes, parameter resolution in run.zig, interpolateParams() helper in scheduler.zig threading runtime_params through execution chain). Testing: ~776 LOC (22 integration tests covering basic params, required params, multiple params, CLI syntaxes, type validation, {{param}} interpolation, help integration, list display, history tracking, workflow integration, error handling, backward compatibility). Documentation: ~620 LOC comprehensive guide at docs/guides/parameterized-tasks.md with usage examples, CLI syntaxes, env var interpolation, comparison with just/make/Task, migration guides, real-world examples, best practices, troubleshooting. All unit tests passing (1434/1442). Total: ~1764 LOC across 4 commits. Ready for v1.75.0 release.

### Task Aliases & Silent Mode

Add multiple names for tasks (aliases) and output suppression (silent mode) to improve CLI ergonomics and reduce noise from well-behaving tasks. Currently each task has one name, and all output is always shown. Aliases enable intuitive shortcuts (e.g., `b` for `build`, `t` for `test`), while silent mode lets you focus on errors by hiding successful task output. Includes:
- ✅ **Task aliases**: `aliases = ["b", "compile"]` field in task definition — all names work identically (Cycle 144)
- ✅ **Alias display**: `zr list` shows aliases: `build [aliases: b, compile]` (Cycle 144)
- ✅ **Alias conflicts**: Error if alias collides with existing task name or other aliases (Cycle 147)
- ✅ **Silent mode**: `silent = true` in task — suppress stdout/stderr unless task fails (Cycle 144)
- ✅ **Global silent flag**: `zr run --silent <task>` or `zr run -s <task>` overrides task config (Cycle 146)
- ✅ **Error passthrough**: Silent tasks show full output on failure for debugging (Cycle 144)
- ✅ **Integration tests**: 12 comprehensive tests for aliases and silent mode (Cycle 145, 147)
- ✅ **Documentation**: 350+ LOC comprehensive docs in configuration.md (Cycle 147)
**Status: DONE** — Completed 2026-04-21 (Cycles 144-147). Implementation spans parser.zig (aliases parsing), types.zig (schema), run.zig (alias resolution), list.zig (display), scheduler.zig (silent mode), loader.zig (conflict detection), main.zig (--silent flag). Total: ~450 LOC implementation, ~310 LOC tests (12 integration tests + 3 unit tests), ~350 LOC docs. All tests passing (1430 unit tests). Ready for v1.73.0 release.

### Enhanced Task Retry & Error Recovery

Improve task execution resilience with sophisticated retry mechanisms and error recovery strategies. Currently tasks fail immediately on error with basic retry count. This milestone adds exponential backoff, conditional retry, failure hooks, and enhanced error context. Includes:
- ✅ **Exponential backoff**: `retry_backoff_multiplier` with configurable multipliers (1.0=linear, 2.0=exponential, 1.5=moderate)
- ✅ **Conditional retry**: `retry_on_codes` (exit codes), `retry_on_patterns` (stdout/stderr patterns) — retry only on specific failure types
- ✅ **Failure hooks**: `hooks = [{ point = "failure", cmd = "..." }]` runs after all retries exhausted
- ✅ **Jitter**: `retry_jitter = true` adds ±25% random variance to prevent thundering herd
- ✅ **Max backoff ceiling**: `max_backoff_ms` caps exponential growth
- ✅ **Error context preservation**: Retry count tracked in history (`retry_count` field)
- ✅ **Integration tests**: 13 comprehensive tests (970-982) covering backoff timing, conditional retry, failure hooks
- ✅ **Documentation**: Comprehensive retry strategies section in docs/guides/configuration.md with examples and best practices
**Status: DONE** — Completed 2026-04-07 (Cycle 109). All v1.47.0 retry features were already implemented in codebase, missing only documentation and hook interaction tests. Enhanced docs with backoff strategies, conditional retry examples, jitter explanation, smart retry guidelines. Added 5 new integration tests for retry+hooks interaction. Total implementation: ~200 lines of docs, 167 lines of tests. All features backward compatible with existing `retry_backoff` boolean.

### Advanced Task Composition & Mixins

Enable task reusability through mixins and composition patterns to reduce duplication beyond workspace inheritance. Currently tasks can only inherit via workspace shared_tasks or depend on other tasks. This milestone adds mixin composition, task templates with parameters, and dynamic task generation. Includes:
- **Task mixins**: `mixins = ["common_env", "docker_auth"]` — compose multiple partial task definitions
- **Mixin definitions**: `[mixins.common_env]` section with partial task fields (env, deps, tags)
- **Template parameters**: `[task_templates.deploy]` with `{{target}}` placeholders, instantiate via `zr add task --from-template deploy --param target=prod`
- **Field merging semantics**: env merges (child overrides parent), deps concatenates, tags unions, command overrides
- **Nested mixins**: Mixins can include other mixins (DAG resolution, cycle detection)
- **Dynamic task generation**: `zr generate tasks --from-template matrix --params targets.json` creates N tasks from template × parameters
- ✅ **Integration tests**: 20 comprehensive tests (8000-8019) covering mixin resolution, nested mixins, merge semantics, cycle detection
- ✅ **Documentation**: Comprehensive 315-line "Mixins" section in docs/guides/configuration.md with real-world examples
**Status: DONE** — Completed 2026-04-07 (Cycle 113). Implementation already complete in commit 7417a88 (2594 lines across 6 files). Added comprehensive documentation with before/after examples, field merging semantics table, nested mixin patterns, 4 real-world use cases (CI pipelines, multi-environment, language tooling, resource constraints), benefits, comparison with templates/workspace, error handling. All 20 integration tests passing. Release v1.67.0.

### Shell Integration & Developer Ergonomics

Improve command-line ergonomics with enhanced shell integration, smart defaults, and workflow shortcuts. Currently users type full commands for common operations. This milestone adds shell aliases, context-aware defaults, and quick navigation. Includes:
- ✅ **Smart task running**: `zr` (no args) → interactive picker if multiple tasks, auto-run if single task, or run `default` task if defined
- ✅ **Recent task shortcuts**: `zr !!` → re-run last task, `zr !-2` → run 2nd-to-last task from history
- ✅ **Workflow quick-run**: `zr w/<workflow>` shorthand for `zr workflow <workflow>`
- ✅ **Integration tests**: 12 comprehensive tests covering smart defaults, history shortcuts, workflow shorthand, flag combinations
- ✅ **Documentation**: Complete shell integration guide at docs/guides/shell-setup.md with bash/zsh/fish examples, tips, and troubleshooting
- **Note**: Task name abbreviation, shell function generation, and `eval $(zr env --export)` deferred to future milestones (nice-to-have features; core UX improvements delivered)
**Status: DONE** — Completed 2026-04-10 (Cycle 114). Implemented 3 core productivity features: (1) Smart no-args behavior with default task/single task/picker logic, (2) History shortcuts !! and !-N for quick re-runs, (3) Workflow shorthand w/<name> for concise workflow execution. All features respect global flags (--profile, --dry-run, --jobs). Integration tests validate all scenarios including edge cases. Documentation provides complete shell setup guide with examples for all major shells. Total implementation: ~140 lines of logic, 252 lines of tests, 398 lines of docs. Zero breaking changes.

### Sailor v1.38.0 & v1.38.1 Migration

Dependency update: sailor v1.37.0 → v1.38.1 (batch migration). v1.38.0 introduces migration tooling for upcoming v2.0.0, v1.38.1 fixes migration script bugs. Both are maintenance releases with zero breaking changes. Includes:
- **Update dependency**: Update build.zig.zon from v1.37.0 → v1.38.1
- **Deprecation warnings**: New deprecation warnings for Rect.new(), Block.withTitle() in preparation for v2.0.0
- **Migration tooling**: Migration script infrastructure (consumer-facing, not required for zr codebase)
- **Build verification**: Ensure all unit tests pass (expected: 1408/1416 passing)
- **Integration tests**: Verify all existing tests pass without modification (backward compatible)
- **Issue closure**: Close GitHub issues #52 (v1.38.0), #53 (v1.38.1)
**Status: DONE** — Completed 2026-04-11 (Cycle 118). Updated build.zig.zon from v1.37.0 to v1.38.1 with correct hash. All 1408 unit tests passing (8 skipped, 0 failed). Zero code changes required - backward compatible maintenance release. Closed issues #52, #53. Release v1.68.1.

### Task Name Abbreviation & Fuzzy Matching

Reduce typing friction with intelligent task name abbreviation and fuzzy matching. Currently users must type complete task names (`zr build-docker-production`) even when unambiguous. This milestone adds prefix matching, unique prefix resolution, and fuzzy fallback for typos. Includes:
- ✅ **Prefix matching**: `zr run b` matches `build` if unique, shows ambiguity error if multiple matches (build, bench, backup)
- ✅ **Unique prefix resolution**: `zr run dep` → `deploy` if only task starting with "dep", resolves automatically
- ✅ **Fuzzy fallback**: `zr run tset` suggests "test" via Levenshtein distance (reuses existing v1.0 implementation)
- ✅ **Abbreviation hints**: `zr list` displays minimum unique prefix for each task (e.g., [b] → build, [tea] → teardown)
- ✅ **Exact match precedence**: Exact task name matches always take priority over prefix matches
- ✅ **Integration tests**: 8 comprehensive tests covering unique match, ambiguous prefix, fuzzy suggestions, exact precedence, dependencies
- **Note**: Workspace-aware prefixes (`member:prefix`) deferred to future milestone (not required for core functionality)
**Status: DONE** — Completed 2026-04-14 (Cycle 124). Implemented prefix matching via `findTasksByPrefix()` in src/cli/run.zig with exact match priority, unique prefix auto-resolution, and ambiguity detection. Added `calculateUniquePrefix()` for displaying abbreviation hints in `zr list` output. All features integrated into existing fuzzy matching system (Levenshtein fallback). Created 8 integration tests validating all scenarios. Fixed use-after-free bug in empty slice allocation. Total implementation: ~150 LOC logic (run.zig + list.zig), ~250 LOC tests (task_abbreviation_test.zig). Zero breaking changes - feature is additive only.

### Task Environment Export & Shell Functions

Enable seamless shell environment integration with task-defined variables and generated shell functions. Currently task environment variables only apply within task execution, not to parent shell. This milestone adds `zr env --export` for sourcing and automatic shell function generation. Includes:
- ✅ **Environment export**: `eval $(zr env --task build --export)` loads task env vars into current shell
- ✅ **Task-specific export**: `zr env --task <name> --export` loads only specified task's environment
- ✅ **Shell auto-detection**: Detects shell from SHELL env var, supports explicit shell type (bash/zsh/fish)
- ✅ **Shell function generation**: `eval $(zr env --functions)` creates `zr_build()`, `zr_test()` functions
- ✅ **Special character escaping**: Properly escapes $, ", and other special characters in all shells
- ✅ **Shell-specific output formats**: `export FOO=bar` (bash/zsh), `set -x FOO bar` (fish)
- ✅ **Integration tests**: 11 comprehensive tests covering all shell formats, auto-detection, error handling
- ✅ **Documentation**: Added comprehensive "Environment Loading" section to docs/guides/shell-setup.md (~120 lines)
**Status: DONE** — Completed 2026-04-15 (Cycle 127). Implemented `--export` and `--functions` flags in src/cli/env.zig with shell-specific formatters, auto-detection from SHELL env var, and proper escaping. Created 11 integration tests validating all scenarios (bash/zsh/fish formats, special characters, error cases). Enhanced documentation with detailed examples, usage patterns, and best practices. Total implementation: ~240 LOC logic (env.zig), ~180 LOC tests (env_export_test.zig), ~130 LOC docs. Zero breaking changes - feature is additive only.

### Real-Time Task Output Filtering & Grep

Add live filtering and pattern matching for task output streams, enabling quick debugging and log analysis without post-processing. Currently users must pipe task output to `grep` manually or review full logs. This milestone adds built-in filtering with highlighting and tail-follow. Includes:
- ✅ **CLI flags**: `--grep`, `--grep-v`, `--highlight`, `-C/--context` added to main.zig
- ✅ **Filter module**: LineFilter class with pattern parsing, substring matching, context buffer (src/output/filter.zig, 375 LOC)
- ✅ **OutputCapture integration**: Filter applied in writeLine() with multi-line context buffer flush support
- ✅ **Scheduler integration**: filter_options passed from SchedulerConfig to OutputCapture, auto-enables buffering when filtering
- ✅ **Pattern alternatives**: Pipe-separated OR logic (`error|warning|fatal`)
- ✅ **Highlight mode**: ANSI bold yellow color injection for matched patterns
- ✅ **Context lines**: FIFO context buffer for grep -C style context display
- ✅ **Color preservation**: ANSI escape sequences preserved in filtered output
- ✅ **Integration tests**: 12 comprehensive tests (9500-9511) covering all filter combinations, edge cases, multi-task scenarios
- ✅ **Documentation**: Comprehensive "Output Filtering" section in docs/guides/commands.md with usage examples, pattern syntax, performance notes
**Status: DONE** — Completed 2026-04-17 (Cycle 131). Full implementation across 4 cycles (128-131): CLI flags, filter module with 5 unit tests, OutputCapture integration, scheduler wiring, 12 integration tests, comprehensive documentation. Total implementation: ~450 LOC filter module + integration, 313 LOC tests, ~150 LOC docs. Substring matching MVP (not regex) with pipe-separated alternatives. All features backward compatible. Release v1.70.0.

### Performance Benchmarking & Competitive Analysis

Establish quantitative performance baseline and competitive positioning through comprehensive benchmarking. Currently zr lacks formal performance comparison against make/just/task/npm-scripts. This milestone creates reproducible benchmarks, identifies bottlenecks, and validates performance claims. Includes:
- ✅ **Benchmark suite**: 6 representative scenarios (cold start, hot run, parallel graph, cache hit, large config, watch mode)
- ✅ **Competitor comparison**: Head-to-head timing vs make 4.4+, just 1.25+, task 3.35+, npm scripts, bun run
- ⏸️ **Real-world projects**: Test on actual open-source projects (Linux kernel Makefile, Turborepo demo, nx workspace) — deferred to future milestone
- ⏸️ **Metrics dashboard**: HTML report with charts (startup latency, throughput, memory usage, cache effectiveness) — deferred to future milestone
- ⏸️ **Performance regression tests**: CI integration to detect slowdowns (fail if >10% slower than baseline) — deferred to future milestone
- ⏸️ **Optimization opportunities**: Profile zr itself (flamegraph, allocation tracing) to identify hot paths — deferred to future milestone
- ✅ **Documentation**: Add benchmarks/ section to docs with methodology, results, and competitive positioning
**Status: DONE** — Completed 2026-04-19 (Cycle 139). Implemented 6 comprehensive benchmark scenarios: (01) cold start, (02) parallel graph, (03) hot run (10x repeated execution), (04) cache hit (content-based caching), (05) large config (500 tasks), (06) watch mode (file change latency). All scenarios compare zr vs make/just/task/npm with CSV output. Updated benchmarks/README.md with detailed scenario descriptions, methodology, and interpretation guide. Updated RESULTS.md with 6-scenario suite overview. Real-world projects, HTML dashboard, CI regression tests, and profiling deferred to future milestone (core scenarios complete). Total implementation: ~600 LOC benchmark scripts, ~300 LOC documentation.

### Migration Tool Enhancement

Expand `zr init` to auto-convert configurations from popular task runners and build tools. Currently `zr init --detect` handles basic project detection but doesn't import existing task definitions. This milestone adds migration from package.json scripts, Makefiles, Justfiles, and Taskfiles with semantic analysis. Includes:
- ✅ **package.json migration**: `zr init --from npm` parses scripts section, converts run-s/run-p patterns to zr deps
- ✅ **Makefile migration**: `zr init --from make` extracts targets, dependencies (.PHONY), variables, pattern rules
- ✅ **Justfile migration**: `zr init --from just` converts recipes, dependencies, variables (1:1 mapping)
- ✅ **Taskfile migration**: `zr init --from task` converts tasks.yml to zr.toml with deps/cmds/vars
- ✅ **Semantic analysis**: Detect parallel patterns (&&, run-p), watch patterns, common env vars, infer task tags
- ⏸️ **Interactive review**: Show proposed zr.toml, allow user edits before writing (deferred to future milestone)
- ✅ **Dry-run mode**: `--dry-run` flag to preview conversion without creating files
- ✅ **Migration reports**: Summary of converted tasks, warnings for unsupported features, manual steps required
- ✅ **Integration tests**: Test conversion accuracy on real-world configs from popular GitHub repos (8 tests: 10100-10107)
- ✅ **Documentation**: Add "Migrating from X" guides to docs/guides/ with before/after examples
**Status: DONE** — Completed 2026-04-18 (Cycle 138). Full implementation across 3 cycles (133, 136, 138): npm migration parser (350 LOC), dry-run mode, migration reporting system (150 LOC), 8 integration tests (10100-10107), comprehensive documentation (~260 LOC in docs/guides/migration.md). Interactive review mode deferred (dry-run provides core preview functionality). All parsers (npm/make/just/task) with semantic analysis complete. Total implementation: ~580 LOC across npm.zig, report.zig, init.zig; ~410 LOC tests; ~310 LOC docs. Release v1.71.0.

### Documentation Site & Onboarding Experience

Polish documentation and create comprehensive getting-started experience for new users. Currently docs are scattered across README, docs/guides/, and PRD. This milestone creates a cohesive documentation site with interactive examples and smooth onboarding flow. Includes:
- ✅ **Documentation site structure**: docs/README.md as landing page, organized sections (Installation, Quick Start, Configuration, Commands, Advanced)
- ✅ **Interactive quick start**: getting-started.md already exists with step-by-step tutorial
- ✅ **Command reference**: Complete command-reference.md with all 50+ commands, usage examples, options
- ✅ **Configuration reference**: Complete config-reference.md with field-by-field schema documentation
- ✅ **Migration guides**: migration.md already complete (from make/just/task/npm-scripts)
- ✅ **Best practices**: best-practices.md with patterns for large projects, monorepos, CI/CD, caching
- ⏸️ **Video walkthrough**: Deferred to future milestone (documentation complete)
- ⏸️ **Example projects**: Deferred to future milestone (examples/ directory exists)
- ✅ **Troubleshooting FAQ**: troubleshooting.md with common errors, solutions, diagnostic commands
- ⏸️ **Site generation**: Deferred to future milestone (mdBook or similar static site generator)
**Status: DONE** — Completed 2026-04-19 (Cycle 141). Created 6 comprehensive documentation files: (1) docs/README.md as documentation hub with clear navigation structure, (2) command-reference.md with all CLI commands, usage examples, exit codes, (3) config-reference.md with complete zr.toml schema reference, (4) best-practices.md with production-tested patterns for task organization, performance, monorepos, CI/CD, caching, error handling, security, (5) troubleshooting.md with installation, configuration, execution, performance, cache, workspace, toolchain, CI/CD debugging + comprehensive FAQ. Total implementation: ~153 LOC landing page, ~1744 LOC command reference, ~1450 LOC config reference, ~1800 LOC best practices, ~2300 LOC troubleshooting = ~7447 LOC documentation. Existing guides (getting-started.md, migration.md, shell-setup.md, configuration.md) already provided core content. Video walkthrough, example projects, and static site generation deferred to future milestone (core documentation complete).

### Sailor v1.37.0 Migration

Dependency update: sailor v1.36.0 → v1.37.0. v2.0.0 API bridge release enabling smooth transition to sailor v2.0 with backward compatibility. Includes:
- ✅ **Deprecation warning system**: Compile-time warnings for deprecated v1.x APIs to guide v2.0.0 migration
- ✅ **Buffer.set() API**: Renamed setChar() → set() for consistency (both APIs available)
- ✅ **Style inference helpers**: withForeground/Background/Colors method chaining for cleaner style composition
- ✅ **Widget lifecycle standardization**: Consistent init/deinit patterns across all widgets (Block.init() → Block{})
- ✅ **Migration guide**: docs/v1-to-v2-migration.md in sailor repo
- ✅ **Update dependency**: Updated build.zig.zon to v1.37.0
- ✅ **Build verification**: All 1408 unit tests passing (8 skipped, 0 failed)
- ✅ **Code compatibility check**: Fixed 6 Block.init() call sites across analytics_tui, graph_tui, tui_runner
- ✅ **Integration tests**: All existing tests pass without modification (backward compatible)
**Status: DONE** — Completed 2026-04-07 (Cycle 108). v1.37.0 provides v1.x/v2.0 API bridge with zero breaking changes. Fixed stateless widget API changes (Block.init() → Block{}). All tests passing. This release prepares codebase for eventual v2.0.0 migration while maintaining full backward compatibility. Related: GitHub issue #51.

### Task Parallel Execution Groups

Extend parallel execution control with task-level concurrency groups and resource pools. Currently all tasks share a single global worker pool (`max_workers`). This milestone adds fine-grained control for heterogeneous workloads. Includes:
- ✅ **Concurrency groups**: Define named groups (`[concurrency_groups.gpu]`, `[concurrency_groups.memory_intensive]`) with separate worker limits
- ✅ **Task-level assignment**: `concurrency_group = "gpu"` in task config
- ✅ **Dynamic resource allocation**: Worker pool adjusts based on active groups
- ✅ **Mixed workloads**: Some tasks use `gpu` group (limit 2), others use `network` group (limit 10), rest use default pool
- ✅ **Integration tests**: Verify concurrent execution respects group limits (20 tests covering single/multi-group, overflow, default fallback)
- ✅ **Documentation**: Add concurrency groups section to docs/guides/configuration.md with examples
**Status: DONE** — Completed 2026-04-06 (Cycle 103). All features implemented, 20 integration tests (5000-5019), comprehensive documentation. Released in v1.62.0.

### Workspace-Level Task Inheritance

Enable task definition sharing across workspace members to reduce duplication in monorepos. Currently each member must define identical tasks (lint, test, build). This milestone implements inheritance with override capabilities. Includes:
- ✅ **Workspace-level tasks**: Define common tasks in root `zr.toml` under `[workspace.shared_tasks.NAME]`
- ✅ **TOML parsing**: Parse `[workspace.shared_tasks.NAME]` sections into Workspace.shared_tasks HashMap
- ✅ **Inheritance API**: `inheritWorkspaceSharedTasks()` function to merge shared tasks into member config
- ✅ **Override semantics**: Member task with same name overrides workspace task (complete replacement, not merge)
- ✅ **Visibility**: `zr list` in member shows both inherited and local tasks with `(inherited)` marker
- ✅ **Dependency resolution**: Inherited tasks can depend on member-local tasks (via standard DAG)
- ✅ **Integration tests**: 15 tests (6000-6014) covering inheritance, override, cross-dependencies, validation
- ✅ **CLI Integration**: Wired up `inheritWorkspaceSharedTasks()` in workspace.zig (3 call sites: cmdWorkspaceRun, both execution paths, cmdWorkspaceRunFiltered)
- ✅ **Documentation**: Added comprehensive "Workspace-Level Task Inheritance" section to docs/guides/configuration.md with examples, override semantics, usage patterns
**Status: DONE** (Cycle 106) — Complete implementation. All features working: data structures, TOML parsing, inheritance logic, display markers, CLI integration, comprehensive tests (15 integration tests), documentation. Members automatically inherit workspace shared tasks, overrides work correctly, `(inherited)` marker visible in `zr list`.

### Enhanced Task Discovery & Search

Improve task discoverability with full-text search, smart filters, and recent task tracking. Builds on existing fuzzy search (Cycle 59) with richer querying. Includes:
- ✅ **Full-text search**: `zr list --search="docker build"` searches task names, descriptions, commands
- ✅ **Tag-based filters**: `zr list --tags="ci,lint"` shows only tasks with ALL specified tags (AND logic, changed from ANY)
- ✅ **Exclude filters**: `zr list --exclude-tags="slow"` hides tasks with ANY of these tags
- ✅ **Frequently used tasks**: `zr list --frequent[=N]` shows top N tasks by execution count from history (default 10)
- ✅ **Execution time filters**: `zr list --slow[=THRESHOLD]` shows tasks exceeding avg execution time (default 30s/30000ms)
- ✅ **Combined filters**: All filters work together with AND logic (`--tags=ci --exclude-tags=flaky --frequent=10`)
- ✅ **JSON output**: All filters work with `--json` for programmatic use
- ✅ **Integration tests**: 6 comprehensive tests (7000-7005) covering all filter combinations, empty results, combined queries
- ✅ **Documentation**: Enhanced "Task Discovery" section in docs/guides/commands.md with examples
**Status: DONE** (Cycle 107) — Complete implementation. All features working: tag AND logic, exclude-tags, full-text search (including commands), frequent/slow filters from execution history, combined filters, JSON output compatibility. 6 integration tests passing (7000-7005). Comprehensive documentation in commands.md with usage examples. Makes large projects (100+ tasks) easier to navigate with powerful query capabilities.

### Sailor v1.35.0-v1.36.0 Migration

Dependency update: sailor v1.34.0 → v1.36.0. Batch migration incorporating 2 major releases with accessibility enhancements and performance monitoring capabilities. Includes:
- ✅ **v1.35.0 - Accessibility Overhaul** (Cycle 101):
  - ARIA Attributes module with 30+ widget roles (button, checkbox, slider, table, tree)
  - AriaAttributes struct with 8 state flags
  - Builder pattern API for ARIA attributes
  - Screen reader announcement generation with live region support
  - Focus Trap implementation for modal/popup focus containment
  - Configurable tab cycling behavior
  - FocusTrapStack for nested dialog support
  - Standard keyboard shortcuts (Ctrl+C/X/V, undo/redo, select-all)
  - Accessibility demo showcasing all features
  - +63 new tests (3,022 total, all passing)
  - Zero memory leaks
  - Cross-platform verification (6 targets: Linux/macOS/Windows on x86_64/ARM64)
- ✅ **v1.36.0 - Performance Monitoring System** (Cycle 101):
  - render_metrics.zig: Widget rendering metrics with percentile analysis (min/max/avg/p50/p95/p99)
  - memory_metrics.zig: Allocation tracking per widget (peak and current bytes)
  - event_metrics.zig: Event processing latency and queue depth
  - MetricsDashboard widget with 3 layout modes (vertical/horizontal/grid)
  - Auto-formatted time and memory units
  - Color-coded performance warnings (yellow: P95 >10ms, red: P99 >10ms)
  - Performance regression tests with baselines (<50μs avg, <100μs P95 for block widgets)
  - Example implementation (metrics_dashboard.zig) with realistic workloads
  - +143 new tests (3,162 total, all passing)
  - **Zero breaking changes** (fully backward compatible)
  - Establishes performance baselines ahead of v2.0.0
- ✅ **Migration** (Cycle 101):
  - Updated build.zig.zon: v1.34.0 → v1.36.0
  - All 1408 unit tests passing (8 skipped)
  - No code changes required (backward compatible)
**Status: DONE** — Completed 2026-04-06 (Cycle 101). Both releases fully integrated, all tests passing, zero breaking changes. Accessibility features enable screen reader support and WCAG compliance. Performance monitoring tools establish optimization baselines for future work.

### CLI Command Unit Test Coverage Enhancement

Strengthen test coverage by adding dedicated unit tests for CLI utilities and language providers currently covered only by integration tests. Move from 93.6% to 99.5% file coverage by adding unit tests for business logic in untested files. Includes:
- ✅ **`src/cli/estimate.zig` unit tests**: Added 7 tests for formatDuration (ms/s/min, edge cases) — Cycle 97: a74c0a5
- ✅ **`src/cli/failures.zig` unit tests**: Added 5 tests for FailuresOptions struct (defaults, custom values) — Cycle 97: 62b4736
- ✅ **Language provider unit tests**: Added unit tests for all 7 language providers (76 total tests)
  - ✅ `src/lang/bun.zig`: Added 10 tests (URL construction, binary paths, platform mapping) — Cycle 98: 0ce189d
  - ✅ `src/lang/deno.zig`: Added 10 tests (URL construction, binary paths, triple format) — Cycle 98: cec3d8a
  - ✅ `src/lang/go.zig`: Added 12 tests (module parsing, URL construction, binary paths, GOROOT env) — Cycle 97: 69f53e0
  - ✅ `src/lang/java.zig`: Added 11 tests (URL construction, binary paths, JAVA_HOME env) — Cycle 98: db4b7cc
  - ✅ `src/lang/python.zig`: Added 11 tests (URL construction, binary paths, python-build-standalone) — Cycle 98: 7b04aa6
  - ✅ `src/lang/rust.zig`: Added 12 tests (URL construction, binary paths, target triples) — Cycle 98: 76603ac
  - ✅ `src/lang/zig.zig`: Added 10 tests (URL construction, binary paths, archive formats) — Cycle 98: 3ff82f6
- ✅ **Coverage improvement**: 93.6% → 99.5% (88 new unit tests across 9 files)
- ✅ **Remaining files**: `src/cli/cd.zig`, `src/cli/registry.zig`, `src/upgrade/installer.zig` covered by integration tests (tests/registry_test.zig, tests/upgrade_test.zig)
**Status: DONE** — Completed 2026-04-06 (Cycle 99). All deliverables complete: 88 new unit tests (7 estimate, 5 failures, 76 language providers), coverage improved from 93.6% to 99.5% (179/180 files tested). Only 1 file without inline unit tests: installer.zig (covered by integration tests with comment explaining why unit tests are inappropriate for filesystem/network operations).

### CI/CD Integration Templates

Provide pre-built CI/CD templates and automation tools to streamline zr adoption in continuous integration pipelines. Make it trivial to integrate zr into GitHub Actions, GitLab CI, CircleCI, and other popular CI platforms. Includes:
- ✅ **GitHub Actions Templates**: Pre-built workflow files for common zr patterns (Cycle 91: a40c191)
  - `.github/workflows/zr-ci.yml` — Basic CI template (install zr, run tasks)
  - `.github/workflows/zr-monorepo.yml` — Monorepo template (affected detection, parallel builds, cache)
  - `.github/workflows/zr-release.yml` — Release automation template (version bump, publish, tagging)
  - Templates in `src/ci/templates/github_actions.zig`
- ✅ **GitLab CI Templates**: `.gitlab-ci.yml` templates for GitLab CI/CD (Cycle 92: f51c169)
  - Basic CI template (install, cache, parallel jobs)
  - Monorepo template (rules, changes detection, DAG dependencies)
  - Templates in `src/ci/templates/gitlab.zig`
- ✅ **CircleCI Templates**: `.circleci/config.yml` templates for CircleCI (Cycle 93: 0fd0d4f)
  - Executor configuration with zr installation
  - Parameterized jobs for monorepo support
  - Workspace persistence and tag-triggered release workflows
  - Templates in `src/ci/templates/circleci.zig`
- ✅ **`zr ci generate`**: New command to generate CI config for detected platform (Cycle 91: a40c191)
  - Auto-detect existing CI files (.github/workflows/, .gitlab-ci.yml, .circleci/)
  - Platform flag (--platform=github-actions|gitlab|circleci)
  - Template type flag (--type=basic|monorepo|release, default: basic)
  - Custom output path (--output=<path>)
- ✅ **`zr ci list`**: Command to list all available templates (Cycle 91: a40c191)
  - Shows all platforms and template types with descriptions
  - Organized by platform
- ✅ **Template Registry**: Extensible template system in `src/ci/templates/` (Cycle 91: a40c191)
  - Template struct with platform/type/name/description/content/variables
  - Variable substitution engine (${VAR} syntax with default values)
  - Registry pattern for template discovery
  - Support for 9 templates (3 platforms × 3 types)
- ✅ **Integration Tests**: Black-box tests for CI template generation (Cycles 91-93: 9079251, efce51f)
  - 24 GitHub Actions tests (basic, monorepo, release, variable substitution, error cases)
  - 11 CircleCI tests (executors, parameterized jobs, workspace persistence, tag filtering)
  - Platform auto-detection, custom output paths, success messages
  - Total: 35 CI template integration tests
- ✅ **Documentation**: Comprehensive CI command reference (Cycle 93: f809d53)
  - `docs/guides/commands.md` — CI/CD Commands section with usage examples
  - Variable substitution table
  - Platform-specific features and defaults
  - Template type descriptions
**Status: DONE** — Completed 2026-04-05 (Cycle 93). All deliverables complete: 3 platform template systems (GitHub Actions, GitLab CI, CircleCI), template registry with variable substitution, CLI commands (`zr ci generate`, `zr ci list`), 35 integration tests, comprehensive documentation.

### Task Templates & Scaffolding

Provide a library of reusable task templates for common development workflows, reducing boilerplate and accelerating zr.toml configuration. Similar to Cookiecutter or Yeoman generators, but task-focused. Includes:
- ✅ **Built-in Task Templates**: Pre-defined task patterns for common workflows (Cycle 94: 8bbdfbe)
  - `build` template: 6 templates (go-build, cargo-build, npm-build, zig-build, maven-build, make-build)
  - `test` template: 7 templates (pytest, jest, cargo-test, go-test, junit, rspec, vitest)
  - `lint` template: 6 templates (eslint, clippy, ruff, golangci-lint, checkstyle, rubocop)
  - `deploy` template: 4 templates (docker-push, k8s-deploy, terraform-apply, heroku-deploy)
  - `ci` template: 4 templates (cache-setup, artifact-upload, parallel-matrix, docker-build-ci)
  - `release` template: 4 templates (semantic-release, cargo-publish, npm-publish, docker-tag)
  - **Total**: 31 built-in templates across 6 categories
- ✅ **`zr template list [--builtin]`**: List all available templates with descriptions (Cycle 94: 8bbdfbe)
  - Categorize by type (build, test, lint, deploy, ci, release)
  - Show template names and descriptions in organized format
  - Support for both built-in and user-defined templates
- ✅ **`zr template add <name> [--builtin]`**: Template application with variable substitution (Cycle 94: 8bbdfbe)
  - `--var KEY=VALUE` flags for variable input
  - `--output <path>` for file output (default: stdout)
  - Variable substitution with ${VAR} syntax
  - Required variable validation
  - Default value application
- ✅ **`zr template show <name> [--builtin]`**: Preview template content before applying (Cycle 94: 8bbdfbe)
  - Display template TOML with variable placeholders
  - Show required variables and validation rules
  - Display default values for optional variables
  - Show complete template content with syntax
- ✅ **Template Engine**: Variable substitution engine (Cycle 94: 8bbdfbe)
  - Support ${VAR} placeholders with default values
  - src/template/engine.zig with render() function
  - Variable map management (setVar, render)
  - String substitution with error handling
- ✅ **Custom Template Support**: User-defined templates in `.zr/templates/` (Cycle 94: d0051bd)
  - src/template/loader.zig for filesystem template loading
  - Simple TOML metadata parser (name, category, description)
  - Support for local project templates (.zr/templates/)
  - Support for global templates (~/.zr/templates/)
  - Graceful error handling for malformed templates
- ✅ **Template Registry Module**: `src/template/` directory with registry pattern (Cycle 94: 8bbdfbe)
  - `registry.zig`: Template discovery, lookup, category filtering
  - `engine.zig`: Variable substitution and rendering
  - `builtin/`: 6 category modules with 31 template definitions
  - `loader.zig`: Custom template loading from filesystem
  - `types.zig`: Template/TemplateVariable/Category type definitions
- ✅ **Integration Tests**: Black-box tests for template application (Cycle 94: d0051bd)
  - tests/builtin_templates_test.zig (10 tests: 4000-4009)
  - List templates with category grouping verification
  - Show template details with variable display
  - Add templates with variable substitution (go-build, cargo-build, pytest, eslint)
  - Required variable validation (missing PROJECT_NAME error)
  - Default value handling (OUTPUT_DIR, CGO_ENABLED defaults)
  - Error cases (nonexistent template, missing variables)
**Status: DONE** — Completed 2026-04-05 (Cycle 94). All deliverables complete: 31 built-in templates (6 categories), template registry with variable substitution, CLI commands (`zr template list/show/add` with `--builtin` flag), custom template loader for `.zr/templates/`, 10 integration tests. Template system reduces configuration friction with language-specific scaffolding for common workflows.


### Resource Affinity & NUMA Enhancements

Complete the deferred CPU affinity and NUMA memory allocation features for fine-grained resource control in compute-intensive workflows. Currently parsed but not enforced — this milestone implements the actual enforcement. Includes:
- ✅ **Work-stealing CPU affinity**: Task with `cpu_affinity = [0, 1, 2, 3]` uses work-stealing across all specified cores (Cycle 83)
- ✅ **Affinity validation**: Warn if requested cores exceed available cores, fallback to available range (Cycle 83)
- ✅ **NUMA memory allocation APIs**: NumaAllocator wrapper for binding memory to NUMA nodes via mbind (Linux), best-effort on Windows/macOS (Cycle 84)
- ✅ **NUMA-aware scheduler integration**: Integrated NumaAllocator into worker threads — all task-scoped allocations bound to NUMA node when specified (Cycle 86)
- ✅ **Performance benchmarks**: 8 benchmarks comparing baseline vs NUMA vs affinity vs combined (Cycle 87: tests/numa_bench.zig)
- ✅ **Integration tests**: 12 integration tests for CPU affinity, NUMA allocation, combined usage, edge cases (Cycle 87: tests/numa_affinity_test.zig)
- ✅ **Documentation**: Comprehensive NUMA best practices, platform support, performance characteristics, anti-patterns (Cycle 87: docs/guides/configuration.md)
**Status: DONE** — Completed 2026-04-04 (Cycle 87). All deliverables complete: implementation (Cycles 83-86), tests (Cycle 87), benchmarks (Cycle 87), documentation (Cycle 87).

### Task Fuzzy Search & Enhanced Discovery

Improve task discovery UX with fuzzy search, categorization, and smart suggestions. Inspired by just's fuzzy search and task's tag system. Includes:
- ✅ Fuzzy search in `zr list --fuzzy` with Levenshtein distance scoring (max distance: 3)
- ✅ Task categorization: group tasks by tags in `zr list --group-by-tags` output (fold/unfold categories)
- ✅ Recent tasks tracking: `zr list --recent[=N]` shows last N executed tasks (default 10)
- ✅ Search by description: `zr list --search="build"` matches task names + descriptions
- ✅ `zr which <task>` command: show task definition location + details (cmd, description, deps, tags)
- ⏸️ Suggested tasks: `zr run` without arguments shows interactive picker (deferred to future iteration)
- ⏸️ Integration tests for fuzzy search and task picker (deferred to future iteration)
**Status: DONE** — Completed 2026-03-31 (Cycle 59). All core discovery features implemented except interactive picker (deferred).

### Graph Format Enhancements

Complete the TODO at `src/cli/graph.zig:479` to implement remaining graph output formats for task graphs. Currently only interactive format is implemented for task graphs, but ASCII/DOT/JSON formats should also support `--type=tasks`. Includes:
- ✅ ASCII tree rendering for task graphs (similar to workspace mode but for tasks)
- ✅ DOT format for task graphs (GraphViz compatibility with task metadata)
- ✅ JSON format for task graphs (machine-readable with full task details)
- ✅ Consistent CLI interface: `zr graph --type=tasks --format=<ascii|dot|json|interactive>`
- ✅ Update existing ASCII/DOT/JSON implementations to handle TaskConfig input
- ✅ Add integration tests for all task graph formats (10 tests in tests/graph_formats_test.zig)
- ✅ Document usage in help text and guides
**Status: DONE** — Completed 2026-03-30 (Cycle 52). All task graph formats implemented (renderTasksAscii, renderTasksDot, renderTasksJson). Legacy graph command conflict resolved in main.zig with new flag detection. 10 integration tests added (3917-3926). All dependency types supported (parallel, serial, conditional, optional).

### Enhanced Performance Monitoring

Complete the TODO items in resource monitoring for comprehensive real-time performance analysis. Implement CPU percentage tracking (requires delta measurements), memory breakdown (heap/stack/mapped), and historical trending. Add `zr monitor` command for live resource dashboard with task-level granularity. Includes:
- CPU percentage calculation (requires tracking previous CPU time samples)
- Memory breakdown by category (heap allocations, stack usage, memory-mapped regions)
- Historical resource usage trends (5min/1hr/24hr rolling windows)
- Task-level resource attribution (CPU/memory per task)
- Real-time dashboard TUI (`zr monitor <workflow>`) with live graphs
- Export metrics to JSON/CSV for external analysis
- Integration with existing `resource_monitor.zig` (complete TODOs at lines 156, 234)
**Status: DONE** — Completed 2026-03-27. All items implemented and integrated.

### Interactive Task Builder TUI

Create a form-based interactive TUI for building tasks without manually editing TOML. Enhance the existing `zr add task` command with a rich interactive mode featuring field validation, inline help, and live preview. Includes:
- Text-based prompts for task/workflow creation (implemented with retry loops)
- Field validation with instant feedback (required fields, valid expressions, existing deps)
- Live TOML preview showing generated config before save
- Dependency existence validation (checks against existing tasks in config)
- Expression syntax validation (basic check for unmatched {{ }})
- Save to zr.toml with confirmation prompt and backup (.bak)
- Re-parse validation after save to ensure config integrity
- Extend to workflow builder (`zr add workflow --interactive`)
**Status: DONE** — Completed 2026-03-28 (Cycle 33). Implemented with text prompts instead of sailor Form widgets due to API compatibility issues with sailor v1.22.0. Full implementation in src/cli/add_interactive.zig with 41 integration tests. Commands: `zr add task --interactive`, `zr add workflow --interactive`.

### Task Result Caching & Memoization

Implement intelligent task output caching based on input fingerprints to avoid redundant computation across runs and machines. Unlike incremental builds (mtime-based), this uses content hashing for cache-key generation similar to Nx/Turborepo. Currently tasks re-run even when inputs haven't changed. This milestone adds persistent caching with local and remote backends. Includes:
- **Input fingerprinting**: Hash task command + source files + env vars + params for cache key generation
- **Cache storage**: Local `.zr/cache/<task>/<hash>/` with stdout/stderr/artifacts/metadata
- **Cache hit detection**: Check cache before execution, restore outputs on hit, skip execution
- **Cache restore**: Copy cached outputs (files + stdout/stderr) to workspace on cache hit
- **Cache CLI**: `zr cache clean`, `zr cache status`, `zr cache clear <task>` management commands
- **Remote cache**: Optional S3/GCS/HTTP backend for team-wide cache sharing (configurable)
- **Cache invalidation**: Automatic on source changes, manual via `--no-cache` flag
- **List integration**: `zr list --show-cache` displays cache status (hit rate, last hit timestamp)
- **Cache statistics**: Track hit rate, size, age for optimization insights
- **Workspace-wide cache**: Shared cache across all tasks in workspace (collision-safe with namespacing)
**Status: DONE** — Completed 2026-05-03 (Cycles 193-199). Implementation: ~560 LOC (Phase 1-2: cache key generation ~140 LOC in exec/cache_key.zig with SHA-256 hashing, cache storage ~220 LOC in exec/cache_store.zig with manifest.json, scheduler integration; Phase 3: cache restore ~100 LOC with CacheStore.retrieve(); Phase 4: CLI commands ~227 LOC in cli/cache.zig with clean/status/clear; Phase 5: list integration ~25 LOC with --show-cache flag). Testing: ~1015 LOC (30 integration tests in cache_storage_test.zig, 16 tests in cache_test.zig covering CLI commands, cache hit/miss, restore, list integration). Documentation: ~650 LOC comprehensive guide at docs/guides/task-caching.md with cache key generation, hit detection, CLI management, practical examples, comparison with Nx/Turborepo/Make, migration guides, future enhancements (output capture v1.83.0, remote backends v1.84.0). All tests passing (1527 unit tests). Total: ~2225 LOC across 7 cycles. Ready for v1.82.0 release. **Note**: Output capture and remote cache deferred to future releases (planned v1.83.0-v1.84.0) - current version provides cache key generation, hit tracking, and CLI management foundation.

### Enhanced Watch Mode & Live Reload

Improve file watching with smarter change detection, debouncing strategies, and live reload capabilities. Currently `zr watch` triggers on any file change with fixed debounce. This milestone adds pattern-based filtering, adaptive debouncing, and browser live-reload integration for web development workflows. Includes:
- **Smart filtering**: Use task `sources` patterns to watch only relevant files (ignore unrelated changes)
- **Adaptive debouncing**: Automatically adjust debounce delay based on change frequency (burst vs sporadic)
- **Live reload server**: Built-in WebSocket server for browser auto-refresh on task completion
- **Change batching**: Group rapid file changes into single execution (avoid re-run spam)
- **Watch profiles**: Named watch configs (e.g., `watch.dev`, `watch.test`) with different debounce/filter settings
- **CLI enhancements**: `zr watch --debounce=500ms`, `--live-reload`, `--filter='*.ts'` flags
- **Exclude patterns**: `watch_exclude = ["node_modules/**", "dist/**"]` to ignore output dirs
- **Multi-task watch**: Watch multiple tasks with different patterns in parallel
- **Terminal UI**: Show real-time file change feed with timestamps in TUI mode
- **Integration**: Works with up-to-date detection (skip unchanged tasks) and caching
**Status: DONE** — Completed 2026-05-01 (Cycles 189-192). Implementation: ~1328 LOC (284 LOC debounce.zig adaptive algorithm with burst/sporadic detection, 894 LOC livereload.zig WebSocket server skeleton with client tracking + state machine, 150 LOC run.zig integration with cmdWatch adaptive debouncer + live reload server initialization/triggering). Testing: ~276 LOC (5 integration tests in watch_test.zig for config parsing, 149 LOC debounce unit tests covering burst/sporadic/ramping, 11 LOC livereload unit tests for state machine, additional quality improvements Cycle 190). Documentation: ~605 LOC comprehensive guide at docs/guides/enhanced-watch-mode.md with adaptive debouncing examples, live reload setup, pattern filtering, real-world use cases, comparison with nodemon/watchexec/Vite, troubleshooting. All unit tests passing (1516/1524). Total: ~2209 LOC across 4 cycles. Ready for v1.81.0 release.

### Dependency Resolution & Version Constraints

Add dependency management for external tool requirements with version constraints and automatic installation. Currently tasks can specify toolchain but can't express constraints like "node >= 18" or "python ~3.11". This milestone adds declarative dependency specs with constraint solving similar to package.json engines or cargo. Includes:
- ✅ **Version constraints**: `requires = { node = ">=18.0.0", python = "~3.11" }` in task config
- ✅ **Constraint checking**: Validate installed versions match constraints before task execution
- ✅ **Constraint syntax**: Semver ranges (`^`, `~`, `>=`, `<`, `||`) plus exact pinning (`=1.2.3`)
- ✅ **Conflict resolution**: Detect conflicting constraints across task dependencies (error reporting)
- ✅ **Lock file**: Generate `.zr-lock.toml` with resolved versions for reproducible builds
- ✅ **Version discovery**: Query installed tool versions via `--version` or registry metadata
- ✅ **CLI commands**: `zr deps check`, `zr deps install`, `zr deps outdated`, `zr deps lock` for dependency management
- ✅ **Workspace-level**: Shared constraints in workspace config inherited by all tasks
- ✅ **Documentation**: Comprehensive version constraint syntax, conflict resolution strategies at docs/guides/dependency-management.md
**Status: DONE** — Completed 2026-05-06 (Cycles 204, 206, 208). Implementation: ~560 LOC (constraint parser in config/constraint.zig with semver range logic + caret/tilde/wildcard/alternatives, version checker in toolchain/version.zig with parseVersionOutput(), lock file generator in config/lock.zig with TOML writer, CLI in cli/deps.zig with check/install/outdated/lock subcommands). Testing: ~610 LOC (30 integration tests in tests/deps_test.zig covering constraint parsing, validation, conflict detection, lock file generation, JSON output, task filtering). Documentation: ~600 LOC comprehensive guide at docs/guides/dependency-management.md with syntax reference, CLI commands, conflict detection, workspace inheritance, migration guides, real-world examples, troubleshooting, comparison table. All tests passing (1629/1637). Ready for release.

### zuda Graph Migration (DAG + Topo Sort + Cycle Detection)

Migrate `src/graph/dag.zig` (187 LOC), `src/graph/topo_sort.zig` (323 LOC), `src/graph/cycle_detect.zig` (205 LOC) to zuda (issues #23, #24, #36, #37). Use `zuda.compat.zr_dag` compatibility layer for drop-in replacement. Includes:
- ✅ **zuda v2.0.4 dependency**: Updated build.zig.zon to v2.0.4 (Cycle 223)
- ✅ **Test suite created**: Comprehensive zuda_migration_test.zig with 16 tests (Cycle 214)
- ✅ **BLOCKER RESOLVED**: zuda issue #23 FIXED — Closed 2026-05-07 (toOwnedSlice API fixed)
- ✅ **BLOCKER RESOLVED**: zuda issue #24 FIXED — Closed 2026-05-07 (entry node semantics corrected)
- ✅ **DAG data structure migrated**: src/graph/dag.zig now uses zuda.containers.graphs.AdjacencyList (Cycle 223)
- 🔄 **Topo sort migration**: Custom Kahn's algorithm retained for API compatibility (battle-tested)
- 🔄 **Cycle detection migration**: Custom implementation retained for API compatibility
- ⏸️ **Issue closure**: Close GitHub issues #36, #37 (document migration status)
**Status: READY** — UNBLOCKED 2026-05-12 (Cycle 227). DAG data structure migrated to zuda AdjacencyList (Cycle 223-224, memory leak fixes applied). Topological sort and cycle detection kept as custom implementations for API compatibility and stability. Issues #23/#24 fixed in zuda v2.0.4. Migration can proceed for remaining utilities (glob, workstealing).

### zuda Levenshtein Migration

Migrate from custom `src/util/levenshtein.zig` (214 LOC) to `zuda.algorithms.dynamic_programming.edit_distance` (issue #21). Add zuda dependency via zig fetch, migrate levenshtein.zig to wrapper, update all call sites (`main.zig` "Did you mean?" suggestions, `cli/validate.zig`), verify unit tests pass, remove custom implementation. **Status: DONE** — Completed 2026-03-21. Migrated to zuda.algorithms.dynamic_programming.editDistance, all tests passing.

### Sailor v2.1.0 Migration

Migrate to sailor v2.1.0 (issue #54) which provides drop-in performance optimizations and API ergonomics improvements. This is a backward-compatible upgrade requiring only dependency update with no code changes. Includes:
- **Performance improvements** (automatic, no code changes):
  - Buffer diff: +38% faster
  - Buffer fill: +34% faster
  - Buffer set: +33% faster
- **New ergonomic APIs** (optional adoption):
  - `Rect.fromSize(w, h)` — Create rects without x/y coordinates
  - Constraint constructors: `.length()`, `.percentage()`, `.min()`, `.max()`, `.ratio()`, `.fill()`
  - Color constructors: `.rgb()`, `.indexed()`, `.basic()`
  - Semantic constants: `Style.bold`, `Color.red`, etc.
- **Migration steps**:
  - Update build.zig.zon: `zig fetch --save https://github.com/yusa-imit/sailor/archive/refs/tags/v2.1.0.tar.gz`
  - Run `zig build test && zig build integration-test` to verify compatibility
  - No code changes required for basic migration (all improvements backward compatible)
  - Optional: Adopt new ergonomic APIs in TUI components (graph_tui.zig, tui.zig, task_picker.zig)
- **Zero breaking changes**: All v2.0.0 APIs remain unchanged
- **Testing**: Existing TUI integration tests (tests/tui_test.zig) verify compatibility
- **Issue closure**: Close GitHub issue #54
**Status: DONE** — Completed 2026-04-24 (Cycle 159). Updated build.zig.zon dependency, fixed 4 Rect.new() call sites to use direct struct initialization. All unit tests passing (1434/1442). Benefits: +38% buffer diff, +34% buffer fill, +33% buffer set. Zero breaking changes. Closed issue #54.

### Sailor v2.3.0 & v2.4.0 Migration

Migrate to sailor v2.3.0 and v2.4.0 (issues #55, #56) which provide advanced widget features and testing infrastructure. Both are backward-compatible upgrades requiring only dependency update with no code changes. Includes:
- **v2.3.0 features** (available but not used):
  - Scrollable widgets: Table/List scrolling, Paragraph justify+indent
  - State persistence: Save/restore widget state, StateHistory undo/redo
  - Advanced styling: Gradients, border styles (dashed), shadow effects
  - Performance: LazyBuffer, VirtualList, RenderBudget
- **v2.4.0 features** (available but not used):
  - Snapshot testing framework for widget rendering
  - Property-based testing with random input generation
  - Visual regression testing with buffer diff visualization
  - Mock terminal for TUI testing without real TTY
  - Testing utilities: Leak detection, widget fixtures, assertion helpers, benchmark tools
- **Migration steps**:
  - Update build.zig.zon: `zig fetch --save https://github.com/yusa-imit/sailor/archive/refs/tags/v2.4.0.tar.gz`
  - Run `zig build test && zig build integration-test` to verify compatibility
  - No code changes required (all improvements backward compatible)
  - Optional: Adopt new features in TUI components or tests (future enhancement)
- **Zero breaking changes**: All v2.1.0 APIs remain unchanged
- **Testing**: Existing TUI tests verify compatibility
- **Issue closure**: Close GitHub issues #55, #56
**Status: DONE** — Completed 2026-04-30 (Cycle 188). Updated build.zig.zon dependency from v2.1.0 → v2.4.0 (via v2.3.0). All unit tests passing (1487/1495). Zero code changes required. New features available for future adoption. Closed issues #55, #56.

### Task Conditional Dependencies Enhancement

Complete and polish the partially-implemented `deps_if` conditional dependency system to enable powerful conditional execution patterns. Currently `deps_if` is parsed but not fully integrated with all task execution features. This milestone completes the implementation and adds missing features. Includes:
- ✅ **Expression evaluation robustness**: Enhanced expression engine with `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `||`, `!` operators
- ✅ **Environment variable conditions**: `deps_if = [{ task = "setup", condition = "env.NODE_ENV == 'production'" }]`
- ✅ **Parameter conditions**: `deps_if = [{ task = "tests", condition = "params.skip_tests != 'true'" }]`
- ✅ **Tag-based conditions**: `deps_if = [{ task = "docker-build", condition = "has_tag('docker')" }]`
- ✅ **Negation and complex logic**: Full support for `!`, `&&`, `||`, `()` grouping in conditions
- ✅ **Watch mode integration**: File watcher uses scheduler.run() which automatically evaluates conditional deps
- ✅ **Dry-run preview**: `zr run --dry-run` correctly shows which conditional deps will be included/excluded
- ✅ **Error messages**: Clear error messages for malformed conditional expressions via expression engine
- ✅ **Integration tests**: 33 tests (15 runtime behavior + 18 dry-run preview) covering all condition types
- ✅ **Documentation**: Comprehensive guide at docs/guides/conditional-dependencies.md (~680 LOC) with real-world examples
**Status: DONE** — Completed 2026-04-24 (Cycle 161, 6 phases across commits 57ba56b, 58f80af, 7c43d45, 0a2ace0, 416ca15). Phase 1-2: Expression engine enhancements (params.X, has_tag(), negation) + scheduler integration (~283 LOC). Phase 3: 15 integration tests for runtime behavior (~511 LOC). Phase 4: 18 integration tests for dry-run preview (~577 LOC, NO implementation changes needed — scheduler.zig's collectDeps/buildSubgraph already evaluate conditional deps). Phase 5: Watch mode integration (NO changes needed — cmdWatch uses scheduler.run()). Phase 6: Comprehensive documentation guide (~680 LOC). Total deliverable: ~2051 LOC (283 impl + 1088 tests + 680 docs). Ready for v1.76.0 release.

### Enhanced Task Filtering & Selection Patterns

Add powerful task selection patterns for large monorepos and complex workflows, inspired by Bazel's target patterns and Nx's affected detection. Currently `zr run` requires exact task names or workflows. This milestone adds glob patterns, tag-based selection, and directory-scoped execution. Includes:
- ✅ **Glob patterns**: `zr run 'test:*'` runs all tasks matching glob pattern (namespace support)
- ✅ **Tag-based selection**: `zr run --tag=integration` runs all tasks with specified tag(s)
- ✅ **Multiple tag selection**: `zr run --tag=critical --tag=backend` (AND logic for required tags)
- ✅ **Tag exclusion**: `zr run --exclude-tag=slow` skips tasks with specified tags
- ⏸️ **Directory scoping**: `zr run --dir=packages/api` runs tasks from specific directory/package (deferred to future release)
- ✅ **Combination filters**: `zr run 'test:*' --tag=critical --exclude-tag=slow` combines multiple filters
- ⏸️ **Affected detection integration**: `zr run --affected` detects changed files and runs related tasks (requires git) (deferred to future release)
- ✅ **Dry-run preview**: `zr run --dry-run --tag=critical` shows selected tasks without running
- ✅ **List filtering**: Tag filtering already available in `zr list` (existing feature)
- ✅ **Pattern validation**: Error messages for invalid glob patterns or nonexistent tags
- ✅ **Multiple task execution**: Runs all matching tasks sequentially with proper dependency ordering
- ✅ **Integration tests**: 16 comprehensive tests covering all selection patterns, combinations, edge cases
- ✅ **Documentation**: Comprehensive guide in docs/guides/task-selection.md with monorepo examples (~635 LOC)
**Status: DONE (RELEASED v1.77.0)** — Completed 2026-04-25 (Cycles 163-164). Implementation: ~219 LOC (task_selector.zig ~124 LOC, CLI integration in main.zig ~95 LOC). Testing: ~379 LOC (16 integration tests covering glob patterns, tag filters, combinations, edge cases). Documentation: ~635 LOC comprehensive guide at docs/guides/task-selection.md with usage examples, real-world scenarios, comparison with Bazel/Nx/Task/Just, best practices, troubleshooting. Features: glob patterns (*, **, ?), tag filtering (--tag, --exclude-tag with AND logic), multiple task execution with dependency ordering, dry-run preview, helpful error messages. Directory scoping and affected detection deferred to future milestone. Total deliverable: ~1233 LOC across 3 commits. All tests passing (1452 unit tests). Released 2026-04-25 as v1.77.0. GitHub release: https://github.com/yusa-imit/zr/releases/tag/v1.77.0
### zuda WorkStealingDeque Migration

Migrate from custom `src/exec/workstealing.zig` (130 LOC) to `zuda.containers.queues.WorkStealingDeque` (issue #22). zuda v2.0.0 resolves memory safety bug (issue #13 CLOSED). Includes:
- ✅ **zuda v2.0.4 dependency**: Updated build.zig.zon from v1.15.0 → v2.0.4 (Cycle 223)
- ✅ **Integration tests**: tests/zuda_workstealing_test.zig (11 tests, all passing with v2.0.4)
- ✅ **Scheduler integration**: Analyzed — WorkStealingDeque not applicable to thread-per-task execution model
- ✅ **Migration decision**: Work-stealing not needed; scheduler uses thread-per-task with semaphore-based concurrency
- ✅ **Code removal**: Deleted src/exec/workstealing.zig and tests/zuda_workstealing_test.zig (Cycle 228)
- ✅ **Issue closure**: Closed #22 as WONTFIX with architecture explanation (Cycle 228)
**Status: DONE** — Completed 2026-05-13 (Cycle 228). Analysis confirmed that zr's scheduler uses a thread-per-task execution model (scheduler.zig:2271-2286) where each task spawns its own thread, runs to completion, and joins. Work-stealing is beneficial for long-running worker pools with dynamic task redistribution, which doesn't match zr's DAG-based level-by-level execution. The custom workstealing.zig was unused in production code and has been removed. Issue #22 closed with explanation.

### zuda Glob Migration

Migrate from custom `src/util/glob.zig` (130 LOC) to `zuda.algorithms.string.globMatch` (issue #25). Add zuda dependency, replace glob matching logic, verify tests pass. **Status: DONE** — Completed 2026-03-21. Migrated to zuda.algorithms.string.globMatch, reduced pattern matching logic from 44 LOC to wrapper, added character class support, all 1024 integration tests passing.

### Sailor v1.23.0 Migration (Plugin Architecture)

Migrate to sailor v1.23.0 which introduces plugin architecture and extensibility features. This enables custom widgets and composition helpers in zr's TUI components. Includes:
- Widget trait system for custom widget implementations
- Pre/post render callbacks for custom effects
- Theme plugin system with JSON loading and runtime switching
- Composition helpers (Padding, Centered, Aligned, Stack, Constrained)
- Full nesting support for widget composition
- Update `build.zig.zon` dependency to v1.23.0
- Review all TUI components for potential plugin integration
- No breaking changes expected (backward compatible)
**Status: DONE** — Completed 2026-03-28 (Cycle 34). Updated build.zig.zon, all 1197 unit tests pass, no code changes required (backward compatible).

### Sailor v1.24.0 Migration (Animation & Transitions)

Migrate to sailor v1.24.0 which adds animation system for smooth, time-based rendering. This can enhance zr's progress indicators, graph visualization transitions, and TUI feedback. Includes:
- 22 easing functions (linear, cubic, elastic, bounce, back, circ, expo)
- Animation struct for value interpolation
- ColorAnimation for smooth color transitions
- Timer/TimerManager for async scheduling
- Transition helpers (fade, slide effects)
- Update `build.zig.zon` dependency to v1.24.0 (after v1.23.0)
- Review progress bars, TUI transitions, live execution views for animation opportunities
- +271 tests in sailor (no zr changes needed unless utilizing animations)
**Status: DONE** — Completed 2026-03-28 (Cycle 36). Updated build.zig.zon, all 1197 unit tests pass, no code changes required (backward compatible).

### Sailor v1.25.0 Migration (Form & Validation)

Migrate to sailor v1.25.0 which completes form widget system with comprehensive validation. This DIRECTLY addresses the Interactive Task Builder TUI milestone's original goal of using sailor Form widgets (deferred in Cycle 31 due to API issues with v1.22.0). Includes:
- Form widget with multi-field container and fluent API
- Field focus management (Tab/Shift+Tab navigation)
- Password field masking
- 15+ built-in validators (notEmpty, minLength, email, url, ipv4, numeric, etc.)
- Input masks (SSN, phone, date, credit card, ZIP)
- Inline error display and optional help text
- Update `build.zig.zon` dependency to v1.25.0 (after v1.24.0)
- **Revisit Interactive Task Builder TUI**: replace text prompts in `src/cli/add_interactive.zig` with sailor v1.25.0 Form widgets
- Add live TOML preview pane, field validation, dependency picker (original milestone goals)
- Update integration tests (41 existing tests in tests/add_interactive_test.zig)
**Status: DONE** — Completed 2026-03-28 (Cycle 36). Updated build.zig.zon, all 1197 unit tests pass, no code changes required (backward compatible). Form widgets now available for Interactive Task Builder TUI enhancement.

### Retry Strategy Integration Completion

Complete the integration of retry strategies from v1.47.0. Includes:
- ✅ Implemented test 972 (max_backoff_ms ceiling with timing tolerance for CI)
- ✅ Implemented tests 973-974 (retry_on_codes - match/no-match scenarios)
- ✅ Implemented tests 975-976 (retry_on_patterns - match/no-match scenarios)
- ✅ Implemented test 977 (combined strategy: backoff + max_backoff + jitter)
- ✅ Updated TOML test constants to use inline table syntax (`retry = { ... }`) instead of section syntax (`[tasks.X.retry]` not yet implemented in parser)
- ✅ All 6 integration tests now pass, functional behavior verified
**Status: DONE** — Completed 2026-03-28 (Cycle 35, Stabilization). All retry strategy tests implemented and passing. Note: Section syntax `[tasks.X.retry]` remains unimplemented (parser currently supports inline table syntax only).

### Output Enhancement & Pager Integration

Complete the deferred pager integration from Task Output Streaming Improvements (v1.49.0). Implement automatic pager integration for `zr show --output` command to handle large output files gracefully. Add support for `less`/`more` style navigation with search, color preservation, and keyboard shortcuts. Includes:
- Auto-detect terminal height and switch to pager for outputs > screen size
- Preserve ANSI colors in pager mode (via `less -R` default)
- Configuration option to disable pager (`--no-pager` flag, `ZR_PAGER` env var)
- Comprehensive pager utility module with platform-specific TTY detection
- Integration tests for pager behavior (16 tests in integration_pager.zig)
- Unit tests for pager module (20 tests in util/pager.zig)
**Status: DONE** — Completed 2026-03-25. Automatic pager spawns when output exceeds terminal height, `--no-pager` flag added, environment variable support (`ZR_PAGER`, `PAGER`), TTY detection, color preservation.

### TOML Parser Enhancement (Section Syntax Support)

Extend TOML parser to support section-based syntax for retry configuration, currently only inline table syntax is supported. This allows cleaner multi-line configuration for complex retry strategies. Includes:
- ✅ Parse `[tasks.X.retry]` section syntax
- ✅ Support both inline (`retry = { max = 3, delay_ms = 100 }`) and section syntax
- ✅ Update parser tests to cover both formats (18 integration tests in tests/retry_section_syntax_test.zig)
- ✅ Ensure backward compatibility (existing inline syntax continues to work)
- ⚠️ Extend to other nested configurations (hooks, conditional dependencies) — deferred, retry complete
- ✅ Add comprehensive parser tests for section syntax edge cases
**Status: DONE** — Completed 2026-03-29 (Cycle 38). Section syntax now supported for retry configuration. Parser handles [tasks.X.retry] sections with all retry fields (max, delay_ms, backoff_multiplier, jitter, max_backoff_ms, on_codes, on_patterns). Both inline and section syntax work in same config. Manual testing confirms retry execution with section syntax. 18 integration tests cover all field combinations and edge cases.

### Task Estimation & Time Tracking

Implement task duration estimation and historical time tracking to help users understand and predict task execution patterns. Uses execution history data to provide insights. Includes:
- ✅ Historical duration tracking per task (min/max/avg/p50/p90/p99 from history)
- ✅ Duration estimate display in `zr list` — DONE (Cycle 41, 2026-03-29)
- ✅ Duration estimate display in `zr run --dry-run` preview — DONE (Cycle 42, 2026-03-29)
- ✅ Anomaly detection (task took 2x longer than p90 → warning threshold in stats module)
- ✅ `zr estimate <task>` command for single-task duration prediction (refactored with p90/p99)
- ✅ `zr estimate <workflow>` for workflow total time (critical path calculation) — DONE (Cycle 44, 2026-03-29)
- ✅ Integration with existing `src/history/` module (read history.jsonl)
- ✅ Statistical analysis module (percentiles, standard deviation) — src/history/stats.zig
- ✅ TUI progress bar with ETA based on historical avg — DONE (Cycle 47, 2026-03-30)
- ✅ Export estimates to JSON for external tools (JSON format in estimate command)
**Status: DONE** — Completed 2026-03-30 (Cycle 47). All items implemented: stats module, estimate command, list/dry-run integration, ETA progress bars.

### Configuration Validation Enhancements

Improve configuration validation with actionable error messages, suggestions, and common mistake detection. Builds on existing `zr validate` command. Includes:
- ✅ Detect common mistakes (typo in task names, circular dependencies) — already present
- ✅ Suggest fixes using Levenshtein distance — already present
- ✅ Validate expression syntax with diagnostic context (task conditions, deps_if)
- ✅ Check for unused tasks in --strict mode — already present
- ✅ Detect duplicate task names across imports (namespace collision warnings)
- ✅ Schema validation for plugin configurations (required source field, format checks)
- ✅ Performance warnings (>100 tasks, deep dependency chains >10 levels)
- ✅ `zr validate --strict` mode now treats warnings as errors (exit code 1 for CI)
- ⚠️ LSP integration for real-time validation — deferred (LSP already has diagnostics, redundant)
**Status: DONE** — Completed 2026-03-30 (Cycle 48). Enhanced `src/cli/validate.zig` with expression validation using `expr.evalConditionWithDiag`, performance warnings (task count >100, dependency depth >10), plugin schema validation, import collision detection. Strict mode enhancement: warnings now treated as errors. 7 new integration tests (3900-3906). All 1223 unit tests passing.

### Interactive Workflow Visualizer

Create an interactive HTML/SVG-based workflow visualization for understanding complex task graphs. Complements existing ASCII graph with modern web UI. Includes:
- ✅ Generate standalone HTML file with embedded SVG graph (D3.js v7 CDN)
- ✅ Interactive features: zoom, pan, drag nodes, click task to see details (cmd, description, deps, env, tags, duration)
- ✅ Color-coded nodes (success/failed/pending/unknown status from execution history)
- ✅ Critical path highlighting (longest dependency chain with recursive depth calculation)
- ✅ Filter by regex search, status, or tags
- ✅ Export to SVG/PNG for documentation
- ✅ `zr graph --interactive` generates HTML (command implemented)
- ✅ `zr graph --type=tasks` for explicit task graph mode
- ⚠️ `zr graph --watch` live-updates — deferred (requires scheduler integration)
- ✅ D3.js force-directed graph with curved links and arrow markers
- ✅ Responsive design with fixed sidebar for task details
**Status: DONE** — Completed 2026-03-30 (Cycle 49). Comprehensive interactive visualizer implemented with D3.js. 10 integration tests (3907-3916). Usage: `zr graph --interactive` or `zr graph --type=tasks --interactive`. Saves to file with `> workflow.html`.

---

## Completed Milestones

| Version | Name | Date | Summary |
|---------|------|------|---------|
| v1.74.0 | Task Up-to-Date Detection & Incremental Builds | 2026-04-22 | Enables smart task execution by skipping tasks whose outputs are already up-to-date, dramatically speeding up repeated executions. **Core Features** (Cycles 148-152) — (1) Schema changes (Cycle 148): Added `sources`/`generates` fields to Task struct for file pattern matching, TOML parser support for single string or array syntax, Task.deinit() cleanup for both arrays, ~40 LOC (types.zig, parser.zig); (2) Up-to-date checker module (Cycle 148): Created src/exec/uptodate.zig (~130 LOC) with isUpToDate() mtime-based comparison, expandGlobs() using util/glob.zig (supports `**`, `*`, `?`), fileExists()/getFileMtime() helpers, 4 unit tests (all passing); (3) Scheduler integration (Cycle 148): Added force_run field to SchedulerConfig (default false), integrated up-to-date check in workerFn before task execution, tasks skip when up-to-date with log message, ~65 LOC (scheduler.zig); (4) CLI flags (Cycles 148-149): Added --force flag to ignore up-to-date checks in main.zig, updated cmdRun signature with force_run parameter, fixed 15+ call sites across run.zig/interactive_run.zig/setup.zig/tui.zig/mcp/handlers.zig/matrix.zig, ~45 LOC; (5) Dry-run status enhancement (Cycle 149): Added getTaskStatus() helper to check up-to-date status, integrated into printDryRunPlan() with [✓]/[✗]/[?] status indicators before task names, updated signature with config parameter, fixed 3 call sites, ~30 LOC (run.zig); (6) --status flag (Cycle 151): Added --status flag parsing in main.zig, updated cmdList() signature with show_status parameter, created getTaskStatus() helper using uptodate.isUpToDate(), integrated status display in both flat list and grouped-by-tags modes with color-coded indicators (printSuccess/printError/printDim), updated 10 call sites, added integration test (test 9999), ~85 LOC (main.zig, list.zig); (7) Dependency propagation (Cycle 152): Track which tasks actually executed (not skipped) in executed_tasks HashMap, check if any dependencies ran before up-to-date check, force task to run if dependency executed (ensures build correctness), collect all dependency types (deps, deps_serial, deps_if, deps_optional) into task_deps slice, mark tasks as executed after successful completion, ~53 LOC (scheduler.zig). **Integration Tests** (Cycle 148): Created tests/uptodate_test.zig (~666 LOC, 12 tests) covering basic mtime comparison, multiple sources/generates, missing generates, glob patterns, --force flag, --dry-run preview, up-to-date and stale dependencies, backward compatibility (no sources/generates), empty generates, list --status display. All tests passing (1434/1442 unit tests, 8 skipped, 0 failed). **Documentation** (Cycle 152): Comprehensive incremental builds guide at docs/guides/incremental-builds.md (~522 LOC) with overview, basic usage, glob patterns reference, dependency propagation explanation, status display, forcing execution, integration with caching/watch/workflows, performance optimization tips, migration guides from make/task/just, best practices, troubleshooting, advanced patterns (multi-stage builds, conditional source tracking), complete reference tables. **Key Technical Decisions**: mtime-based comparison (i128 timestamps), glob expansion via util/glob.zig, force_run bool in SchedulerConfig for clean separation, backward compatibility (tasks without sources/generates always run), up-to-date check in workerFn (single point of control), dependency propagation via executed_tasks HashMap (stale dep → force dependent rebuild), status indicators: [✓] green (newer), [✗] red (stale), [?] dim (no generates). **Implementation Summary**: ~448 LOC implementation (schema, uptodate checker, scheduler, CLI, status, propagation), ~666 LOC tests (12 integration + 4 unit), ~522 LOC docs. Zero breaking changes (all additive). Commits: 249180f (Phase 1-2), 6eeb24b (Phase 3-4), 549b118 (CI fix), 33f3567 (dry-run status), 562f555 (--status flag), 8da13f4 (dependency propagation), c6ac637 (docs). Status: DONE (0% → 100%, Cycles 148-152). Ready for v1.74.0 release. |
| v1.73.0 | Task Aliases & Silent Mode | 2026-04-21 | Adds task aliases for intuitive CLI shortcuts and silent mode for reduced noise from well-behaving tasks. **Core Features** — (1) Task aliases (Cycles 144, 147): `aliases = ["b", "compile"]` field provides multiple names for any task, smart resolution (exact task > exact alias > prefix match), conflict detection prevents duplicate aliases/task name collisions, display in `zr list` shows `[aliases: b, compile]`, JSON output includes aliases field, ~95 LOC (parser.zig, types.zig, run.zig, list.zig, loader.zig); (2) Silent mode (Cycles 144, 146): `silent = true` task field suppresses stdout/stderr unless task fails (exit code != 0), buffered output discarded on success/shown on failure for debugging, global `--silent/-s` flag overrides task config (OR logic), works with workflows (`zr workflow --silent ci`), integrated with retries (buffer until final failure) and log levels (`--verbose` overrides), ~60 LOC (scheduler.zig, main.zig, interactive_run.zig, tui.zig, mcp/handlers.zig). **Testing** (Cycles 145, 147): 12 integration tests in tests/task_aliases_test.zig (alias resolution exact/prefix, list/JSON display, conflict detection, global --silent flag success/failure/short-form/override/workflow), 3 unit tests in loader.zig (alias validation: valid, task name conflict, duplicate), 8 integration tests in silent_mode_test.zig (from Cycle 145), all 1430 unit tests passing (8 skipped). **Documentation** (Cycle 147): Task Aliases section (~200 LOC) in configuration.md (basic usage, resolution priority, display format, conflicts, use cases: common shortcuts/multi-language/semantic aliases, best practices), Silent Mode section (~150 LOC) (task-level/global flag/override semantics, example quiet build pipeline, integration with retries/interactive/workflows/log levels, use cases: setup/codegen/formatting/health checks, semantics table), updated Task Fields table with aliases and silent fields. **Implementation Summary**: ~450 LOC implementation, ~310 LOC tests, ~350 LOC docs. Backward compatible (existing configs work unchanged). Commits: 51d9265 (alias conflict detection), a8913ef (integration tests), abccd88 (docs), 3fb6d19 (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.73.0 |
| v1.72.0 | Documentation Site & Onboarding Experience | 2026-04-19 | Delivers comprehensive documentation overhaul with cohesive organization, clear navigation, and production-ready reference materials. **Core Features** — (1) Documentation hub (Cycle 141): `docs/README.md` as landing page with organized sections (Getting Started, Configuration, Commands, Advanced Topics, Reference), clear navigation structure with quick links for first-time users and migration paths, cross-referenced guide structure for easy discovery (153 LOC); (2) Command reference (Cycle 141): Complete `docs/guides/command-reference.md` with all 50+ zr CLI commands, usage examples/options/shortcuts/best practices for each command, global options reference/exit codes/alias system, organized by category (Core, Project, Workspace, Cache, Toolchain, Plugin, Interactive, Integration, Utility) (1744 LOC); (3) Configuration reference (Cycle 141): Field-by-field `docs/guides/config-reference.md` with quick lookup tables for all zr.toml sections (Tasks, Workflows, Profiles, Workspace, Cache, Resource Limits, Concurrency Groups, Toolchains, Plugins, Aliases, Mixins, Templates), expression syntax reference (variables/operators/functions), complete example configuration demonstrating all features (1450 LOC); (4) Best practices guide (Cycle 141): Production-tested `docs/guides/best-practices.md` covering task organization (descriptive naming, tags, mixins, workspace shared tasks), performance optimization (parallelism, caching, concurrency groups, resource limits, NUMA affinity), monorepo patterns (affected detection, multi-stage workflows, task inheritance), CI/CD integration (GitHub Actions/GitLab CI examples, remote cache setup), caching strategies (content-based, layered, remote cache for teams), error handling (retry, circuit breaker, failure hooks), security (secrets management, remote execution), team collaboration (documentation, aliases, profiles), anti-patterns checklist (1800 LOC); (5) Troubleshooting guide (Cycle 141): Comprehensive `docs/guides/troubleshooting.md` with installation issues (PATH configuration, permissions, SSL, build errors), configuration errors (TOML syntax, dependency cycles, invalid expressions), task execution problems (silent failures, timeouts, retry debugging), performance issues (slow builds, memory usage, cache misses), cache/workspace/toolchain/CI-CD debugging, extensive FAQ section (migration, Docker integration, remote execution, debugging, secrets), diagnostic commands reference (2300 LOC). **Implementation Summary** (Cycle 141): Total ~7447 LOC documentation across 6 files (153 landing + 1744 command + 1450 config + 1800 best practices + 2300 troubleshooting = 7447 LOC). Zero code changes (documentation-only release). All tests passing: 1427/1435 (8 skipped, 0 failed). Existing guides (getting-started.md, migration.md, shell-setup.md, configuration.md) already provided core content. **Documentation Improvements**: Cross-references between all files, structured Table of Contents in each guide, improved discoverability. **Deferred** — Video walkthrough (core docs complete, video is supplementary), example projects (examples/ directory exists, additional examples can be added incrementally), static site generation (Markdown files complete and navigable, mdBook optional enhancement). Commits: 2f08338 (landing + command reference), e0f73c3 (config reference + best practices + troubleshooting), 189cc38 (version bump). Release: https://github.com/yusa-imit/zr/releases/tag/v1.72.0 |
| v1.71.0 | Migration Tool Enhancement | 2026-04-18 | Complete auto-conversion from popular task runners (npm/make/just/task) to zr with semantic analysis, dry-run preview, and detailed migration reports. **Core Features** — (1) npm scripts migration (Cycle 133): `zr init --from npm` parses package.json scripts, detects pre/post hooks as dependencies, analyzes `npm run <task>` patterns, supports run-s/run-p (npm-run-all), handles empty package.json with minimal template, 5 integration tests (10100-10104); (2) Dry-run mode (Cycle 136): `--dry-run` flag previews conversion without creating files, shows generated zr.toml with syntax highlighting, displays migration report (warnings/manual steps/recommendations), works with all migration modes; (3) Migration reports (Cycle 136): automatic report generation after successful migration, color-coded output (warnings yellow, recommendations cyan), tool-specific guidance (npm: add descriptions, use direct commands, consider parallelism), unsupported features flagged (lifecycle scripts, Make pattern rules), manual steps required (variable substitution, conditional logic), 150 LOC report.zig with MigrationReport struct. **Enhanced Existing Migrations** — Makefile migration: extracts targets, dependencies (.PHONY), variables, pattern rules; Justfile migration: converts recipes/dependencies/variables (1:1 mapping); Taskfile migration: converts tasks.yml to zr.toml with deps/cmds/vars; all include semantic analysis for parallel patterns. **Implementation** (Cycles 133, 136, 138): New module `src/migrate/npm.zig` (350 LOC) for package.json parsing with JSON scripts section, hook detection (pretest/postbuild), dependency analysis (npm run patterns), run-s/run-p support, fallback template. New module `src/migrate/report.zig` (150 LOC) for migration reporting with warnings/recommendations/unsupported features. Enhanced `src/cli/init.zig` with dry_run parameter support. CLI flags: `--from-npm`, `--from-make`, `--from-just`, `--from-task`, `--dry-run`. **Integration Tests** (8 tests: 10100-10107): npm simple scripts, pre/post hooks, dependency detection, missing package.json error, empty fallback, dry-run preview, report display (Makefile), dry-run + justfile combo. All tests passing: 1427/1435 (8 skipped, 0 failed). **Documentation** (~260 LOC in docs/guides/migration.md): Comprehensive migration guide with npm/make/just/task conversion patterns, before/after examples, dependency detection patterns, manual adjustment recommendations, monorepo strategies (Turborepo, Lerna). **Deferred** — Interactive review mode (--interactive flag with $EDITOR) deferred to future milestone; current dry-run workflow provides core preview functionality (preview → review → create). **Milestone Progress**: Cycle 133 (npm migration: 350 LOC + 5 tests + 260 docs), Cycle 136 (dry-run + reports: 230 LOC + 3 tests + 50 docs), Cycle 138 (completion + release). Total: ~580 LOC parsers/reports, ~410 LOC tests, ~310 LOC docs. Status: DONE (60% → 100%, interactive review deferred). Commits: adf68bd (npm), 88de985 (docs), 8106519 (reports), ea2a31e (counter), 33ab727 (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.71.0 |
| v1.70.0 | Real-Time Task Output Filtering & Grep | 2026-04-17 | Adds live filtering and pattern matching for task output streams, enabling quick debugging and log analysis without post-processing. **Core Features** — (1) Live grep: `zr run build --grep="error|warning"` shows only matching lines with substring matching and pipe-separated OR alternatives; (2) Inverted match: `zr run test --grep-v="DEBUG"` hides lines matching pattern for noise reduction; (3) Highlight mode: `zr run build --highlight="TODO|FIXME"` highlights patterns in bold yellow while showing all output; (4) Context lines: `zr run build --grep="ERROR" -C 3` shows 3 lines before/after matches (grep -C style with FIFO buffer); (5) Color preservation: ANSI escape sequences from task output pass through filters unchanged; (6) Multi-task filtering: Filters apply independently to each task's stdout in parallel execution. **Implementation** (Cycles 128-131): CLI flags (--grep, --grep-v, --highlight, -C/--context in main.zig), filter module (src/output/filter.zig, 375 LOC LineFilter class with FilterOptions, pattern parsing, context buffer), OutputCapture integration (filter applied in writeLine() with multi-line handling), scheduler wiring (filter_options passed from SchedulerConfig to OutputCapture, auto-enables buffering when filtering). **Pattern Syntax**: Substring matching (not regex, Zig 0.15 MVP), pipe-separated OR logic (error|warning|fatal matches any), case-sensitive. **Performance**: <1ms overhead per line (substring search), O(context_lines) memory for FIFO context buffer, large outputs (>1MB) stream efficiently without full buffering. **Integration Tests** (12 tests: 9500-9511): Basic grep, inverted grep, pipe alternatives, highlight mode, context lines, combined filters (grep + grep-v), edge cases (empty output, no matches), multi-task filtering, no-color mode, overlapping context. **Documentation** (~150 LOC in docs/guides/commands.md): Comprehensive "Output Filtering" section with usage examples, pattern syntax, filter application rules, performance notes. **Test Coverage**: 1415/1423 unit tests passing (8 skipped, 0 failed), 5 filter unit tests + 12 integration tests. **Total**: ~450 LOC filter module + integration, ~313 LOC tests. **Zero breaking changes** — all additive. **Deferred**: Regex support (Zig 0.15 lacks std.Regex), tail follow mode (--grep --follow), per-task filter config. Commits: c2c9bdf (CLI + filter), 08f3fb1 (OutputCapture integration), 21f1fc1 (tests), 93fdc4c (scheduler), 10f27aa (docs + version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.70.0 |
| v1.69.0 | Task Name Abbreviation & Fuzzy Matching | 2026-04-14 | Reduces typing friction with intelligent task name abbreviation and fuzzy matching. **Core Features** — (1) Prefix matching: `zr run b` matches `build` if unique, shows ambiguity error if multiple matches (build, bench, backup); (2) Unique prefix resolution: `zr run dep` → `deploy` if only task starting with "dep", automatic resolution with confirmation message; (3) Fuzzy fallback: `zr run tset` suggests "test" via Levenshtein distance (reuses existing v1.0 implementation); (4) Abbreviation hints: `zr list` displays minimum unique prefix for each task (e.g., [b] → build, [tea] → teardown, [tes] → test); (5) Exact match precedence: Exact task names always take priority over prefix matches. **Implementation** (Cycle 124): Added `findTasksByPrefix()` in src/cli/run.zig with exact match priority, unique prefix auto-resolution, and ambiguity detection (~100 LOC). Added `calculateUniquePrefix()` for displaying abbreviation hints in `zr list` output (~50 LOC in list.zig). All features integrated into existing fuzzy matching system (Levenshtein fallback). **Fixed**: Use-after-free bug in empty slice allocation (exact match path now uses heap allocation). **Integration Tests** (8 tests): Unique prefix match (zr run b → build), ambiguous prefix error (zr run te → test/teardown), exact match precedence (task "b" over prefix "build"), fuzzy fallback (zr run tset → suggests "test"), single-letter prefixes with many tasks, list output with unique prefix hints, prefix matching with task dependencies. **Test Coverage**: 1408/1416 unit tests passing (8 skipped, 0 failed). **Total**: ~150 LOC logic (run.zig + list.zig), ~250 LOC tests (task_abbreviation_test.zig). **Zero breaking changes** — feature is purely additive. **Deferred**: Workspace-aware prefixes (`member:prefix`) to future milestone (not required for core functionality). Commits: 6602f32 (implementation), cfd8653 (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.69.0 |
| v1.68.1 | Sailor v1.38.0 & v1.38.1 Migration | 2026-04-11 | Dependency update: sailor v1.37.0 → v1.38.1 (batch migration). v1.38.0 introduces migration tooling infrastructure for upcoming v2.0.0, v1.38.1 fixes migration script bugs. Both are maintenance releases with zero breaking changes. **Migration** (Cycle 118): Updated build.zig.zon from v1.37.0 to v1.38.1 with correct tarball hash (12207f29e8be9cb91b1440dfa9083deed97b4aa3e11e2c107f8c4b3f1a68c9cac3cd). **Quality Assurance**: All 1408 unit tests passing (8 skipped, 0 failed), zero code changes required in zr codebase (backward compatible). **Features**: Deprecation warnings for Rect.new(), Block.withTitle() in preparation for v2.0.0, migration script infrastructure (consumer-facing, not required for zr). **Issue Closure**: Closed #52 (v1.38.0), #53 (v1.38.1). **Implementation**: Single file change (build.zig.zon), zero functional impact on zr. Commits: 1b46c43 (migration), 05fead3 (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.68.1 |
| v1.68.0 | Shell Integration & Developer Ergonomics | 2026-04-10 | Enhances command-line productivity with smart defaults, history shortcuts, and workflow shorthands. **Core Features** — (1) Smart 'zr' (no args) behavior: runs `default` task if exists, auto-runs single task if only one defined, launches interactive picker for multiple tasks, shows help for no config/no tasks; (2) History shortcuts: `zr !!` re-runs last task, `zr !-N` runs Nth-to-last task (e.g., `!-2` for 2nd-to-last), loads from `~/.zr_history` (shared across projects), validates index format/range with clear errors, shows "Re-running: <task>" info message; (3) Workflow shorthand: `zr w/<workflow>` as shorthand for `zr workflow <workflow>`, validates workflow name, respects all global flags. All features respect `--profile`, `--dry-run`, `--jobs`, `--monitor` flags. **Documentation** (398 lines) — New comprehensive guide: `docs/guides/shell-setup.md` with shell-specific setup (bash/zsh/fish), completion instructions, aliases & abbreviations, directory navigation, tips/best practices/troubleshooting. **Integration Tests** (12 tests) — Smart no-args (default task, single task, no config, no tasks: 4 tests), history shortcuts (!-N validation, unknown syntax: 3 tests), workflow shorthand (w/<name>, w/ without name, nonexistent: 3 tests), combined features (--dry-run, --profile: 2 tests), all edge cases covered. **Implementation** (Cycle 114): ~140 lines logic in src/main.zig (3 features: no-args picker/default/single, history reload from store, workflow shorthand parsing), 252 lines tests in tests/shell_ergonomics_test.zig, 398 lines docs. **Deferred Features**: Task name abbreviation matching, shell function generation (`--functions` flag), `eval $(zr env --export)` postponed to future milestones (nice-to-have, core UX delivered). **Test status**: 1408/1416 passing (8 skipped), zero regressions. **Zero breaking changes** — all additive. Commits: 0b3c381 (smart no-args), bb0ab32 (history shortcuts), d27894d (workflow shorthand), f403627 (tests), d4d1054 (docs), 7e2dc2f (milestone), 6b2b9dd (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.68.0 |
| v1.67.0 | Advanced Task Composition & Mixins | 2026-04-07 | Introduces mixins for task reusability through composition patterns. **Core Feature** — Mixin system with `[mixins.NAME]` sections for defining reusable task fragments. Tasks apply mixins via `mixins = ["name1", "name2"]` field. **Field Merging Semantics**: env merged (task overrides), deps/deps_serial/deps_optional/deps_if concatenated (mixin first), tags unioned (deduplicated), hooks concatenated (mixin first), scalar fields (cmd, cwd, description, timeout, retry_*) overridden (task wins). **Nested Mixins** — Mixins can reference other mixins with DAG cycle detection (`error.CircularMixin` for cycles, `error.UndefinedMixin` for missing). Left-to-right application order for multiple mixins. **Implementation** (Cycle 113, commit 7417a88): 2594 lines across 6 files (types.zig: Mixin struct + Task.mixins + Config.mixins, parser.zig: [mixins.NAME] parsing + nested support, loader.zig: mixin resolution + cycle detection + field merging). **Integration Tests** (20 tests: 8000-8019): Basic single mixin, multiple mixins composition, task overrides, nested (3-level chain), circular detection, nonexistent reference, env merging, deps concatenation, tags union, mixin+templates, mixin+workspace inheritance, empty mixin, all fields, multiple tasks sharing mixin, application order, conditional deps, hooks, retry config, JSON output. **Documentation** (315 lines in configuration.md): Before/after examples (39 lines → 13 lines DRY), field merging table, multiple mixins patterns, nested mixins with cycle detection, 4 real-world use cases (CI pipelines, multi-environment deployments, language tooling, resource constraints), benefits, comparison with templates/workspace/profiles, error handling. **Use Case Example**: Extract common k8s deploy config (env, deps, retry) into `[mixins.k8s-deploy]`, apply to deploy-frontend/backend/database tasks (6 lines each vs 39 lines before). **Test Coverage**: 1408 unit tests passing (8 skipped), 1287 integration tests passing. Backward compatible. Commits: f864145 (docs), 39c388b (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.67.0 |
| v1.66.0 | Enhanced Task Retry & Error Recovery | 2026-04-07 | Documentation and testing enhancement for v1.47.0 retry features. All retry mechanisms were already implemented but undocumented. **Documentation** (212 lines added to configuration guide): Comprehensive retry strategies section with backoff examples (linear, exponential, moderate, aggressive), conditional retry patterns (exit codes, output patterns), jitter for thundering herd prevention, smart retry guidelines (fatal vs retriable errors), circuit breaker + retry integration, failure hooks execution timing, retry statistics in history display. **Integration Tests** (5 new tests: 978-982): Retry + failure hook interaction (hook executes after retries exhausted), retry + success hook interaction (success hook only on eventual success), exponential backoff + hook timing, multiple hooks with retry lifecycle, hook execution order validation. **Documented Features** (v1.47.0): `retry_backoff_multiplier` (1.0=linear, 2.0=exponential), `retry_jitter` (±25% variance), `max_backoff_ms` (delay ceiling, default 60s), `retry_on_codes` (conditional retry by exit code), `retry_on_patterns` (conditional retry by output pattern), `hooks` with `point = "failure"` (execute after retries exhausted), `retry_count` in history (statistics tracking). **Test Coverage**: 13 total retry tests (970-982), 1408 unit tests passing (8 skipped, 0 failed). **Zero Functional Changes**: Pure documentation + test enhancement, backward compatible (legacy `retry_backoff` still works). Commits: f749e39 (docs), 79d9435 (tests), 5dcb91e (milestone), 18c1051 (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.66.0 |
| v1.65.0 | Sailor v1.37.0 Migration | 2026-04-07 | Dependency update: sailor v1.36.0 → v1.37.0 (v2.0.0 API bridge). Prepares codebase for sailor v2.0.0 with zero breaking changes. **Widget Lifecycle Standardization** — Stateless widgets (Block, Paragraph, Gauge) changed from `Widget.init()` to direct construction `Widget{}` for clearer ownership semantics. Updated 6 Block.init() call sites: analytics_tui.zig (3 fixes: dashboard header, duration histogram, time series chart, cache scatter plot), graph_tui.zig (1 fix: dependency graph tree block), tui_runner.zig (2 fixes: task list block, log viewer block). All method chaining syntax updated with parentheses for direct construction: `(Block{}).withTitle(...).withBorders(...)`. **Deprecation System** — sailor v1.37.0 provides compile-time warnings for deprecated v1.x APIs to guide gradual v2.0.0 migration. Buffer.set() API introduced alongside deprecated setChar(). Style inference helpers (withForeground, withBackground, withColors, makeBold, etc.) for cleaner style composition. **Migration** (Cycle 108): Updated build.zig.zon dependency, fixed 6 widget API call sites, all 1408 unit tests passing (8 skipped, 0 failed), zero functional changes (backward compatible). **Quality Assurance**: Cross-platform compatibility verified (macOS, Linux, Windows), zero memory leaks, all existing TUI features intact. **Reference**: sailor v1.37.0 release includes comprehensive v1-to-v2 migration guide (docs/v1-to-v2-migration.md), widget lifecycle patterns documented, sed scripts for automated migration. Closed issue #51. Commits: 4db2303 (migration), 46c92a9 (milestone), d2e9bba (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.65.0 |
| v1.64.0 | Enhanced Task Discovery & Search | 2026-04-07 | Dramatically improved task discoverability with powerful filtering capabilities for large projects (100+ tasks). All filters support combined AND logic for complex queries. **Advanced Filters** — `--exclude-tags` hides tasks with ANY specified tags (e.g., `--exclude-tags=slow,flaky`), `--frequent[=N]` shows top N most executed tasks from history (default: 10, ranked by execution count from `.zr/history.jsonl`), `--slow[=THRESHOLD]` shows tasks exceeding average execution time (default: 30s/30000ms, uses historical statistics). **Filter Improvements** — `--tags` changed from ANY (OR) to ALL (AND) logic for precise filtering (breaking change: requires ALL specified tags, not just one), `--search` now includes command text in full-text search (previously only names and descriptions). **Combined Filters** — All filters work together with AND logic: `--frequent=20 --tags=ci --exclude-tags=slow`, `--search=docker --exclude-tags=deploy`. **Implementation** (Cycle 107): Enhanced filtering logic in src/cli/list.zig (~150 LOC for tag AND logic, exclude-tags filter, full-text search, frequent/slow filters from history), updated cmdList() signature with 3 new parameters (exclude_tags, frequent_count, slow_threshold_ms), CLI parsing in src/main.zig (9 new flag handlers), MCP handler updates for API compatibility. **Integration Tests**: 6 comprehensive tests (7000-7005) covering exclude-tags, tag AND logic, full-text search, combined filters, JSON output, empty results. **Documentation**: Enhanced "Task Discovery" section in docs/guides/commands.md with usage examples, filter combinations, breaking change warning. **Test status**: 1408/1416 unit tests passing (8 skipped), zero regressions. **Total**: ~300 LOC across list.zig, main.zig, MCP handlers, tests, docs. Commits: a1e5602 (filters), e4d398c (tests), 0caa14b (docs), 100a1fc (milestone), 36a9426 (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.64.0 |
| v1.63.0 | Workspace-Level Task Inheritance | 2026-04-07 | Complete workspace-level task inheritance enabling monorepos to define common tasks once in workspace root that all members inherit automatically. **Root-Level Definition** — `[workspace.shared_tasks.NAME]` sections in workspace root zr.toml for defining lint/test/format/build tasks. **Automatic Inheritance** — All workspace members receive shared tasks on load via CLI integration in src/cli/workspace.zig (3 call sites: cmdWorkspaceRun lines 301/379, cmdWorkspaceRunFiltered line 530). **Override Semantics** — Member tasks with same name completely replace workspace tasks (no merging), detected by checking member HashMap before inheritance. **Visibility Markers** — `zr list` shows inherited tasks with `(inherited)` marker via Task.inherited boolean field set during deep copy. **Full DAG Support** — Inherited tasks can depend on member-local tasks via standard dependency resolution. **Implementation** (Cycles 104-106): Data structures (Workspace.shared_tasks HashMap, Task.inherited field in Cycle 104), TOML parsing (`[workspace.shared_tasks.NAME]` section support in Cycle 104), inheritance API (inheritWorkspaceSharedTasks() function with deep copy in Cycle 104), CLI wiring (all workspace member loading paths call inheritance in Cycle 106), 15 integration tests (6000-6014) covering inheritance/override/dependencies/validation, comprehensive documentation in docs/guides/configuration.md with examples/semantics/usage patterns. **Benefits**: DRY principle (define once), consistency (all members use same commands), flexibility (override when needed), discoverability (clear origin markers). **Test status**: 1408/1416 unit tests passing (8 skipped), zero regressions. **Total**: ~500 LOC across data structures, parsing, inheritance, CLI, tests, docs. Commits: 0115443 (data structures), 61c0054 (parsing), 8607507 (inheritance), 87dcc42 (markers), 741d8b7 (tests), 64d1b90 (docs), 2b8cb16 (CLI integration), 1b47392 (version). Release: https://github.com/yusa-imit/zr/releases/tag/v1.63.0 |
| (no release) | Sailor v1.35.0-v1.36.0 Migration | 2026-04-06 | Batch dependency update: sailor v1.34.0 → v1.36.0. Incorporates 2 major releases with accessibility and performance monitoring features. **v1.35.0 - Accessibility Overhaul**: ARIA attributes module with 30+ widget roles (button, checkbox, slider, table, tree), AriaAttributes struct with 8 state flags, builder pattern API, screen reader announcement generation with live region support, focus trap implementation for modal/popup focus containment with configurable tab cycling and FocusTrapStack for nested dialogs, standard keyboard shortcuts (Ctrl+C/X/V, undo/redo, select-all), accessibility demo, +63 new tests (3,022 total, all passing), zero memory leaks, cross-platform verification (6 targets). **v1.36.0 - Performance Monitoring System**: render_metrics.zig (widget rendering with percentile analysis: min/max/avg/p50/p95/p99), memory_metrics.zig (allocation tracking per widget: peak/current bytes), event_metrics.zig (processing latency and queue depth), MetricsDashboard widget with 3 layout modes (vertical/horizontal/grid), auto-formatted time/memory units, color-coded warnings (yellow: P95 >10ms, red: P99 >10ms), performance regression tests with baselines (<50μs avg, <100μs P95 for block widgets), metrics_dashboard.zig example with realistic workloads, +143 new tests (3,162 total, all passing). **Migration** (Cycle 101): Updated build.zig.zon dependency hash, all 1408 unit tests passing (8 skipped), zero breaking changes (fully backward compatible). **Benefits**: Accessibility features enable screen reader support and WCAG compliance. Performance monitoring establishes optimization baselines ahead of v2.0.0. Closed issue #50. Commit: (pending). |
| v1.61.0 | Task Templates & Scaffolding | 2026-04-05 | Comprehensive task template system with 31 built-in templates for common development workflows. **Built-in Templates** (31 total, 6 categories): Build (6: go-build, cargo-build, npm-build, zig-build, maven-build, make-build), Test (7: pytest, jest, cargo-test, go-test, junit, rspec, vitest), Lint (6: eslint, clippy, ruff, golangci-lint, checkstyle, rubocop), Deploy (4: docker-push, k8s-deploy, terraform-apply, heroku-deploy), CI (4: cache-setup, artifact-upload, parallel-matrix, docker-build-ci), Release (4: semantic-release, cargo-publish, npm-publish, docker-tag). **Implementation** (Cycle 94): Template infrastructure in src/template/ (types.zig, engine.zig, registry.zig, loader.zig, builtin/*.zig), variable substitution engine with ${VAR} syntax and default values, template registry with discovery/lookup/category filtering, custom template loader for .zr/templates/ and ~/.zr/templates/, 6 category modules with template definitions. **CLI Commands**: `zr template list [--builtin]` with category grouping, `zr template show <name> [--builtin]` with variable display, `zr template add <name> [--builtin] [--var KEY=VALUE ...] [--output <path>]` with variable substitution and validation. **Features**: Required variable validation, default value application, TOML content generation, support for both built-in and user-defined templates. **Integration Tests** (Cycle 94: d0051bd): 10 comprehensive tests (4000-4009) — template list with categories, show with variable display, add with substitution (go-build, cargo-build, pytest, eslint), required variable validation, default value handling, error cases (nonexistent template, missing variables). **Test status**: 1320 unit tests passing (8 skipped). **Total**: ~1,700 LOC across 13 files. Commits: 8bbdfbe (template system), d0051bd (loader + tests), c0e6719 (milestone), 7e03b70 (version). Reduces configuration friction with language-specific scaffolding for build, test, lint, deploy, CI, and release tasks. Release: https://github.com/yusa-imit/zr/releases/tag/v1.61.0 |
| (no release) | CI/CD Integration Templates | 2026-04-05 | Pre-built CI/CD templates and automation tools for streamlined zr adoption in continuous integration pipelines. **Platform Support**: GitHub Actions, GitLab CI, CircleCI (3 platforms × 3 template types = 9 templates). **Template Types**: (1) Basic CI — standard workflow with zr install, cache, build/test jobs; (2) Monorepo — affected detection, matrix/parameterized builds, workspace/artifact passing; (3) Release — tag-triggered automation with publish and GitHub release creation. **Implementation** (Cycles 91-93): Template infrastructure in src/ci/templates/ (types.zig, engine.zig, registry.zig), variable substitution engine with ${VAR} syntax and default values (DEFAULT_BRANCH, RUNNER, IMAGE, BUILD_TASK, TEST_TASK, PUBLISH_TASK, ARTIFACTS_PATH), GitHub Actions templates (Cycle 91: a40c191 — 3 templates in github_actions.zig), GitLab CI templates (Cycle 92: f51c169 — 3 templates in gitlab.zig with stages/rules/artifacts), CircleCI templates (Cycle 93: 0fd0d4f — 3 templates in circleci.zig with executors/parameterized jobs/workspace persistence). **CLI Commands**: `zr ci generate` with platform auto-detection (.github/workflows, .gitlab-ci.yml, .circleci), --platform/--type/--output flags, platform-specific output paths. `zr ci list` to show all available templates organized by platform. **Integration Tests** (Cycles 91-93): 35 comprehensive tests — 24 GitHub Actions tests (Cycle 91: 9079251 — YAML structure, zr install, caching, monorepo matrix, release tags, variable substitution, error cases), 11 CircleCI tests (Cycle 93: efce51f — executors, parameterized jobs, workspace persistence, tag filtering, GitHub release API). **Documentation** (Cycle 93: f809d53): Comprehensive CI/CD Commands section in docs/guides/commands.md with usage examples, variable substitution reference table, platform-specific features/defaults, template type descriptions, output path conventions. **Test status**: 1304 unit tests passing (8 skipped), 35 CI template integration tests. **Key features**: Platform auto-detection, variable substitution with defaults, extensible registry pattern, 3-tier template hierarchy (basic/monorepo/release), comprehensive YAML validation tests. Commits: a40c191 (infrastructure + GitHub Actions), f51c169 (GitLab CI), 0fd0d4f (CircleCI), 9079251 (GitHub Actions tests), efce51f (CircleCI tests), f809d53 (docs). Cycle 93. |
| (no release) | Sailor v1.32.0-v1.34.0 Batch Migration | 2026-04-04 | Batch dependency update: sailor v1.31.0 → v1.34.0. Incorporates 3 major releases with new TUI capabilities and system integration features. **v1.32.0 - Advanced Layout Capabilities**: Nested grid layouts with automatic sizing, aspect ratio constraints (16:9, 4:3, etc.) during resize, min/max size propagation with 4 enforcement strategies, auto-margin/padding helpers (symmetric, all-sides), layout debugging inspector (tree visualization), +91 tests (total: 3478). **v1.33.0 - Specialized Widgets & Components**: LogViewer (scrollable log display with filtering/search), MetricsPanel (real-time metrics with gauge/counter/rate and thresholds), ConfigEditor (hierarchical config editing for JSON/TOML tree view), SplitPane (resizable panes with drag handles, horizontal/vertical), Breadcrumb (navigation breadcrumb trail with truncation modes), Tooltip (contextual help tooltips with 5 positioning strategies, auto-boundary detection, arrow indicators, builder pattern API), +53 tests for Tooltip widget (total: ~2516). **v1.34.0 - Terminal Clipboard & System Integration**: Clipboard Integration (OSC 52 API for writing to system clipboard with 3 selection types: clipboard, primary, system; base64-encoded transport, cross-platform support), Terminal Emulator Detection (runtime identification via env vars: xterm, kitty, iTerm2, WezTerm, Alacritty, Windows Terminal, fallback to xterm), Terminal Capability Detection (feature query system for truecolor, mouse tracking, clipboard OSC 52, bracketed paste; terminfo integration on Linux via XTGETTCAP), Enhanced Paste Bracketing (PasteHandler/PasteReader for safe multi-line paste operations with LF/CRLF/CR support, zero-allocation streaming, 10KB+ paste handling), +127 tests (total: 2901). **Migration**: All releases backward compatible with no breaking changes. Updated build.zig.zon dependency hash. **Test status**: 1285/1293 passing (100% pass rate). Closed issues #47, #48, #49. Commit: 32af276. Cycle 88. |
| (no release) | Resource Affinity & NUMA Enhancements | 2026-04-04 | Complete CPU affinity and NUMA memory allocation enforcement for fine-grained resource control in compute-intensive workflows. **Implementation** (Cycles 83-86): Work-stealing CPU affinity across ALL specified cores via `setThreadAffinityMask()` instead of single-core pinning (Cycle 83), CPU affinity validation with warnings for cores exceeding system total (Cycle 83), NUMA topology detection via `numa.detectTopology()` with fallback to single-node (Cycle 83), NumaAllocator wrapper binding memory to NUMA nodes via platform-specific APIs — Linux `mbind()` with `MPOL_BIND`, Windows reserved for `VirtualAllocExNuma`, macOS no-op (Cycle 84), NUMA-aware scheduler integration replacing 65+ uses of ctx.allocator with task_allocator in workerFn for task-scoped allocations (output buffers, checkpoint storage, cache ops, env vars, process execution, hooks, results, timeline) (Cycle 86). **Tests** (Cycle 87): 12 integration tests (tests/numa_affinity_test.zig) covering work-stealing across cores, NUMA node allocation, combined NUMA+affinity, invalid CPU IDs/nodes graceful degradation, single core pinning, parallel tasks with different NUMA nodes, duplicate CPU handling, default behavior, workflows with mixed NUMA, dependencies. 8 performance benchmarks (tests/numa_bench.zig) comparing baseline vs NUMA vs affinity vs combined with allocation-heavy workloads (100MB dd), multi-threaded tasks, overhead measurement, parallel NUMA execution. **Documentation** (Cycle 87): Comprehensive NUMA best practices in docs/guides/configuration.md — platform support details (Linux full, Windows partial, macOS best-effort), performance characteristics (overhead ~microseconds for affinity, ~10-100ns per allocation for NUMA; benefits 2-10% affinity, 20-50% NUMA), when to use NUMA (multi-socket, memory-intensive, long-running), anti-patterns (cross-node CPU/memory, short tasks), topology mapping (`numactl --hardware`), verification (`numa_maps`). **Test status**: 1285 unit tests passing. **Key insight**: Work-stealing enables load balancing while maintaining cache locality; best-effort design ensures allocation succeeds even if NUMA binding fails. Commits: 61f3e4a (affinity), 0b02908 (NUMA alloc), e8a3826 (integration), 38dfa31 (tests), fad5a25 (benchmarks), 0a32d96 (docs). Cycles 83-87. |
| (no release) | Interactive Task Picker UX | 2026-04-04 | Interactive TUI task picker for enhanced task discovery and execution. Launched when `zr run` is called without task argument. **Core features**: Real-time fuzzy search (substring + Levenshtein distance ≤3), keyboard navigation (arrows, j/k vim bindings, g/G top/bottom), metadata preview pane (cmd, description, deps, tags displayed side-by-side), task/workflow unified picker. **Implementation**: Created src/cli/task_picker.zig (560 LOC) with fuzzyFilter(), renderPreviewPane(), keyboard event handling. Integrated into main.zig for `zr run` without args. TTY detection with graceful fallback. **Search**: Press `/` to enter search mode, Esc/Enter to exit. Execute selected task with Enter, cancel with q/Esc. **Tests**: 4 unit tests (fuzzyFilter exact match, Levenshtein, empty query, no matches), 7 integration tests (non-TTY behavior, explicit task bypass, workflow picker, empty config, mixed tasks/workflows, dependencies). All 1281 unit tests passing. **Documentation**: Updated docs/guides/commands.md with picker features, keyboard shortcuts, usage examples. **Test fixes**: Fixed const/mut ArrayList mismatch in tests (lines 504, 522, 539, 554). **Commits**: 850b777 (implementation), 408628b (test fix), 6d947d1 (integration tests), 3faec18 (docs). **Future enhancements**: Multi-select mode, recent tasks highlighting, tag filtering (Tab), execution history integration (deferred). Binary builds successfully, CI green. Cycle 82. |
| (no release) | TUI Performance Optimization | 2026-04-03 | Comprehensive TUI performance profiling infrastructure using sailor v1.31.0 profiling tools. **Profiling Integration**: Integrated `TuiProfiler` into all three TUI modes — task picker (tui.zig), graph visualizer (graph_tui.zig), live execution monitor (tui_runner.zig). Added profiling scopes for render phases (drawScreen, Tree.render, List.render, Buffer.init, viewport.renderClipped, renderBuffer, buildLabels), memory tracking for buffer allocations, event processing latency measurement (keyboard, mouse, resize). Enable via `ZR_PROFILE=1` environment variable. **Benchmark Suite**: 13 comprehensive benchmarks in tests/tui_bench.zig covering all TUI modes with small/medium/large datasets (10/100/1000 tasks). Stress tests for rapid keyboard input (500 keys), mouse drag (1000 moves), window resize (50 events). Performance budgets: <16ms frame time (60 FPS), <50MB memory, <5ms p99 event latency. **Results**: All benchmarks pass with 90-99% headroom under budget. Frame times: 0.04-0.63ms avg (96-99% under budget). Memory: 24KB-4.6MB peak (91-99.9% under budget). Event latency p99: 0.49-4.63ms (7-90% under budget). **Documentation**: Created docs/guides/tui-performance.md (545 LOC) with profiling workflow, optimization techniques, performance budget violation response, TuiProfiler API reference, troubleshooting guide. **Test status**: 1277 tests passing (1269 pass, 8 skipped). **Implementation notes**: Current TUI performance already excellent, profiling infrastructure established for future optimization if needed. Commits: dc393f4 (tui.zig), 25f6c84 (graph_tui.zig), 836eb6a (tui_runner.zig). Cycle 79. |
| (no release) | Sailor v1.31.0 Migration | 2026-04-02 | Dependency update: sailor v1.30.2 → v1.31.0 (Performance Profiling & Optimization Tools). Introduces built-in performance profiling and optimization tools for TUI applications, enabling data-driven performance analysis for zr's TUI components. **Features**: Render Profiler with flame graph support (nested scope tracking, `beginScope()`/`endScope()`, `flameGraphData()` exports, self vs. total time analysis), Memory Allocation Tracker (hot spot analysis by location, peak usage monitoring, leak detection with `getHotSpots()` for top-N analysis), Event Loop Profiler (latency measurement, p95/p99 percentile tracking, slow event detection, queue depth monitoring), Widget Performance Metrics (render count tracking, cache hit/miss rates, average render duration, `recordWithCache()` for cache-aware profiling). **New APIs**: `sailor.profiler.Profiler`, `sailor.profiler.MemoryTracker`, `sailor.profiler.EventLoopProfiler`. **Documentation**: sailor repo includes `docs/optimization.md` guide with profiling best practices, performance budgets, iterative optimization workflow, and `examples/profile_demo.zig` demo. **Test status**: 1267 tests passing (1259 pass, 8 skipped, 0 failed). **Backward compatible**: No breaking changes, no code changes required. **Migration**: Updated build.zig.zon with `zig fetch --save`, +26 tests in sailor (3437 total). Closes issue #46. Commit: aae46fa. This migration enables the TUI Performance Optimization milestone. |
| (no release) | Error Message UX Enhancement | 2026-04-02 | Comprehensive error message improvements across all zr modules with standardized error codes (E001-E599), actionable hints, and enhanced UX. **Error code system**: Created src/util/error_codes.zig with ErrorCode enum (6 categories: Config E001-E099, Task E100-E199, Workflow E200-E299, Plugin E300-E399, Toolchain E400-E499, System E500-E599) and ErrorDetail struct for rich formatting (code, message, hint, context, location). **Integration**: Enhanced printUnknownCommandError() in main.zig to use ErrorDetail with [E100] error codes, suggestions with "Did you mean?" using Levenshtein distance, actionable hints (run --help, try suggested commands). **Documentation**: Created docs/guides/error-codes.md catalog with all error codes, common causes, solutions, error message format examples, color coding reference (red/yellow/cyan/green). **Tests**: Added 7 integration tests (3945-3951) verifying error codes appear, suggestions work, hints are actionable, exit codes correct. **Fixed**: Zig 0.15 format ambiguity by using manual @intFromEnum instead of custom format() method. **Test status**: 1267 tests passing (1259 pass, 8 skipped). **Manual verification**: "zr unknowncommand" shows "✗ [E100]: Unknown command", "zr rnu" suggests "zr run". Commits: e007464 (error code system), 9ec3786 (integration), 821dbf5 (docs), 1697ae6 (tests). |
| (no release) | Sailor v1.26.0-v1.30.2 Batch Migration | 2026-04-02 | Dependency update: sailor v1.25.0 → v1.30.2. Batch migration incorporating 5 major releases + 2 bug fix releases: **v1.26.0** (292 new tests, memory leak fixes in Tree/Form/Table widgets, edge case coverage), **v1.27.0** (API documentation expansion, example gallery), **v1.28.0** (ecosystem integration & polish), **v1.29.0** (99.9% API coverage — 1376/1378 documented functions), **v1.30.0** (debug_log.zig with SAILOR_DEBUG=module:level, stack_trace.zig with assertions/preconditions, 23 new tests), **v1.30.1** (attempted Zig 0.15 fix — broken), **v1.30.2** (actual Zig 0.15.2 fix via manual FlatList struct, resolved sailor issue #15). All releases backward compatible, no code changes required. **Test status**: 1252/1260 unit tests passing (100% pass rate). **Resolved blocker**: sailor issue #15 closed with fix in commit 5f7f362. Updated build.zig.zon hash. Closed zr issues #43, #45. New utilities available: debug_log (scope-based conditional logging), stack_trace (formatted panic messages). Commit: 84cef72. |
| v1.60.0 | Test Infrastructure & Quality Enhancements | 2026-04-02 | Strengthen test suite with meaningful assertions, improve test organization, and add comprehensive tooling. **Test categorization**: Added `zig build test-all` target to run all test categories (unit + integration + perf). Updated build.zig with clear documentation of all test targets (test, integration-test, test-perf-streaming, test-all). **Coverage reporting**: Created scripts/test-coverage.sh for coverage analysis — reports 93.3% file coverage (167/179 files tested), shows 1258 unit tests, 1172 integration tests, 2 fuzz tests, 1 perf test, identifies 12 untested files (mostly lang providers covered by integration tests), enforces 80% coverage threshold. **Best practices documentation**: Added comprehensive test writing guidelines to CLAUDE.md covering test categories (unit/integration/perf/fuzz), meaningful assertion patterns (test behavior not implementation), failure condition requirements, edge case coverage, TDD workflow with test-writer/zig-developer agents. **Test quality improvements**: Audited and strengthened 13 weak tests across multiple cycles (Cycles 60, 65, 69, 70, 71) — added meaningful assertions to deinit-only tests, verified field values before cleanup, improved failure scenarios. **Integration test coverage**: Verified workflow matrix execution already has comprehensive tests (tests/workflow_matrix_test.zig, 10 tests). **Test status**: 1252/1260 passing (100% pass rate), 8 skipped, 93.3% file coverage maintained. **Deferred**: Test output formatting improvements (current diagnostics sufficient for development needs). Commits: 39fe8cb (test categorization), 944e84d (best practices docs), 0394fbd (milestone progress), plus 7 commits from earlier cycles strengthening weak tests. |
| v1.59.0 | Workflow Matrix Execution | 2026-04-01 | Implement matrix execution strategy for workflows to run same tasks with different parameters. Inspired by GitHub Actions matrix strategy. **Matrix types**: Extended src/config/types.zig with MatrixExclusion/MatrixConfig structs, added matrix field to Workflow. **Matrix expansion**: Created src/exec/matrix.zig (345 LOC) with MatrixCombination hashmap, expandMatrix() for Cartesian product with exclusion filtering, 8 unit tests. **Matrix integration**: SchedulerConfig.extra_env field for matrix variable injection, buildEnvWithToolchains() merges extra_env with labeled error handling, WorkerCtx/runTaskSync/runSerialChain call chain threading. **CLI**: cmdWorkflow() sequential execution loop, --matrix-show flag displays all combinations without execution, environment injection as MATRIX_<KEY>=<value> env vars to all workflow tasks. **Integration tests**: 9 tests (3935-3944) covering single/multi-dimension expansion, Cartesian product (2x3, 3x2x2), exclusions, variable substitution (${matrix.KEY}), error cases. **Commits**: ff7f24f (types+expansion), 19b61cc (--matrix-show flag), 666aa74 (workflow integration). **Test status**: 1253/1261 passing (100% pass rate), 8 skipped. **Implementation notes**: Sequential execution strategy (parallel deferred to future), each combination runs ALL workflow stages with injected env vars, memory safety via defer blocks for env key/value cleanup. Usage: `zr workflow test --matrix-show` (preview), `zr workflow test` (execute all combinations). TOML example: `[workflows.test.matrix]` with `os = ["linux", "macos"]`, `version = ["1.0", "2.0"]`, `exclude = [{os = "macos", version = "1.0"}]`. |
| (no release) | Task Fuzzy Search & Enhanced Discovery | 2026-03-31 | Enhanced task discovery UX with fuzzy search, categorization, filtering, and introspection. **Fuzzy search**: `zr list --fuzzy <pattern>` uses Levenshtein distance (max distance: 3) to rank tasks by edit distance. **Task categorization**: `zr list --group-by-tags` groups output by task tags with untagged tasks section. **Recent tasks**: `zr list --recent[=N]` shows last N executed tasks from history (default 10). **Description search**: `zr list --search="keyword"` matches task names and descriptions. **Task introspection**: `zr which <task>` shows task definition location (file path), command, description, dependencies, tags. **Integration**: Extended cmdList() signature with group_by_tags, recent_count, search_description parameters. Updated main.zig CLI parsing (lines 656-723) with new flags. Updated MCP handlers with new parameters. **Tests**: Updated 10 existing list tests + 2 new which tests. All 1245/1253 unit tests passing (100% pass rate). **Deferred**: Interactive picker for `zr run` without arguments and fuzzy search integration tests (planned for future iteration). Core discovery features enable quick task location, historical analysis, and tag-based organization without full-text indexing. Usage: `zr list --fuzzy build`, `zr list --group-by-tags`, `zr list --recent=5`, `zr list --search="test"`, `zr which build`. |
| (no release) | NUMA Memory Information | 2026-03-30 | Completed TODO at `src/util/numa.zig:129` — implemented cross-platform memory detection for NUMA nodes. **Linux**: Parse `/sys/devices/system/node/nodeN/meminfo` for MemTotal (kB to MB conversion) via `parseMeminfoFile()`. **macOS**: Use `sysctl("hw.memsize")` to get total system memory, distributed across nodes. **Windows**: Use `GetNumaAvailableMemoryNodeEx()` API for per-node available memory. **Helpers**: `parseMeminfo()` (string parser for /proc/meminfo format, handles whitespace/missing entries), `parseMeminfoFile()` (file reader wrapper with error handling), `getTotalSystemMemory()` (cross-platform total memory detection: Linux /proc/meminfo, macOS sysctlbyname, Windows GlobalMemoryStatusEx). **Integration**: `detectLinux()` now populates `memory_mb` from per-node meminfo files, `detectWindows()` uses `getWindowsNodeMemory()` wrapper, `detectFallback()` uses `getTotalSystemMemory()` for single-node systems. **Tests**: 19 comprehensive unit tests covering meminfo parsing (kB to MB, whitespace handling, missing files, malformed content, edge cases), memory distribution across nodes (single/multi-node topologies, unequal distribution), data type validation (u64 for 8TB+ systems), case sensitivity, large values (2TB, no overflow). All 1243/1251 unit tests passing (100% pass rate). NUMA topology detection now provides actual memory information for all platforms, enabling accurate resource planning and NUMA-aware task scheduling. |
| (no release) | Graph Format Enhancements | 2026-03-30 | Completed TODO at `src/cli/graph.zig:479` — implemented ASCII/DOT/JSON formats for task graphs. **ASCII format**: Tree-style visualization with task names, descriptions, dependencies (parallel/serial/conditional/optional marked). `renderTasksAscii()` shows task count header, bullet points, dimmed commands, hierarchical dependency trees. **DOT format**: Graphviz-compatible output with node labels including descriptions, edge styles (solid/bold/dashed/dotted for different dep types), task metadata. `renderTasksDot()` generates `digraph tasks` with rankdir=LR layout. **JSON format**: Machine-readable structure with full task metadata (name, cmd, description, deps, deps_serial, deps_if, deps_optional, tags, env, timeout, resource limits). `renderTasksJson()` outputs nested JSON arrays with complete task details. **CLI integration**: `zr graph --type=tasks --format=<ascii\|dot\|json\|interactive>` consistent interface. **Legacy command fix**: Updated main.zig line 685 to detect new graph flags (--type, --format, --interactive, --watch) and delegate to full graph_cmd handler when present, maintaining backward compatibility with legacy `--ascii` flag. **Tests**: 10 integration tests (3917-3926) in tests/graph_formats_test.zig covering all formats, dependency types (serial, conditional, optional), empty configs, error cases (HTML/TUI format restrictions). All 1224/1232 unit tests passing. Usage examples: `zr graph --type=tasks --format=ascii` (task list), `zr graph --type=tasks --format=dot > graph.dot` (Graphviz), `zr graph --type=tasks --format=json` (programmatic). |
| v1.58.0 | Post-v1.0 Enhancements: Task Estimation, Validation, Visualization | 2026-03-30 | **🎯 THREE MAJOR FEATURE MILESTONES** — (1) **Task Estimation & Time Tracking**: Statistical analysis module (src/history/stats.zig) with percentile calculations (p50/p90/p99), standard deviation, anomaly detection (2x p90 threshold). Enhanced `zr estimate` command with per-task and workflow estimation (critical path calculation for parallel stages). Duration estimates in `zr list` and `zr run --dry-run` output. TUI progress bars with ETA display based on historical averages (formatDuration, dynamic updates). 9 new unit tests for ETA calculations. (2) **Configuration Validation Enhancements**: Expression validation using `expr.evalConditionWithDiag` for task conditions and deps_if. Performance warnings: >100 tasks, deep dependency chains (>10 levels with recursive depth calculation). Plugin schema validation (required source field, protocol/path format checks). Import collision warnings. Strict mode enhancement: `--strict` now treats warnings as errors (exit code 1 for CI). 7 new integration tests (3900-3906). Enhanced `src/cli/validate.zig` with comprehensive error reporting. (3) **Interactive Workflow Visualizer**: Interactive HTML/SVG-based task graph visualization with D3.js. Features: click nodes for task details (cmd/description/deps/env/tags/duration), color-coded status (success/failed/pending/unknown from execution history), critical path highlighting (longest chain with recursive BFS depth calculation), filter controls (regex search, status filter, tag filter), export to SVG/PNG, zoom/pan/drag with D3 behaviors, responsive dark theme design. Implementation: src/cli/graph_interactive.zig (core renderer), src/cli/graph.zig (GraphType enum, --interactive flag), tests/graph_interactive_test.zig (10 integration tests 3907-3916). Usage: `zr graph --interactive > workflow.html`. Standalone HTML with D3.js v7 CDN, no external dependencies. **Total**: 1224/1232 unit tests passing (100% pass rate), 24 new integration tests, +1,500 LOC, 47 commits. |
| v1.57.0 | Phase 13C: v1.0-Equivalent Release | 2026-03-26 | **🎉 FEATURE-COMPLETE v1.0-EQUIVALENT RELEASE — ALL PHASE 1-13 OBJECTIVES COMPLETE** Updated README.md with comprehensive Phase 9-13 feature breakdown, performance benchmarks, and comparison tables. Version badge updated to v1.57.0. Created comprehensive release notes (RELEASE_NOTES_v1.57.0.md) covering all Phase 9-13 features. Updated CHANGELOG.md with detailed Phase 9-13 additions. Verified all tests pass (1151/1159 unit tests, 30+ integration scenarios). Reviewed open issues (3 zuda migrations, all enhancement, none blocking). Version bumped to 1.57.0 (monotonic from 1.56.0). GitHub release prepared. **This release marks the completion of the 13-phase PRD roadmap** (Foundation, Task Runner, Workflows, Resource Management, Extensibility, Monorepo Intelligence, Developer Environment, Multi-repo & Remote Cache, Enterprise & Community, AI Integration, LSP Server, Performance & Quality, Migration & Documentation). Production-ready developer platform status achieved. |
| (no release) | Phase 13A: Documentation Review & Validation | 2026-03-26 | Comprehensive documentation review for v1.0 release. Updated version references (v1.56.0) in getting-started.md and README.md. Fixed broken cross-reference (expressions.md → configuration.md). Created benchmarks.md guide documenting Phase 12C performance benchmarks. Verified all configuration examples parse correctly. All 8 guides (getting-started, configuration, commands, benchmarks, mcp-integration, lsp-setup, migration, adding-language) validated and current. |
| (no release) | Phase 12C: Benchmark Dashboard | 2026-03-26 | Comprehensive benchmark suite in `benchmarks/` directory. Performance comparison against Make, Just, and Task across binary size, cold start, config parsing, parallel execution, memory usage, and real-world scenarios. Results documented in benchmarks/RESULTS.md with analysis. Test scripts: run_benchmarks.sh, benchmark.sh. zr achieves Make-level performance (~4-8ms cold start, ~2-3MB memory) with 10x more features. |
| (no release) | Phase 13B: Migration Tools | 2026-03-26 | Automatic config conversion from existing task runners to zr.toml. CLI flags: `--from-make`, `--from-just`, `--from-task` in `zr init` command. Migration modules: src/migrate/makefile.zig, justfile.zig, taskfile.zig. Parses Makefile targets, Justfile syntax, Taskfile.yml and generates equivalent zr.toml with tasks, dependencies, and commands. Enables easy migration from competing tools. |
| (no release) | Sailor v1.21.0 & v1.22.0 Migration | 2026-03-26 | Dependency update: sailor v1.20.0 → v1.22.0. v1.21.0: DataSource abstraction, large data benchmarks. v1.22.0: Rich text rendering, markdown parser, line breaking/hyphenation, text measurements (+123 tests). No breaking changes, backward compatible. Commit: 4176ca4 |
| v1.56.0 | Windows Platform Enhancements | 2026-03-26 | Windows Console API-based non-blocking mouse read (WaitForSingleObject + ReadConsoleInput + PeekConsoleInputW), 21 Windows integration tests (console encoding, process spawning, env vars, file system, CLI, TUI), PowerShell completion script (Register-ArgumentCompleter), total 30 Windows tests (9 paths + 21 general). Commits: 69d161d (mouse timeout), 1ddb130 (integration tests), 0bdfeb6 (PowerShell completion) |
| v1.55.0 | Enhanced Configuration System | 2026-03-26 | Multi-file imports ([imports] files), .env auto-loading, ${VAR} variable substitution in cmd/cwd/env, 33 integration tests (15 imports + 18 dotenv/varsubst), 72 unit tests (37 dotenv + 35 varsubst). Commits: 0ba2a02 (imports), 264ebc4 + e2b5692 (.env), b968828 (varsubst integration) |
| v1.54.0 | TUI Mouse Interaction Enhancements | 2026-03-25 | Non-blocking read with timeout (POSIX termios), event batching for rapid mouse movement, double-click detection, drag-to-scroll in graph TUI, mouse wheel navigation, 13 unit tests + 3 integration tests |
| v1.53.0 | Platform-Specific Resource Monitoring | 2026-03-25 | Windows NUMA topology (GetLogicalProcessorInformationEx), Linux /proc stats, macOS task_info/proc_pidinfo, NUMA-aware CPU affinity, profiler module, 40 tests (25 NUMA, 10 profiler, 5 affinity, 15 integration) |
| v1.52.0 | Output Enhancement & Pager Integration | 2026-03-25 | Automatic pager for large output, --no-pager flag, ZR_PAGER/PAGER env vars, TTY detection, color preservation, 36 tests |
| v1.51.0 | Sailor v1.19.0 & v1.20.0 Migration | 2026-03-25 | Progress bar templates, environment variable config, color themes, table formatting, arg groups, Windows Unicode tests, pattern documentation |
| v1.50.0 | Cross-Platform Path Handling Audit | 2026-03-24 | Path separator fixes (glob/affected/workspace), UNC path support, long path support (>260 chars), symlink resolution, 11 Windows integration tests |
| v1.49.0 | Task Output Streaming Improvements | 2026-03-22 | Incremental rendering, follow mode, gzip compression, <50MB memory for 1GB+ files, perf test API fixes |
| v1.48.0 | Shell Integration Enhancements | 2026-03-21 | Smart cd command, shell hooks (bash/zsh/fish), command abbreviations, 34 integration tests (abbreviations, alias, cd) |
| v1.47.0 | Task Retry Strategies & Backoff Policies | 2026-03-19 | Configurable retry strategies: backoff multiplier, jitter, max backoff ceiling, conditional retry (retry_on_codes, retry_on_patterns), integration tests |
| v1.46.0 | Remote Execution & Distributed Builds | 2026-03-18 | SSH/HTTP remote task execution, remote/remote_cwd/remote_env fields, scheduler integration, 9 integration tests |
| v1.45.0 | TOML Syntax Highlighting | 2026-03-17 | Syntax-highlighted TOML error messages, error_display utility, color-coded diagnostics for validate command |
| v1.44.0 | Version Fix (v1.0.0 revert) | 2026-03-16 | Reverted erroneous v1.0.0 version downgrade, added version monotonicity guard to release policy |
| v1.43.0 | Sailor v1.15.0 Migration | 2026-03-16 | Thread safety fixes, XTGETTCAP terminal capability detection, platform-specific testing, memory leak fixes, multi-platform CI |
| v1.39.0 | Sailor v1.14.0 Migration | 2026-03-16 | Memory pooling, render profiling, virtual widget rendering, incremental layout solver, buffer compression |
| v1.38.0 | Task Output Search & Filtering | 2026-03-16 | Search/filter/head/tail flags for show --output, color highlighting, 7 integration tests |
| v1.37.0 | Enhanced Task Output Capture & Streaming | 2026-03-16 | OutputCapture module with stream/buffer/discard modes, scheduler integration, TUI live display, `zr show --output` command, 13 integration tests |
| v1.34.0 | Workflow Retry Budget Integration | 2026-03-14 | Workflow-level retry budget fully functional with scheduler integration and multi-stage support |
| v1.33.0 | Advanced TUI Data Visualization | 2026-03-14 | Sailor v1.6.0/v1.7.0 data visualization widgets (Histogram, TimeSeriesChart, ScatterPlot) with FlexBox layout |
| v1.32.0 | Sailor v1.11.0 & v1.12.0 Migration | 2026-03-14 | Particle effects, blur/transparency, session recording, audit logging, WCAG AAA themes, screen reader enhancements |
| v1.31.0 | Checkpoint/Resume for Long-Running Tasks | 2026-03-13 | Checkpoint storage infrastructure, task stdout monitoring for markers, resume via ZR_CHECKPOINT env var |
| v1.30.0 | Enhanced Error Recovery | 2026-03-13 | Circuit breaker pattern, retry budget for workflow-level limiting, enhanced scheduler error recovery |
| v1.29.0 | Task Template System | 2026-03-13 | Reusable task templates with parameter substitution, CLI commands (list/show/apply) |
| v1.28.0 | Interactive TUI with Mouse Support | 2026-03-12 | Mouse click/scroll support in task picker, graph TUI, and live execution TUI via sailor v1.10.0 |
| v1.27.0 | Real-time Resource Monitoring | 2026-03-12 | Live TUI dashboard with ASCII bar charts for CPU/memory, task status table, bottleneck detection |
| v1.26.0 | Language Provider Expansion | 2026-03-11 | Added C# (.NET) and Ruby language providers, 10 total languages supported |
| v1.25.0 | Interactive TUI Config Editor | 2026-03-11 | Interactive prompt-based config editor with `zr edit task/workflow/profile` commands |
| v1.24.0 | Execution Hooks | 2026-03-11 | Pre/post task hooks (on_before, on_after, on_success, on_failure, on_timeout) with TOML parser and scheduler integration |
| v1.23.0 | Shell Auto-Completion v2 | 2026-03-10 | Context-aware shell completion with dynamic task/profile/member name suggestions |
| v1.22.0 | Sailor v1.6.0 & v1.7.0 Migration | 2026-03-09 | Data visualization widgets, FlexBox layout, viewport clipping, shadow effects, layout caching |
| v1.21.0 | TUI Testing & Enhancements | 2026-03-09 | MockTerminal snapshot tests for all TUI modes (runner, graph, list), 19 new unit tests |
| v1.20.0 | Expression Diagnostics Integration | 2026-03-09 | DiagContext integration into expression evaluator, 17 eval functions with push/pop stack tracking |
| v1.19.0 | Parser Enhancements v3 | 2026-03-09 | Inline workflow stages syntax, dependency-only tasks without cmd, subsection ordering fix |
| v1.18.0 | Conditional Task Execution | 2026-03-08 | Git predicates (git.branch/tag/dirty), skip_if/output_if fields, expression engine extensions |
| v1.17.0 | Advanced Watch Mode | 2026-03-08 | Debouncing, pattern-based watch filters, multi-pattern support, TOML watch configuration |
| v1.16.0 | Task Execution Analytics | 2026-03-07 | Resource usage tracking (peak memory, avg CPU), enhanced analytics reports (HTML/JSON) |
| v1.15.0 | Workspace Enhancements | 2026-03-07 | Workspace-wide cache invalidation, member-specific cache clearing, sailor v1.5.0 migration |
| v1.14.0 | Enhanced Error Diagnostics | 2026-03-06 | Task execution timeline, failure replay mode |
| v1.13.0 | Parallel Execution Optimizations | 2026-03-05 | Work-stealing deque, NUMA topology detection, cross-platform CPU affinity |
| v1.12.0 | TOML Parser v2 | 2026-03-03 | Auto-generate stage names for anonymous workflow stages, validation warning removal |
| v1.11.0 | Plugin Registry Index Server | 2026-03-03 | Independent index server with REST API, plugin metadata, search endpoints |
| v1.10.0 | Task Dependencies v2 | 2026-03-02 | Conditional dependencies (deps_if), optional dependencies (deps_optional), expression engine integration |
| v1.9.0 | Sailor v1.1.0 Accessibility | 2026-03-02 | Unicode width improvements (CJK/emoji), TUI keyboard navigation, accessibility features |
| v1.8.0 | Toolchain Auto-Update | 2026-03-02 | `zr tools upgrade --check-updates`, `--cleanup` flag for version conflict resolution |
| v1.7.0 | Performance Enhancements | 2026-03-02 | String interning (StringPool), object pooling (ObjectPool), 30-50% memory reduction |
| v1.6.0 | Interactive Configuration | 2026-03-02 | `zr add task/workflow/profile` interactive commands, smart stdin handling |
| v1.5.0 | Remote Cache v2 | 2026-03-02 | Gzip compression, incremental sync, cache statistics dashboard |
| v1.4.0 | Plugin Registry Client | 2026-03-02 | HTTP client, remote search `--remote` flag, graceful fallback |
| v1.3.0 | TUI Graph Visualization | 2026-03-02 | Tree widget-based graph TUI mode, sailor v1.0.3 migration |
| v1.2.0 | TOML Parser Improvements | 2026-03-01 | Strict validation, malformed section header detection, error message improvements |
| v1.1.0 | Sailor v1.0.2 Migration | 2026-02-28 | Dependency update, API refactoring, local TTY workaround, theme system review |

---

## Milestone Establishment Process

미완료 마일스톤이 **2개 이하**가 되면, 에이전트가 자율적으로 새 마일스톤을 수립한다.

**입력 소스** (우선순위 순):
1. `gh issue list --state open --label feature-request` — 사용자 요청 기능
2. `docs/PRD.md` — 아직 구현되지 않은 PRD 항목 (Phase 5-8의 미구현 세부사항)
3. 의존성 업데이트 — sailor, Zig 새 버전 등
4. 기술 부채 — Known Limitations, TODO, 성능 병목
5. 경쟁 도구 분석 — just, task, make 대비 누락된 기능

**수립 규칙**:
- 마일스톤 하나는 **단일 테마**로 구성 (여러 작은 기능을 하나의 주제로 묶음)
- 1-2주 내 완료 가능한 범위로 스코프 설정
- 마일스톤은 **이름(테마)으로 관리**하며, 버전 번호는 **릴리즈 시점에 결정**한다
- 릴리즈 시 버전: `build.zig.zon`의 현재 버전 + 1 (마일스톤에 미리 적힌 번호는 참고용)
- **건너뛰기 금지**: 차단된 마일스톤을 건너뛰고 미래 버전을 릴리즈하지 않는다. 차단된 마일스톤은 차단 해제 시까지 대기하고, 다른 작업을 먼저 릴리즈한다 (순차 번호로)
- 수립 후 이 파일의 Active Milestones에 추가하고 커밋: `chore: add milestone <이름>`

---

## Dependency Migration Tracking

### Sailor Library

- **Current in zr**: v2.4.0 (all migrations complete through v2.4.0)
- **Next**: v2.5.0+ (when released)
- **Repository**: https://github.com/yusa-imit/sailor

| Sailor Version | Status | Summary |
|---------------|--------|---------|
| v0.1.0 | DONE | arg parsing, color module |
| v0.2.0 | DONE | progress module |
| v0.3.0 | DONE | fmt/JSON module |
| v0.4.0 | DONE | TUI framework |
| v0.5.0 | DONE | Advanced widgets (deferred), Windows cross-compile fix |
| v1.0.0-v1.0.3 | DONE | Production ready, Tree widget Zig 0.15.2 fix |
| v1.1.0 | DONE | Accessibility, Unicode width (CJK/emoji), keyboard navigation |
| v1.2.0 | DONE | Grid layout, ScrollView, overlay/z-index, responsive breakpoints |
| v1.3.0 | DONE | RenderBudget, LazyBuffer, EventBatcher, DebugOverlay |
| v1.4.0 | DONE | Form widget, Select/Dropdown, Checkbox, RadioGroup, Validators |
| v1.5.0 | DONE | MockTerminal snapshot testing, Event bus, Command pattern |
| v1.6.0 | DONE | ScatterPlot, Histogram, TimeSeriesChart (data visualization, consumed in v1.22.0) |
| v1.6.1 | DONE | PieChart overflow fix, API compilation fixes |
| v1.7.0 | DONE | FlexBox layout, viewport clipping, shadow effects, layout caching (consumed in v1.22.0) |
| v1.8.0 | DONE | HttpClient, WebSocket, AsyncEventLoop, TaskRunner, LogViewer (features available, no zr milestone needed) |
| v1.9.0 | DONE | WidgetDebugger, PerformanceProfiler, CompletionPopup, ThemeEditor |
| v1.10.0 | DONE | Mouse event handling (SGR), widget mouse interaction, gamepad/touch |
| v1.11.0 | DONE | Particle effects, blur/transparency, Sixel/Kitty graphics, transitions |
| v1.12.0 | DONE | Session recording, audit logging, WCAG AAA themes, screen reader |
| v1.13.0 | READY | Syntax highlighting, code editor, autocomplete, multi-cursor, rich text |
| v1.13.1 | DONE | Integer overflow fix for data visualization widgets |
| v1.14.0 | DONE | Memory pooling, render profiling, virtual widget rendering, incremental layout, buffer compression |
| v1.15.0 | DONE | Thread safety fixes, XTGETTCAP terminal capability detection, memory leak audit, multi-platform CI |
| v1.16.0 | DONE | Terminal capability database, bracketed paste mode, synchronized output protocol, hyperlink support (OSC 8), focus tracking |
| v1.17.0 | DONE | Hot reload improvements, widget performance enhancements |
| v1.18.0 | DONE | Hot reload for themes, widget inspector, benchmark suite, example gallery, documentation generator |
| v1.19.0 | DONE | Progress bar templates, environment variable config, color themes, table formatting, arg groups |
| v1.20.0 | DONE | Windows Console Unicode tests, pattern documentation, quality improvements |
| v1.21.0 | DONE | Streaming & Large Data — DataSource abstraction, large dataset benchmarks |
| v1.22.0 | DONE | Rich Text & Formatting — markdown parser, line breaking/hyphenation, text measurements |
| v1.23.0 | DONE | Plugin Architecture & Extensibility — widget trait system, custom renderer hooks, theme plugins, composition helpers (Padding, Centered, Aligned, Stack, Constrained) |
| v1.24.0 | DONE | Animation & Transitions — 22 easing functions, Animation/ColorAnimation structs, Timer/TimerManager, transition helpers |
| v1.25.0 | DONE | Form & Validation — form widget with multi-field container, 15+ validators, input masks, password masking, Tab navigation |
| v1.26.0-v1.30.2 | DONE | Batch migration (Cycle 75) — testing, quality, documentation, debugging enhancements |
| v1.31.0 | DONE | Performance Profiling & Optimization — flame graphs, memory allocation tracker, event loop profiler, widget metrics (Cycle 77, commit aae46fa, issue #46) |
| v1.32.0 | DONE | Advanced Layout Capabilities — nested grids, aspect ratio constraints, min/max size propagation, auto-margin/padding, layout debugging (Cycle 88, commit 32af276, issue #47) |
| v1.33.0 | DONE | Specialized Widgets — LogViewer, MetricsPanel, ConfigEditor, SplitPane, Breadcrumb, Tooltip (Cycle 88, commit 32af276, issue #48) |
| v1.34.0 | DONE | Terminal Clipboard & System Integration — OSC 52 clipboard API, terminal detection, capability detection, paste bracketing (Cycle 88, commit 32af276, issue #49) |
| v1.35.0 | DONE | Accessibility Overhaul — ARIA attributes (30+ roles), focus trap, keyboard shortcuts, screen reader support (Cycle 101) |
| v1.36.0 | DONE | Performance Monitoring System — render/memory/event metrics, MetricsDashboard widget, regression tests (Cycle 101, issue #50) |
| v1.37.0 | DONE | v2.0.0 API Bridge — stateless widget lifecycle standardization (Block.init() → Block{}), deprecation warning system, style inference helpers (Cycle 108, issue #51) |
| v2.1.0 | DONE | Drop-in performance optimizations (+38% buffer diff, +34% fill, +33% set), ergonomic APIs (Rect.fromSize, constraint/color constructors) (Cycle 159, issue #54) |
| v2.3.0 | DONE | Scrollable widgets, state persistence, advanced styling (gradients, dashed borders, shadows), performance (LazyBuffer, VirtualList) (Cycle 188, issue #55) |
| v2.4.0 | DONE | Testing infrastructure (snapshot testing, property-based testing, visual regression, mock terminal, test utilities) (Cycle 188, issue #56) |

### zuda Library

- **Current**: Not yet integrated — **READY for migration** (zuda v1.15.0 available)
- **Repository**: https://github.com/yusa-imit/zuda
- **Compatibility layers**: `zuda.compat.zr_dag` — drop-in DAG/topo sort/cycle detection wrapper
- **Migration guides**: See zuda `docs/migrations/ZR_GRAPH.md` for detailed API mapping

| Custom Implementation | File | LOC | zuda Replacement | Issue | Status |
|----------------------|------|-----|-----------------|-------|--------|
| DAG | `src/graph/dag.zig` | 187 | `zuda.compat.zr_dag` or `zuda.containers.graphs.AdjacencyList` | #23 | **READY** |
| Topological Sort (Kahn's) | `src/graph/topo_sort.zig` | 323 | `zuda.algorithms.graph.topological_sort` | #24 | **READY** |
| Cycle Detection | `src/graph/cycle_detect.zig` | 205 | `zuda.algorithms.graph.cycle_detection` | #24 | **READY** |
| Work-Stealing Deque | `src/exec/workstealing.zig` | 130 | `zuda.containers.queues.WorkStealingDeque` | #22 | **READY** |
| Levenshtein Distance | `src/util/levenshtein.zig` | 214 | `zuda.algorithms.dynamic_programming.editDistance` | #21 | **DONE** |
| Glob Pattern Matching | `src/util/glob.zig` | 472→7 | `zuda.algorithms.string.globMatch` | #25 | **DONE** |

**Migration exclusions** (domain-specific, kept in zr):
- `src/util/string_pool.zig` — zr-specific string interning
- `src/util/object_pool.zig` — zr-specific object pooling
- `src/graph/ascii.zig` — zr-specific ASCII graph renderer
