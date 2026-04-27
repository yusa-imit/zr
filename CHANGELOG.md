# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.79.0] - 2026-04-28

### Added
- **Task Documentation & Rich Help System** — Comprehensive task documentation with structured metadata
  - **Rich descriptions**: Support for `description.short` and `description.long` with multiline text
  - **Task examples**: `examples = ["zr run build", "zr run build --release"]` for usage examples in help
  - **Output documentation**: `outputs` table to document files/artifacts tasks produce
  - **Related tasks**: `see_also = ["test", "deploy"]` for cross-referencing related tasks
  - **Help command**: `zr help <task>` displays formatted help with all metadata (descriptions, params, examples, outputs, deps)
  - **List --verbose flag**: `zr list --verbose` shows descriptions and metadata in task listing
  - **Backward compatibility**: Simple string descriptions still work (`description = "Build the project"`)

### Documentation
- Added comprehensive `docs/guides/task-documentation.md` (704 LOC)
  - Complete guide to task documentation best practices
  - Real-world examples (build pipelines, test suites, multi-env deployment, data processing)
  - Documentation patterns and standards
  - Migration guides from make/just/Task/npm
  - Comparison with other CLI documentation tools (make, just, Task, npm)
  - Troubleshooting guide (5 common issues)
  - Future enhancements roadmap (type annotations, searchable docs, diagrams)

### Implementation Details
- **types.zig**: TaskDescription union type for rich/simple descriptions (~85 LOC)
- **parser.zig**: Parse description.short/long, examples array, outputs table, see_also (~146 LOC)
- **list.zig**: --verbose flag integration (~23 LOC)
- Total implementation: ~254 LOC across 3 commits (Cycles 172-174, 177)

### Tests
- Added 63 integration tests for task documentation (~2084 LOC)
  - 29 tests in task_documentation_test.zig (help command, list verbose, edge cases, feature integration)
  - 34 tests in task_documentation_parser_test.zig (rich descriptions, examples, outputs, see_also, error cases)
  - Comprehensive coverage of parsing, display, and backward compatibility

### Stats
- **Total**: ~3042 LOC across 5 cycles (Cycles 172-174, 177, 179)
  - Implementation: 254 LOC
  - Tests: 2084 LOC (63 integration tests)
  - Documentation: 704 LOC
- All unit tests passing (1484/1492, 8 skipped, 0 failed)

## [1.78.0] - 2026-04-26

### Added
- **Enhanced Environment Variable Management** — Complete .env file support with variable interpolation
  - `.env file loading`: `env_file = ".env"` or `env_file = [".env.local", ".env"]` for loading environment variables from files
  - **Variable interpolation engine**: Support for `${VAR}`, `$VAR`, and `$$` escape sequences in .env values
  - **Recursive expansion**: Variables can reference other variables (e.g., `VAR1=${VAR2}`, `VAR2=value`)
  - **Cross-file expansion**: Variables in later .env files can reference variables from earlier files
  - **Circular reference detection**: Prevents infinite loops when variables reference each other
  - **Priority system**: Task env > env_file > system env (later files override earlier)
  - **CLI --show-env flag**: `zr list --show-env` and `zr run --show-env` for debugging effective environment
  - **Workspace inheritance**: Child tasks inherit parent workspace env_file settings
  - **Comprehensive .env format support**: Comments (#), blank lines, quoted values, special characters
  - **Error handling**: Graceful handling of missing files, invalid format, undefined variables

### Documentation
- Added comprehensive `docs/guides/environment-management.md` (650 LOC)
  - Complete .env file format specification
  - Variable interpolation syntax and examples
  - Priority and merging system documentation
  - Real-world examples (multi-env deployment, secrets management, Docker integration, monorepo)
  - Best practices (security, validation, naming conventions)
  - Troubleshooting guide (7 common issues)
  - Comparison with other tools (dotenv libraries, docker-compose, make, just/Task)
  - Migration guides (from inline env, docker-compose, make, shell scripts)

### Tests
- Added 27 integration tests for environment variable management (~495 LOC)
  - 13 tests for .env file loading (single/multiple files, priority, inheritance, special chars)
  - 14 tests for variable interpolation (${VAR}, $VAR, $$, recursive, cross-file, circular refs, undefined vars)
  - All tests passing with comprehensive coverage of edge cases

### Implementation Details
- **env_loader.zig**: .env file parser with `parseEnvFile()` and `interpolateEnvValue()` (~140 LOC)
- **scheduler.zig**: Runtime .env loading with `loadAndMergeEnvFiles()` (~45 LOC)
- **types.zig**: Schema changes for `env_file` field (single string or array)
- **parser.zig**: TOML parsing for env_file field
- **CLI integration**: --show-env flag in main.zig, run.zig, list.zig (~83 LOC)
- Total implementation: ~268 LOC across 5 commits (Cycles 168-171)

### Stats
- **Total deliverables**: ~1413 LOC (268 impl + 495 tests + 650 docs)
- **Unit tests**: 1483/1491 passing (8 skipped, 0 failed)
- **Integration tests**: 27 new env-related tests
- **Milestone completion**: 1 development cycle

## [1.77.0] - 2026-04-25

### ⚡ Enhanced Task Filtering & Selection Patterns (Complete)

This release introduces powerful task filtering capabilities with glob patterns and tag-based selection, enabling developers to run multiple tasks efficiently without writing complex shell scripts. Monorepos, CI/CD pipelines, and large projects can now execute task subsets declaratively.

### Added

**Core Feature: Task Filtering** (Cycles 163-164)
- `zr run 'test:*'` — glob pattern matching with `*` (single-level wildcard)
- `zr run 'backend:**'` — multi-level glob matching with `**` (recursive)
- `zr run 'build*'` — prefix matching with `*` and `?` wildcards
- `--tag=name` CLI flag for tag-based filtering (repeatable for AND logic)
- `--exclude-tag=name` CLI flag for tag exclusion
- Combined filters: `zr run 'backend:**' --tag=api --exclude-tag=deprecated`
- Multiple task execution with dependency-aware ordering
- Dry-run preview shows selected tasks before execution
- Helpful error messages when no tasks match filters
- ~219 LOC implementation (task_selector.zig module + CLI integration)

**Testing** (Cycle 163)
- 16 integration tests covering all filter combinations:
  - 6 tests for glob patterns (single-level `*`, multi-level `**`, prefix/suffix)
  - 4 tests for tag filtering (single tag, multiple tags AND, exclusion)
  - 6 tests for combined filters (glob + tags, complex scenarios, edge cases)
- All 1452 unit tests passing (8 skipped, 0 failed)
- Total: ~379 LOC of integration tests

**Documentation** (Cycle 164)
- Comprehensive guide at `docs/guides/task-selection.md` (~635 LOC)
- Real-world examples: monorepos, CI/CD pipelines, environment-specific builds, test suites
- Comparison with competitors: Bazel, Nx, Task, Just
- Best practices: namespace organization, tagging taxonomy, dry-run workflows
- Troubleshooting: no matches, pattern syntax, tag spelling, execution order

**Stats**:
- **Total deliverable**: ~1233 LOC (219 impl + 379 tests + 635 docs)
- **Commits**: 3 phases across Cycles 163-164
- **Breaking changes**: None — fully backward compatible

**Examples**:
```toml
# Run all backend tests
zr run 'backend:test:*'

# Run critical integration tests only
zr run 'test:**' --tag=critical --exclude-tag=slow

# Build all services except deprecated ones
zr run 'services:*:build' --exclude-tag=deprecated
```

**Use Cases**:
- **Monorepos**: `zr run 'apps/frontend:**' --tag=build` — build all frontend apps
- **CI/CD**: `zr run 'test:**' --tag=smoke --exclude-tag=flaky` — run smoke tests only
- **Environment-specific**: `zr run 'deploy:*' --tag=production` — deploy prod services
- **Test suites**: `zr run 'test:**' --exclude-tag=slow --exclude-tag=integration` — fast unit tests

### Changed
- `zr run` now accepts glob patterns in task names (backward compatible)
- Multiple tasks can be executed in a single command with dependency resolution

### Improved
- Error messages now suggest similar task names when no matches found
- Task execution order respects dependencies even with glob patterns

## [1.76.0] - 2026-04-24

### ⚡ Task Conditional Dependencies Enhancement (Complete)

This release completes the conditional dependency system with full expression evaluation, enabling sophisticated task execution patterns based on environment variables, runtime parameters, and task tags. Build pipelines can now adapt behavior dynamically without duplicating task definitions.

### Added

**Core Feature: Conditional Dependencies** (Cycles 160-161)
- `deps_if = [{ task = "setup", condition = "env.NODE_ENV == 'production'" }]` — conditional task dependencies
- Expression engine with full operator support: `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `||`, `!`, `()`
- `params.param_name` access for parameter-based conditions (e.g., `params.skip_tests != 'true'`)
- `has_tag('tag-name')` function for tag-based conditional dependencies
- `env.VAR_NAME` access for environment variable conditions
- Dry-run preview: `zr run --dry-run` shows which conditional deps are included/excluded
- Watch mode integration: file watcher automatically evaluates conditional dependencies
- ~283 LOC implementation (expression.zig enhancements, scheduler.zig integration)

**Testing** (Cycles 160-161)
- 33 integration tests covering all condition types and edge cases:
  - 15 tests for runtime behavior (env-based, param-based, tag-based, combined, negation)
  - 18 tests for dry-run preview (all condition types, complex expressions, error cases)
- All 1452 unit tests passing (8 skipped, 0 failed)
- Total: ~1088 LOC of integration tests

**Documentation** (Cycle 161)
- Comprehensive guide at `docs/guides/conditional-dependencies.md` (~680 LOC)
- Real-world examples: multi-environment deploys, optional features, platform-specific tasks
- Expression syntax reference, condition patterns, best practices, troubleshooting
- Migration examples from static dependencies

**Stats**:
- **Total deliverable**: ~2051 LOC (283 impl + 1088 tests + 680 docs)
- **Commits**: 6 phases across Cycles 160-161
- **Breaking changes**: None — fully backward compatible

**Examples**:
```toml
# Skip tests via runtime parameter
[tasks.deploy]
cmd = "deploy.sh"
params = [{ name = "skip_tests", default = "false" }]
deps_if = [
  { task = "tests", condition = "params.skip_tests != 'true'" }
]

# Production-only database migration
[tasks.app]
cmd = "app.sh"
deps_if = [
  { task = "db-migrate", condition = "env.NODE_ENV == 'production'" }
]

# Docker build only when tagged
[tasks.deploy]
cmd = "deploy.sh"
tags = ["docker"]
deps_if = [
  { task = "docker-build", condition = "has_tag('docker')" }
]

# Complex conditions with negation and logic
[tasks.integration-test]
cmd = "test.sh"
deps_if = [
  { task = "docker-setup", condition = "!env.CI && has_tag('docker')" },
  { task = "mock-services", condition = "env.CI || params.use_mocks == 'true'" }
]
```

## [1.73.0] - 2026-04-21

### ⚡ Task Aliases & Silent Mode (Complete)

This release adds task aliases for intuitive CLI shortcuts and silent mode for reduced noise from well-behaving tasks. You can now run `zr run b` instead of `zr run build`, and suppress output from setup/formatting tasks that only matter when they fail.

### Added

**Core Feature: Task Aliases** (Cycles 144, 147)
- `aliases = ["b", "compile"]` field in task definition — provide multiple names for any task
- Alias resolution with priority: exact task name > exact alias > prefix on task name > prefix on alias
- `zr list` displays aliases: `build [aliases: b, compile]`
- `zr list --json` includes `"aliases": ["b", "compile"]` field
- Conflict detection: error if alias conflicts with existing task name or duplicate across tasks
- Integration with prefix matching, task history, and shell completion
- ~95 LOC implementation (parser.zig, types.zig, run.zig, list.zig, loader.zig)

**Core Feature: Silent Mode** (Cycles 144, 146)
- `silent = true` task field — suppress stdout/stderr unless task fails (exit code != 0)
- Buffered output on success (discarded), full output shown on failure for debugging
- Global `--silent` / `-s` flag overrides task-level `silent=false` (OR logic semantics)
- Works with workflows: `zr workflow --silent ci-pipeline` suppresses all tasks
- Integration with retries (buffer until final failure), log levels (`--verbose` overrides)
- ~60 LOC implementation (scheduler.zig, main.zig, interactive_run.zig, tui.zig, mcp/handlers.zig)

**Testing** (Cycles 145, 147)
- 12 integration tests in `tests/task_aliases_test.zig`:
  - Alias resolution (exact, prefix), list/JSON display, conflict detection
  - Global --silent flag (success, failure, short form -s, override, workflow)
- 3 unit tests in `src/config/loader.zig`: alias validation (valid, task name conflict, duplicate)
- 8 integration tests in `tests/silent_mode_test.zig` (from Cycle 145)
- All 1430 unit tests passing (8 skipped)

**Documentation** (Cycle 147)
- New section: **Task Aliases (v1.73.0)** in `docs/guides/configuration.md` (~200 LOC)
  - Basic usage, alias resolution priority, display format, conflict detection
  - Use cases: common shortcuts, multi-language projects, semantic aliases
  - Best practices: short & memorable, semantic names, consistent patterns
- New section: **Silent Mode (v1.73.0)** in `docs/guides/configuration.md` (~150 LOC)
  - Task-level silent mode, global --silent/-s flag, override semantics
  - Example: quiet build pipeline with selective output
  - Integration with retries, interactive tasks, workflows, log levels
  - Use cases (setup, codegen, formatting, health checks), best practices, semantics table
- Updated Task Fields table with `aliases` and `silent` fields

### Implementation Summary
- **Total**: ~450 LOC implementation, ~310 LOC tests, ~350 LOC docs
- **Commits**: 51d9265 (alias conflict detection), a8913ef (integration tests), abccd88 (docs)
- **Backward Compatible**: All existing configs work without changes
- **Ready for**: v1.73.0 release

## [1.72.0] - 2026-04-19

### 📚 Documentation Site & Onboarding Experience (Complete)

This release delivers a comprehensive documentation overhaul with cohesive organization, clear navigation, and production-ready reference materials. New users can quickly get started, and experienced users have detailed references at their fingertips.

### Added

**Core Feature: Documentation Hub** (Cycle 141)
- `docs/README.md` — Documentation landing page with organized sections (Getting Started, Configuration, Commands, Advanced, Reference)
- Clear navigation structure with quick links for first-time users, migration paths, and common tasks
- Cross-referenced guide structure for easy discovery

**Core Feature: Command Reference** (Cycle 141)
- `docs/guides/command-reference.md` — Complete reference for all 50+ zr CLI commands
- Usage examples, options, shortcuts, and best practices for each command
- Global options reference, exit codes, and alias system documentation
- ~1744 LOC comprehensive command documentation

**Core Feature: Configuration Reference** (Cycle 141)
- `docs/guides/config-reference.md` — Field-by-field schema documentation for all zr.toml sections
- Quick lookup tables for Tasks, Workflows, Profiles, Workspace, Cache, Resource Limits, Concurrency Groups, Toolchains, Plugins, Aliases, Mixins, Templates
- Expression syntax reference with variables, operators, and functions
- Complete example configuration demonstrating all features
- ~1450 LOC schema reference documentation

**Core Feature: Best Practices Guide** (Cycle 141)
- `docs/guides/best-practices.md` — Production-tested patterns for task organization, performance, monorepos, CI/CD
- Task Organization: Descriptive naming, tags, mixins, workspace shared tasks
- Performance Optimization: Parallelism, caching, concurrency groups, resource limits, NUMA affinity
- Monorepo Patterns: Affected detection, multi-stage workflows, task inheritance
- CI/CD Integration: GitHub Actions, GitLab CI examples, remote cache setup
- Caching Strategies: Content-based, layered, remote cache for teams
- Error Handling: Retry, circuit breaker, failure hooks, allow_failure
- Security: Secrets management, remote execution, input validation
- Team Collaboration: Documentation, aliases, profiles, version control
- Anti-patterns checklist
- ~1800 LOC best practices documentation

**Core Feature: Troubleshooting Guide** (Cycle 141)
- `docs/guides/troubleshooting.md` — Comprehensive debugging reference with FAQ
- Installation Issues: PATH configuration, permissions, SSL certificates, build errors
- Configuration Errors: TOML syntax, dependency cycles, task not found, invalid expressions
- Task Execution Problems: Silent failures, command not found, timeouts, file descriptor limits, retry debugging
- Performance Issues: Slow builds, high memory usage, cache misses
- Cache Problems: Permissions, remote cache, cache size
- Workspace Issues: Members not found, inheritance, affected detection
- Toolchain Problems: Install failures, version conflicts
- CI/CD Issues: zr installation, remote cache, parallel jobs
- Frequently Asked Questions: Migration, Docker integration, remote execution, debugging, environment variables, secrets, contributions
- Diagnostic commands reference
- ~2300 LOC troubleshooting documentation

### Changed

**Documentation Improvements**
- Existing guides (getting-started.md, migration.md, shell-setup.md, configuration.md) already provided core content
- Added clear cross-references between all documentation files
- Improved discoverability with structured Table of Contents in each guide

### Notes

**Deferred to Future Milestone**:
- Video walkthrough (5-minute screen recording) — Core documentation complete, video is supplementary
- Example projects (real zr.toml files) — examples/ directory exists, additional examples can be added incrementally
- Static site generation (mdBook or similar) — Markdown files are complete and navigable, site generator is optional enhancement

**Implementation Summary**:
- Total documentation: ~7447 LOC across 6 files
- 153 LOC landing page (docs/README.md)
- 1744 LOC command reference
- 1450 LOC config reference
- 1800 LOC best practices
- 2300 LOC troubleshooting
- Zero code changes (documentation-only release)

## [1.71.0] - 2026-04-18

### ✨ Migration Tool Enhancement (Complete)

This release completes the migration tool enhancement milestone, providing comprehensive auto-conversion from popular task runners to zr. Migrate existing projects from npm scripts, Make, Just, or Task to zr.toml with semantic analysis, intelligent dependency detection, and detailed migration reports.

### Added

**Core Feature: npm Scripts Migration** (Cycle 133)
- `zr init --from npm` parses package.json scripts section
- Pre/post hook detection: `pretest`, `postbuild` wired as dependencies
- `npm run <task>` dependency analysis: detects task-to-task calls
- `run-s`/`run-p` pattern support (npm-run-all sequential/parallel)
- Empty package.json fallback with minimal template
- 5 integration tests (10100-10104) covering all scenarios
- Comprehensive documentation in docs/guides/migration.md

**Core Feature: Dry-Run Mode** (Cycle 136)
- `--dry-run` flag previews conversion without creating files
- Shows generated zr.toml content with syntax highlighting
- Displays migration report (warnings, manual steps, recommendations)
- Useful for reviewing before committing changes
- Works with all migration modes (npm/make/just/task)
- Integration test 10105 validates preview-only behavior

**Core Feature: Migration Reports** (Cycle 136)
- Automatic report generation after successful migration
- Color-coded output (warnings in yellow, recommendations in cyan)
- Tool-specific recommendations (npm: add descriptions, use direct commands, consider parallel deps)
- Unsupported features flagged (npm lifecycle scripts, Make pattern rules)
- Manual steps required (variable substitution, conditional logic)
- 150 LOC report.zig with MigrationReport struct and format() method
- Integration tests 10106-10107 validate report display

**Enhanced Existing Migrations**
- Makefile migration: extracts targets, dependencies (.PHONY), variables
- Justfile migration: converts recipes, dependencies, variables (1:1 mapping)
- Taskfile migration: converts tasks.yml to zr.toml with deps/cmds/vars
- All migrations include semantic analysis for parallel patterns, watch patterns, env vars
- All migrations generate detailed reports with warnings and recommendations

**Implementation Details**
- New module: `src/migrate/npm.zig` (350 LOC) for package.json parsing
- New module: `src/migrate/report.zig` (150 LOC) for migration reporting
- Enhanced: `src/cli/init.zig` with dry_run parameter support
- CLI flags: `--from-npm`, `--from-make`, `--from-just`, `--from-task`, `--dry-run`
- Integration tests: 8 tests total (10100-10107) covering all migration modes
- Documentation: ~260 LOC in docs/guides/migration.md with before/after examples

**Migration Documentation**
- Prerequisites and conversion tables for all tools
- Before/after examples with real-world patterns
- Dependency detection patterns (npm run, run-s, pre/post hooks)
- Manual adjustment recommendations (descriptions, direct commands, parallelism)
- Known limitations and workarounds
- Monorepo migration tips (Turborepo, Lerna)
- Makefile/Justfile/Taskfile specific guides

### Testing

**Unit Tests**
- 4 tests in npm.zig (simple scripts, hooks, deps, empty package.json)
- All existing migration tests passing (1427/1435 total)

**Integration Tests**
- Test 10100: npm simple scripts migration
- Test 10101: npm pre/post hooks as dependencies
- Test 10102: npm run dependency detection
- Test 10103: missing package.json error handling
- Test 10104: empty package.json fallback
- Test 10105: dry-run preview without file creation
- Test 10106: migration report display for Makefile
- Test 10107: dry-run + justfile combination

### Documentation

**New Content**
- docs/guides/migration.md: Comprehensive migration guide (~260 LOC)
  - npm scripts → zr.toml conversion patterns
  - Makefile → zr.toml conversion guide
  - Justfile → zr.toml conversion guide
  - Taskfile.yml → zr.toml conversion guide
  - Before/after examples for each tool
  - Dependency detection patterns and limitations
  - Manual adjustment recommendations
  - Monorepo migration strategies

### Notes

**Deferred Features**
- Interactive review mode (`--interactive` flag with $EDITOR integration) deferred to future milestone
  - Current workflow: `--dry-run` to preview → review → run without flag to create
  - Interactive mode would add: preview → prompt to edit/accept/cancel → $EDITOR → write
  - Not blocking: dry-run provides core preview functionality

**Migration Coverage**
- ✅ npm scripts (package.json)
- ✅ GNU Make (Makefile)
- ✅ Just (justfile)
- ✅ Task (Taskfile.yml)
- Future: Gradle, Maven, Bazel, Pants (based on user demand)

**Milestone Progress**
- Cycle 133: npm migration (350 LOC + 5 tests + 260 docs)
- Cycle 136: dry-run mode + migration reports (230 LOC + 3 tests + 50 docs)
- Total implementation: ~580 LOC across npm.zig, report.zig, init.zig
- Total testing: ~410 LOC integration tests (8 tests)
- Total documentation: ~310 LOC in migration.md
- **Milestone status: DONE** (60% → 100%, interactive review deferred)

## [1.70.0] - 2026-04-17

### ✨ Real-Time Task Output Filtering & Grep

This release adds live filtering and pattern matching for task output streams, enabling quick debugging and log analysis without post-processing. Filter task output in real-time with grep-like patterns, highlight mode, and context lines.

### Added

**Core Feature: Live Grep**
- `zr run build --grep="error|warning"` shows only matching lines
- Substring matching with pipe-separated OR alternatives (error|warning|fatal)
- Case-sensitive pattern matching (MVP implementation)
- Filters apply to stdout (stderr always displayed)
- Compatible with all output modes (buffer, stream, live)

**Core Feature: Inverted Match**
- `zr run test --grep-v="DEBUG"` hides lines matching pattern
- Noise reduction for verbose output
- Can combine with --grep (both filters apply as AND)
- Example: `--grep="status" --grep-v="verbose"` shows status lines excluding verbose ones

**Core Feature: Highlight Mode**
- `zr run build --highlight="TODO|FIXME"` highlights patterns in bold yellow
- Shows ALL output with pattern highlighting (non-filtering mode)
- ANSI color code injection: `\x1b[1;33m<match>\x1b[0m`
- Preserves existing ANSI colors from task output
- Useful for visual scanning without hiding lines

**Core Feature: Context Lines**
- `zr run build --grep="ERROR" -C 3` shows 3 lines before/after matches
- grep -C style context display with FIFO buffer
- Handles multi-line output correctly
- Context buffer flushes on match + N lines after
- Minimal memory overhead (O(context_lines))

**Implementation Details**
- Added 4 global CLI flags: `--grep`, `--grep-v`, `--highlight`, `-C/--context`
- New filter module: `src/output/filter.zig` (375 LOC) with LineFilter class
- FilterOptions struct passed through SchedulerConfig → OutputCapture
- Filter applied in OutputCapture.writeLine() with multi-line handling
- Auto-enables buffering when filter_options.isEnabled()
- 5 unit tests + 12 integration tests (9500-9511)

**Performance**
- Filtering overhead: <1ms per line (substring search)
- Memory usage: O(context_lines) for context buffer
- Large outputs (>1MB) stream efficiently without full buffering

**Documentation**
- Comprehensive "Output Filtering" section in docs/guides/commands.md
- Usage examples, pattern syntax, performance notes, combined filter patterns

### Technical Details

- **Filter Architecture**: LineFilter integrated into OutputCapture.writeLine()
- **Pattern Parsing**: Pipe-separated alternatives for OR logic (no regex, substring matching)
- **Context Buffer**: FIFO queue with configurable size for grep -C behavior
- **Color Preservation**: ANSI escape sequences pass through filters unchanged
- **Scheduler Integration**: filter_options wired from CLI → SchedulerConfig → OutputCapture
- **Backward Compatible**: All existing output modes work unchanged when no filters specified

### Changed

- OutputCapture now accepts filter_options and use_color in config
- OutputCapture auto-created when filter_options.isEnabled() (previously required explicit output_mode)
- cmdRun signature accepts FilterOptions parameter (15 call sites updated)

### Tests

- 5 unit tests in src/output/filter.zig (FilterOptions.isEnabled, basic grep, inverted grep, pipe alternatives, highlighting)
- 12 integration tests in tests/output_filtering_test.zig (9500-9511):
  - Basic grep, inverted grep, pipe alternatives, highlight mode
  - Context lines, combined filters, edge cases, multi-task filtering
  - No-color mode, overlapping context
- All 1415 unit tests passing (8 skipped, 0 failed)

### Deferred

- Regex support (Zig 0.15 lacks std.Regex, substring matching is MVP)
- Tail follow mode (`--grep --follow` for continuous filtering)
- Per-task filter configuration in zr.toml

### Total Implementation

- ~450 LOC filter module + integration
- ~313 LOC tests (5 unit + 12 integration)
- ~150 LOC documentation

**Milestone**: Real-Time Task Output Filtering & Grep (Cycle 131) — COMPLETE

## [1.69.0] - 2026-04-14

### ✨ Task Name Abbreviation & Fuzzy Matching

This release reduces typing friction with intelligent task name abbreviation, unique prefix resolution, and enhanced fuzzy matching. Run tasks with minimal keystrokes.

### Added

**Core Feature: Prefix Matching**
- `zr run b` matches `build` if it's the only task starting with "b"
- Automatic resolution when prefix is unambiguous (single match)
- Shows "Resolved 'b' → 'build'" confirmation message
- Works with any prefix length (single letter to full name)
- Exact task names always take precedence over prefix matches

**Core Feature: Ambiguity Detection**
- `zr run te` fails with clear error if multiple matches exist (e.g., test, teardown)
- Lists all matching tasks with hint: "Use a more specific prefix or full task name"
- Prevents accidental execution of wrong tasks

**Core Feature: Fuzzy Fallback**
- No prefix match → falls back to existing Levenshtein-based fuzzy matching
- `zr run tset` suggests "test" via edit distance (already in v1.0)
- Seamless integration with existing "Did you mean?" suggestions

**Core Feature: Unique Prefix Hints**
- `zr list` now displays minimum unique prefix for each task
- Example: `[b] → build`, `[tea] → teardown`, `[tes] → test`
- Only shown when prefix differs from full name (no hints for already-short names)
- Helps users learn optimal abbreviations for their workflow

**Implementation Details**
- `findTasksByPrefix()`: Returns exact match or all prefix matches with ownership tracking
- `calculateUniquePrefix()`: Computes minimal disambiguation prefix for each task
- Fixed use-after-free bug in empty slice allocation (exact match path)
- Zero breaking changes - feature is purely additive

### Changed
- `src/cli/run.zig`: Added prefix matching logic before fuzzy fallback (~100 LOC)
- `src/cli/list.zig`: Display unique prefix hints in task listing (~50 LOC)
- `tests/integration.zig`: Imported task_abbreviation_test.zig
- `build.zig.zon`: Version 1.68.1 → 1.69.0

### Fixed
- Empty slice stack allocation bug in `findTasksByPrefix()` (heap allocation for exact matches)

### Tests
- 8 new integration tests in `tests/task_abbreviation_test.zig`:
  - Unique prefix match (zr run b → build)
  - Ambiguous prefix error (zr run te → test/teardown)
  - Exact match precedence (task "b" over prefix "build")
  - Fuzzy fallback (zr run tset → suggests "test")
  - Single-letter prefixes with many tasks
  - List output with unique prefix hints
  - Prefix matching with task dependencies

### Documentation
- Implementation notes in milestone docs/milestones.md
- Examples in commit message and test file comments

### Performance
- Minimal overhead: O(N) prefix scan on task name lookup (N = number of tasks)
- Unique prefix calculation: O(N²) worst case, done once per `zr list` invocation
- No performance impact on exact task name matches

### Migration Notes
- No migration required - feature works automatically
- Users can start using abbreviations immediately
- Backward compatible: full task names continue to work

## [1.68.1] - 2026-04-11

### 🔧 Dependency Updates

**Sailor v1.38.1 Migration**
- Updated sailor dependency from v1.37.0 to v1.38.1 (batch migration)
- v1.38.0: Migration tooling infrastructure for upcoming v2.0.0
- v1.38.1: Migration script bug fixes and test coverage improvements
- Zero breaking changes - backward compatible maintenance release
- All 1408 unit tests passing (8 skipped, 0 failed)
- No code changes required in zr codebase

### Changed
- `build.zig.zon`: sailor v1.37.0 → v1.38.1 with correct tarball hash
- Closed issues #52 (sailor v1.38.0), #53 (sailor v1.38.1)

## [1.68.0] - 2026-04-10

### 🚀 Shell Integration & Developer Ergonomics

This release enhances command-line productivity with smart defaults, history shortcuts, and workflow shorthands. Run tasks faster with less typing.

### Added

**Core Feature: Smart No-Args Behavior**
- `zr` (no arguments) now intelligently picks what to do:
  - Runs `default` task if it exists
  - Auto-runs single task if only one defined
  - Launches interactive picker for multiple tasks
  - Shows help if no config or no tasks
- Respects all global flags (`--profile`, `--dry-run`, `--jobs`, `--monitor`)

**Core Feature: History Shortcuts**
- `zr !!` — Re-run the most recently executed task
- `zr !-N` — Run Nth-to-last task from history (e.g., `!-2` for 2nd-to-last)
- Loads from `~/.zr_history` (shared across all projects)
- Validates index format and range with clear error messages
- Shows "Re-running: <task>" info message before execution

**Core Feature: Workflow Shorthand**
- `zr w/<workflow>` — Shorthand for `zr workflow <workflow>`
- Example: `zr w/ci` instead of `zr workflow ci`
- Respects all global flags (`--profile`, `--dry-run`, `--jobs`)
- Validates workflow name and shows helpful errors

**Documentation**
- New comprehensive guide: `docs/guides/shell-setup.md`
- Shell-specific setup examples (bash/zsh/fish)
- Completion setup instructions
- Aliases & abbreviations guide
- Directory navigation patterns
- Tips, best practices, and troubleshooting
- 398 lines of complete shell integration documentation

**Integration Tests (12 tests)**
- Smart no-args: default task, single task, no config, no tasks (4 tests)
- History shortcuts: !-N validation, unknown syntax handling (3 tests)
- Workflow shorthand: w/<name>, w/ without name, nonexistent workflow (3 tests)
- Combined features: --dry-run, --profile flag interaction (2 tests)
- All tests cover edge cases and error scenarios

### Implementation Notes

**Total Changes:**
- ~140 lines of implementation logic across `src/main.zig`
- 252 lines of integration tests in `tests/shell_ergonomics_test.zig`
- 398 lines of documentation in `docs/guides/shell-setup.md`
- Zero breaking changes — all features are additive

**Deferred Features:**
- Task name abbreviation matching — Deferred to future milestone
- Shell function generation (`--functions` flag) — Deferred to future milestone
- `eval $(zr env --export)` — Deferred to future milestone
- Core UX improvements delivered; nice-to-have features postponed

### Milestone

**Shell Integration & Developer Ergonomics** — DONE (Cycle 114)

## [1.67.0] - 2026-04-07

### 🎯 Advanced Task Composition & Mixins

This release introduces **mixins** — a powerful composition pattern for reducing task configuration duplication. Mixins enable reusable partial task definitions that can be combined with clear merge semantics.

### Added

**Core Feature: Mixins (v1.67.0)**
- `[mixins.NAME]` sections for defining reusable task fragments
- `mixins = ["name1", "name2"]` field in tasks for applying mixins
- Field merging semantics:
  - `env`: Merged (task overrides mixin values)
  - `deps`, `deps_serial`, `deps_optional`, `deps_if`: Concatenated (mixin first, then task)
  - `tags`: Union (deduplicated)
  - `hooks`: Concatenated (mixin hooks run before task hooks)
  - Scalar fields (`cmd`, `cwd`, `description`, `timeout_ms`, retry fields): Override (task wins)
- Nested mixin support — mixins can reference other mixins
- Cycle detection with `error.CircularMixin` for invalid references
- Undefined mixin detection with `error.UndefinedMixin`
- Left-to-right application order for multiple mixins

**Documentation (315 lines)**
- Comprehensive "Mixins" section in configuration guide
- Before/after examples showing DRY benefits (39 lines → 13 lines)
- Field merging semantics table
- Multiple mixins composition patterns
- Nested mixins with cycle detection
- 4 real-world use cases:
  - CI pipeline configurations
  - Multi-environment deployments
  - Language-specific tooling
  - Resource constraints
- Benefits and comparison with templates/workspace/profiles
- Error handling examples

**Integration Tests (20 tests: 8000-8019)**
- Basic single mixin inheritance
- Multiple mixins composition
- Task overrides mixin values
- Nested mixins (3-level chain)
- Circular mixin detection
- Nonexistent mixin reference
- Env merging semantics
- Deps concatenation
- Tags union
- Mixin with templates
- Mixin + workspace inheritance
- Empty mixin (no-op)
- All supported fields
- Multiple tasks sharing same mixin
- Order of application
- Conditional deps
- Hooks
- Retry config
- JSON output

### Use Cases

**Before Mixins** (repetitive):
```toml
[tasks.deploy-frontend]
cmd = "kubectl apply -f frontend.yaml"
env = { KUBECONFIG = "/home/user/.kube/prod" }
deps = ["docker-login", "validate-config"]
retry_max = 3

[tasks.deploy-backend]
cmd = "kubectl apply -f backend.yaml"
env = { KUBECONFIG = "/home/user/.kube/prod" }
deps = ["docker-login", "validate-config"]
retry_max = 3
```

**After Mixins** (DRY):
```toml
[mixins.k8s-deploy]
env = { KUBECONFIG = "/home/user/.kube/prod" }
deps = ["docker-login", "validate-config"]
retry_max = 3

[tasks.deploy-frontend]
cmd = "kubectl apply -f frontend.yaml"
mixins = ["k8s-deploy"]

[tasks.deploy-backend]
cmd = "kubectl apply -f backend.yaml"
mixins = ["k8s-deploy"]
```

### Technical Details
- Implementation: 2594 lines across 6 files (types, parser, loader, tests)
- Total unit tests: 1408 passing (8 skipped, 0 failed)
- Total integration tests: 1287 passing (including 20 new mixin tests)
- Backward compatible — no breaking changes

### Files Changed
- `src/config/types.zig`: Mixin struct, Task.mixins, Config.mixins
- `src/config/parser.zig`: [mixins.NAME] parsing, nested mixin support
- `src/config/loader.zig`: Mixin resolution, cycle detection, field merging
- `tests/mixin_test.zig`: 20 comprehensive integration tests (new)
- `docs/guides/configuration.md`: 315 lines of documentation

## [1.66.0] - 2026-04-07

### 📚 Enhanced Task Retry & Error Recovery Documentation

This release completes comprehensive documentation and testing for zr's sophisticated retry mechanisms (implemented in v1.47.0). All retry features were already fully functional, but documentation was minimal and hook interaction tests were missing.

### Added

**Documentation (212 lines)**
- Comprehensive "Timeouts and Retries" section in configuration guide
- Backoff strategy examples (linear, exponential, moderate, aggressive)
- Conditional retry patterns (retry_on_codes, retry_on_patterns)
- Jitter explanation for thundering herd prevention
- Smart retry decision guidelines (fatal vs retriable errors)
- Circuit breaker + retry integration examples
- Failure hooks execution after retry exhaustion
- Retry statistics in history display

**Integration Tests (5 new tests: 978-982)**
- Test retry + failure hook interaction (hook executes after retries exhausted)
- Test retry + success hook interaction (success hook only on eventual success)
- Test exponential backoff + failure hook timing
- Test multiple hooks with retry lifecycle
- Test hook execution order with retry logic

### Documented Features (v1.47.0)

All these features were **already implemented** but undocumented:
- `retry_backoff_multiplier` — Configurable backoff multiplier (1.0=linear, 2.0=exponential, 1.5=moderate)
- `retry_jitter` — Add ±25% random variance to delays (prevents thundering herd)
- `max_backoff_ms` — Maximum retry delay ceiling (default: 60s)
- `retry_on_codes` — Only retry on specific exit codes (empty = retry all)
- `retry_on_patterns` — Only retry when output contains patterns (empty = retry all)
- Combined conditions — Both exit code AND pattern must match (AND logic)
- `hooks` with `point = "failure"` — Execute command after all retries exhausted
- `retry_count` in history — Track total retry attempts across tasks

### Technical Details
- Total retry tests: 13 (970-982) — backoff, jitter, ceiling, conditional retry, hooks
- Total unit tests: 1408 passing (8 skipped, 0 failed)
- Backward compatible — legacy `retry_backoff` boolean still works
- Zero functional changes — pure documentation and test enhancement
- Milestone: Enhanced Task Retry & Error Recovery (complete)

## [1.65.0] - 2026-04-07

### 🎨 Sailor v1.37.0 Migration (v2.0.0 API Bridge)

This release updates the sailor TUI library dependency to v1.37.0, preparing the codebase for the upcoming sailor v2.0.0 API with zero breaking changes. All existing functionality remains intact.

### Changed

**Dependency Updates**
- **sailor v1.36.0 → v1.37.0** — v2.0.0 API bridge release
  - Stateless widget lifecycle standardization (Block, Paragraph, Gauge)
  - `Block.init()` → `Block{}` (direct construction for stateless widgets)
  - Deprecation warning system for gradual v2.0.0 migration
  - Style inference helpers (withForeground, withBackground, withColors, makeBold, etc.)
  - Buffer.set() API introduced alongside deprecated setChar()
  - Comprehensive v1-to-v2 migration guide in sailor repo

**Widget API Compatibility**
- Updated 6 Block widget call sites across TUI modules
  - analytics_tui.zig: 3 fixes (dashboard header, duration histogram, cache scatter plot, time series chart)
  - graph_tui.zig: 1 fix (dependency graph tree block)
  - tui_runner.zig: 2 fixes (task list block, log viewer block)
- All changes backward compatible (v1.x APIs still work with deprecation warnings)
- Zero functional changes — purely API modernization

### Fixed
- Widget lifecycle patterns now consistent across all TUI components
- Method chaining syntax updated for stateless widget construction

### Technical Details
- Total tests: 1408 passing (8 skipped, 0 failed)
- Cross-platform compatibility verified (macOS, Linux, Windows)
- Prepares codebase for future sailor v2.0.0 adoption
- Related: GitHub issue #51

## [1.64.0] - 2026-04-07

### 🔍 Enhanced Task Discovery & Search

This release dramatically improves task discoverability with powerful filtering capabilities, making it easy to navigate large projects with 100+ tasks. All filters support combined AND logic for complex queries.

### Added

**Advanced Task Filters**
- **--exclude-tags** — Hide tasks with ANY of the specified tags
  - `zr list --exclude-tags=slow` hides all tasks tagged "slow"
  - `zr list --exclude-tags=slow,flaky` hides tasks with either tag
  - Useful for filtering out problematic tests in CI
- **--frequent[=N]** — Show top N most executed tasks from history
  - `zr list --frequent` shows top 10 most-run tasks (default)
  - `zr list --frequent=5` limits to top 5
  - Ranked by execution count from `.zr/history.jsonl`
  - Helps identify commonly-used workflows
- **--slow[=THRESHOLD]** — Show tasks exceeding average execution time
  - `zr list --slow` shows tasks averaging >30s (default: 30000ms)
  - `zr list --slow=60000` shows tasks averaging >1 minute
  - Uses historical statistics from execution history
  - Identifies performance bottlenecks

**Filter Improvements**
- **--tags now uses AND logic** — Changed from ANY (OR) to ALL (AND) for precise filtering
  - `zr list --tags=ci,integration` requires BOTH tags (not just one)
  - Breaking change: tasks must have ALL specified tags
  - More intuitive behavior for complex projects
- **--search full-text** — Now searches task names, descriptions, AND commands
  - `zr list --search=docker` matches commands containing "docker"
  - Previously only searched names and descriptions
  - Enables discovery based on implementation details

**Combined Filters**
- All filters work together with AND logic:
  - `zr list --frequent=20 --tags=ci --exclude-tags=slow`
  - `zr list --search=docker --exclude-tags=deploy`
  - `zr list --tags=ci,test --slow=10000 --exclude-tags=flaky`
- JSON output (`--format json`) supports all filters
- 6 comprehensive integration tests (7000-7005)

**Documentation**
- Enhanced "Task Discovery" section in `docs/guides/commands.md`
- Examples for all filter combinations
- Usage patterns for large projects

### Changed
- **Breaking**: `--tags` filter changed from ANY (OR) to ALL (AND) logic
  - Old: `--tags=ci,test` matched tasks with ci OR test
  - New: `--tags=ci,test` matches tasks with ci AND test
  - Use `--tags=ci` separately from `--tags=test` to get OR behavior

### Implementation
- Updated `cmdList()` signature with 3 new parameters
- Enhanced filtering logic in `src/cli/list.zig`
- Updated CLI parsing in `src/main.zig`
- Updated MCP handlers for API compatibility
- All 1408 unit tests passing (8 skipped)

## [1.63.0] - 2026-04-07

### 🎯 Workspace-Level Task Inheritance

This release completes workspace-level task inheritance, enabling monorepos to define common tasks once in the workspace root that all members inherit automatically. This eliminates duplication for lint, test, format, and other shared tasks.

### Added

**Workspace Shared Tasks**
- **Root-Level Definition** — `[workspace.shared_tasks.NAME]` sections in workspace root `zr.toml`
  - Define common tasks (lint, test, format, build) in one place
  - All workspace members automatically inherit these tasks
  - No manual configuration needed in each member directory
- **Automatic Inheritance** — Members receive all workspace shared tasks on load
  - CLI integration in `src/cli/workspace.zig` (3 call sites)
  - `inheritWorkspaceSharedTasks()` called after member config load
  - Works in `zr workspace run`, affected detection, and filtered execution
- **Override Semantics** — Member tasks completely replace workspace tasks with same name
  - No merging of task fields (complete replacement)
  - Member can customize inherited task behavior when needed
  - Override detected by checking member's task HashMap before inheritance
- **Visibility Markers** — `zr list` shows inherited tasks with `(inherited)` marker
  - Clear distinction between local and inherited tasks
  - `Task.inherited` boolean field set during inheritance
  - Rendered in list output alongside task descriptions
- **Dependency Resolution** — Inherited tasks can depend on member-local tasks
  - Standard DAG resolution handles cross-dependencies
  - No special handling needed for inherited task dependencies

**Configuration Example**
```toml
# Root zr.toml
[workspace]
members = ["packages/*", "apps/*"]

[workspace.shared_tasks.lint]
cmd = "eslint ."
description = "Run linter on all files"

[workspace.shared_tasks.test]
cmd = "jest"
description = "Run unit tests"

[workspace.shared_tasks.format]
cmd = "prettier --write ."
description = "Format code"
```

**Member Behavior**
```bash
cd packages/api
zr list              # Shows: lint (inherited), test (inherited), format (inherited)
zr run lint          # Runs workspace lint command
```

**Member Override Example**
```toml
# packages/api/zr.toml - Override test task
[tasks.test]
cmd = "cargo test"  # Replaces workspace "jest" command
description = "Run Rust tests"
```

**Benefits**
- **DRY Principle** — Define common tasks once in workspace root
- **Consistency** — All members use same commands by default
- **Flexibility** — Members can override when needed
- **Discoverability** — Clear markers show task origin

### Changed

**CLI Integration**
- `cmdWorkspaceRun()` — Inherit workspace tasks for all members (line 301, 379)
- `cmdWorkspaceRunFiltered()` — Load root config and inherit for affected members (line 530)
- All workspace member loading paths now call `inheritWorkspaceSharedTasks()`

**Documentation**
- Added "Workspace-Level Task Inheritance" section to `docs/guides/configuration.md`
  - Comprehensive examples with root and member configs
  - Override semantics and visibility marker documentation
  - Usage patterns and benefits explanation
  - Updated Table of Contents with workspace subsections

### Tests

- **15 Integration Tests** — `tests/workspace_inheritance_test.zig` (6000-6014)
  - Basic inheritance of single/multiple tasks
  - Override semantics (member replaces workspace task)
  - Cross-dependencies between inherited and local tasks
  - Null inheritance (members with no workspace)
  - Validation (nonexistent shared tasks, name collisions)
- **All 1408 Unit Tests Passing** — Zero regressions

### Implementation

**Data Structures** (Cycle 104)
- `Workspace.shared_tasks` HashMap in `src/config/types.zig`
- `Task.inherited` boolean field for display markers

**TOML Parsing** (Cycle 104)
- `[workspace.shared_tasks.NAME]` section parsing in `src/config/parser.zig`
- Shared tasks stored in workspace struct during config load

**Inheritance Logic** (Cycle 104)
- `inheritWorkspaceSharedTasks()` function in `src/config/loader.zig`
- Deep copy shared tasks into member config
- Skip if member already defines task (override)
- Mark copied tasks with `inherited = true`

**CLI Wiring** (Cycle 106)
- All workspace member loading paths call inheritance function
- Graceful fallback if workspace has no shared tasks
- Error handling via `catch {}` (non-critical failures)

**Total**: ~500 LOC (data structures, parsing, inheritance, CLI integration, tests, docs)

This milestone completes the Workspace-Level Task Inheritance feature, making monorepo task management significantly more maintainable.

## [1.62.0] - 2026-04-06

### 🚀 Task Parallel Execution Groups

This release introduces concurrency groups for fine-grained parallel execution control in heterogeneous workloads. Define named groups with independent worker limits to manage GPU tasks, database connections, and API rate limits separately.

### Added

**Concurrency Groups**
- **Named Group Definitions** — `[concurrency_groups.NAME]` sections with `max_workers` limits
  - Define groups like `gpu` (limit=2), `network` (limit=10), `database` (limit=5)
  - Each group has independent worker pool separate from global `max_workers`
  - Groups run concurrently with each other (not subject to global limit)
- **Task-Level Assignment** — `concurrency_group = "group_name"` field in task config
  - Tasks without `concurrency_group` use default global worker pool
  - Tasks with group use that group's semaphore for concurrency control
  - Nonexistent groups fall back to global semaphore (defensive)
- **Scheduler Integration** — Per-group semaphores in `src/exec/scheduler.zig`
  - Dynamic semaphore creation for each concurrency group
  - Group semaphores replace global semaphore for grouped tasks
  - Proper cleanup and release of group semaphores on task completion
- **Use Cases**:
  - GPU-bound tasks (limit to GPU count)
  - Network tasks with rate limits or connection pools
  - Database operations limited by connection pool size
  - Memory-intensive tasks requiring exclusive RAM access

**Configuration**
```toml
[concurrency_groups.gpu]
max_workers = 2

[concurrency_groups.network]
max_workers = 10

[tasks.train_model]
cmd = "./train.py --gpu"
concurrency_group = "gpu"

[tasks.fetch_data]
cmd = "curl https://api.example.com/data"
concurrency_group = "network"
```

**Documentation**
- Added comprehensive "Concurrency Groups" section to `docs/guides/configuration.md`
  - Use cases and examples (basic, advanced, mixed workloads)
  - Field reference tables for groups and tasks
  - Integration with dependencies, retry, cache, workflows
  - Behavior explanation (independent pools, per-group limits)

**Testing**
- **20 Integration Tests** (tests 5000-5019) covering:
  - Basic group execution with limits
  - Multiple groups with independent limits
  - Mixed tasks (with/without groups)
  - Null max_workers inheritance
  - Nonexistent group fallback
  - Parallel execution respecting limits
  - Independent worker pools per group
  - Dependencies with concurrency groups
  - Unlimited groups (max_workers=0)
  - --jobs flag independence
  - Workflow stage integration
  - Retry, cache, max_concurrent compatibility
  - CPU affinity, NUMA hints, timeout compatibility

### Changed
- Scheduler worker pool logic now supports per-group semaphores in addition to global
- Task execution respects `concurrency_group` field for semaphore selection

### Compatibility
- **Fully Backward Compatible** — Tasks without `concurrency_group` behave identically to v1.61.0
- All existing configurations continue to work unchanged
- Zero breaking changes to TOML schema or CLI

## [1.61.0] - 2026-04-05

### 🎯 Task Templates & Scaffolding

This release provides a comprehensive task template system with 31 built-in templates for common development workflows, reducing boilerplate and accelerating zr.toml configuration.

### Added

**Built-in Template Library**
- **31 Built-in Templates** across 6 categories
  - **Build** (6): go-build, cargo-build, npm-build, zig-build, maven-build, make-build
  - **Test** (7): pytest, jest, cargo-test, go-test, junit, rspec, vitest
  - **Lint** (6): eslint, clippy, ruff, golangci-lint, checkstyle, rubocop
  - **Deploy** (4): docker-push, k8s-deploy, terraform-apply, heroku-deploy
  - **CI** (4): cache-setup, artifact-upload, parallel-matrix, docker-build-ci
  - **Release** (4): semantic-release, cargo-publish, npm-publish, docker-tag

**Template System Architecture**
- **Template Registry** (`src/template/registry.zig`) — Template discovery, lookup, category filtering
- **Template Engine** (`src/template/engine.zig`) — Variable substitution with ${VAR} syntax
- **Template Types** (`src/template/types.zig`) — Template/TemplateVariable/Category definitions
- **Custom Template Loader** (`src/template/loader.zig`) — Load user-defined templates from filesystem
- **Built-in Templates** (`src/template/builtin/*.zig`) — 6 category modules with template definitions

**CLI Commands**
- **`zr template list [--builtin]`** — List all available templates by category
  - Show template names and descriptions in organized format
  - Support for both built-in and user-defined templates
- **`zr template show <name> [--builtin]`** — Preview template details
  - Display template TOML with variable placeholders
  - Show required vs optional variables
  - Display default values
- **`zr template add <name> [--builtin]`** — Apply template with variable substitution
  - `--var KEY=VALUE` flags for variable input
  - `--output <path>` for file output (default: stdout)
  - Variable validation (required variables, defaults)

**Template Features**
- **Variable Substitution** — ${VAR} syntax with default values
- **Required Variables** — Validation ensures required variables are provided
- **Default Values** — Optional variables use sensible defaults
- **Custom Templates** — Support for .zr/templates/ and ~/.zr/templates/
- **TOML Generation** — Templates generate valid zr.toml task configurations

### Tests

**Integration Tests** (10 tests: 4000-4009)
- Template list with category grouping verification
- Template show with variable display
- Template add with variable substitution (go-build, cargo-build, pytest, eslint)
- Required variable validation
- Default value handling
- Error cases (nonexistent template, missing variables)

**Test Status**: 1320 unit tests passing (8 skipped)

### Implementation Details

- Commits: 8bbdfbe (template system), d0051bd (loader + tests), c0e6719 (milestone)
- Total: ~1,700 LOC added across 13 files
- Complete milestone: Task Templates & Scaffolding

## [1.59.0] - 2026-04-01

### 🎯 Workflow Matrix Execution

This release implements matrix execution strategy for workflows, enabling automated execution of tasks across multiple parameter combinations.

### Added

**Matrix Configuration**
- **Matrix Types** — Extended `src/config/types.zig` with workflow matrix support
  - `MatrixExclusion` struct for key-value exclusion conditions
  - `MatrixConfig` struct with dimensions and exclusions
  - Optional `matrix` field in `Workflow` struct
  - Full `deinit` implementation for memory cleanup

**Matrix Expansion**
- **Matrix Module** (`src/exec/matrix.zig`, 345 LOC) — Cartesian product expansion with exclusion filtering
  - `MatrixCombination` struct: hashmap for variable name → value mapping
  - `expandMatrix()`: generates all valid combinations from matrix dimensions
  - `isExcluded()`: filters combinations based on exclusion rules
  - 8 unit tests covering initialization, cloning, expansion, exclusions

**Workflow Integration**
- **Scheduler Enhancement** — `SchedulerConfig.extra_env` field for matrix variable injection
  - `buildEnvWithToolchains()` merges extra_env with labeled error handling
  - Call chain threading: WorkerCtx → runTaskSync → runSerialChain
  - Memory safety: defer blocks for env key/value cleanup
- **Matrix Execution Loop** (`src/cli/run.zig`)
  - Sequential execution of all matrix combinations (parallel deferred to future)
  - Each combination runs ALL workflow stages with injected environment
  - Matrix variables exposed as `MATRIX_<KEY>=<value>` env vars
  - Variable substitution: `${matrix.os}` in task commands

**CLI Commands**
- **`--matrix-show` Flag** — Preview matrix combinations without execution
  - Displays all generated combinations with their variables
  - Shows total combination count
  - Useful for debugging matrix configurations

### Tests

**Integration Tests** (9 tests in `tests/workflow_matrix_test.zig`)
- Test 3935: Single dimension expansion (3 arch values)
- Test 3936: Cartesian product 2x3 (os × version)
- Test 3937: Matrix with exclusions (3x2 → 5 after exclusion)
- Test 3938: Multi-dimension 3x2x2 (12 combinations)
- Test 3939: Variable substitution ${matrix.KEY}
- Test 3940: Empty matrix config
- Test 3941: Matrix with single value
- Test 3942: Complex exclusions (multiple rules)
- Test 3943: Matrix show with exclusions
- Test 3944: Matrix execution with workflow stages

**Test Status**: 1253/1261 unit tests passing (100% pass rate), 8 skipped

### Usage Example

```toml
[workflows.test]
stages = [
  { tasks = ["build", "test"] },
]

[workflows.test.matrix]
os = ["linux", "macos", "windows"]
version = ["1.0", "2.0"]

[[workflows.test.matrix.exclude]]
os = "macos"
version = "1.0"

[tasks.build]
cmd = "build --os=${matrix.os} --version=${matrix.version}"

[tasks.test]
cmd = "test --os=${matrix.os}"
```

```bash
# Preview all combinations
zr workflow test --matrix-show

# Execute all combinations
zr workflow test
```

### Commits
- ff7f24f: feat: add matrix execution types and expansion logic
- 19b61cc: feat: add workflow matrix --matrix-show flag
- 666aa74: feat: implement workflow matrix execution

## [1.58.0] - 2026-03-30

### 🎯 Post-v1.0 Enhancements: Task Estimation, Validation, Visualization

This release delivers three major post-v1.0 enhancement milestones focused on workflow intelligence, configuration quality, and interactive visualization.

### Added

**Task Estimation & Time Tracking**
- **Statistics Module** (`src/history/stats.zig`) — Percentile calculations (p50/p90/p99), standard deviation, anomaly detection (2x p90 threshold)
- **Estimate Command** — Enhanced `zr estimate <task|workflow>` with per-task and workflow estimation
  - Critical path calculation for parallel workflow stages (MAX for parallel, SUM for sequential)
  - JSON export format with full statistical breakdown
  - P90/P99 percentiles and anomaly thresholds in text output
- **Duration Displays** — Time estimates integrated throughout CLI
  - `zr list`: Shows `[~8.2s (avg), 0.6-27.6s range]` estimates alongside task names
  - `zr run --dry-run`: Displays per-task estimates and total estimated workflow time
  - TUI Progress Bars: Live ETA display based on historical averages with dynamic updates

**Configuration Validation Enhancements**
- **Expression Syntax Validation** — Uses `expr.evalConditionWithDiag` to validate task conditions and `deps_if` expressions with diagnostic context
- **Performance Warnings** — Warns when task count >100 or dependency chains >10 levels deep (recursive depth calculation)
- **Plugin Schema Validation** — Checks required `source` field presence and format in plugin configurations
- **Import Collision Detection** — Warns about namespace collisions with multiple imports
- **Strict Mode Enhancement** — `zr validate --strict` now treats warnings as errors (exit code 1 for CI)

**Interactive Workflow Visualizer**
- **Interactive HTML/SVG Visualization** — D3.js v7 force-directed graph with zoom/pan/drag behaviors
  - Standalone HTML output with embedded JSON data (no external dependencies)
  - Dark theme UI matching zr's aesthetic
- **Task Details Panel** — Click nodes to view cmd, description, dependencies, environment variables, tags, duration
- **Status Color Coding** — Loads `.zr_history` for task status (success/failed/pending/unknown)
- **Critical Path Highlighting** — Recursive BFS depth calculation marks longest dependency chains (golden border)
- **Filter Controls** — Regex search, status dropdown, tag dropdown with real-time node opacity updates
- **Export Functionality** — SVG and PNG download buttons with 2x scaling for quality
- **Command Integration** — `zr graph --interactive > workflow.html` generates interactive visualization

### Changed

- **Refactored Estimate Command** — Reduced from 249 LOC to 53 LOC (-196 LOC) by extracting shared statistics module
- **Enhanced Validation** — 7 new validation rules integrated into `src/cli/validate.zig`

### Technical

- **Test Coverage**: 1224/1232 unit tests passing (100% pass rate), 8 skipped
- **Integration Tests**: 24 new tests (7 validation, 7 estimation, 10 interactive graph)
- **Lines of Code**: +1,500 LOC (stats module, validation enhancements, interactive renderer)
- **Commits**: 47 commits since v1.57.0

## [1.57.0] - 2026-03-26

### 🎉 v1.0-Equivalent Release (Phase 13C Complete)

After 13 development phases and 100+ releases, zr v1.57.0 marks feature-complete v1.0-equivalent status as a production-ready developer platform. All Phase 9-13 objectives complete.

### Added

**Phase 9: Foundation Infrastructure**
- **LanguageProvider Interface** — Extensible architecture for toolchain support
  - Unified interface for 8 toolchains (Node, Python, Zig, Go, Rust, Deno, Bun, Java)
  - Registry pattern for easy language additions
  - Automatic project detection and task extraction
- **JSON-RPC Shared Infrastructure** — Common transport layer for MCP & LSP
  - Content-Length framing (LSP) and newline-delimited (MCP) support
  - Bidirectional message passing with request/response correlation
  - JSON-RPC 2.0 error handling
- **Levenshtein Distance** — Smart error suggestions
  - "Did you mean?" suggestions for typos in task names and commands
  - Integrated into CLI error handling
- **Enhanced Error Messages** — Developer-friendly diagnostics
  - Line and column numbers in TOML parse errors
  - Syntax-highlighted error context
  - Actionable suggestions for missing dependencies

**Phase 10: AI Agent Integration**
- **MCP Server** (`zr mcp serve`) — Model Context Protocol server for AI agents
  - 9 tools exposed: `run_task`, `list_tasks`, `validate_config`, `show_history`, `graph_tasks`, `show_output`, `list_workflows`, `init_config`, `explain_config`
  - Real-time streaming output for long-running tasks
  - In-memory execution with result capture
  - Documented in `docs/guides/mcp-integration.md`
- **Auto-generate Configuration** (`zr init --detect`)
  - Automatically detects project languages from package.json, setup.py, Cargo.toml, go.mod, etc.
  - Extracts common tasks (build, test, lint) from existing configs
  - Generates complete zr.toml with sensible defaults
- **Natural Language Interface** (`zr ai "..."`)
  - Keyword-based pattern matching for common workflows
  - Extensible pattern matching engine

**Phase 11: Editor Integration**
- **LSP Server** (`zr lsp serve`) — Language Server Protocol for zr.toml
  - Autocomplete for task names, fields, dependencies, expressions, toolchain versions
  - Hover documentation with field descriptions and Big-O complexity
  - Go-to-definition for task references and workflow stages
  - Real-time diagnostics for syntax errors, missing deps, circular dependencies
  - Supports VS Code, Neovim, Helix, Emacs, Zed
  - Setup guide in `docs/guides/lsp-setup.md`

**Phase 12: Performance & Quality**
- **Binary Optimization** — Minimal footprint, maximum performance
  - 1.2MB binary (ReleaseSmall + strip) — 10x smaller than Task, 5x smaller than Just
  - 4-8ms cold start — competitive with Make
  - 2-3MB memory — 30-50% reduction via string interning and arena allocators
- **Fuzz Testing** — Comprehensive robustness testing
  - TOML parser, expression engine, JSON-RPC parser (10+ minutes, zero crashes)
  - Memory safety verification with AddressSanitizer
- **Performance Benchmarks** — Validated against alternatives
  - Comprehensive benchmark suite vs Make, Just, Task
  - Results documented in `benchmarks/RESULTS.md`
  - Binary size, cold start, config parsing, parallel execution, memory usage

**Phase 13: Migration & Documentation**
- **Migration Tools** — Seamless migration from existing task runners
  - `zr init --from-make` — Convert Makefile → zr.toml
  - `zr init --from-just` — Convert Justfile → zr.toml
  - `zr init --from-task` — Convert Taskfile.yml → zr.toml
  - Migration guide in `docs/guides/migration.md`
- **8 Comprehensive Guides**
  - getting-started, configuration, commands, benchmarks, mcp-integration, lsp-setup, migration, adding-language
  - 300+ pages of documentation
- **README Overhaul** — Feature matrix, performance benchmarks, comparison tables

### Changed
- Updated version badge to v1.0.0 (blue badge for stable release)
- Enhanced Phase 9-13 section in README with detailed feature breakdown
- Updated performance metrics with actual benchmark results

### Developer Notes
- **Test Status**: 1151/1159 unit tests passing (8 skipped) — 100% pass rate
- **Integration Tests**: 30+ scenarios covering CLI, TUI, config parsing, output streaming
- **Memory Leaks**: 0 (verified with std.testing.allocator)
- **Cross-platform**: 6 targets tested (Linux x64/ARM64, macOS x64/ARM64, Windows x64, WASM)
- **Documentation**: 8 guides, complete API reference
- **Open Enhancement Issues**: 3 (zuda migrations, deferred to post-v1.0)

## [1.51.0] - 2026-03-25

### Changed
- **Sailor v1.19.0 & v1.20.0 Migration** - CLI enhancements and quality improvements
  - Sailor v1.19.0 features:
    - Progress bar templates: 5 presets (download, build, test_run, install, processing)
    - Environment variable config: `env.get/getBool/getInt` for runtime customization
    - Color themes: Light/dark presets with auto-detection
    - Table formatting: Alignment, padding, multi-line cells
    - Arg groups: Better CLI option organization
  - Sailor v1.20.0 features:
    - Windows Console Unicode tests: 23 comprehensive tests covering UTF-16 surrogates, CJK width, ANSI escapes
    - Pattern documentation: `docs/patterns.md` with examples for all major APIs
    - Quality improvements: Directory scanning for docgen, error context module, edge case hardening

### Developer Notes
- All 996 unit tests passing (8 skipped)
- No breaking changes - fully backward compatible
- Closes issues #32 (sailor v1.19.0), #33 (sailor v1.20.0)

## [1.50.0] - 2026-03-24

### Added
- **Cross-Platform Path Handling Audit (v1.50.0)** - Complete Windows compatibility overhaul
  - Path separator fixes: replaced hardcoded `/` with `std.fs.path.sep` in glob.zig (5), affected.zig (2), workspace.zig (6)
  - UNC path support: Windows network paths (`\\server\share`) now work in cwd, remote_cwd, workspace members
  - Long path support: handles paths >260 characters on Windows 10 1607+
  - Symlink resolution: proper handling of directory symlinks on Windows (requires Dev Mode or admin)
  - 11 new Windows-specific integration tests in `tests/integration_windows_paths.zig`
  - 18 path separator compatibility tests in `tests/integration_path_separator.zig`

### Fixed
- SSH timeout: added ConnectTimeout to prevent hanging tests and zombie processes (#12799f7)
- Parent directory search: `zr list` from nested directories now searches up for zr.toml (#b103b20)
- Temp paths: replaced hardcoded `/tmp` with platform-specific temp directories (#d0cd4fd)
- Test helpers: added `runCommand()` helper for git operations in integration tests (#402e733)

### Developer Notes
- Milestone: Cross-Platform Path Handling Audit (COMPLETE 5/5)
- Total integration test files: 67 (added windows_paths.zig)
- CI status: GREEN (all cross-platform tests passing)

## [1.49.0] - 2026-03-22

### Added
- **Task Output Streaming Improvements (v1.49.0)**
  - Incremental rendering for `zr show --output` (stream large files without buffering entire output)
  - Follow mode: `zr show --output <task> --follow` (tail -f style live following)
  - Compression on-the-fly: gzip-compress stored task output to reduce history storage by 5-10x
    - Configurable via `compress = true` in task config
    - Auto-detection of `.gz` files on read
  - Performance: Memory usage stays under 50MB when streaming 1GB+ output files
  - New module: `src/exec/output_capture.zig` with streaming infrastructure

### Fixed
- Performance test API compatibility with Zig 0.15 (`streamUntilDelimiter` migration)

### Developer Notes
- Milestone: Task Output Streaming Improvements (3/5 complete, pager deferred)
- CI status: GREEN (all tests passing)
- Performance tests validate <50MB memory usage for 1GB+ files

## [1.48.0] - 2026-03-21

### Added
- **Shell Integration Enhancements (v1.48.0)**
  - Smart `cd` command: `zr cd [task]` changes directory to task's working directory
  - Shell hooks: bash/zsh/fish integration for seamless workflow switching
  - Command abbreviations: define short aliases for frequently used commands
  - 34 new integration tests (abbreviations, alias, cd commands)

## [1.47.0] - 2026-03-19

### Added
- **Task Retry Strategies & Backoff Policies (v1.47.0)**
  - Configurable backoff multiplier for exponential/linear/custom retry delays
    - `retry_backoff_multiplier` field (default: 2.0 for exponential, 1.0 for linear)
    - Example: `retry_backoff_multiplier = 3.0` → delays grow 3x each attempt
  - Jitter support to prevent thundering herd problem
    - `retry_jitter = true` adds ±25% random variance to retry delays
    - Helps distribute retry attempts across time when multiple tasks fail simultaneously
  - Max backoff ceiling to cap exponential growth
    - `max_backoff_ms` field (default: 60000ms = 1 minute)
    - Prevents unbounded exponential delays that could stall workflows
  - Conditional retry based on exit codes
    - `retry_on_codes = [2, 3, 124]` — only retry when exit code matches
    - Use case: retry on transient errors (exit 2), skip on fatal errors (exit 1)
  - Conditional retry based on output patterns
    - `retry_on_patterns = ["FLAKY", "TIMEOUT", "Connection refused"]`
    - Only retry when stdout/stderr contains one of the specified patterns
    - Requires `output_mode = "buffer"` for pattern matching
  - Integration with existing features:
    - Circuit breaker: still prevents retry storms even with custom strategies
    - Retry budget: workflow-level retry limits still enforced
    - Timeline tracking: logs actual delay used for each retry attempt
  - New module: `src/exec/retry_strategy.zig` with comprehensive backoff calculation
  - 8 new integration tests (970-977) covering all retry strategy combinations

### Changed
- Scheduler retry loop refactored to use `RetryStrategy` module (previously hardcoded)
- Retry delay calculation now respects multiplier, jitter, and max backoff ceiling
- Timeline events now include actual delay: `"retry 2/5 (delay: 120ms)"`

### Developer Notes
- Total unit tests: 980/986 (24 new in retry_strategy.zig, 6 skipped, 0 leaks)
- Total integration tests: 975/976 (8 new retry tests, 1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)
- No breaking changes — new fields are optional with backward-compatible defaults
- Deprecated: `retry_backoff` boolean (replaced by `retry_backoff_multiplier`)
  - Old: `retry_backoff = true` → doubles delay each attempt
  - New: `retry_backoff_multiplier = 2.0` (explicit control)
  - Migration: `retry_backoff = true` → `retry_backoff_multiplier = 2.0`
  - Old field still works (maps to multiplier 2.0 internally)

## [1.46.0] - 2026-03-18

### Added
- **Remote Execution & Distributed Builds**
  - Execute tasks on remote machines via SSH or HTTP workers
  - Support for SSH targets: `user@host:port` or `ssh://user@host:port`
  - Support for HTTP/HTTPS worker endpoints for distributed task execution
  - New task fields: `remote`, `remote_cwd`, `remote_env` for remote execution configuration
  - Scheduler integration: tasks with `remote` field automatically route to RemoteExecutor
  - Connection pooling and retry logic for transient network failures
  - Graceful error handling for SSH connection failures (exit code 255) and HTTP errors
  - Output capture from remote processes (stdout/stderr streaming)
  - Progress monitoring for remote task execution
  - Use cases: distributed builds, GPU processing, multi-platform testing, CI/CD pipelines
  - 9 integration tests covering SSH/HTTP target parsing, config validation, error handling
  - Comprehensive documentation in `docs/guides/configuration.md` with examples

### Developer Notes
- Total unit tests: 932/938 (6 skipped, 0 leaks)
- Total integration tests: 967/968 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)
- New module: `src/exec/remote.zig` (SSH and HTTP executors)
- Scheduler updated to route remote tasks via `RemoteExecutor.execute()`
- No breaking changes — purely additive feature

## [1.45.0] - 2026-03-17

### Added
- **TOML Syntax Highlighting**
  - Syntax-highlighted TOML code snippets in error messages using sailor v1.13.0+ features
  - Error display utility (`src/util/error_display.zig`) for beautiful diagnostic output
  - Color-coded TOML elements: sections (cyan), keys (yellow), strings (green), numbers (magenta), booleans (blue), comments (dim)
  - Context lines with line numbers for better error localization
  - Integrated with `zr validate` command for enhanced validation feedback
  - Works seamlessly with sailor's existing color system and accessibility features

### Developer Notes
- Total unit tests: 877/885 (8 skipped, 0 leaks)
- Total integration tests: 959/960 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)
- Leverages sailor v1.15.0 syntax highlighting capabilities
- No breaking changes — purely additive feature

## [1.43.0] - 2026-03-16

### Changed
- **Sailor v1.15.0 Migration**
  - Upgraded sailor dependency from v1.14.0 to v1.15.0
  - Fixed async_loop.zig dangling pointer and race conditions (thread safety)
  - Implemented XTGETTCAP terminal capability querying
  - Replaced environment variable detection with proper capability negotiation
  - Enhanced Sixel and Kitty graphics protocol detection
  - Added 13 new edge case tests for Windows, Linux, macOS
  - Improved terminal size detection on all platforms
  - Better handling of non-TTY environments
  - Fixed 6 memory leaks in repl.zig and editor.zig
  - Multi-platform native testing in CI (not just cross-compilation)
  - Tests run on real VMs: ubuntu-latest, macos-13, macos-latest, windows-latest
  - All optimization modes tested (Debug, ReleaseSafe, ReleaseSmall, ReleaseFast)
  - No breaking changes — drop-in replacement for v1.14.0

### Developer Notes
- Total unit tests: 845/853 (8 skipped, 0 leaks)
- Total integration tests: 957/958 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)
- Sailor library: 1243 tests passing, 6 cross-compile targets verified

## [1.39.0] - 2026-03-16

### Changed
- **Sailor v1.14.0 Migration**
  - Upgraded sailor dependency from v1.13.1 to v1.14.0
  - Memory pooling system reduces allocations for frequently created objects
  - Render profiling tools identify slow widgets and detect bottlenecks
  - Virtual widget rendering only renders widgets in viewport, skips off-screen
  - Incremental layout solver caches layout results, only recomputes on changes
  - Buffer compression reduces memory footprint for large TUI applications
  - All features are opt-in and backward compatible

### Developer Notes
- Total unit tests: 845/853 (8 skipped, 0 leaks)
- Total integration tests: 967/968 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)
- No breaking changes from sailor v1.14.0

## [1.34.0] - 2026-03-14

### Added
- **Workflow Retry Budget Integration** (v1.34.0)
  - Added `retry_budget` field to `SchedulerConfig` struct for workflow-level retry limiting
  - Initialize `RetryBudgetTracker` from workflow config when executing stages
  - Updated `cmdWorkflow` to extract and pass workflow `retry_budget` to scheduler
  - Retry budget is now shared across all stages in multi-stage workflows
  - 3 new integration tests (941-943) covering workflow retry scenarios
  - Documentation updated with multi-stage workflow examples

### Changed
- Workflow retry budget (from v1.30.0 infrastructure) is now fully functional
- Multi-stage workflows can limit total retries across all stages with a single `retry_budget` value

### Developer Notes
- Total unit tests: 820/828 (8 skipped, 0 leaks)
- Total integration tests: 942/943 (1 skipped, 0 leaks)
- CI status: GREEN (all tests passing)

## [1.33.0] - 2026-03-14

### Added
- **Advanced TUI Data Visualization** (v1.33.0)
  - Created `src/cli/analytics_tui.zig` with three data visualization widgets
  - Histogram for task duration distribution (5 bins)
  - TimeSeriesChart for build time trends (last 50 executions)
  - ScatterPlot for cache hit rate vs build time correlation
  - FlexBox layout for responsive three-panel dashboard
  - Viewport clipping for efficient large graph rendering
  - Added `--tui` flag to `zr analytics` command

### Changed
- Graph rendering now uses viewport clipping for better performance with large graphs
- Virtual buffer (2x terminal height) reduces memory usage

### Developer Notes
- Total unit tests: 820/828 (8 skipped, 0 leaks)
- Total integration tests: 939/940 (1 skipped, 0 leaks)
- Uses sailor v1.6.0/v1.7.0 data visualization widgets

## [1.32.0] - 2026-03-14

### Changed
- **Sailor Library Migration** (v1.10.0 → v1.12.0)
  - Upgraded sailor dependency from v1.10.0 to v1.12.0
  - v1.11.0 features (terminal graphics & effects):
    - Particle effects system (confetti, sparkles for celebrations)
    - Blur/transparency effects for visual depth
    - Sixel/Kitty graphics protocol support for inline images
    - Animated widget transitions
  - v1.12.0 features (enterprise & accessibility):
    - Session recording & playback for debugging TUI interactions
    - Audit logging infrastructure for compliance tracking
    - High contrast WCAG AAA themes (dark, light, amber, green)
    - Screen reader enhancements (OSC8 hyperlinks, ARIA attributes, JSON modes)
    - Keyboard-only navigation improvements (skip links, focus indicators)

### Developer Notes
- All features are opt-in and non-breaking
- Total unit tests: 819/827 (8 skipped, 0 leaks)
- Total integration tests: 939/940 (1 skipped, 0 leaks)
- CI status: GREEN (all cross-compile targets passing)

## [1.31.0] - 2026-03-13

### Added
- **Checkpoint/Resume for Long-Running Tasks** (`src/exec/checkpoint.zig`)
  - CheckpointStorage interface with vtable for pluggable backends
  - FileSystemStorage backend with JSON format
  - Task stdout monitoring for "CHECKPOINT: <data>" markers
  - Automatic checkpoint save (respecting interval_ms config)
  - Resume protocol via ZR_CHECKPOINT environment variable
  - Scheduler integration with worker thread support
  - 3 new integration tests (938-940)
  - Comprehensive documentation in configuration.md

### Developer Notes
- Total unit tests: 819/827 (8 skipped, 0 leaks)
- Total integration tests: 939/940 (1 skipped, 0 leaks)
- Checkpoint monitoring only works when inherit_stdio=false
- Interactive tasks cannot emit checkpoints (limitation documented)

## [1.30.0] - 2026-03-13

### Added
- **Enhanced Error Recovery** (`src/exec/scheduler.zig`)
  - Circuit breaker pattern with failure threshold tracking
  - Circuit states: closed → open (threshold exceeded) → half-open (reset timeout)
  - Workflow-level retry budget for limiting total retry attempts
  - Per-task circuit breaker state isolation
  - 9 new unit tests for circuit breaker and retry budget
  - 5 new integration tests (933-937)
  - Comprehensive documentation in configuration.md

### Developer Notes
- Total unit tests: 816/824 (8 skipped, 0 leaks)
- Total integration tests: 937/937 (936 passed, 1 skipped, 0 leaks)
- Circuit breaker state resets between zr run invocations

## [1.29.0] - 2026-03-13

### Added
- **Task Template System** (`src/cli/template.zig`)
  - Reusable task templates with parameter substitution
  - template and params fields in Task struct
  - Automatic template application with field merging
  - CLI commands: zr template list/show/apply
  - 12 new integration tests (921-932)
  - Comprehensive documentation in configuration.md

### Developer Notes
- Total unit tests: 807/815 (8 skipped, 0 leaks)
- Total integration tests: 931/932 (1 skipped, 0 leaks)

## [1.28.0] - 2026-03-12

### Added
- **Interactive TUI with Mouse Support** (`src/cli/tui_mouse.zig`)
  - Mouse input integration module with InputEvent union
  - SGR mouse event parsing (click/drag/scroll)
  - Interactive task picker mouse support (left-click to select)
  - Graph TUI mouse support (click nodes, scroll to navigate)
  - Live execution TUI mouse support (click tasks, scroll logs)
  - Thread-safe mouse tracking in background inputThread
  - 5 new unit tests for mouse input handling
  - Updated documentation with navigation instructions

### Developer Notes
- Total unit tests: 801/809 (8 skipped, 0 leaks)
- Total integration tests: 919/920 (1 skipped, 0 leaks)
- Leveraged sailor v1.10.0 mouse input features

## [1.27.0] - 2026-03-12

### Added
- **Live Resource Monitoring Dashboard** (`src/cli/monitor.zig`)
  - MonitorDashboard component for real-time task execution monitoring
  - ASCII bar charts for CPU usage (10 rows × 60 columns)
  - ASCII bar charts for memory usage (8 rows × 60 columns)
  - Task status table with color-coded status (running/completed/failed)
  - Bottleneck detection algorithm (CPU > 80%, memory > 500MB)
  - Circular buffer history (60 data points at 1Hz update interval)
  - Foundation for future live TUI monitoring features

### Developer Notes
- Total unit tests: 796/804 (8 skipped, 0 leaks) — +4 new tests
- Total integration tests: 919/920 (1 skipped, 0 leaks)
- New tests: MonitorDashboard init/deinit, addTask, formatBytes, estimateBytesLen
- Existing `--monitor` flag integration tests (916-920) continue to pass
- Remote monitoring server (WebSocket) deferred to v1.31.0

## [1.22.0] - 2026-03-09

### Changed
- **Sailor Library Upgrade**: Updated from v1.5.0 to v1.7.0
  - **v1.6.0 features**: Data visualization widgets (ScatterPlot, Histogram, TimeSeriesChart, Heatmap, PieChart)
  - **v1.7.0 features**: Advanced layout and rendering
    - FlexBox layout: CSS flexbox-inspired with justify/align support
    - Viewport clipping: Efficient rendering of large virtual buffers
    - Shadow & 3D border effects: Visual depth for widgets
    - Custom widget traits: Extensible widget protocol
    - Layout caching: LRU cache for constraint computation
  - All new features are opt-in and non-breaking
  - Enables future TUI enhancements with advanced data visualization and layout capabilities

### Developer Notes
- Total unit tests: 769/777 (8 skipped, 0 leaks)
- Total integration tests: 894/894 (100% pass rate)
- No breaking changes, seamless upgrade from v1.5.0

## [1.21.0] - 2026-03-09

### Added
- **TUI Testing Framework**: Comprehensive test coverage for all TUI modes using sailor v1.5.0 MockTerminal
  - **MockTerminal snapshot tests**: 19 new unit tests for pixel-perfect TUI rendering verification
  - **TUI Runner tests**: 5 tests covering empty runner, single task, multiple states, resize events, char/style access
  - **Graph TUI tests**: 8 tests including buildTreeNodes unit tests and MockTerminal snapshot tests
  - **List TUI tests**: 6 tests for empty items, single task, multiple items, navigation, truncation, and helper functions
  - All tests verify proper rendering, selection highlighting, and layout consistency
- **Documentation**: Added TUI testing guide to CONTRIBUTING.md with MockTerminal usage examples

### Developer Notes
- Total unit tests: 769 (up from 763), all integration tests pass (894/894)
- Event bus and command pattern integration deferred to future versions as optional enhancements
- All TUI modes (runner, graph, list) now have comprehensive snapshot test coverage

## [1.18.0] - 2026-03-08

### Added
- **Conditional Task Execution**: Control task execution with powerful conditional expressions
  - **Git predicates**: Check repository state in task conditions
    - `git.branch`: Current branch name (e.g., `skip_if = "git.branch != 'main'"`)
    - `git.tag`: Current tag if HEAD is tagged (e.g., `skip_if = "git.tag == 'v1.0.0'"`)
    - `git.dirty`: Boolean indicating uncommitted changes (e.g., `skip_if = "git.dirty"`)
    - Supports `==` and `!=` operators for branch/tag comparisons
  - **skip_if**: Skip task execution when condition evaluates to true
    - Evaluated before task execution
    - Failed conditions default to `false` (task runs)
    - Skipped tasks report success with zero exit code
    - Example: `skip_if = "env.CI != 'true'"` (skip unless in CI)
  - **output_if**: Control task output visibility based on conditions
    - Evaluated at task execution time
    - Failed conditions default to `true` (show output)
    - Example: `output_if = "env.DEBUG == 'true'"` (hide output unless debugging)
  - **Integration tests**: 9 comprehensive tests covering all predicates and conditions

### Fixed
- Parser state bleed between TOML sections (caused incorrect task field assignments)
- Missing `!=` operator support in git predicate expressions
- CI test failures due to inconsistent git default branch naming

### Developer Notes
- All 746 unit tests pass (8 skipped), all 890 integration tests pass
- Comprehensive error diagnostics for condition failures deferred to v1.20.0

## [1.17.0] - 2026-03-08

### Added
- **Advanced Watch Mode**: Enhanced file watching with debouncing and pattern filtering
  - **Debouncing**: Configurable delay (`debounce_ms`) to coalesce rapid file changes
    - Default: 300ms delay before triggering task execution
    - Set to 0 to disable debouncing (execute immediately on each change)
    - Prevents excessive rebuilds during rapid editing sessions
  - **Pattern-based filtering**: Glob patterns for precise control over watched files
    - `patterns`: Include only specific file types (e.g., `["**/*.zig", "*.toml"]`)
    - `exclude_patterns`: Exclude directories/files (e.g., `["**/node_modules/**", "**/.git/**"]`)
    - Exclude patterns take precedence over include patterns
    - Empty include list watches all files (unless excluded)
  - **Watch configuration in TOML**: `[tasks.*.watch]` section for task-specific settings
    - `debounce_ms`: Delay in milliseconds (default: 300)
    - `patterns`: Array of glob patterns for inclusion
    - `exclude_patterns`: Array of glob patterns for exclusion
    - `mode`: "native" or "polling" (auto-selects if null)
  - **Enhanced watcher implementation**: Updated `src/watch/watcher.zig` with filtering logic
    - New `WatcherOptions` struct for configuration
    - `matchesPatterns()` method for glob-based filtering
    - Debouncing logic with timestamp tracking and event coalescing
    - Backwards compatible: existing code works without changes
  - **CLI integration**: Watch mode automatically applies task configuration
    - Shows active settings in output: "(using native mode, debounce: 500ms, patterns: 2)"
    - Pattern and debounce info displayed when configured
  - **Tests**: 3 new unit tests for pattern filtering (include, exclude, combined)
  - **Documentation**: Comprehensive guide in `docs/guides/configuration.md`
    - Complete field reference with examples
    - Usage patterns and best practices
    - Pattern matching rules and debouncing behavior

### Changed
- Watcher initialization now requires `WatcherOptions` parameter (backwards compatible with `.{}`)
- Watch mode output shows configuration details when debouncing or patterns are active

### Developer Notes
- All 746 unit tests pass (8 skipped), all 881 integration tests pass
- Existing watch_test.zig integration tests verify TOML parsing of watch config

## [1.16.0] - 2026-03-07

### Added
- **Task Execution Analytics**: Resource usage tracking and enhanced reporting
  - **Resource tracking**: Peak memory and average CPU monitoring
    - Sampled at 100ms intervals during task execution
    - Peak memory recorded in bytes (max RSS usage)
    - Average CPU calculated from samples (percentage)
  - **Analytics collector**: Extended TaskStats with resource metrics
    - Integrated into scheduler's result tracking
    - Zero configuration required
  - **Enhanced reports**: HTML/JSON output includes resource columns
    - Peak memory displayed in human-readable format (MB/GB)
    - Average CPU shown as percentage
    - Sortable columns in HTML reports
  - **Tests**: 2 new integration tests (874-875) verifying resource tracking
  - **Documentation**: Updated commands.md with resource tracking examples

### Changed
- Analytics reports now include peak_memory_bytes and avg_cpu_percent columns
- HTML report tables extended with resource usage metrics

## [1.15.0] - 2026-03-07

### Added
- **Workspace-wide cache invalidation**: Clear cache for all workspace members at once
  - `zr cache clear --workspace` clears cache for root and all member projects
  - `zr cache clear --member <path>` clears cache for specific workspace member
  - Enables efficient cache management in multi-project workspaces
  - Integration tests: 4 new tests (870-873) verifying workspace cache features
  - Documentation: Updated commands.md with examples and flag descriptions
- **Sailor v1.5.0 migration**: Testing utilities and state management
  - Widget snapshot testing: `assertSnapshot()` method for pixel-perfect TUI verification
  - EventSimulator and MockTerminal available for TUI testing
  - Event bus and Command pattern for future TUI features
  - Non-breaking upgrade: all tests pass (743/751 unit, 873/873 integration)

### Changed
- Workspace cache commands now support targeting specific members
- Cache clearing operations provide better feedback for workspace scenarios

### Developer Notes
- Expression diagnostics integration deferred to future milestone (requires refactoring ~15 functions)
- Future enhancements planned: dependency visualization improvements, cross-workspace tasks

## [1.14.0] - 2026-03-07

### Added
- **Enhanced Error Diagnostics**: Comprehensive diagnostic framework for debugging task failures
  - **Timeline tracking**: Records all task execution events (started, completed, retry_started, skipped, cancelled, timeout, memory_limit)
    - Automatic duration analysis and execution analytics
    - Longest task identification, retry/skip/cancel/timeout counts
    - Integrated directly into scheduler (zero configuration)
  - **Failure replay mode**: Captures full context for failed tasks
    - Records cmd, cwd, env, exit code, timeline events
    - Automatic storage to `.zr/failures` directory
    - Full diagnostic information for post-mortem analysis
  - **CLI command**: `zr failures [list|clear]` to view and manage captured failure reports
    - `--task=<name>` to filter by specific task
    - `--storage-dir=<path>` to customize storage location (default: `.zr/failures`)
    - Color-coded output with detailed failure context
  - **Expression diagnostics module**: Foundation for stack traces in expression evaluation
    - `src/config/expr_diagnostics.zig` with StackFrame, DiagContext, DiagnosticError types
    - Integration into expression evaluator deferred to v1.15.0
- **Integration**: Timeline and replay managers automatically initialized in scheduler (commit a7218f0)
  - Zero configuration - works out of the box for all task executions
  - Failure contexts captured on task failure with full diagnostic information
  - Worker threads track events through shared timeline
- **Tests**: 10 new unit tests (743/751 total, 8 skipped), 3 new integration tests (865 total, 100% pass rate)
  - All integration tests pass (865/865)
  - Known issue: Minor memory leak in unit tests (non-blocking)

### Fixed
- **Memory leaks in failures integration tests**: Fixed tests 863-864 by properly freeing writeTmpConfig() return value (commit 972f627)

## [1.13.0] - 2026-03-03

### Added
- **Parallel Execution Optimizations**: CPU affinity and NUMA awareness for performance-critical tasks
  - `cpu_affinity` field: Pin tasks to specific CPU cores (array of core IDs)
  - `numa_node` field: Bind tasks to specific NUMA nodes
  - Work-stealing deque (Chase-Lev algorithm) for future scheduler improvements
  - NUMA topology detection (Linux + fallback for other platforms)
  - Cross-platform CPU affinity support (Linux, Windows, macOS)
  - Best-effort implementation: silently ignored if platform doesn't support affinity
  - Use cases: Cache locality, avoiding CPU migration, reducing memory latency
- **Documentation**: Comprehensive CPU affinity and NUMA guide in configuration.md
  - Platform support matrix (Linux: full, Windows: full, macOS: advisory)
  - Example configurations for database, web server, ML training
  - Performance tuning guidance
- **Integration tests**: 5 new tests for cpu_affinity/numa_node TOML parsing (tests 853-857)
- **Partial version resolution**: `zr tools install` now supports partial version specifications
  - `node@20` resolves to latest 20.x.x version
  - `node@20.11` resolves to latest 20.11.x version
  - Currently supports Node.js (other toolchains coming soon)
  - Provides helpful error messages for unsupported toolchains

### Changed
- Scheduler WorkerCtx now includes cpu_affinity and numa_node fields
- Worker threads set CPU affinity at start (if specified in task)

### Fixed
- **Linux cross-compilation**: Replaced CPU_ZERO/CPU_SET macros with direct bit manipulation
  - Fixes build failures on x86_64-linux-gnu and aarch64-linux-gnu targets
  - CPU_ZERO/CPU_SET macros from sched.h cannot be translated by Zig's @cImport
  - Uses @memset and manual bitset operations for cpu_set_t manipulation
- **Child.Term handling**: Use switch statement for proper tagged union access in toolchain downloader
  - Fixes Zig 0.15.2 compatibility issue with `result.term.Exited` access pattern
  - Properly handles all exit status cases (Exited, Signaled, Stopped, Unknown)

## [1.12.0] - 2026-03-03

### Added
- **Auto-generated stage names for anonymous workflow stages**: TOML array-of-tables syntax `[[workflows.X.stages]]` without explicit `name =` field now works correctly
  - Parser auto-generates names like "stage-1", "stage-2", etc. for anonymous stages
  - Works seamlessly with mixed named/anonymous stages
  - All example configs (docker-kubernetes, github-actions-ci) now parse correctly
- **Unit tests**: 3 new parser tests for anonymous stage handling (730/738 total)
- **Integration tests**: 3 new workflow tests for anonymous stages (852/852 total)

### Fixed
- **Anonymous workflow stages no longer discarded**: Previously, stages without `name =` were silently dropped during parsing
  - Fixes "0 stages" validation warnings in example configs
  - Resolves Known Limitation documented in debugging.md
- **flushPendingStage() helper**: Refactored 5 stage flush points to use unified helper function
  - Ensures consistent behavior across all section transitions
  - Proper memory management with auto-generated names

### Changed
- Enhanced TOML parser with anonymous stage name generation logic
- Improved workflow stage handling for better ergonomics

## [1.10.1] - 2026-03-02

### Fixed
- **Windows stdin buffering**: Fixed prompt display issue in `zr add` command on Windows
  - Added explicit stdout flush before reading stdin
  - Ensures prompts appear correctly before user input
  - Fixes issue where prompts appeared after entering input

## [1.10.0] - 2026-03-02

### Added
- **Conditional dependencies (`deps_if`)**: Run dependencies only when a condition evaluates to true
  - Syntax: `deps_if = [{ task = "lint", condition = "env.CI == 'true'" }]`
  - Supports full expression engine (env vars, platform checks, boolean logic)
  - Useful for environment-specific workflows (CI-only linting, platform-specific builds)
- **Optional dependencies (`deps_optional`)**: Silently skip dependencies if they don't exist
  - Syntax: `deps_optional = ["format", "optional-task"]`
  - Runs the dependency if defined, skips without error if not found
  - Useful for conditional features or plugin-based workflows
- **Integration tests**: 5 new tests for conditional/optional dependency execution (837/837 total)
- **Unit tests**: 16 new tests for deps v2 parser, graph builder, validation, and helper functions (716/724 total)

### Changed
- Enhanced dependency traversal in scheduler to support conditional and optional deps
- Updated configuration documentation with `deps_if` and `deps_optional` examples

### Fixed
- Execution logic now correctly evaluates conditional dependencies during graph building

## [1.9.0] - 2026-03-02

### Added
- **Accessibility features**: Enhanced TUI with screen reader support and better visual feedback
  - Position indicator in header showing current selection (e.g., "selected: 3/10")
  - Item count display for context awareness
  - Distinctive [T]/[W] symbols for task/workflow type differentiation
  - Footer showing currently selected item details
  - Improved semantic labels for better screen reader compatibility
- **Unicode width calculation**: Proper display width for CJK characters and emoji in TUI
  - Fixes alignment issues with multibyte characters
  - Supports full Unicode width calculation (combining characters, zero-width, etc.)
- **Enhanced keyboard navigation**: Extended TUI navigation shortcuts
  - `g/G`: Jump to top/bottom of list (Vim-style)
  - `Home/End`: Navigate to first/last item
  - `PgUp/PgDn`: Page up/down through lists
  - Arrow key support (↑/↓) in addition to j/k

### Changed
- Upgraded sailor library to v1.2.0 (layout & composition features)
- Improved TUI layout with dedicated footer area
- Better visual hierarchy with semantic type indicators

## [1.8.0] - 2026-03-02

### Added
- **Toolchain auto-update**: `zr tools upgrade` command for managing installed toolchains
  - `zr tools upgrade`: Dry-run mode shows available updates for all installed tools
  - `zr tools upgrade --check-updates`: Auto-install latest versions
  - `zr tools upgrade --cleanup`: Remove old versions after upgrade
  - Kind filtering support (e.g., `zr tools upgrade node`)
  - Version conflict resolution strategy (keeps only latest version)
- **Integration tests**: 7 new tests for `zr tools upgrade` command (826/831 total integration tests)
- **Unit tests**: 4 new tests for upgrade logic (689/697 total unit tests)

### Changed
- Enhanced toolchain management with automated upgrade workflow
- Improved version conflict detection and resolution

## [1.7.0] - 2026-03-02

### Added
- **String interning (StringPool)**: Memory-efficient string deduplication
  - Reduces heap allocations for repeated strings (task names, file paths, etc.)
  - 30-50% memory reduction in typical workloads
- **Object pooling (ObjectPool(T))**: Reusable object allocation
  - Eliminates allocation churn for frequently created/destroyed objects
  - Improves performance for hot paths (task execution, graph traversal)
- **Automated benchmark suite**: Hyperfine-based performance testing
  - `scripts/bench.sh`: Automated benchmark runner comparing against Make, Just, Task
  - Cold start benchmarks (empty task, 10 tasks, 100 tasks)
  - Parallel execution benchmarks (2/4/8 workers)
  - Results: 17% faster cold start, 28% lower RSS memory

### Changed
- Optimized task graph construction with string interning
- Reduced memory footprint with object pooling
- Updated benchmark documentation with Quick Start guide

### Performance
- Cold start: ~5ms → ~4.2ms (17% improvement)
- Memory (RSS): ~2.5MB → ~1.8MB (28% reduction)
- Binary size: Maintained at ~1.2MB

## [1.6.0] - 2026-03-02

### Added
- **Interactive configuration builder**: `zr add` command for creating tasks, workflows, and profiles interactively
  - `zr add task [name]`: Interactive task creation with prompts for cmd, description, dependencies
  - `zr add workflow [name]`: Interactive workflow creation with multi-stage support (each stage accepts comma-separated task lists)
  - `zr add profile [name]`: Interactive profile creation with environment variables (KEY=VALUE format)
  - Smart stdin handling with byte-by-byte reading (Zig 0.15 compatible)
  - Yes/no prompts for optional fields
  - Graceful error handling (missing config file, EOF, empty input)
  - Appends to existing `zr.toml` file without overwriting
- **Integration tests**: 6 new tests for `zr add` command (819/819 total, 100% pass rate)
- **Documentation**: Updated getting-started.md and commands.md with comprehensive examples and usage notes

### Fixed
- stdin error handling: Added `NotOpenForReading` to catch closed stdin in tests
- ArrayList API: Updated to Zig 0.15.2 unmanaged API (`.{}` initialization, allocator parameters for `.append`, `.deinit`, `.writer`)

### Closed Issues
- Closes #11 (need interactive add feature)

## [1.5.0] - 2026-03-02

### Added
- **Remote cache compression**: gzip compression for remote cache entries (reduces network transfer and storage costs)
  - New `compression` field in `RemoteCacheConfig` (default: true)
  - Auto-compress on push, auto-decompress on pull
  - Cross-platform using gzip CLI
- **Incremental sync**: Chunked upload/download for remote cache with deduplication
  - Split large cache entries into 1MB chunks
  - Track chunks via SHA256 hashes in manifest
  - Upload only missing chunks (deduplication across entries)
  - New `incremental_sync` field in `RemoteCacheConfig` (default: false)
  - Works with all backends (HTTP, S3, GCS, Azure)
- **Enhanced cache stats dashboard**: Improved `zr cache status` command
  - Human-readable size formatting (B, KB, MB, GB)
  - Average entry size calculation
  - Enhanced visual layout with separator line

### Changed
- Updated cache statistics display from "Cache Status" to "Cache Statistics" with better formatting

## [1.4.0] - 2026-03-02

### Added
- **Plugin registry client**: HTTP client for `registry.zr.dev` API with search, list, and getPlugin endpoints
- **Remote plugin search**: `zr plugin search --remote <query>` to browse the central plugin registry
- **Registry documentation**: Complete API specification in `docs/plugin-registry-api.md`
- **Graceful fallback**: CLI continues to work when registry is unreachable (returns empty results)
- **Integration tests**: 3 new tests (811-813) for remote search functionality

### Changed
- Updated `zr plugin search` help text to document `--remote` flag
- Enhanced PLUGIN_GUIDE.md with registry usage examples and API information
- Updated commands.md with remote search options and examples

## [1.3.0] - 2026-03-02

### Added
- **Interactive graph TUI mode**: `zr graph --format=tui` with sailor Tree widget for dependency visualization
- **Sailor v1.0.3 migration**: Updated to latest sailor library with Zig 0.15.2 compatibility fixes

### Fixed
- Re-enabled graph TUI mode (was temporarily disabled pending sailor#8 fix)
- Tree widget ArrayList API compatibility with Zig 0.15.2

### Changed
- Updated sailor dependency from v1.0.2 to v1.0.3

## [1.0.2] - 2026-03-01

### Fixed
- Windows terminal ANSI color code bleeding
- Windows console codepage UTF-8 setup for proper ANSI escape sequence handling

## [1.0.1] - 2026-02-28

### Fixed
- Minor post-release documentation improvements

## [1.0.0] - 2026-02-28

### Added

#### Phase 13 - v1.0 Release
- **Comprehensive documentation site**: 6 user guides (getting-started, configuration, commands, mcp-integration, lsp-setup, adding-language)
- **Migration guides**: `zr init --from-make`, `--from-just`, `--from-task` automatic conversion
- **README overhaul**: Complete rewrite with feature matrix, quick start, and comparison tables
- **Installation scripts**: `install.sh` (macOS/Linux) and `install.ps1` (Windows) for automated binary deployment
- **Contributor guide**: CONTRIBUTING.md with development setup, coding standards, and workflow

#### Phase 12 - Performance & Stability
- **Binary optimization**: ReleaseSmall + strip options (~1.2MB binary)
- **Fuzz testing**: TOML parser, expression engine, JSON-RPC parser (10min+ crash-free)
- **Benchmark dashboard**: Performance comparison vs Make, Just, Task(go-task)

#### Phase 11 - LSP Server
- **LSP core + diagnostics**: Full LSP server with document management and TOML parse error diagnostics
- **Auto-completion**: Context-aware completion for task names, field names, deps, expression keywords
- **Hover documentation**: Field hover docs and go-to-definition for deps → task definitions

#### Phase 10 - MCP Server
- **MCP Server core**: JSON-RPC based MCP server with 9 tools (run_task, list_tasks, show_task, validate_config, show_graph, run_workflow, task_history, estimate_duration, generate_config)
- **Auto-detection**: `zr init --detect` generates zr.toml from detected language providers

#### Phase 9 - Infrastructure + DX Quick Wins
- **LanguageProvider interface**: 8 languages (Node, Python, Zig, Go, Rust, Deno, Bun, Java) with single-file addition pattern
- **JSON-RPC shared infrastructure**: Content-Length + newline-delimited transport for MCP/LSP
- **"Did you mean?" suggestions**: Levenshtein distance-based typo suggestions for commands and task names
- **Error message improvements**: Line/column numbers in parse errors, similar name suggestions for missing deps

#### Additional Improvements
- **Version display**: Binary version derived from build.zig.zon as single source of truth
- **15 example projects**: Docker/Kubernetes, Make migration, all 8 language providers, plugin examples
- **Sailor library integration**: v0.5.1 for arg parsing, color, progress, JSON formatting, TUI widgets

### Changed
- Upgraded from development (v0.0.5) to production-ready (v1.0.0)
- All 13 PRD phases complete with comprehensive test coverage

### Performance
- Binary size: ~1.2MB (ReleaseSmall)
- Cold start: < 10ms (~4ms measured)
- Memory usage: ~2-3MB RSS
- Unit tests: 670/678 (8 skipped, 0 memory leaks)
- Integration tests: 805/805 (100% pass rate)
- Cross-compilation: 6 targets (linux/macos/windows x x86_64/aarch64)

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
| **1.0.0** | 2026-02-28 | 9-13 | MCP/LSP servers, LanguageProvider, DX improvements, binary optimization, documentation |
| **0.0.5** | 2026-02-23 | - | Shell environment export, task-specific env layering |
| **0.0.4** | 2026-02-23 | 5-8 | Enterprise features, Multi-repo, Toolchain management, Remote cache |
| **0.0.3** | 2026-02-20 | 3-4 | Interactive TUI, Resource limits, WASM plugins, Docker plugin |
| **0.0.2** | 2026-02-17 | 1-2 | MVP task runner, Workflows, Expression engine, Watch mode |
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

- [GitHub Repository](https://github.com/yusa-imit/zr)
- [Documentation](./docs/)
- [PRD (Product Requirements)](./docs/PRD.md)
- [Plugin Development Guide](./docs/PLUGIN_DEV_GUIDE.md)
- [Plugin User Guide](./docs/PLUGIN_GUIDE.md)

[Unreleased]: https://github.com/yusa-imit/zr/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yusa-imit/zr/compare/v0.0.5...v1.0.0
[0.0.5]: https://github.com/yusa-imit/zr/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/yusa-imit/zr/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/yusa-imit/zr/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/yusa-imit/zr/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/yusa-imit/zr/releases/tag/v0.0.1
