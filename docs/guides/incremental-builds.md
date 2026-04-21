# Incremental Builds Guide

## Overview

Incremental builds allow zr to skip tasks whose outputs are already up-to-date, dramatically speeding up repeated executions. Similar to `make`'s file timestamp checking and Task's `sources`/`generates` pattern, zr tracks which files affect a task (sources) and which files the task produces (generates).

When you run a task, zr checks if:
1. All generated files exist
2. All generated files are newer than all source files
3. No dependencies have changed

If all conditions are met, the task is skipped. This is especially powerful for large codebases where most files don't change between runs.

---

## Basic Usage

### Defining Sources and Generates

Add `sources` and `generates` fields to your task definition:

```toml
[tasks.build]
cmd = "zig build"
sources = ["src/**/*.zig", "build.zig", "build.zig.zon"]
generates = ["zig-out/bin/zr"]
description = "Build the zr binary"
```

**Sources** are files that affect the task's output:
- Source code files
- Configuration files
- Build scripts
- Dependencies (package manifests, lock files)

**Generates** are files created by the task:
- Compiled binaries
- Build artifacts
- Generated code
- Documentation outputs

### Running with Up-to-Date Detection

```bash
# First run: executes the task
$ zr run build
✓ build (5.2s)

# Second run: skips if sources unchanged
$ zr run build
⊘ build (up-to-date, skipped)

# Force execution even if up-to-date
$ zr run build --force
✓ build (5.1s)
```

---

## Glob Patterns

zr supports flexible glob patterns for matching multiple files:

### Pattern Syntax

| Pattern | Matches | Example |
|---------|---------|---------|
| `*` | Any characters except `/` | `*.ts` → `app.ts`, `util.ts` |
| `**` | Any characters including `/` (recursive) | `src/**/*.ts` → all `.ts` files in `src/` tree |
| `?` | Single character | `test?.ts` → `test1.ts`, `testA.ts` |
| `[abc]` | Character class | `[a-z]*.ts` → files starting with lowercase letter |

### Examples

```toml
[tasks.test]
cmd = "npm test"
# All TypeScript files in src/ (any depth)
sources = ["src/**/*.ts", "package.json"]
# All files in coverage/ directory
generates = ["coverage/**/*"]

[tasks.docs]
cmd = "typedoc"
# Source files and config
sources = [
    "src/**/*.ts",
    "tsconfig.json",
    "typedoc.json"
]
# Generated documentation
generates = [
    "docs/api/**/*.html",
    "docs/api/**/*.json"
]
```

---

## Dependency Propagation

**Critical feature**: If a task's dependency runs (not skipped), the task must run too — even if its own outputs are up-to-date.

### Why This Matters

Consider this pipeline:

```toml
[tasks.preprocess]
cmd = "python preprocess.py"
sources = ["data.raw"]
generates = ["data.processed"]

[tasks.analyze]
cmd = "python analyze.py"
sources = ["data.processed"]
generates = ["report.txt"]
deps = ["preprocess"]
```

**Scenario**:
1. First run: `data.raw` → `preprocess` → `data.processed` → `analyze` → `report.txt`
2. You modify `data.raw`
3. Second run: `preprocess` runs (source changed), `analyze` **must run** even if `report.txt` is newer than `data.processed`

Without dependency propagation, `analyze` would be skipped because `report.txt` is newer than `data.processed`. But `data.processed` just changed, so the report is stale.

### How It Works

zr tracks which tasks actually executed (not skipped). Before checking if a task is up-to-date:
1. Check if any dependencies ran in this execution
2. If yes → force this task to run
3. If no → perform normal up-to-date check

This ensures correctness while still skipping tasks when safe.

---

## Status Display

### Check Task Status

See which tasks are up-to-date without running them:

```bash
$ zr list --status

Available tasks:
  [✓] build         — Build the zr binary (up-to-date)
  [✗] test          — Run unit tests (stale: sources changed)
  [?] docs          — Generate documentation (never run)
  [✓] benchmark     — Performance benchmarks (up-to-date)
```

**Status indicators**:
- `[✓]` (green) — Up-to-date: all generates exist and are newer than sources
- `[✗]` (red) — Stale: sources changed since last run
- `[?]` (dim) — Unknown: task has no `generates` field or never run

### Dry-Run Preview

See what would run without executing:

```bash
$ zr run --dry-run test

Execution plan:
  [✗] build         — would run (sources changed)
  [✓] test          — would skip (up-to-date)
```

---

## Forcing Execution

### Global Force Flag

Ignore all up-to-date checks:

```bash
# Always run, even if up-to-date
$ zr run --force build

# Force all tasks in a workflow
$ zr workflow --force ci
```

### When to Use `--force`

- After manual changes to generated files
- When external dependencies changed (not tracked in `sources`)
- When debugging build issues
- In CI/CD pipelines (ensure clean build)

---

## Integration with Other Features

### Caching

Up-to-date detection works alongside content-based caching:

```toml
[tasks.build]
cmd = "zig build"
sources = ["src/**/*.zig"]
generates = ["zig-out/bin/zr"]
cache = true  # Hash-based cache
```

**Execution order**:
1. Check if task is up-to-date (mtime comparison) — skip if true
2. Check cache hit (hash comparison) — skip if true
3. Run task

### Watch Mode

File watcher uses `sources` patterns to filter relevant changes:

```bash
# Only re-run when sources change
$ zr watch build
```

If `sources` is defined, zr only triggers on changes to those files. Otherwise, it watches the entire working directory.

### Workflows

Up-to-date detection applies to workflow tasks:

```toml
[workflows.ci]
tasks = ["lint", "test", "build"]
```

Each task is checked independently. If `lint` is up-to-date but `test` is stale, only `test` and `build` run (due to dependency propagation).

---

## Performance Optimization

### File System I/O

Up-to-date checks involve stat() calls for every source/generate file. To minimize overhead:

1. **Use specific patterns**: `src/**/*.ts` is faster than `**/*` (fewer files to stat)
2. **Limit generates**: Only list files that actually indicate completion
3. **Group sources logically**: Use `package.json` instead of `node_modules/**/*`

### Example: Efficient Configuration

**Bad** (slow):
```toml
[tasks.build]
sources = ["**/*"]  # Stats entire directory tree
generates = ["dist/**/*"]  # Stats all output files
```

**Good** (fast):
```toml
[tasks.build]
# Only source files and config
sources = ["src/**/*.ts", "tsconfig.json", "package.json"]
# Just the entry point or manifest
generates = ["dist/index.js", "dist/package.json"]
```

---

## Migrating from Other Tools

### From Make

```makefile
# Makefile
dist/app.js: src/app.ts src/util.ts
	tsc
```

```toml
# zr.toml
[tasks.build]
cmd = "tsc"
sources = ["src/app.ts", "src/util.ts"]
generates = ["dist/app.js"]
```

### From Task (go-task)

```yaml
# Taskfile.yml
tasks:
  build:
    sources:
      - src/**/*.ts
    generates:
      - dist/**/*.js
    cmds:
      - tsc
```

```toml
# zr.toml
[tasks.build]
cmd = "tsc"
sources = ["src/**/*.ts"]
generates = ["dist/**/*.js"]
```

### From Just

Just doesn't have built-in up-to-date detection. In zr:

```justfile
# justfile (no incremental builds)
build:
  zig build
```

```toml
# zr.toml (with incremental builds)
[tasks.build]
cmd = "zig build"
sources = ["src/**/*.zig", "build.zig"]
generates = ["zig-out/bin/app"]
```

---

## Best Practices

### 1. Include Configuration Files in Sources

```toml
[tasks.test]
sources = [
    "src/**/*.ts",
    "tests/**/*.ts",
    "jest.config.js",  # ← Config affects output
    "package.json"      # ← Dependencies affect behavior
]
```

### 2. Use Precise Generate Patterns

Don't list files that might change independently:

**Bad**:
```toml
generates = ["logs/**/*"]  # Logs change constantly
```

**Good**:
```toml
generates = ["dist/bundle.js"]  # Only the build output
```

### 3. Separate Stable and Volatile Tasks

```toml
[tasks.build]
# Stable: only runs when sources change
sources = ["src/**/*.zig"]
generates = ["zig-out/bin/zr"]

[tasks.test]
# No sources/generates: always runs (tests should always execute)
cmd = "zig build test"
```

### 4. Document Why Tasks Have No Sources/Generates

```toml
[tasks.deploy]
# No sources/generates: deployment depends on external state (server status)
# Always runs to ensure latest version is deployed
cmd = "kubectl apply -f k8s/"
```

---

## Troubleshooting

### Task Runs When It Should Skip

**Symptom**: Task executes even though sources haven't changed.

**Causes**:
1. Generated files were manually deleted
2. Source patterns are too broad (include volatile files)
3. Clock skew (file timestamps in future)
4. Dependency ran, triggering propagation

**Solutions**:
```bash
# Check status first
$ zr list --status

# Verify timestamps
$ ls -lt src/ zig-out/bin/

# Force re-run to reset timestamps
$ zr run --force build
```

### Task Skipped When It Should Run

**Symptom**: Task is skipped, but output is incorrect.

**Causes**:
1. External dependencies not tracked in `sources`
2. Missing `generates` files
3. Dependency relationship missing

**Solutions**:
```toml
[tasks.build]
# Add all inputs
sources = [
    "src/**/*.zig",
    "build.zig",
    "build.zig.zon",  # ← Missing dependency manifest
]
# Add all dependencies
deps = ["generate-code"]  # ← Missing dependency
```

### Slow Up-to-Date Checks

**Symptom**: Noticeable delay before task execution.

**Cause**: Too many files in `sources` or `generates` patterns.

**Solution**:
```toml
# Instead of:
sources = ["**/*"]  # Stats entire tree

# Use:
sources = ["src/**/*.zig", "build.zig"]  # Only relevant files
```

---

## Advanced Patterns

### Multi-Stage Builds

```toml
[tasks.generate]
cmd = "python codegen.py"
sources = ["schema.json"]
generates = ["src/generated.ts"]

[tasks.compile]
cmd = "tsc"
sources = ["src/**/*.ts"]  # Includes generated.ts
generates = ["dist/index.js"]
deps = ["generate"]

[tasks.bundle]
cmd = "esbuild dist/index.js"
sources = ["dist/index.js"]
generates = ["dist/bundle.min.js"]
deps = ["compile"]
```

**Behavior**:
- If `schema.json` changes → all three tasks run
- If `src/app.ts` changes → `compile` and `bundle` run (not `generate`)
- If nothing changes → all tasks skip

### Conditional Source Tracking

```toml
[tasks.test]
cmd = "npm test"
sources = ["src/**/*.ts", "tests/**/*.ts"]
generates = ["coverage/lcov.info"]
# Skip if no sources changed
# Always run if --force specified

[tasks.test-ci]
cmd = "npm test -- --coverage"
# No sources/generates: always run in CI
deps = ["test"]
```

---

## Reference

### Task Fields

| Field | Type | Description |
|-------|------|-------------|
| `sources` | Array of strings | Glob patterns for input files |
| `generates` | Array of strings | Glob patterns for output files |

### CLI Flags

| Flag | Description |
|------|-------------|
| `--force` | Ignore up-to-date checks, always run |
| `--dry-run` | Show execution plan without running |
| `--status` | Show task up-to-date status (with `list`) |

### Status Indicators

| Symbol | Meaning |
|--------|---------|
| `[✓]` | Up-to-date (all generates newer than sources) |
| `[✗]` | Stale (sources changed since last run) |
| `[?]` | Unknown (no generates or never run) |

---

## See Also

- [Configuration Reference](config-reference.md) — Full task field documentation
- [Best Practices](best-practices.md) — General task runner patterns
- [Commands Reference](command-reference.md) — CLI command details
