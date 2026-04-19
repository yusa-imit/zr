# Best Practices

Production-tested patterns for organizing tasks, optimizing performance, and managing large projects with zr.

## Table of Contents

- [Task Organization](#task-organization)
- [Performance Optimization](#performance-optimization)
- [Monorepo Patterns](#monorepo-patterns)
- [CI/CD Integration](#cicd-integration)
- [Caching Strategies](#caching-strategies)
- [Error Handling](#error-handling)
- [Security](#security)
- [Team Collaboration](#team-collaboration)

---

## Task Organization

### Use Descriptive Task Names

**Good**:
```toml
[tasks.build-frontend-production]
[tasks.deploy-api-staging]
[tasks.test-integration-database]
```

**Bad**:
```toml
[tasks.b]
[tasks.deploy]
[tasks.test2]
```

**Why**: Clear names improve discoverability and reduce errors.

---

### Organize with Tags

Use consistent tagging for filtering and CI/CD workflows.

```toml
[tasks.lint-frontend]
cmd = "eslint apps/web"
tags = ["lint", "frontend", "ci"]

[tasks.lint-backend]
cmd = "cargo clippy"
tags = ["lint", "backend", "ci"]

[tasks.test-unit]
cmd = "npm test"
tags = ["test", "unit", "ci"]

[tasks.test-e2e]
cmd = "playwright test"
tags = ["test", "e2e", "ci"]
```

**Usage**:
```bash
# Run all linters
zr list --tags lint | xargs -L1 zr run

# Run all CI tasks
zr list --tags ci --format json | jq -r '.[].name' | xargs zr run
```

**Recommended tag categories**:
- **Type**: `build`, `test`, `lint`, `deploy`, `docs`
- **Scope**: `frontend`, `backend`, `api`, `mobile`
- **Environment**: `dev`, `staging`, `production`
- **Purpose**: `ci`, `release`, `setup`, `cleanup`

---

### Group Related Tasks with Mixins

Avoid repetition with mixins for common configurations.

```toml
[mixins.docker-task]
env = { DOCKER_BUILDKIT = "1" }
tags = ["docker"]
timeout_ms = 600000

[mixins.k8s-deploy]
timeout_ms = 300000
retry_max = 3
retry_backoff_multiplier = 2.0
tags = ["deploy", "k8s"]

[tasks.deploy-frontend]
cmd = "kubectl apply -f frontend.yaml"
mixins = ["docker-task", "k8s-deploy"]

[tasks.deploy-backend]
cmd = "kubectl apply -f backend.yaml"
mixins = ["docker-task", "k8s-deploy"]
```

---

### Use Workspace Shared Tasks

For monorepos, define common tasks once in the root.

**Root `zr.toml`**:
```toml
[workspace]
members = ["packages/*", "apps/*"]

[workspace.shared_tasks.lint]
cmd = "eslint ."
tags = ["ci", "lint"]

[workspace.shared_tasks.test]
cmd = "npm test"
tags = ["ci", "test"]
deps = ["lint"]

[workspace.shared_tasks.format]
cmd = "prettier --write ."
tags = ["format"]
```

**Member override** (if needed):
```toml
# apps/web/zr.toml
[tasks.test]
cmd = "vitest run"  # Overrides workspace shared task
deps = ["lint"]
```

---

## Performance Optimization

### Maximize Parallelism with Correct Dependencies

**Bad** (sequential, slow):
```toml
[tasks.build]
deps_serial = ["lint", "test", "format"]  # Unnecessary serialization
```

**Good** (parallel, fast):
```toml
[tasks.build]
deps = ["lint", "test", "format"]  # Runs in parallel
```

**When to use `deps_serial`**:
- Database migrations (must run in order)
- Sequential deployment steps
- Dependencies between tasks (A must complete before B starts)

---

### Enable Caching for Expensive Tasks

```toml
[tasks.build-docker-image]
cmd = "docker build -t myapp:latest ."
cache = true
cache_inputs = [
  "src/**/*",
  "Dockerfile",
  "package.json",
  "package-lock.json"
]
cache_outputs = []  # Docker images cached via Docker daemon
```

**Caching best practices**:
- Cache only deterministic tasks (same inputs → same outputs)
- Include all relevant inputs (source files, config, dependencies)
- Use content-based hashing (zr does this automatically)
- Set up remote cache for team collaboration

---

### Use Concurrency Groups for Resource-Constrained Tasks

Prevent resource exhaustion with concurrency groups.

```toml
[concurrency_groups.gpu]
max_workers = 2
description = "GPU-bound ML training tasks"

[concurrency_groups.memory_intensive]
max_workers = 4
description = "Tasks requiring >4GB memory"

[tasks.train-model-v1]
cmd = "python train.py --model v1"
concurrency_group = "gpu"

[tasks.train-model-v2]
cmd = "python train.py --model v2"
concurrency_group = "gpu"

[tasks.build-large-dataset]
cmd = "./process-data.sh"
concurrency_group = "memory_intensive"
max_memory = 8589934592  # 8 GB
```

**Result**: Only 2 GPU tasks run simultaneously, preventing OOM errors.

---

### Optimize Resource Limits

Set per-task resource limits to prevent runaway processes.

```toml
[resource_limits]
max_workers = 12  # Global limit
max_memory = 34359738368  # 32 GB total
max_cpu = 16

[tasks.heavy-compilation]
cmd = "cargo build --release"
max_cpu = 8  # Use half the cores
max_memory = 8589934592  # 8 GB max
timeout_ms = 600000  # 10 minutes
```

---

### Use NUMA Affinity for High-Performance Tasks

For multi-socket systems, bind tasks to NUMA nodes.

```toml
[tasks.benchmark-cpu-numa0]
cmd = "./bench --threads 16"
numa_node = 0
cpu_affinity = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

[tasks.benchmark-cpu-numa1]
cmd = "./bench --threads 16"
numa_node = 1
cpu_affinity = [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
```

**Why**: Reduces cross-NUMA memory access latency (30-50% speedup on some workloads).

---

## Monorepo Patterns

### Use Affected Detection in CI

Only run tasks on changed packages.

```bash
# .github/workflows/ci.yml
- name: Test affected
  run: zr affected test --base origin/main
```

**Configuration**:
```toml
[workspace]
members = ["packages/*", "apps/*"]

[workspace.shared_tasks.test]
cmd = "npm test"
cache = true
cache_inputs = ["src/**/*", "package.json"]
```

---

### Multi-Stage Workflows for CI

Parallelize early stages, serialize critical steps.

```toml
[workflows.ci]
description = "Continuous integration pipeline"
stages = [
  # Stage 1: Fast checks (parallel)
  { tasks = ["lint", "typecheck", "format-check"] },

  # Stage 2: Tests (parallel)
  { tasks = ["test-unit", "test-integration"] },

  # Stage 3: Build (serial, after tests pass)
  { tasks = ["build-frontend", "build-backend"] },

  # Stage 4: E2E tests (serial, needs built artifacts)
  { tasks = ["test-e2e"] },

  # Stage 5: Deploy (serial, final step)
  { tasks = ["deploy-staging"], max_concurrent = 1 }
]
```

**Result**: Fast feedback (lint/typecheck fail in 30s), full pipeline in 5-10 minutes.

---

### Task Inheritance for Consistency

Use shared tasks for workspace-wide standards.

```toml
# Root zr.toml
[workspace.shared_tasks.lint]
cmd = "eslint . --max-warnings 0"
tags = ["ci", "lint"]

[workspace.shared_tasks.format-check]
cmd = "prettier --check ."
tags = ["ci", "format"]

[workspace.shared_tasks.build]
cmd = "npm run build"
cache = true
cache_inputs = ["src/**/*", "package.json"]
cache_outputs = ["dist/**/*"]
```

**Members** automatically inherit these tasks.

---

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install zr
        run: |
          curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
          echo "$HOME/.zr/bin" >> $GITHUB_PATH

      - name: Setup toolchains
        run: zr setup

      - name: Run CI workflow
        run: zr workflow ci --jobs 4

      - name: Upload cache
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-cache
          path: .zr/cache
```

---

### GitLab CI Example

```yaml
# .gitlab-ci.yml
stages:
  - test
  - build
  - deploy

variables:
  ZR_VERSION: "1.71.0"

before_script:
  - curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
  - export PATH="$HOME/.zr/bin:$PATH"
  - zr setup

test:
  stage: test
  script:
    - zr workflow ci
  cache:
    paths:
      - .zr/cache

deploy:
  stage: deploy
  script:
    - zr run deploy --profile production
  only:
    - main
```

---

### Remote Cache Setup (S3)

Share cache across CI runners.

```toml
[cache]
enabled = true
dir = ".zr/cache"

[cache.remote]
type = "s3"
bucket = "my-org-build-cache"
prefix = "zr-cache/"
region = "us-east-1"
```

**Environment variables** (CI secrets):
```bash
AWS_ACCESS_KEY_ID=<key>
AWS_SECRET_ACCESS_KEY=<secret>
```

**Result**: First CI run takes 10 minutes, subsequent runs take 2 minutes (cache hits).

---

## Caching Strategies

### Content-Based Caching

Always use content hashing for correctness.

```toml
[tasks.build-frontend]
cmd = "npm run build"
cache = true
cache_inputs = [
  "src/**/*.{ts,tsx,css}",
  "public/**/*",
  "package.json",
  "package-lock.json",
  "tsconfig.json",
  "vite.config.ts"
]
cache_outputs = ["dist/**/*"]
```

**Why**: Ensures cache invalidation when dependencies change.

---

### Layered Caching

Cache intermediate steps separately.

```toml
[tasks.install-deps]
cmd = "npm ci"
cache = true
cache_inputs = ["package-lock.json"]
cache_outputs = ["node_modules/**/*"]

[tasks.build]
cmd = "npm run build"
deps = ["install-deps"]
cache = true
cache_inputs = ["src/**/*", "package.json"]
cache_outputs = ["dist/**/*"]
```

**Result**: Dependency changes invalidate `install-deps` but not `build` (if source unchanged).

---

### Remote Cache for Teams

Use S3/GCS/Azure for shared cache.

```toml
[cache.remote]
type = "s3"
bucket = "team-cache"
prefix = "zr/${git.branch}/"
region = "us-west-2"
```

**Benefits**:
- Developers share build artifacts
- CI runners reuse cache across jobs
- Faster onboarding (new devs get cached builds)

---

## Error Handling

### Retry Transient Failures

Network requests, external APIs, flaky tests.

```toml
[tasks.fetch-data]
cmd = "curl https://api.example.com/data -o data.json"
retry_max = 5
retry_delay_ms = 1000
retry_backoff_multiplier = 2.0  # 1s, 2s, 4s, 8s, 16s
retry_jitter = true
max_backoff_ms = 30000  # Cap at 30s
retry_on_codes = [429, 503, 504]  # Rate limit, service unavailable, gateway timeout
retry_on_patterns = ["timeout", "ECONNREFUSED"]
```

---

### Circuit Breaker for External Services

Stop calling failing services to reduce load.

```toml
[tasks.health-check-api]
cmd = "./check-api.sh"
circuit_breaker = {
  failure_threshold = 5,      # Open circuit after 5 failures
  success_threshold = 2,      # Close after 2 successes
  timeout_ms = 60000          # Wait 1 minute before half-open
}
```

**States**:
1. **Closed**: Normal operation
2. **Open**: Failing fast (after 5 failures)
3. **Half-Open**: Testing with single request (after 60s)
4. **Closed**: Back to normal (after 2 successes)

---

### Failure Hooks

Clean up on failure, send notifications.

```toml
[tasks.deploy]
cmd = "./deploy.sh"
hooks = [
  { point = "before", cmd = "echo 'Starting deployment...'" },
  { point = "success", cmd = "./notify-success.sh" },
  { point = "failure", cmd = "./rollback.sh && ./notify-failure.sh" }
]
```

---

### Allow Failure for Non-Critical Tasks

```toml
[tasks.optional-linter]
cmd = "experimental-linter ."
allow_failure = true  # Don't fail build if this fails

[tasks.build]
deps = ["optional-linter"]
cmd = "npm run build"
```

---

## Security

### Avoid Secrets in Configuration

**Bad**:
```toml
[tasks.deploy]
env = { API_KEY = "sk_live_1234567890" }  # NEVER DO THIS
```

**Good**:
```toml
[tasks.deploy]
env = { API_KEY = "${env.DEPLOY_API_KEY}" }  # Read from environment

[profiles.production]
env = { DEPLOY_API_KEY = "${env.SECRET_API_KEY}" }  # CI injects this
```

**Best**:
```bash
# .env.local (gitignored)
DEPLOY_API_KEY=sk_live_1234567890

# CI secrets (GitHub Actions, GitLab CI, etc.)
DEPLOY_API_KEY=<injected-by-ci>
```

---

### Use Remote Execution for Sensitive Operations

```toml
[tasks.deploy-production]
cmd = "./deploy.sh"
remote = "deploy-bot@prod-bastion.example.com"
remote_cwd = "/opt/deployments"
condition = "${git.branch == 'main' && env.CI == 'true'}"
```

**Why**: Production credentials never leave the bastion host.

---

### Validate Inputs

```toml
[tasks.deploy]
cmd = "./deploy.sh"
condition = "${env.DEPLOY_ENV != ''} && ${matches('^(dev|staging|prod)$', env.DEPLOY_ENV)}"
```

**Result**: Fails fast if `DEPLOY_ENV` is missing or invalid.

---

## Team Collaboration

### Document Tasks with Descriptions

```toml
[tasks.build-docker-production]
description = "Build production Docker image with optimizations (multi-stage, layer caching)"
cmd = "docker build --target production -t myapp:${git.commit} ."
tags = ["build", "docker", "production"]
```

---

### Use Aliases for Common Workflows

```toml
[aliases]
dev = "run server --profile development"
test = "workflow ci --jobs 4"
deploy-staging = "workflow deploy --profile staging"
deploy-prod = "workflow deploy --profile production"
```

**Team usage**:
```bash
zr dev          # Everyone runs the same dev server
zr test         # Consistent CI workflow locally
zr deploy-prod  # Safe production deployment
```

---

### Standardize Environment with Profiles

```toml
[profiles.development]
env = {
  NODE_ENV = "development",
  DEBUG = "true",
  LOG_LEVEL = "debug"
}

[profiles.staging]
env = {
  NODE_ENV = "production",
  DEBUG = "false",
  LOG_LEVEL = "info",
  API_URL = "https://api-staging.example.com"
}

[profiles.production]
env = {
  NODE_ENV = "production",
  DEBUG = "false",
  LOG_LEVEL = "warn",
  API_URL = "https://api.example.com"
}
```

---

### Version Control for Toolchains

```toml
[toolchains]
node = "20.11.1"
python = "3.12.1"
zig = "0.15.2"
```

**Benefits**:
- Consistent versions across team
- Reproducible builds
- Easy onboarding (`zr setup` installs everything)

---

## Anti-Patterns

### Don't Overuse `deps_serial`

**Bad**:
```toml
[tasks.ci]
deps_serial = ["lint", "test", "build"]  # 3x slower than parallel
```

**Good**:
```toml
[tasks.ci]
deps = ["lint", "test"]  # Parallel (fast)

[tasks.build]
deps = ["ci"]  # Build after CI passes
```

---

### Don't Mix Responsibilities in One Task

**Bad**:
```toml
[tasks.deploy]
cmd = "npm run build && npm test && kubectl apply -f app.yaml"  # Build, test, deploy in one task
```

**Good**:
```toml
[tasks.build]
cmd = "npm run build"

[tasks.test]
cmd = "npm test"
deps = ["build"]

[tasks.deploy]
cmd = "kubectl apply -f app.yaml"
deps = ["test"]
```

**Why**: Separate tasks enable caching, parallelism, and better error messages.

---

### Don't Hardcode Paths

**Bad**:
```toml
[tasks.test]
cmd = "node /Users/alice/project/test.js"  # Won't work on Bob's machine
```

**Good**:
```toml
[tasks.test]
cmd = "npm test"
dir = "."  # Relative to zr.toml
```

---

### Don't Ignore Cache Invalidation

**Bad**:
```toml
[tasks.build]
cache = true
cache_inputs = ["src/**/*"]  # Missing package.json, lockfile
```

**Good**:
```toml
[tasks.build]
cache = true
cache_inputs = [
  "src/**/*",
  "package.json",
  "package-lock.json",
  "tsconfig.json"
]
```

---

## Checklist

Before committing `zr.toml`:

- [ ] All tasks have descriptive names
- [ ] Sensitive data uses `${env.*}` instead of hardcoded values
- [ ] Caching enabled for expensive tasks with complete `cache_inputs`
- [ ] Retry configured for transient failures (network, APIs)
- [ ] Resource limits set for heavy tasks
- [ ] Tasks tagged for filtering (`ci`, `test`, `build`, etc.)
- [ ] Workspace shared tasks used for monorepo consistency
- [ ] Workflows use stages for optimal parallelism
- [ ] Aliases defined for common team workflows
- [ ] Toolchain versions specified in `[toolchains]`

---

## Additional Resources

- [Configuration Guide](configuration.md) — Complete zr.toml reference
- [Command Reference](command-reference.md) — All CLI commands
- [Performance Benchmarks](benchmarks.md) — zr vs make/just/task
- [Migration Guide](migration.md) — Migrate from other tools
