# Conditional Dependencies Guide

## Overview

Conditional dependencies allow you to dynamically control which task dependencies execute based on runtime conditions. Instead of always running the same dependency chain, you can make decisions based on environment variables, task tags, or parameters.

When you add conditional dependencies to a task, zr evaluates each condition at runtime and only includes dependencies whose conditions evaluate to true. This enables sophisticated workflows like platform-specific build steps, environment-based deployment pipelines, and feature flag toggles — all within a single configuration file.

This is especially powerful for:
1. **Platform-specific dependencies**: Different build/test steps for Linux, macOS, Windows
2. **Environment-based workflows**: Run database migrations only in production, skip code signing in dev
3. **Feature toggles**: Include beta/experimental features only when explicitly enabled
4. **CI/CD optimization**: Skip expensive checks (coverage, linting) in local dev, run them in CI

---

## Basic Usage

### Defining Conditional Dependencies

Add a `deps_if` field to your task definition with an array of conditional dependency objects:

```toml
[tasks.setup-db]
cmd = "pg_ctl start && diesel migration run"
description = "Initialize production database"

[tasks.deploy]
cmd = "kubectl apply -f deployment.yaml"
deps_if = [
  { task = "setup-db", condition = "env.TARGET == 'production'" }
]
description = "Deploy application"
```

Each conditional dependency has:
- **task** (required): Name of the dependency task to run (if condition is true)
- **condition** (required): Boolean expression that determines if the dependency is included

### Simple Environment Variable Condition

```toml
[tasks.docker-build]
cmd = "docker build -t myapp ."

[tasks.test]
cmd = "npm test"
deps_if = [
  { task = "docker-build", condition = "env.USE_DOCKER == 'true'" }
]
```

Running the task:

```bash
# With USE_DOCKER env var set
$ USE_DOCKER=true zr run test
✓ docker-build (5.2s)
✓ test (12.3s)

# Without USE_DOCKER env var (or set to anything other than 'true')
$ zr run test
✓ test (12.3s)
```

### Tag-Based Condition

```toml
[tasks.setup-gpu]
cmd = "nvidia-smi && python -c 'import torch; print(torch.cuda.is_available())'"
description = "Verify GPU availability"

[tasks.train]
cmd = "python train.py"
tags = ["ml", "gpu"]
deps_if = [
  { task = "setup-gpu", condition = "has_tag('gpu')" }
]
```

The `setup-gpu` dependency only runs when the `train` task has the `gpu` tag.

### Negation

```toml
[tasks.expensive-validation]
cmd = "npm run validate:slow"

[tasks.build]
cmd = "npm run build"
tags = ["ci"]
deps_if = [
  { task = "expensive-validation", condition = "!has_tag('skip-validation')" }
]
```

The validation runs **unless** the task has the `skip-validation` tag.

### Multiple Conditional Dependencies

A task can have multiple conditional dependencies with different conditions:

```toml
[tasks.lint]
cmd = "npm run lint"

[tasks.test]
cmd = "npm test"

[tasks.coverage]
cmd = "npm run test:coverage"

[tasks.build]
cmd = "npm run build"
deps_if = [
  { task = "lint", condition = "env.SKIP_LINT != 'true'" },
  { task = "test", condition = "env.SKIP_TEST != 'true'" },
  { task = "coverage", condition = "has_tag('ci')" }
]
tags = ["ci"]
```

Running in different contexts:

```bash
# Local development (skip lint and test)
$ SKIP_LINT=true SKIP_TEST=true zr run build
✓ coverage (8.1s)    # Runs because task has 'ci' tag
✓ build (3.2s)

# CI environment (run everything)
$ zr run build
✓ lint (2.3s)
✓ test (12.5s)
✓ coverage (8.2s)
✓ build (3.1s)
```

---

## Expression Syntax

Conditional dependency expressions use the same syntax as zr's built-in expression engine (used for environment variable interpolation and workflow conditions).

### Comparison Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equality | `env.MODE == 'prod'` |
| `!=` | Inequality | `env.SKIP != 'true'` |
| `<` | Less than | `env.WORKERS < '10'` |
| `>` | Greater than | `env.MEMORY > '1024'` |
| `<=` | Less than or equal | `env.RETRIES <= '3'` |
| `>=` | Greater than or equal | `env.MIN_VERSION >= '2.0'` |

**Note**: All comparisons are lexicographic (string-based). `'10' < '2'` is true because '1' < '2' lexically.

### Logical Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `&&` | Logical AND (both conditions must be true) | `env.A == 'x' && env.B == 'y'` |
| `\|\|` | Logical OR (either condition can be true) | `has_tag('dev') \|\| has_tag('test')` |
| `!` | Logical NOT (negation) | `!has_tag('skip')` |

### Grouping

Use parentheses `()` to control evaluation order:

```toml
condition = "(env.A == 'x' && env.B == 'y') || env.C == 'z'"
```

Without parentheses, `&&` binds tighter than `||`:
- `a || b && c` is equivalent to `a || (b && c)`
- `(a || b) && c` requires explicit grouping

### Functions

| Function | Description | Example |
|----------|-------------|---------|
| `has_tag('tag')` | Check if the task has the specified tag | `has_tag('docker')` |

### Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `env.VAR` | Access environment variable `VAR` | `env.TARGET`, `env.CI` |
| `params.NAME` | Access task parameter `NAME` | `params.env`, `params.region` |

**Empty/missing values**: If an environment variable or parameter doesn't exist, it evaluates to an empty string `""`. In boolean contexts (e.g., `if env.VAR`), empty strings are falsy.

### String Literals

Use single or double quotes for string literals in comparisons:

```toml
# Both are equivalent
condition = "env.MODE == 'production'"
condition = "env.MODE == \"production\""
```

### Truthy/Falsy Checks

You can check if a variable is non-empty (truthy):

```toml
# Runs if USE_FEATURE is set to any non-empty value
condition = "env.USE_FEATURE"

# Runs if USE_FEATURE is NOT set (or empty)
condition = "!env.USE_FEATURE"
```

---

## Advanced Patterns

### Platform-Specific Dependencies

```toml
[tasks.setup-linux]
cmd = "sudo apt-get install libgtk-3-dev"
description = "Install Linux-specific dependencies"

[tasks.setup-macos]
cmd = "brew install gtk+3"
description = "Install macOS-specific dependencies"

[tasks.setup-windows]
cmd = "choco install gtk"
description = "Install Windows-specific dependencies"

[tasks.build]
cmd = "npm run build:native"
deps_if = [
  { task = "setup-linux", condition = "env.OS == 'linux'" },
  { task = "setup-macos", condition = "env.OS == 'darwin'" },
  { task = "setup-windows", condition = "env.OS == 'windows'" }
]
```

Usage:

```bash
# Linux
$ OS=linux zr run build
✓ setup-linux (15.2s)
✓ build (8.1s)

# macOS
$ OS=darwin zr run build
✓ setup-macos (12.3s)
✓ build (8.0s)
```

### Environment-Based Workflow

```toml
[tasks.db-migrate]
cmd = "diesel migration run"
description = "Run database migrations"

[tasks.seed-data]
cmd = "node scripts/seed-dev-data.js"
description = "Populate development test data"

[tasks.start]
cmd = "node server.js"
deps_if = [
  { task = "db-migrate", condition = "env.ENV == 'production'" },
  { task = "seed-data", condition = "env.ENV == 'dev' || env.ENV == 'test'" }
]
params = [{ name = "env", default = "dev" }]
```

```bash
# Development: seeds test data
$ zr run start env=dev
✓ seed-data (2.1s)
✓ start (0.5s)

# Production: runs migrations only
$ zr run start env=production
✓ db-migrate (5.3s)
✓ start (0.5s)
```

### Feature Toggle Dependencies

```toml
[tasks.build-legacy]
cmd = "tsc --project tsconfig.legacy.json"
description = "Build legacy ES5 bundle"

[tasks.build-modern]
cmd = "tsc --project tsconfig.modern.json"
description = "Build modern ES2020 bundle"

[tasks.bundle]
cmd = "rollup -c"
deps_if = [
  { task = "build-legacy", condition = "env.LEGACY_SUPPORT == 'true'" },
  { task = "build-modern", condition = "!env.LEGACY_SUPPORT" }
]
```

```bash
# Enable legacy support
$ LEGACY_SUPPORT=true zr run bundle
✓ build-legacy (8.2s)
✓ bundle (3.1s)

# Modern-only build (default)
$ zr run bundle
✓ build-modern (6.1s)
✓ bundle (3.0s)
```

### Combined Conditions

```toml
[tasks.docker-push]
cmd = "docker push myapp:latest"
description = "Push Docker image to registry"

[tasks.deploy]
cmd = "kubectl apply -f k8s/"
tags = ["deploy", "production"]
deps_if = [
  {
    task = "docker-push",
    condition = "env.ENV == 'production' && has_tag('deploy') && !env.DRY_RUN"
  }
]
```

The `docker-push` dependency runs only when:
- Environment is production (`env.ENV == 'production'`)
- AND task has the `deploy` tag (`has_tag('deploy')`)
- AND `DRY_RUN` is not set (`!env.DRY_RUN`)

### Complex Boolean Logic with Grouping

```toml
[tasks.security-scan]
cmd = "npm audit && snyk test"

[tasks.deploy]
cmd = "kubectl apply -f k8s/"
deps_if = [
  {
    task = "security-scan",
    condition = "(env.ENV == 'staging' || env.ENV == 'prod') && (has_tag('security') || env.FORCE_SCAN == 'true')"
  }
]
tags = ["security"]
```

Security scan runs when:
- Environment is staging OR production
- AND (task has `security` tag OR `FORCE_SCAN` is enabled)

Execution scenarios:

```bash
# Staging + security tag → scan runs
$ ENV=staging zr run deploy  # (task has 'security' tag)
✓ security-scan (15.2s)
✓ deploy (8.1s)

# Dev + security tag → scan skipped (not staging/prod)
$ ENV=dev zr run deploy
✓ deploy (8.0s)

# Staging without tag but FORCE_SCAN → scan runs
$ ENV=staging FORCE_SCAN=true zr run deploy-no-tag
✓ security-scan (15.3s)
✓ deploy-no-tag (8.2s)
```

---

## Integration with Other Features

### Dry-Run Mode

Conditional dependencies are evaluated during dry-run planning:

```bash
$ ENV=production zr run --dry-run deploy

Execution plan (dry-run):
  [1] setup-db         — would run (condition met: env.ENV == 'production')
  [1] docker-build     — would run (always)
  [2] deploy           — would run (depends on setup-db, docker-build)
```

Tasks whose conditions are not met are excluded from the plan entirely:

```bash
$ ENV=dev zr run --dry-run deploy

Execution plan (dry-run):
  [1] docker-build     — would run (always)
  [2] deploy           — would run (depends on docker-build)

  Skipped conditional dependencies:
    setup-db (condition not met: env.ENV == 'production')
```

### Watch Mode

File watcher re-evaluates conditional dependencies on each trigger:

```bash
$ ENV=dev zr watch test

[watch] Watching: src/**/*.ts
[watch] Trigger: src/app.ts changed
✓ test (12.3s)

# Change environment mid-watch
$ export ENV=production

[watch] Trigger: src/util.ts changed
✓ db-migrate (5.1s)  # Now runs because ENV changed to production
✓ test (12.5s)
```

Conditions are evaluated at execution time, not watch setup time, so changing environment variables affects subsequent runs.

### Task Parameters

Conditional dependencies can access task parameters:

```toml
[tasks.setup-prod]
cmd = "terraform apply -var-file=prod.tfvars"

[tasks.deploy]
cmd = "kubectl apply -f k8s/{{env}}.yaml"
params = [{ name = "env", default = "dev" }]
deps_if = [
  { task = "setup-prod", condition = "params.env == 'prod'" }
]
```

```bash
$ zr run deploy env=prod
✓ setup-prod (8.2s)
✓ deploy (5.1s)

$ zr run deploy env=staging
✓ deploy (5.0s)
```

### Environment Variables in Conditions

All environment variables are accessible via `env.VAR` syntax:

```toml
deps_if = [
  { task = "lint", condition = "env.CI == 'true'" },
  { task = "test", condition = "env.SKIP_TEST != 'true'" },
  { task = "deploy", condition = "env.GITHUB_REF == 'refs/heads/main'" }
]
```

This integrates seamlessly with CI/CD platforms that inject environment variables (GitHub Actions, GitLab CI, Jenkins, etc.).

### Tags in Conditions

The `has_tag()` function checks tags on the **current task** (the one with `deps_if`), not the dependency:

```toml
[tasks.expensive-setup]
cmd = "npm install --production=false"

[tasks.build]
cmd = "npm run build"
tags = ["full-build"]
deps_if = [
  { task = "expensive-setup", condition = "has_tag('full-build')" }
]
```

The condition evaluates against `build`'s tags, not `expensive-setup`'s tags.

---

## Real-World Examples

### Multi-Environment Deployment

```toml
[tasks.setup-dev]
cmd = "docker-compose up -d postgres redis"
description = "Start local dev dependencies"

[tasks.setup-staging]
cmd = "kubectl config use-context staging && helm upgrade --install deps ./charts/deps"
description = "Deploy staging infrastructure"

[tasks.setup-prod]
cmd = "kubectl config use-context prod && helm upgrade --install deps ./charts/deps --values prod.yaml"
description = "Deploy production infrastructure"

[tasks.migrate-db]
cmd = "diesel migration run --database-url=$DATABASE_URL"
description = "Run database migrations"

[tasks.deploy]
cmd = "kubectl apply -f k8s/$TARGET_ENV/"
env = {
  DATABASE_URL = "postgres://{{env}}.example.com/mydb",
  TARGET_ENV = "{{env}}"
}
params = [{ name = "env", description = "Target environment (required)" }]
deps_if = [
  { task = "setup-dev", condition = "params.env == 'dev'" },
  { task = "setup-staging", condition = "params.env == 'staging'" },
  { task = "setup-prod", condition = "params.env == 'prod'" },
  { task = "migrate-db", condition = "params.env == 'staging' || params.env == 'prod'" }
]
description = "Deploy to target environment"
```

Usage:

```bash
# Development: spins up local services
$ zr run deploy env=dev
✓ setup-dev (8.2s)
✓ deploy (3.1s)

# Staging: deploys infra + runs migrations
$ zr run deploy env=staging
✓ setup-staging (15.3s)
✓ migrate-db (5.2s)
✓ deploy (8.1s)

# Production: full deployment pipeline
$ zr run deploy env=prod
✓ setup-prod (18.5s)
✓ migrate-db (6.1s)
✓ deploy (9.2s)
```

### Cross-Platform Build

```toml
[tasks.install-linux-deps]
cmd = "sudo apt-get update && sudo apt-get install -y libssl-dev pkg-config"
description = "Install Linux build dependencies"

[tasks.install-macos-deps]
cmd = "brew install openssl pkg-config"
description = "Install macOS build dependencies"

[tasks.install-windows-deps]
cmd = "choco install openssl"
description = "Install Windows build dependencies"

[tasks.build-native]
cmd = "cargo build --release"
deps_if = [
  { task = "install-linux-deps", condition = "env.OS == 'Linux'" },
  { task = "install-macos-deps", condition = "env.OS == 'Darwin'" },
  { task = "install-windows-deps", condition = "env.OS == 'Windows_NT'" }
]
description = "Build native binary for current platform"
```

```bash
# Linux
$ OS=Linux zr run build-native
✓ install-linux-deps (25.3s)
✓ build-native (45.2s)

# macOS
$ OS=Darwin zr run build-native
✓ install-macos-deps (18.5s)
✓ build-native (42.1s)
```

**Tip**: Use `uname -s` on Unix or `echo %OS%` on Windows to get the OS name, then set it as an environment variable.

### CI/CD with Optional Steps

```toml
[tasks.lint]
cmd = "eslint src/"
description = "Lint source code"

[tasks.test]
cmd = "jest"
description = "Run unit tests"

[tasks.coverage]
cmd = "jest --coverage --coverageReporters=lcov"
description = "Generate test coverage report"

[tasks.security-audit]
cmd = "npm audit && snyk test"
description = "Security vulnerability scan"

[tasks.build]
cmd = "webpack --mode=production"
deps_if = [
  { task = "lint", condition = "!has_tag('skip-lint')" },
  { task = "test", condition = "!has_tag('skip-test')" },
  { task = "coverage", condition = "has_tag('ci')" },
  { task = "security-audit", condition = "has_tag('ci') && !env.SKIP_SECURITY" }
]
description = "Build production bundle"
```

Local development (skip expensive checks):

```bash
$ zr run build
# Runs: lint, test, build (skips coverage and security-audit)
```

CI environment (full pipeline):

```bash
$ zr run build --tags ci
# Runs: lint, test, coverage, security-audit, build
```

Emergency bypass (skip security checks in CI):

```bash
$ SKIP_SECURITY=true zr run build --tags ci
# Runs: lint, test, coverage, build (skips security-audit)
```

### Feature Flags

```toml
[tasks.build-ui-v2]
cmd = "npm run build:ui-v2"
description = "Build experimental UI (v2 design system)"

[tasks.build-ui-legacy]
cmd = "npm run build:ui-legacy"
description = "Build stable UI (v1 design system)"

[tasks.setup-analytics]
cmd = "node scripts/setup-analytics.js"
description = "Configure analytics tracking"

[tasks.bundle]
cmd = "rollup -c"
deps_if = [
  { task = "build-ui-v2", condition = "env.FEATURE_UI_V2 == 'true'" },
  { task = "build-ui-legacy", condition = "env.FEATURE_UI_V2 != 'true'" },
  { task = "setup-analytics", condition = "env.ENABLE_ANALYTICS == 'true'" }
]
description = "Bundle application with feature flags"
```

```bash
# Beta users: new UI + analytics
$ FEATURE_UI_V2=true ENABLE_ANALYTICS=true zr run bundle
✓ build-ui-v2 (12.3s)
✓ setup-analytics (2.1s)
✓ bundle (8.5s)

# Stable release: legacy UI, no analytics
$ zr run bundle
✓ build-ui-legacy (10.2s)
✓ bundle (8.1s)
```

---

## Comparison with Alternatives

### vs. Regular Dependencies (`deps`)

**Regular dependencies** always run:

```toml
[tasks.test]
deps = ["build"]  # Always runs 'build' before 'test'
```

**Conditional dependencies** run based on conditions:

```toml
[tasks.test]
deps_if = [
  { task = "build", condition = "env.REBUILD == 'true'" }
]
```

Use regular `deps` for **mandatory** dependencies (e.g., build before test). Use `deps_if` for **optional** dependencies that depend on context.

### vs. Optional Dependencies (`deps_optional`)

**Optional dependencies** run if the task exists, but don't fail if it's missing:

```toml
[tasks.test]
deps_optional = ["lint"]  # Runs 'lint' if defined, skips if not
```

**Conditional dependencies** run based on **runtime conditions**, not task existence:

```toml
[tasks.test]
deps_if = [
  { task = "lint", condition = "env.CI == 'true'" }
]
```

Use `deps_optional` for **soft dependencies** (tasks that may or may not exist in all configs). Use `deps_if` for **conditional logic** based on environment/tags/params.

### vs. Sequential Dependencies (`deps_serial`)

**Sequential dependencies** enforce execution order (one at a time, in array order):

```toml
[tasks.deploy]
deps_serial = ["build", "test", "push"]  # Runs in order: build → test → push
```

**Conditional dependencies** control **whether** a dependency runs, not **when**:

```toml
[tasks.deploy]
deps_if = [
  { task = "test", condition = "env.SKIP_TEST != 'true'" }
]
```

You can combine both:

```toml
[tasks.deploy]
deps_serial = ["build", "push"]  # Always run in order
deps_if = [
  { task = "test", condition = "env.CI == 'true'" }  # Conditionally include
]
```

### When to Use Each Type

| Dependency Type | Use When |
|-----------------|----------|
| `deps` | Dependency **always** required (e.g., build before test) |
| `deps_serial` | Dependencies must run **in order** (e.g., db-migrate before seed-data) |
| `deps_optional` | Dependency **may not exist** in all configs (e.g., optional lint task) |
| `deps_if` | Dependency depends on **runtime context** (env, tags, params) |

---

## Best Practices

### 1. Keep Conditions Simple and Readable

**Bad** (hard to understand):
```toml
condition = "((env.A == 'x' || env.B == 'y') && (has_tag('z') || !env.C)) || (env.D != 'q' && has_tag('w'))"
```

**Good** (clear intent):
```toml
# Break into multiple deps_if entries
deps_if = [
  { task = "setup-prod", condition = "env.ENV == 'prod'" },
  { task = "setup-staging", condition = "env.ENV == 'staging'" }
]
```

### 2. Use Tags for Categorical Flags

Tags represent **what** the task is:

```toml
tags = ["docker", "ci", "slow"]
deps_if = [
  { task = "docker-setup", condition = "has_tag('docker')" },
  { task = "full-validation", condition = "has_tag('ci')" }
]
```

Use tags instead of multiple boolean environment variables.

### 3. Use Environment Variables for Runtime Values

Environment variables represent **how** or **where** the task runs:

```toml
deps_if = [
  { task = "deploy-us-west", condition = "env.REGION == 'us-west'" },
  { task = "deploy-eu", condition = "env.REGION == 'eu'" },
  { task = "notify-slack", condition = "env.SLACK_WEBHOOK" }  # Truthy check
]
```

### 4. Document Conditions in Task Descriptions

```toml
[tasks.deploy]
cmd = "kubectl apply -f k8s/"
deps_if = [
  { task = "db-migrate", condition = "env.ENV == 'prod'" }
]
description = "Deploy to k8s (runs db-migrate only in production)"
```

Users can see the conditional logic in `zr list` output.

### 5. Test Both Met and Unmet Conditions

Always verify your conditions work in both scenarios:

```bash
# Condition met
$ ENV=prod zr run deploy
# Expected: runs db-migrate + deploy

# Condition not met
$ ENV=dev zr run deploy
# Expected: runs deploy only (skips db-migrate)
```

Use `--dry-run` to verify dependency resolution before execution:

```bash
$ ENV=prod zr run --dry-run deploy
# Shows: which deps will run and why
```

### 6. Avoid Complex Nested Conditions

If your condition requires more than 3 operators (`&&`, `||`, `!`), consider splitting into separate tasks:

**Bad**:
```toml
condition = "(env.A == 'x' && env.B == 'y') || (env.C == 'z' && env.D != 'q')"
```

**Good**:
```toml
[tasks.setup-scenario-1]
deps_if = [
  { task = "setup-a", condition = "env.A == 'x'" },
  { task = "setup-b", condition = "env.B == 'y'" }
]

[tasks.setup-scenario-2]
deps_if = [
  { task = "setup-c", condition = "env.C == 'z'" },
  { task = "setup-d", condition = "env.D != 'q'" }
]

[tasks.main]
deps_if = [
  { task = "setup-scenario-1", condition = "env.SCENARIO == '1'" },
  { task = "setup-scenario-2", condition = "env.SCENARIO == '2'" }
]
```

### 7. Use Dry-Run to Verify Dependency Resolution

Before running potentially destructive operations, preview the execution plan:

```bash
$ ENV=prod zr run --dry-run deploy

Execution plan:
  [1] db-migrate        — would run (condition: env.ENV == 'prod')
  [1] docker-build      — would run (always)
  [2] deploy            — would run (depends on db-migrate, docker-build)
```

This shows exactly which conditional dependencies will be included.

### 8. Combine with Regular Dependencies for Mandatory Steps

```toml
[tasks.deploy]
cmd = "kubectl apply -f k8s/"
deps = ["build", "test"]  # Always required
deps_if = [
  { task = "security-scan", condition = "env.ENV == 'prod'" }  # Conditional
]
```

Use `deps` for non-negotiable steps, `deps_if` for contextual steps.

---

## Troubleshooting

### Condition Always False

**Symptom**: Dependency never runs, even when you expect it to.

```bash
$ ENV=production zr run deploy
✓ deploy (5.0s)
# Expected: db-migrate to run, but it didn't
```

**Common causes**:

1. **Typo in environment variable name**:
   ```toml
   condition = "env.TERGET == 'production'"  # Typo: TERGET vs TARGET
   ```
   **Fix**: Double-check variable names (case-sensitive).

2. **Typo in tag name**:
   ```toml
   condition = "has_tag('dcoker')"  # Typo: dcoker vs docker
   ```
   **Fix**: Verify tag spelling in both task definition and condition.

3. **Wrong comparison value**:
   ```bash
   $ ENV=prod zr run deploy  # Set to 'prod'
   ```
   ```toml
   condition = "env.ENV == 'production'"  # Expects 'production', not 'prod'
   ```
   **Fix**: Match exact string values (comparisons are case-sensitive).

4. **Environment variable not set**:
   ```bash
   $ zr run deploy  # ENV not set
   ```
   ```toml
   condition = "env.ENV == 'production'"  # Empty string != 'production'
   ```
   **Fix**: Ensure the variable is set: `ENV=production zr run deploy`

**Debugging**:
```bash
# Use dry-run to see condition evaluation
$ ENV=production zr run --dry-run deploy
# Shows which deps are included/excluded and why
```

### Unexpected Dependencies Running

**Symptom**: Dependency runs when you expected it to be skipped.

```bash
$ ENV=dev zr run deploy
✓ db-migrate (5.2s)  # Expected: should skip in dev
✓ deploy (3.1s)
```

**Common causes**:

1. **Negation logic error**:
   ```toml
   condition = "env.ENV != 'dev'"  # Runs in everything EXCEPT dev
   ```
   You might have meant: only run in prod.
   **Fix**:
   ```toml
   condition = "env.ENV == 'prod'"
   ```

2. **OR condition with unintended truthy branch**:
   ```toml
   condition = "env.ENV == 'prod' || env.FORCE_MIGRATE"
   ```
   If `FORCE_MIGRATE` is set to any value (even "false"), the condition is true.
   **Fix**: Use explicit comparison:
   ```toml
   condition = "env.ENV == 'prod' || env.FORCE_MIGRATE == 'true'"
   ```

3. **Multiple conditions with AND instead of OR**:
   ```toml
   # Wrong: task needs BOTH 'docker' AND 'gpu' tags to skip
   condition = "!has_tag('docker') && !has_tag('gpu')"
   ```
   **Fix**: Use OR for "skip if has ANY of these tags":
   ```toml
   condition = "!has_tag('docker') && !has_tag('gpu')"  # Skip if has NEITHER
   # OR
   condition = "!(has_tag('docker') || has_tag('gpu'))"  # Skip if has ANY
   ```

**Debugging**:
```bash
# Check condition evaluation in dry-run
$ ENV=dev zr run --dry-run deploy
```

### Syntax Errors in Conditions

**Symptom**: zr fails to parse the configuration file.

```
✗ Parse error: Invalid expression syntax at line 15
```

**Common causes**:

1. **Using `=` instead of `==`**:
   ```toml
   condition = "env.ENV = 'prod'"  # Wrong: single =
   ```
   **Fix**:
   ```toml
   condition = "env.ENV == 'prod'"  # Correct: double ==
   ```

2. **Unmatched quotes**:
   ```toml
   condition = "env.ENV == 'prod"  # Missing closing quote
   ```
   **Fix**:
   ```toml
   condition = "env.ENV == 'prod'"
   ```

3. **Unmatched parentheses**:
   ```toml
   condition = "(env.A == 'x' && env.B == 'y'"  # Missing closing paren
   ```
   **Fix**:
   ```toml
   condition = "(env.A == 'x' && env.B == 'y')"
   ```

4. **Invalid function name**:
   ```toml
   condition = "hasTag('docker')"  # Wrong: camelCase
   ```
   **Fix**:
   ```toml
   condition = "has_tag('docker')"  # Correct: snake_case
   ```

### Missing Environment Variables

**Symptom**: Condition fails silently because env var is not set.

```bash
$ zr run deploy
✓ deploy (3.1s)
# Expected: db-migrate to run, but TARGET not set
```

**Cause**: Undefined environment variables evaluate to empty string `""`.

```toml
condition = "env.TARGET == 'production'"  # Empty string != 'production'
```

**Solutions**:

1. **Set the variable**:
   ```bash
   $ TARGET=production zr run deploy
   ```

2. **Use default in shell**:
   ```bash
   $ export TARGET=${TARGET:-dev}  # Default to 'dev' if not set
   $ zr run deploy
   ```

3. **Check for empty in condition**:
   ```toml
   # Runs if TARGET is set to ANY non-empty value
   condition = "env.TARGET"
   ```

### Tag Not Found

**Symptom**: Condition with `has_tag()` always false.

```bash
$ zr run build
✓ build (5.0s)
# Expected: docker-setup to run
```

**Cause**: Task doesn't have the tag, or tag name is misspelled.

```toml
[tasks.build]
tags = ["production", "dcoker"]  # Typo: dcoker
deps_if = [
  { task = "docker-setup", condition = "has_tag('docker')" }  # No match
]
```

**Fix**: Check tag spelling (case-sensitive):
```toml
tags = ["production", "docker"]  # Correct spelling
```

**Debugging**:
```bash
# List task with its tags
$ zr list
build (tags: production, docker)  — Build application
```

---

## Migration Guide

### From Make

**Make** uses `ifeq`/`ifdef` for conditional logic:

```makefile
# Makefile
ifdef USE_DOCKER
deploy: docker-build
else
deploy:
endif
	kubectl apply -f k8s/
```

**zr equivalent**:

```toml
# zr.toml
[tasks.docker-build]
cmd = "docker build -t myapp ."

[tasks.deploy]
cmd = "kubectl apply -f k8s/"
deps_if = [
  { task = "docker-build", condition = "env.USE_DOCKER" }
]
```

CLI usage:

```bash
# Make
$ USE_DOCKER=1 make deploy

# zr
$ USE_DOCKER=true zr run deploy
```

### From Just

**Just** doesn't have built-in conditional dependencies. Workarounds use shell scripts:

```just
# justfile
deploy env:
  #!/bin/bash
  if [ "{{env}}" = "prod" ]; then
    just db-migrate
  fi
  kubectl apply -f k8s/
```

**zr equivalent**:

```toml
# zr.toml
[tasks.db-migrate]
cmd = "diesel migration run"

[tasks.deploy]
cmd = "kubectl apply -f k8s/"
params = [{ name = "env" }]
deps_if = [
  { task = "db-migrate", condition = "params.env == 'prod'" }
]
```

CLI usage:

```bash
# Just
$ just deploy prod

# zr
$ zr run deploy env=prod
```

### From Task (go-task)

**Task** uses `status` field with shell commands for conditional skipping:

```yaml
# Taskfile.yml
tasks:
  db-migrate:
    cmds:
      - diesel migration run
    status:
      - test "$ENV" != "prod"  # Skip if ENV is not prod

  deploy:
    deps: [db-migrate]
    cmds:
      - kubectl apply -f k8s/
```

**zr equivalent**:

```toml
# zr.toml
[tasks.db-migrate]
cmd = "diesel migration run"

[tasks.deploy]
cmd = "kubectl apply -f k8s/"
deps_if = [
  { task = "db-migrate", condition = "env.ENV == 'prod'" }
]
```

Task's `status` skips the task itself; zr's `deps_if` controls dependencies.

---

## Future Enhancements

Planned improvements for conditional dependencies:

- **Typed parameters**: `params.port > 8000` with numeric comparison (not lexicographic)
- **Regex matching**: `env.BRANCH =~ '^release/'` for pattern-based conditions
- **File existence checks**: `file_exists('config.prod.toml')` in conditions
- **Dynamic dependency generation**: `deps_if` with computed task names (e.g., `"task-${env.ENV}"`)
- **Condition caching**: Cache condition evaluations across workflow runs for performance
- **Conditional workflows**: Apply `deps_if` logic to workflow-level task orchestration

See `docs/milestones.md` for roadmap and tracking.

---

## See Also

- [Parameterized Tasks Guide](parameterized-tasks.md) — Using `params.X` in conditions
- [Incremental Builds Guide](incremental-builds.md) — Combining `deps_if` with up-to-date detection
- [Configuration Reference](config-reference.md) — Full TOML schema for `deps_if`
- [Expression Engine](expressions.md) — Complete syntax reference for conditions
- [Workflow Guide](workflows.md) — Orchestrating tasks with conditional dependencies
