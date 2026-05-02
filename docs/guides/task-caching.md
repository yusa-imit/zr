# Task Result Caching & Memoization

> **Feature Status**: Available in zr v1.82.0+
>
> Cache task execution results to skip redundant computations across runs and machines.

## Overview

zr's task result caching system uses content-based fingerprinting to detect when a task's inputs haven't changed, allowing it to skip re-execution. Unlike incremental builds (mtime-based), caching uses cryptographic hashes of command + environment for cache-key generation, similar to Nx and Turborepo.

**Key Benefits**:
- ⚡ **Skip redundant work**: Tasks with unchanged inputs don't re-run
- 🔒 **Content-based detection**: Hash-based keys ensure correctness
- 📊 **Hit tracking**: `zr list --show-cache` shows cache status
- 🧹 **Easy management**: `zr cache clean/status/clear` commands

---

## Basic Usage

### Enable Caching for a Task

Add `cache = true` to any task:

```toml
[tasks.build]
cmd = "zig build"
cache = true  # Enable caching for this task
```

When you run `zr run build`:
1. **First run**: Task executes normally, result cached with generated key
2. **Subsequent runs** (same cmd + env): Cache hit, execution skipped

### Check Cache Status

View which tasks have cached results:

```bash
zr list --show-cache
```

Output shows `[cached]` marker for tasks with cache entries:

```
Available tasks:
  build         [cached]  Build the project
  test                    Run unit tests
  deploy        [cached]  Deploy to production
```

---

## Cache Key Generation

Cache keys are SHA-256 hashes computed from:

| Input | Purpose |
|-------|---------|
| **Task command** | Different commands = different cache entries |
| **Environment variables** | Different env = different cache entries |

**Example**:
```toml
[tasks.deploy]
cmd = "kubectl apply -f deploy.yaml"
env = { ENVIRONMENT = "staging" }
cache = true
```

Running with different environments creates separate cache entries:
- `zr run deploy` → cache key includes `ENVIRONMENT=staging`
- `zr run deploy --env ENVIRONMENT=production` → different cache key

---

## Cache Hit Detection

Cache hits occur when:
1. Task has `cache = true`
2. Command hasn't changed
3. Environment variables haven't changed
4. Cache entry exists for the generated key

**Workflow**:
```
┌──────────────┐
│  Run task    │
└──────┬───────┘
       │
       ▼
┌──────────────────────────┐
│ Compute cache key from:  │
│ • Task cmd               │
│ • Environment vars       │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Check local cache store  │
│ .zr/cache/<cache_key>/   │
└──────┬───────────────────┘
       │
       ├─── Hit? ───┐
       │            │
       ▼            ▼
   Execute     Skip execution
   & cache     (use cached metadata)
```

---

## Cache CLI Commands

### View Cache Statistics

```bash
zr cache status
```

Shows:
- Total cache entries
- Total cache size
- Per-task breakdown

Example output:
```
Cache Status:
  Total entries: 12
  Total size: 45.3 MB

Per-task breakdown:
  build: 3 entries (12.1 MB)
  test: 5 entries (18.4 MB)
  deploy: 4 entries (14.8 MB)
```

### Clear All Cache

```bash
zr cache clean
```

Removes entire `.zr/cache` directory.

### Clear Task-Specific Cache

```bash
zr cache clear <task>
```

Removes cache entries for a specific task.

---

## Practical Examples

### Example 1: Build Caching

Cache build results to skip redundant compilations:

```toml
[tasks.build]
cmd = "zig build -Doptimize=ReleaseSafe"
cache = true

[tasks.build-debug]
cmd = "zig build"
cache = true  # Separate cache from release build
```

**Workflow**:
1. `zr run build` → First run compiles, caches result
2. `zr run build` → Cache hit, skips compilation
3. `zr run build-debug` → Different command, cache miss, compiles

### Example 2: Test Result Caching

Skip test re-runs when code hasn't changed:

```toml
[tasks.test]
cmd = "zig build test"
cache = true

[tasks.test-integration]
cmd = "zig build integration-test"
cache = true
```

**Benefits**:
- CI runs skip unchanged test suites
- Local development avoids redundant test execution
- Separate cache for unit vs integration tests

### Example 3: Environment-Specific Caching

Cache deployment tasks per environment:

```toml
[tasks.deploy]
cmd = "kubectl apply -f k8s/"
env = { ENVIRONMENT = "staging" }
cache = true

[tasks.deploy-prod]
cmd = "kubectl apply -f k8s/"
env = { ENVIRONMENT = "production" }
cache = true
```

Cache keys differ by environment, so staging and production deployments cache separately.

### Example 4: CI/CD Caching

Speed up CI pipelines with task caching:

```toml
[tasks.ci-build]
cmd = "docker build -t myapp:latest ."
cache = true

[tasks.ci-test]
cmd = "npm test"
cache = true
deps = ["ci-build"]
```

GitHub Actions workflow:
```yaml
- name: Run build with cache
  run: zr run ci-build

- name: Run tests (may skip if cached)
  run: zr run ci-test
```

---

## Cache Storage Format

Cache entries are stored in `.zr/cache/<cache_key>/`:

```
.zr/cache/
└── <cache_key>/
    └── manifest.json
```

**Manifest structure** (`manifest.json`):
```json
{
  "timestamp": "2026-05-03T12:34:56Z",
  "task_name": "build",
  "cache_key": "abc123...",
  "exit_code": 0,
  "duration_ms": 1234
}
```

**Note**: Current version (v1.82.0) stores metadata only. Future versions will include stdout/stderr capture.

---

## Cache Invalidation

Cache entries are **never automatically invalidated**. They persist until:
- Manual cleanup: `zr cache clean` or `zr cache clear <task>`
- Disk space cleanup (external tools)

**When cache doesn't detect changes**:
- Caching is based on **command + environment**, not file contents
- If your command stays the same but input files change, cache won't detect it
- Use **incremental builds** (sources/generates) for file-based invalidation

---

## Integration with Other Features

### With Incremental Builds

Combine caching with up-to-date detection for best performance:

```toml
[tasks.compile]
cmd = "gcc -o bin/app src/*.c"
sources = ["src/**/*.c", "include/**/*.h"]
generates = ["bin/app"]
cache = true
```

**Behavior**:
1. If `bin/app` is up-to-date (newer than sources), skip execution
2. If cache hit exists (same cmd + env), skip execution
3. Otherwise, execute and cache result

### With Task Parameters

Parameters affect cache keys:

```toml
[tasks.deploy]
cmd = "deploy.sh {{env}}"
params = [{ name = "env", default = "staging" }]
cache = true
```

Running `zr run deploy env=prod` creates a different cache entry than `env=staging`.

### With Workflows

Workflows cache individual tasks, not the entire workflow:

```toml
[workflows.full-ci]
tasks = [
  "lint",    # Cached if enabled
  "build",   # Cached if enabled
  "test"     # Cached if enabled
]
```

Each task's cache is independent.

---

## Best Practices

### 1. Enable Caching for Expensive Tasks

Focus on tasks with high execution cost:
- ✅ Compilations, builds, transpilations
- ✅ Long-running test suites
- ✅ Database migrations
- ❌ Quick commands (< 1 second runtime)

### 2. Use Cache for Deterministic Tasks

Only cache tasks with predictable outputs:
- ✅ Builds with fixed toolchain versions
- ✅ Tests with isolated environments
- ❌ Tasks with randomness or timestamps in output
- ❌ Tasks with side effects (API calls, database writes)

### 3. Combine with Incremental Builds

Use both for maximum efficiency:
```toml
[tasks.build]
cmd = "make"
sources = ["src/**/*.c"]
generates = ["bin/app"]
cache = true  # Cache + incremental
```

### 4. Monitor Cache Size

Periodically check cache size:
```bash
zr cache status
```

Clean when needed:
```bash
zr cache clean  # Remove all cache entries
```

### 5. Use Environment Variables for Variants

Don't create separate tasks for environment variants:

**❌ Bad** (cache duplication):
```toml
[tasks.deploy-staging]
cmd = "deploy.sh staging"
cache = true

[tasks.deploy-prod]
cmd = "deploy.sh production"
cache = true
```

**✅ Good** (single task, environment-based caching):
```toml
[tasks.deploy]
cmd = "deploy.sh {{env}}"
params = [{ name = "env", default = "staging" }]
cache = true
```

### 6. Document Cache Assumptions

Add comments explaining cache behavior:
```toml
[tasks.build]
cmd = "cargo build --release"
cache = true
# Cache assumes: Cargo.lock unchanged, same Rust version
```

---

## Troubleshooting

### Cache Always Misses

**Symptom**: Every run executes, no cache hits

**Causes**:
1. **Environment variables changing**: Check for dynamic env vars (timestamps, UUIDs)
2. **Command interpolation**: Ensure `{{params}}` resolve to same values
3. **Fresh workspace**: First run in new workspace always misses

**Debug**:
```bash
zr list --show-cache  # Check if [cached] marker appears
zr cache status       # Verify cache entries exist
```

### Cache Hits Despite Changes

**Symptom**: Task skips execution when it shouldn't

**Cause**: Cache key doesn't include file changes

**Solution**: Use incremental builds instead:
```toml
[tasks.build]
cmd = "make"
sources = ["src/**"]
generates = ["bin/app"]
cache = false  # Use sources/generates instead
```

### Large Cache Size

**Symptom**: `.zr/cache` directory growing large

**Solution**:
```bash
zr cache clean  # Remove all entries
# Or clear specific tasks:
zr cache clear build
zr cache clear test
```

### Cache Not Showing in `list`

**Symptom**: `zr list --show-cache` doesn't show `[cached]` marker

**Cause**: `--show-cache` flag not provided

**Solution**:
```bash
zr list --show-cache  # Explicitly enable cache status display
```

---

## Comparison with Other Tools

| Feature | zr | Nx | Turborepo | Make |
|---------|-----|-----|-----------|------|
| **Cache key** | cmd + env | content hash | content hash | mtime |
| **Hit detection** | SHA-256 | SHA-256 | SHA-256 | timestamp |
| **Remote cache** | Planned | ✅ | ✅ | ❌ |
| **Output capture** | Planned | ✅ | ✅ | ❌ |
| **CLI mgmt** | ✅ | ✅ | ✅ | ❌ |

**zr advantages**:
- Simple TOML config (no extra cache configuration needed)
- Lightweight (no Node.js required)
- Fast cache key computation (SHA-256 only on cmd + env)

**zr limitations** (current version):
- No output capture (metadata only)
- No remote cache (local only)
- No file content hashing (use incremental builds instead)

---

## Future Enhancements

Planned features for upcoming releases:

### Output Capture (v1.83.0)
- Capture stdout/stderr in cache
- Restore outputs on cache hit
- Display cached task output without re-execution

### Remote Cache Backends (v1.84.0)
- S3 remote cache support
- GCS remote cache support
- HTTP remote cache support
- Team-wide cache sharing

### Content-Based Keys (v1.85.0)
- Include file content hashes in cache keys
- Automatic invalidation on source changes
- Integration with `sources` pattern

---

## Migration from Other Tools

### From Make

Make doesn't have task caching (only timestamp-based rebuilds).

**Before** (Makefile):
```makefile
build:
\tgcc -o app src/*.c
```

**After** (zr.toml):
```toml
[tasks.build]
cmd = "gcc -o app src/*.c"
sources = ["src/*.c"]
generates = ["app"]
cache = true
```

**Benefits**:
- Timestamp checking (sources/generates) + caching (cmd + env)
- Cache persists across clean builds

### From Nx

Nx uses content hashing for cache keys. zr uses cmd + env (lighter weight).

**Before** (project.json):
```json
{
  "targets": {
    "build": {
      "executor": "@nx/webpack:webpack",
      "cache": true
    }
  }
}
```

**After** (zr.toml):
```toml
[tasks.build]
cmd = "webpack build"
cache = true
```

**Differences**:
- Nx: Hashes all input files → comprehensive but slower
- zr: Hashes cmd + env → fast but requires manual sources specification

### From Turborepo

Turbo uses content-based hashing similar to Nx.

**Before** (turbo.json):
```json
{
  "pipeline": {
    "build": {
      "cache": true,
      "outputs": ["dist/**"]
    }
  }
}
```

**After** (zr.toml):
```toml
[tasks.build]
cmd = "npm run build"
cache = true
```

**Differences**:
- Turbo: Automatic dependency detection
- zr: Explicit deps specification required

---

## Summary

Task result caching in zr provides:
- ✅ **Content-based cache keys**: cmd + env hashing ensures correctness
- ✅ **Hit detection**: Skip execution when inputs unchanged
- ✅ **CLI management**: `cache clean/status/clear` commands
- ✅ **List integration**: `--show-cache` flag shows cache status
- 🚧 **Output capture**: Planned for v1.83.0
- 🚧 **Remote backends**: Planned for v1.84.0

**Quick start**:
1. Add `cache = true` to expensive tasks
2. Run `zr list --show-cache` to verify cache status
3. Use `zr cache clean` to clear cache when needed

For file-based invalidation, use [incremental builds](./incremental-builds.md) instead.
