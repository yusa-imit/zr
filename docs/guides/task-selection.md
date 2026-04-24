# Task Selection & Filtering

> **Since**: v1.77.0

zr provides powerful task selection patterns for efficiently targeting tasks in large monorepos and complex workflows. Instead of running tasks one-by-one by exact name, you can use glob patterns, tag-based filters, and combinations to select multiple tasks at once.

## Table of Contents

- [Quick Start](#quick-start)
- [Glob Pattern Matching](#glob-pattern-matching)
- [Tag-Based Selection](#tag-based-selection)
- [Combining Filters](#combining-filters)
- [Multiple Task Execution](#multiple-task-execution)
- [Dry-Run Preview](#dry-run-preview)
- [Real-World Examples](#real-world-examples)
- [Comparison with Other Tools](#comparison-with-other-tools)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

```bash
# Run all tasks matching a glob pattern
zr run 'test:*'

# Run all tasks with a specific tag
zr run build --tag=critical

# Exclude tasks with a tag
zr run test --exclude-tag=slow

# Combine patterns and tags
zr run 'build:*' --tag=production --exclude-tag=deprecated

# Preview without executing
zr run 'test:**' --dry-run
```

---

## Glob Pattern Matching

### Basic Syntax

zr supports glob patterns for task name matching, inspired by file system globs and Bazel's target patterns.

| Pattern | Matches | Example |
|---------|---------|---------|
| `*` | Any characters at single level | `test:*` → `test:unit`, `test:integration` |
| `**` | Any characters across multiple levels | `test:**` → `test:unit:api`, `test:integration:e2e` |
| `?` | Single character | `build?` → `build1`, `buildX` |
| `prefix*` | Tasks starting with prefix | `build*` → `build`, `build-prod`, `build-dev` |

**Note**: Pattern must be quoted in shell to prevent shell glob expansion:
```bash
# ✅ Correct — pattern passed to zr
zr run 'test:*'

# ❌ Wrong — shell expands * before zr sees it
zr run test:*
```

### Single-Level Wildcard (`*`)

Matches tasks at the same namespace level:

```bash
# Run all test tasks in root namespace
zr run 'test:*'
# Matches: test:unit, test:integration
# Skips: test:unit:api (nested)

# Run all build variants
zr run 'build:*'
# Matches: build:dev, build:prod, build:staging
```

### Multi-Level Wildcard (`**`)

Matches tasks at any depth:

```bash
# Run ALL test tasks (any nesting level)
zr run 'test:**'
# Matches: test:unit, test:integration, test:unit:api, test:e2e:browser

# Run all backend tasks
zr run 'backend:**'
# Matches: backend:api, backend:api:tests, backend:worker:queue
```

### Prefix Matching

Match tasks by prefix (no colon separator):

```bash
# All tasks starting with "build"
zr run 'build*'
# Matches: build, build-prod, build-dev, build-docker

# All lint tasks
zr run 'lint*'
# Matches: lint, lint-fix, lint-staged
```

### Pattern Examples

```toml
# Example zr.toml with namespaced tasks
[tasks.test:unit]
cmd = "zig test src/**.zig"

[tasks.test:integration]
cmd = "./scripts/integration.sh"

[tasks.test:e2e]
cmd = "playwright test"

[tasks.build:dev]
cmd = "zig build"

[tasks.build:prod]
cmd = "zig build -Doptimize=ReleaseSafe"

[tasks.deploy:staging]
cmd = "flyctl deploy --env staging"

[tasks.deploy:prod]
cmd = "flyctl deploy --env production"
```

```bash
# Run all tests
zr run 'test:*'

# Run all builds
zr run 'build:*'

# Run all deployments
zr run 'deploy:**'

# Run specific subset
zr run 'test:unit'  # Exact match still works
```

---

## Tag-Based Selection

### Basic Tag Filtering

Tasks can be tagged with metadata for categorization and selection:

```toml
[tasks.api-tests]
cmd = "pytest tests/api"
tags = ["integration", "api", "critical"]

[tasks.unit-tests]
cmd = "pytest tests/unit"
tags = ["unit", "fast"]

[tasks.e2e-tests]
cmd = "playwright test"
tags = ["e2e", "slow"]
```

```bash
# Run all critical tests
zr run test --tag=critical

# Run all integration tests
zr run test --tag=integration

# Run fast tests only
zr run test --tag=fast
```

### Multiple Tag Selection (AND Logic)

Use multiple `--tag` flags to require ALL tags (intersection):

```bash
# Tasks must have BOTH "integration" AND "critical"
zr run test --tag=integration --tag=critical

# Tasks must have ALL three tags
zr run build --tag=production --tag=docker --tag=optimized
```

**Example**:
```toml
[tasks.critical-api-test]
tags = ["integration", "critical", "api"]  # ✅ Matches

[tasks.basic-api-test]
tags = ["integration", "api"]  # ❌ Skipped (missing "critical")

[tasks.critical-unit-test]
tags = ["unit", "critical"]  # ❌ Skipped (missing "integration")
```

```bash
zr run test --tag=integration --tag=critical
# Only runs: critical-api-test
```

### Tag Exclusion

Exclude tasks with specific tags using `--exclude-tag`:

```bash
# Run all tests EXCEPT slow ones
zr run test --exclude-tag=slow

# Run all builds EXCEPT deprecated ones
zr run build --exclude-tag=deprecated

# Exclude multiple tags (OR logic — exclude if ANY match)
zr run test --exclude-tag=slow --exclude-tag=flaky
```

**Example**:
```toml
[tasks.quick-test]
tags = ["test", "fast"]  # ✅ Matches

[tasks.integration-test]
tags = ["test", "slow"]  # ❌ Excluded (has "slow")

[tasks.stress-test]
tags = ["test", "slow", "resource-intensive"]  # ❌ Excluded (has "slow")
```

```bash
zr run test --exclude-tag=slow
# Only runs: quick-test
```

### Combining Include and Exclude

```bash
# Run critical tests that are NOT slow
zr run test --tag=critical --exclude-tag=slow

# Run integration tests that are NOT flaky
zr run test --tag=integration --exclude-tag=flaky --exclude-tag=deprecated
```

---

## Combining Filters

All filter types can be combined for precise task selection.

### Glob + Tag

```bash
# Run all test:* tasks that are critical
zr run 'test:*' --tag=critical

# Run all build:* tasks that are production-ready
zr run 'build:*' --tag=production

# Run backend tasks tagged as API
zr run 'backend:**' --tag=api
```

### Glob + Exclude

```bash
# Run all builds except dev builds
zr run 'build*' --exclude-tag=dev

# Run all tests except slow/flaky ones
zr run 'test:**' --exclude-tag=slow --exclude-tag=flaky
```

### All Filters Combined

```bash
# Complex filter: test namespace, critical tag, exclude slow/flaky
zr run 'test:**' --tag=critical --exclude-tag=slow --exclude-tag=flaky

# Build pattern, production tag, exclude deprecated/experimental
zr run 'build:*' --tag=production --exclude-tag=deprecated --exclude-tag=experimental
```

---

## Multiple Task Execution

When a filter matches multiple tasks, zr executes them according to dependency order and parallelization settings.

### Execution Order

1. **With dependencies**: Tasks run in topological order respecting `deps` declarations
2. **Without dependencies**: Tasks run in parallel (up to `--jobs` limit)
3. **Serial dependencies**: `deps_serial` forces sequential execution

```toml
[tasks.test:unit]
cmd = "zig test"

[tasks.test:integration]
cmd = "./integration.sh"
deps = ["test:unit"]  # Runs after test:unit

[tasks.test:e2e]
cmd = "playwright test"
deps = ["test:integration"]  # Runs after test:integration
```

```bash
# Glob matches all three → runs in order: unit → integration → e2e
zr run 'test:*'
```

### Error Handling

By default, zr stops on first failure. Use `--keep-going` to continue:

```bash
# Stop on first test failure (default)
zr run 'test:**'

# Run all tests even if some fail
zr run 'test:**' --keep-going

# Dry-run to preview execution order
zr run 'test:**' --dry-run
```

### Task Count Limits

```bash
# Limit parallel execution
zr run 'build:*' --jobs=2

# Sequential execution
zr run 'test:**' --jobs=1
```

---

## Dry-Run Preview

Preview which tasks will run without executing them:

```bash
# Show tasks that match glob pattern
zr run 'test:*' --dry-run

# Show tasks with specific tags
zr run build --tag=critical --dry-run

# Show combined filter results
zr run 'backend:**' --tag=api --exclude-tag=deprecated --dry-run
```

**Example output**:
```
[dry-run] Would execute 3 tasks:
  1. test:unit (tags: unit, fast)
  2. test:integration (tags: integration, critical)
  3. test:e2e (tags: e2e, slow)

[dry-run] Filtered out 2 tasks:
  - test:stress (excluded by --exclude-tag=slow)
  - test:flaky (excluded by --exclude-tag=flaky)
```

---

## Real-World Examples

### Monorepo CI/CD

```toml
# packages/frontend/zr.toml
[tasks.test:unit]
tags = ["test", "fast", "ci"]

[tasks.test:e2e]
tags = ["test", "slow", "ci"]

[tasks.lint]
tags = ["check", "fast", "ci"]

[tasks.build]
tags = ["build", "ci"]

# packages/backend/zr.toml
[tasks.test:unit]
tags = ["test", "fast", "ci"]

[tasks.test:integration]
tags = ["test", "slow", "ci"]

[tasks.lint]
tags = ["check", "fast", "ci"]

[tasks.build]
tags = ["build", "ci"]
```

```bash
# CI: Run all fast checks in parallel
zr run --tag=ci --tag=fast

# CI: Run all tests (with dependencies)
zr run 'test:**' --tag=ci

# Local: Quick validation (exclude slow tests)
zr run --tag=ci --exclude-tag=slow

# Pre-deployment: Critical path only
zr run --tag=critical --tag=production
```

### Environment-Specific Builds

```toml
[tasks.build:dev]
tags = ["build", "dev", "fast"]
cmd = "zig build"

[tasks.build:staging]
tags = ["build", "staging", "optimized"]
cmd = "zig build -Doptimize=ReleaseSafe"

[tasks.build:prod]
tags = ["build", "production", "optimized", "critical"]
cmd = "zig build -Doptimize=ReleaseSmall"

[tasks.build:debug]
tags = ["build", "dev", "debug"]
cmd = "zig build -Ddebug=true"
```

```bash
# Development: Quick unoptimized builds
zr run 'build:*' --tag=dev

# Pre-production: Optimized builds for staging/prod
zr run 'build:*' --tag=optimized

# Critical path: Production build only
zr run 'build:*' --tag=critical
```

### Test Suites

```toml
[tasks.test:unit:api]
tags = ["test", "unit", "api", "fast"]

[tasks.test:unit:core]
tags = ["test", "unit", "core", "fast"]

[tasks.test:integration:api]
tags = ["test", "integration", "api", "slow"]

[tasks.test:integration:db]
tags = ["test", "integration", "db", "slow"]

[tasks.test:e2e:smoke]
tags = ["test", "e2e", "critical"]

[tasks.test:e2e:full]
tags = ["test", "e2e", "slow"]
```

```bash
# Quick pre-commit: Fast tests only
zr run 'test:**' --tag=fast

# Full test suite: All tests
zr run 'test:**'

# Integration tests only
zr run 'test:**' --tag=integration

# Critical smoke tests
zr run 'test:**' --tag=critical

# Unit tests for API module
zr run 'test:unit:**' --tag=api
```

### Language-Specific Tasks

```toml
[tasks.lint:zig]
tags = ["lint", "zig"]
cmd = "zig fmt --check src/"

[tasks.lint:python]
tags = ["lint", "python"]
cmd = "ruff check ."

[tasks.lint:typescript]
tags = ["lint", "typescript"]
cmd = "eslint src/"

[tasks.test:zig]
tags = ["test", "zig"]
cmd = "zig build test"

[tasks.test:python]
tags = ["test", "python"]
cmd = "pytest"

[tasks.test:typescript]
tags = ["test", "typescript"]
cmd = "vitest"
```

```bash
# Run all Zig-related tasks
zr run --tag=zig

# Run all linters
zr run 'lint:*'

# Run tests for specific language
zr run --tag=test --tag=python
```

---

## Comparison with Other Tools

### vs. Bazel

```bash
# Bazel target patterns
bazel test //...                    # All tests
bazel test //backend/...            # All backend tests
bazel test //backend:api_test       # Specific test

# zr equivalent
zr run 'test:**'                    # All tests
zr run 'backend:test:**'            # All backend tests (via namespace)
zr run backend:api_test             # Specific test
```

### vs. Nx

```bash
# Nx affected detection
nx affected --target=test           # Tests for changed code
nx run-many --target=build --all    # All builds
nx run-many --target=test --projects=api,worker

# zr equivalent (v1.77.0 has manual filtering)
zr run 'test:**' --tag=affected     # Manual tagging required
zr run 'build:**'                   # All builds
zr run api:test worker:test         # Multiple tasks by name
```

### vs. Task (go-task)

Task v3.35+ has no built-in glob or tag filtering — only run by exact name or `--list-all`:

```bash
# Task — no filtering support
task test:unit
task test:integration
# Must list all tasks manually

# zr — pattern-based selection
zr run 'test:*'
zr run 'test:**' --tag=critical
```

### vs. Just

Just v1.25+ has no glob patterns, no tags — only exact recipes:

```bash
# Just — manual invocation
just test-unit test-integration test-e2e

# zr — pattern matching
zr run 'test:*'
```

---

## Best Practices

### 1. Use Meaningful Namespaces

Organize tasks into logical namespaces for easier glob matching:

```toml
# ✅ Good — clear hierarchy
[tasks.test:unit:api]
[tasks.test:unit:core]
[tasks.test:integration:api]
[tasks.build:dev]
[tasks.build:prod]
[tasks.deploy:staging]
[tasks.deploy:prod]

# ❌ Avoid — flat structure harder to filter
[tasks.api-unit-test]
[tasks.core-unit-test]
[tasks.api-integration-test]
```

### 2. Tag Consistently

Use a consistent tagging taxonomy across your project:

```toml
# Standard tags
tags = ["test", "fast"]           # Category + performance
tags = ["build", "production"]    # Category + environment
tags = ["deploy", "critical"]     # Category + priority

# Anti-pattern: Inconsistent taxonomy
tags = ["testing", "quick"]       # Mixing singular/plural, synonyms
tags = ["build-task", "prod"]     # Redundant prefixes
```

### 3. Prefer Glob Patterns for Namespace Selection

```bash
# ✅ Good — concise glob pattern
zr run 'test:*'

# ❌ Verbose — listing all tasks
zr run test:unit test:integration test:e2e
```

### 4. Use Tags for Cross-Cutting Concerns

```bash
# Cross-cutting: Critical tasks from multiple namespaces
zr run --tag=critical

# Cross-cutting: Fast tasks for quick feedback
zr run --tag=fast

# Cross-cutting: CI tasks (regardless of namespace)
zr run --tag=ci
```

### 5. Dry-Run Before Execution

Always preview with `--dry-run` when using complex filters:

```bash
# Preview first
zr run 'backend:**' --tag=production --exclude-tag=experimental --dry-run

# Then execute if correct
zr run 'backend:**' --tag=production --exclude-tag=experimental
```

### 6. Document Your Tagging Strategy

```toml
# Example: Document tags in workspace config
[workspace]
description = "Tagging taxonomy: [category, environment, priority, performance]"

# Category: test, build, deploy, lint, check
# Environment: dev, staging, production
# Priority: critical, optional
# Performance: fast, slow
```

---

## Troubleshooting

### No Tasks Matched

**Symptom**:
```
✗ No tasks matched pattern: test:xyz

  Pattern: test:xyz
  Available tasks: test:unit, test:integration, test:e2e
```

**Solutions**:
1. Check task names with `zr list`
2. Verify glob syntax (quote the pattern: `'test:*'` not `test:*`)
3. Use dry-run to preview: `zr run 'pattern' --dry-run`

### Pattern Not Working

**Symptom**: `zr run test:*` runs nothing or shell error

**Solutions**:
1. **Quote the pattern**: `zr run 'test:*'` (shell expands `*` if unquoted)
2. Escape special characters: `zr run 'test:\*'` or use single quotes
3. Check namespace separator: `test:*` (colon) vs `test*` (prefix)

### Tag Filter Returns Nothing

**Symptom**:
```
✗ No tasks matched filter: --tag=integration

  Tasks with tags: 12 total
  Tasks with tag "integration": 0
```

**Solutions**:
1. Check exact tag spelling: `integration` vs `Integration` (case-sensitive)
2. List tasks with tags: `zr list` shows all tags
3. Verify task definitions: tags must be lowercase

### Too Many Tasks Selected

**Symptom**: `zr run 'test:**'` runs 100+ tasks unexpectedly

**Solutions**:
1. Add exclusions: `zr run 'test:**' --exclude-tag=slow --exclude-tag=experimental`
2. Narrow pattern: `zr run 'test:unit:*'` instead of `zr run 'test:**'`
3. Preview first: `zr run 'test:**' --dry-run` to see what matches

### Execution Order Wrong

**Symptom**: Tasks run in wrong order or deadlock

**Solutions**:
1. Check dependencies: `deps`, `deps_serial` affect order
2. Use `--dry-run` to preview execution graph
3. Add missing dependencies to task definitions

---

## Future Enhancements

Planned for future releases:

- **Directory scoping**: `zr run --dir=packages/api` (select tasks by location)
- **OR logic for tags**: `--tags-any=critical,urgent` (match ANY tag)
- **Affected detection**: `zr run --affected` (git diff integration)
- **Regex patterns**: `zr run --pattern='test:.*-api$'` (regex matching)
- **Inverse patterns**: `zr run '!test:slow*'` (exclude patterns)

---

## Summary

Task selection in zr enables efficient workflow management through:

1. **Glob patterns** (`*`, `**`, `?`) for namespace-based selection
2. **Tag filters** (`--tag`, `--exclude-tag`) for metadata-based selection
3. **Combination filters** (glob + tags) for precise targeting
4. **Dry-run preview** (`--dry-run`) for safe exploration
5. **Multiple task execution** with dependency-aware ordering

**Key Commands**:
```bash
zr run 'pattern'                    # Glob pattern
zr run task --tag=value             # Tag filter
zr run task --exclude-tag=value     # Tag exclusion
zr run 'pattern' --tag=x --exclude-tag=y  # Combined
zr run ... --dry-run                # Preview
```

For more information:
- [Configuration Reference](./configuration.md) — Task definitions and tags
- [Commands Reference](./commands.md) — CLI usage and flags
- [Best Practices](./best-practices.md) — Large project organization
