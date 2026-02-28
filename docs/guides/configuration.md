# Configuration Reference

This document describes the complete `zr.toml` configuration schema.

## Table of Contents

- [Tasks](#tasks)
- [Workflows](#workflows)
- [Profiles](#profiles)
- [Matrix Expansion](#matrix-expansion)
- [Cache](#cache)
- [Workspace](#workspace)
- [Resource Limits](#resource-limits)
- [Toolchains](#toolchains)
- [Plugins](#plugins)
- [Aliases](#aliases)
- [Schedules](#schedules)
- [Templates](#templates)
- [Versioning](#versioning)
- [Conformance](#conformance)
- [Expressions](#expressions)

---

## Tasks

Tasks are the core building blocks of zr. Each task is defined in a `[tasks.<name>]` section.

### Basic Task

```toml
[tasks.build]
description = "Build the application"
cmd = "npm run build"
```

### Task Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `cmd` | string | ✅ | — | Shell command to execute |
| `description` | string | ❌ | null | Human-readable description |
| `deps` | array | ❌ | [] | Parallel dependencies (run before this task) |
| `deps_serial` | array | ❌ | [] | Sequential dependencies (run one at a time) |
| `env` | table | ❌ | {} | Environment variable overrides |
| `dir` | string | ❌ | null | Working directory (alias: `cwd`) |
| `timeout_ms` | integer | ❌ | null | Timeout in milliseconds |
| `retry_max` | integer | ❌ | 0 | Maximum retry attempts |
| `retry_delay_ms` | integer | ❌ | 0 | Delay between retries (ms) |
| `retry_backoff` | boolean | ❌ | false | Exponential backoff for retries |
| `allow_failure` | boolean | ❌ | false | Continue if task fails |
| `condition` | string | ❌ | null | Expression to evaluate before running |
| `cache` | boolean | ❌ | false | Cache successful runs |
| `max_concurrent` | integer | ❌ | 0 | Max concurrent instances (0 = unlimited) |
| `max_cpu` | integer | ❌ | null | Max CPU cores for this task |
| `max_memory` | integer | ❌ | null | Max memory in bytes |
| `toolchain` | array | ❌ | [] | Required toolchains (e.g., `["node@20"]`) |
| `tags` | array | ❌ | [] | Categorization tags |

### Dependencies

```toml
[tasks.test]
cmd = "npm test"
deps = ["build"]  # runs build first (parallel if multiple)

[tasks.deploy]
cmd = "./deploy.sh"
deps_serial = ["build", "test", "lint"]  # runs in order, one at a time
```

### Environment Variables

```toml
[tasks.server]
cmd = "node server.js"
env = { PORT = "3000", NODE_ENV = "production" }
```

### Working Directory

```toml
[tasks.frontend-build]
cmd = "npm run build"
dir = "./packages/frontend"  # or cwd = "..."
```

### Timeouts and Retries

```toml
[tasks.flaky-test]
cmd = "npm test"
timeout_ms = 60000  # 1 minute
retry_max = 3
retry_delay_ms = 1000
retry_backoff = true  # 1s, 2s, 4s
```

### Conditional Execution

```toml
[tasks.deploy-prod]
cmd = "kubectl apply -f prod.yaml"
condition = "${platform.is_linux} && ${env.CI == 'true'}"
```

### Caching

```toml
[tasks.expensive-build]
cmd = "cargo build --release"
cache = true  # skips if cmd + env unchanged and succeeded before
```

### Resource Limits

```toml
[tasks.memory-intensive]
cmd = "./process-large-data"
max_cpu = 4  # max 4 cores
max_memory = 4294967296  # 4GB
```

### Toolchain Requirements

```toml
[tasks.node-build]
cmd = "npm run build"
toolchain = ["node@20.11"]  # auto-install if missing
```

### Tags

```toml
[tasks.unit-test]
cmd = "npm test"
tags = ["test", "ci"]

[tasks.e2e-test]
cmd = "playwright test"
tags = ["test", "e2e"]
```

---

## Workflows

Workflows organize tasks into sequential stages with advanced control flow.

### Basic Workflow

```toml
[workflow.ci]
description = "Continuous integration pipeline"

[[workflow.ci.stages]]
name = "prepare"
tasks = ["install", "lint"]
parallel = true

[[workflow.ci.stages]]
name = "test"
tasks = ["test-unit", "test-integration"]
parallel = true
fail_fast = true

[[workflow.ci.stages]]
name = "deploy"
tasks = ["deploy-staging"]
approval = true  # require user confirmation
```

### Stage Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | ✅ | — | Stage name |
| `tasks` | array | ✅ | — | Tasks to run in this stage |
| `parallel` | boolean | ❌ | true | Run tasks in parallel |
| `fail_fast` | boolean | ❌ | false | Stop stage on first failure |
| `condition` | string | ❌ | null | Expression to evaluate before stage |
| `approval` | boolean | ❌ | false | Require manual approval |
| `on_failure` | string | ❌ | null | Task to run on failure |

### Conditional Stages

```toml
[[workflow.deploy.stages]]
name = "prod-deploy"
tasks = ["deploy-prod"]
condition = "${env.BRANCH == 'main'}"
```

### Failure Handling

```toml
[[workflow.ci.stages]]
name = "test"
tasks = ["test-all"]
on_failure = "notify-slack"
```

---

## Profiles

Profiles allow environment-specific task overrides.

```toml
[profile.dev]
description = "Development environment"

[profile.dev.env]
NODE_ENV = "development"
DEBUG = "true"

[profile.dev.task.build]
cmd = "npm run build:dev"  # override build task

[profile.prod]
description = "Production environment"

[profile.prod.env]
NODE_ENV = "production"

[profile.prod.task.build]
cmd = "npm run build:prod"
```

Use with `zr run --profile dev build`.

---

## Matrix Expansion

Generate multiple task variants from a parameter matrix.

```toml
[matrix.test-matrix]
os = ["linux", "macos", "windows"]
node = ["18", "20"]

[tasks.test]
cmd = "npm test"
env = { OS = "${matrix.os}", NODE_VERSION = "${matrix.node}" }
```

This expands to 6 tasks: `test-linux-18`, `test-linux-20`, etc.

---

## Cache

### Local Cache

```toml
[cache]
enabled = true
local_dir = "$HOME/.zr/cache"  # default
```

### Remote Cache

```toml
[cache]
enabled = true

[cache.remote]
type = "s3"
bucket = "my-build-cache"
region = "us-west-2"
prefix = "zr-cache/"
```

Supported backends: `s3`, `gcs`, `azure`, `http`.

---

## Workspace

For monorepos, define a workspace in the root `zr.toml`.

### Root Configuration

```toml
[workspace]
members = ["packages/*", "apps/*"]
ignore = ["node_modules", "dist"]
```

### Member Configuration

In `packages/frontend/zr.toml`:

```toml
[workspace]
member_dependencies = ["packages/shared", "packages/utils"]

[tasks.build]
cmd = "npm run build"
deps = ["../../packages/shared:build"]
```

---

## Resource Limits

Global resource limits for all task execution.

```toml
[resources]
max_workers = 8  # max concurrent tasks
max_total_memory = 17179869184  # 16GB total
max_cpu_percent = 80  # 80% CPU usage cap
```

---

## Toolchains

Configure automatic toolchain installation.

```toml
[toolchains.node]
version = "20.11"
auto_install = true

[toolchains.python]
version = "3.12"
auto_install = true
```

Or per-task:

```toml
[tasks.build]
cmd = "npm run build"
toolchain = ["node@20.11"]
```

---

## Plugins

Load native or WASM plugins for extended functionality.

```toml
[plugin.docker]
source = "https://github.com/zr-plugins/docker/releases/download/v1.0.0/docker.wasm"
kind = "wasm"

[plugin.custom]
source = "/path/to/libcustom.so"
kind = "native"
```

Use in tasks:

```toml
[tasks.docker-build]
cmd = "plugin:docker build -t myapp ."
```

---

## Aliases

Define command aliases for common task patterns.

```toml
[alias.ci]
expand = "run build test lint"

[alias.deploy-all]
expand = "run deploy-frontend deploy-backend"
```

Use: `zr ci` → runs `zr run build test lint`.

---

## Schedules

Run tasks on a cron schedule.

```toml
[schedule.nightly-test]
cron = "0 2 * * *"  # 2 AM daily
tasks = ["test-all"]

[schedule.weekly-cleanup]
cron = "0 0 * * 0"  # Sunday midnight
tasks = ["clean"]
```

---

## Templates

Define reusable task templates with parameters.

```toml
[template.test-service]
cmd = "npm test"
dir = "${param.service_dir}"
env = { SERVICE_NAME = "${param.name}" }

[tasks.test-frontend]
template = "test-service"
params = { name = "frontend", service_dir = "./services/frontend" }

[tasks.test-backend]
template = "test-service"
params = { name = "backend", service_dir = "./services/backend" }
```

---

## Versioning

Automatic semantic versioning with conventional commits.

```toml
[versioning]
enabled = true
mode = "auto"  # or "manual"
convention = "conventional"  # conventional commits
tag_prefix = "v"

[versioning.changelog]
path = "CHANGELOG.md"
sections = ["feat", "fix", "perf", "refactor"]
```

---

## Conformance

Architecture governance rules for monorepos.

```toml
[conformance]
enabled = true

[[conformance.rules]]
name = "no-circular-deps"
type = "no-circular"
scope = "all"

[[conformance.rules]]
name = "apps-depend-on-libs"
type = "tag-based"
scope = { tag = "app" }
allowed = ["lib"]

[[conformance.rules]]
name = "ban-legacy"
type = "banned-dependency"
scope = "all"
banned = ["packages/legacy"]
```

---

## Expressions

zr supports expressions in many fields (condition, env values, etc.).

### Platform Detection

```toml
condition = "${platform.is_linux}"  # true on Linux
condition = "${platform.os}"  # "linux", "macos", "windows"
```

### Architecture

```toml
condition = "${arch.is_x86_64}"
condition = "${arch.name}"  # "x86_64", "aarch64"
```

### File Operations

```toml
condition = "${file.exists('package.json')}"
condition = "${file.changed('src/**/*.rs')}"  # since last run
condition = "${file.newer('src/main.rs', 'target/debug/app')}"
condition = "${file.hash('Cargo.lock')}"
```

### Environment Variables

```toml
env = { PATH = "${env.PATH}:/custom/bin" }
condition = "${env.CI == 'true'}"
```

### Shell Execution

```toml
env = { GIT_COMMIT = "${shell('git rev-parse HEAD')}" }
```

### Semantic Versioning

```toml
condition = "${semver('1.2.3', '>=1.0.0')}"
```

### Task Runtime References

```toml
env = { PREV_STATUS = "${task.status('build')}" }  # "success", "failed", "running"
env = { BUILD_OUTPUT = "${task.output('build')}" }
```

---

## Example Configurations

### Simple Project

```toml
[tasks.install]
cmd = "npm install"

[tasks.build]
cmd = "npm run build"
deps = ["install"]

[tasks.test]
cmd = "npm test"
deps = ["build"]
tags = ["ci"]

[tasks.dev]
cmd = "npm run dev"
deps = ["install"]
```

### Monorepo

```toml
# root zr.toml
[workspace]
members = ["packages/*"]

[tasks.build-all]
deps = ["packages/core:build", "packages/utils:build", "packages/app:build"]

[tasks.test-all]
deps = ["packages/core:test", "packages/utils:test", "packages/app:test"]
tags = ["ci"]
```

### CI/CD Pipeline

```toml
[workflow.ci]
description = "Full CI/CD pipeline"

[[workflow.ci.stages]]
name = "prepare"
tasks = ["install", "lint"]

[[workflow.ci.stages]]
name = "test"
tasks = ["test-unit", "test-integration", "test-e2e"]
parallel = true
fail_fast = true

[[workflow.ci.stages]]
name = "build"
tasks = ["build-frontend", "build-backend"]
parallel = true

[[workflow.ci.stages]]
name = "deploy-staging"
tasks = ["deploy-staging"]
condition = "${env.BRANCH == 'develop'}"

[[workflow.ci.stages]]
name = "deploy-prod"
tasks = ["deploy-prod"]
condition = "${env.BRANCH == 'main'}"
approval = true
```

---

## See Also

- [Expressions Guide](expressions.md) — detailed expression syntax
- [Commands Reference](commands.md) — CLI command documentation
- [Getting Started](getting-started.md) — quick start guide
