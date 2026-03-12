# Configuration Reference

This document describes the complete `zr.toml` configuration schema.

## Table of Contents

- [Tasks](#tasks)
  - [Execution Hooks](#execution-hooks-v1240)
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
| `deps_if` | array | ❌ | [] | Conditional dependencies (run if condition is true) |
| `deps_optional` | array | ❌ | [] | Optional dependencies (ignored if task doesn't exist) |
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
| `cpu_affinity` | array | ❌ | [] | Bind task to specific CPU cores (e.g., `[0, 1, 2]`) |
| `numa_node` | integer | ❌ | null | Bind task to specific NUMA node |
| `toolchain` | array | ❌ | [] | Required toolchains (e.g., `["node@20"]`) |
| `tags` | array | ❌ | [] | Categorization tags |
| `watch` | table | ❌ | null | Watch mode configuration (v1.17.0, see [Watch Mode Configuration](#watch-mode-configuration-v1170)) |
| `hooks` | array | ❌ | [] | Execution hooks (v1.24.0, see [Execution Hooks](#execution-hooks-v1240)) |

### Dependencies

```toml
[tasks.test]
cmd = "npm test"
deps = ["build"]  # runs build first (parallel if multiple)

[tasks.deploy]
cmd = "./deploy.sh"
deps_serial = ["build", "test", "lint"]  # runs in order, one at a time

[tasks.build-prod]
cmd = "npm run build"
deps_if = [{ task = "lint", condition = "env.CI == 'true'" }]  # only lint in CI
deps_optional = ["format"]  # run format if it exists, silently skip if not
```

**Dependency Types:**

- `deps`: Parallel dependencies (run concurrently if multiple)
- `deps_serial`: Sequential dependencies (run one after another)
- `deps_if`: Conditional dependencies (only run if expression evaluates to true)
- `deps_optional`: Optional dependencies (silently skip if task doesn't exist)

**Conditional Dependencies Syntax:**

```toml
deps_if = [{ task = "task_name", condition = "expression" }, ...]
```

The condition is evaluated using the same [expression engine](#expressions) as the `condition` field. Common patterns:

- `env.VAR == "value"` - check environment variable
- `platform.is_linux` - check platform
- `env.CI == 'true' && platform.is_linux` - combine conditions

**Note:** Use inline format for `deps_if` (multi-line arrays with indentation are not currently supported).

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

[tasks.performance-critical]
cmd = "./run-simulation"
cpu_affinity = [0, 1]  # pin to cores 0-1
numa_node = 0  # bind to NUMA node 0
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

### Watch Mode Configuration (v1.17.0)

Tasks can define custom watch mode behavior with the `[tasks.*.watch]` section. This controls debouncing and file filtering when running `zr watch <task>`.

**Available Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `debounce_ms` | integer | 300 | Delay in milliseconds before triggering execution after file changes. Multiple rapid changes within this window are coalesced into one execution. |
| `patterns` | array | [] | Glob patterns for file inclusion (e.g., `["**/*.zig", "*.toml"]`). Empty list means watch all files. |
| `exclude_patterns` | array | [] | Glob patterns for file exclusion (e.g., `["**/*.test.zig", "node_modules/**"]`). Takes precedence over include patterns. |
| `mode` | string | null | Watch mode: `"native"` (inotify/kqueue/ReadDirectoryChangesW) or `"polling"`. If null, auto-selects native if available, fallback to polling. |

**Example: Basic debouncing**

```toml
[tasks.build]
cmd = "zig build"

[tasks.build.watch]
debounce_ms = 500  # wait 500ms after last change
```

**Example: Watch only specific file types**

```toml
[tasks.frontend-dev]
cmd = "npm run dev"

[tasks.frontend-dev.watch]
debounce_ms = 200
patterns = ["src/**/*.ts", "src/**/*.tsx", "*.css"]
exclude_patterns = ["**/*.test.ts", "**/node_modules/**"]
```

**Example: Full configuration**

```toml
[tasks.test-watch]
cmd = "npm test"

[tasks.test-watch.watch]
debounce_ms = 300
patterns = ["src/**/*.ts", "test/**/*.ts"]
exclude_patterns = ["**/*.spec.ts", "**/.zig-cache/**", "**/zig-out/**"]
mode = "native"
```

**Usage:**

```bash
# Uses watch config from task definition
zr watch build

# Override watch paths from CLI (patterns still apply)
zr watch build src/ lib/
```

**Pattern Matching:**

- Patterns use glob syntax (`*` = any chars, `**` = any subdirs)
- Exclude patterns take precedence over include patterns
- If no include patterns specified, all files match (unless excluded)
- Paths are matched relative to the watched directory

**Debouncing:**

- Default debounce is 300ms if not specified
- Set to `0` to disable debouncing (execute immediately on each change)
- Useful for preventing excessive rebuilds during rapid editing
- Changes within the debounce window are coalesced into a single execution

---

### Execution Hooks (v1.24.0)

Hooks allow you to execute commands before, after, or on specific task events. Each task can have multiple hooks.

**Basic Hook:**

```toml
[tasks.deploy]
cmd = "kubectl apply -f manifests/"

[[tasks.deploy.hooks]]
cmd = "npm run test"
point = "before"
description = "Run tests before deployment"
```

**Hook Fields:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `cmd` | string | ✅ | — | Command to execute |
| `point` | string | ✅ | — | Execution point: `before`, `after`, `success`, `failure`, `timeout` |
| `description` | string | ❌ | null | Human-readable description |
| `env` | table | ❌ | {} | Environment variable overrides |
| `failure_strategy` | string | ❌ | "warn" | Behavior on hook failure: `warn`, `abort_task`, `abort_all` |

**Execution Points:**

- `before` — Execute before the task starts
- `after` — Execute after the task completes (regardless of success/failure)
- `success` — Execute only if the task succeeds
- `failure` — Execute only if the task fails
- `timeout` — Execute only if the task times out (requires `timeout_ms` field)

**Failure Strategies:**

```toml
[[tasks.critical.hooks]]
cmd = "echo 'Pre-check failed'"
point = "before"
failure_strategy = "abort_task"  # Stop task if hook fails
```

- `warn` (default) — Log warning and continue
- `abort_task` — Stop the task but continue other tasks
- `abort_all` — Stop all execution (fails the entire run)

**Environment Variables:**

Hooks can override environment variables:

```toml
[[tasks.notify.hooks]]
cmd = "curl -X POST $WEBHOOK_URL -d 'Deployment started'"
point = "before"
env = { WEBHOOK_URL = "https://hooks.slack.com/services/..." }
```

**Multiple Hooks:**

Tasks can have multiple hooks of different types:

```toml
[tasks.build]
cmd = "cargo build --release"

[[tasks.build.hooks]]
cmd = "cargo fmt --check"
point = "before"
description = "Check code formatting"

[[tasks.build.hooks]]
cmd = "cargo clippy -- -D warnings"
point = "before"
description = "Run linter"

[[tasks.build.hooks]]
cmd = "echo 'Build succeeded!'"
point = "success"

[[tasks.build.hooks]]
cmd = "echo 'Build failed!' >&2"
point = "failure"
failure_strategy = "warn"
```

**Execution Order:**

1. All `before` hooks run sequentially (in definition order)
2. Main task command executes
3. Result-specific hooks run (`success`, `failure`, or `timeout`)
4. All `after` hooks run (always, regardless of task outcome)

**Use Cases:**

- **Pre-checks:** Validate environment before running task
- **Notifications:** Send messages on success/failure
- **Cleanup:** Remove temporary files after task completion
- **Logging:** Record execution events
- **Rollback:** Revert changes if deployment fails

---

## Workflows

Workflows organize tasks into sequential stages with advanced control flow.

### Basic Workflow

```toml
[workflows.ci]
description = "Continuous integration pipeline"

[[workflows.ci.stages]]
name = "prepare"
tasks = ["install", "lint"]
parallel = true

[[workflows.ci.stages]]
name = "test"
tasks = ["test-unit", "test-integration"]
parallel = true
fail_fast = true

[[workflows.ci.stages]]
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
[[workflows.deploy.stages]]
name = "prod-deploy"
tasks = ["deploy-prod"]
condition = "${env.BRANCH == 'main'}"
```

### Failure Handling

```toml
[[workflows.ci.stages]]
name = "test"
tasks = ["test-all"]
on_failure = "notify-slack"
```

### Syntax Limitations

> **Note**: The following TOML syntax patterns are **not yet supported** by the parser:

#### ❌ Inline Stage Arrays (Not Supported)

```toml
# This syntax does NOT work (parser limitation):
[workflows.ci]
stages = [
    { name = "test", tasks = ["unit", "integration"] },
    { name = "build", tasks = ["build"], fail_fast = true }
]
```

**Workaround**: Use the `[[workflows.*.stages]]` array-of-tables syntax shown above.

#### ❌ Tasks Without `cmd` Field (Not Supported)

```toml
# This syntax does NOT work (parser requires cmd field):
[tasks.all-checks]
description = "Run all checks"
deps = ["lint", "test", "build"]
# Missing: cmd field
```

**Workaround**: Add a no-op command:

```toml
[tasks.all-checks]
description = "Run all checks"
cmd = "echo 'All checks completed'"
deps = ["lint", "test", "build"]
```

These limitations are tracked in [issue #17](https://github.com/yusa-imit/zr/issues/17) and may be addressed in future versions.

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

### CPU Affinity and NUMA

For performance-critical tasks, you can pin tasks to specific CPU cores or NUMA nodes:

```toml
[tasks.build]
cmd = "make -j4"
cpu_affinity = [0, 1, 2, 3]  # Run only on cores 0-3
description = "Build on specific cores for cache locality"

[tasks.database]
cmd = "./run-db"
numa_node = 0  # Bind to NUMA node 0 (closer memory)
description = "Run database on NUMA node 0"

[tasks.compute]
cmd = "./train-model"
cpu_affinity = [4, 5, 6, 7]
numa_node = 1  # Cores 4-7 on NUMA node 1
description = "Run ML training on isolated cores"
```

**CPU Affinity (`cpu_affinity`):**
- Array of CPU core IDs (0-indexed)
- Task will run on the first specified core (future: work-stealing across all cores)
- Best effort: silently ignored if platform doesn't support affinity
- Use case: Cache locality, avoiding CPU migration overhead

**NUMA Node (`numa_node`):**
- Single NUMA node ID
- Currently parsed but not yet enforced (future: memory allocation on specific node)
- Use case: Reduce memory access latency on multi-socket systems

**Platform Support:**
- Linux: Full support via `sched_setaffinity()`
- Windows: Full support via `SetThreadAffinityMask()`
- macOS: Advisory only (not guaranteed)
- Other: Silently ignored

**Example Use Cases:**
1. **Database server**: Pin to node 0 with its local memory
2. **Web server**: Pin to node 1 to avoid contention
3. **Build tasks**: Pin to specific cores for reproducible cache behavior
4. **ML training**: Isolate on dedicated cores to avoid interruptions

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

Define reusable task templates with parameters for common patterns.

### Basic Template Definition

Templates are defined using the `[templates.NAME]` section format:

```toml
[templates.test-watch]
description = "Run tests in watch mode"
params = ["port"]
cmd = "npm test -- --watch --port={{port}}"
cwd = "./tests"
timeout = "60s"
```

### Parameter Substitution

Parameters are defined in the `params` array and referenced using `{{param_name}}` syntax in any string field:

```toml
[templates.server]
params = ["port", "host", "env"]
cmd = "node server.js --port={{port}} --host={{host}}"
env = { NODE_ENV = "{{env}}" }
```

### Applying Templates to Tasks

Tasks can apply a template using the `template` field and provide parameter values via `params`:

```toml
[tasks.dev-server]
template = "server"
params = { port = "3000", host = "localhost", env = "development" }

[tasks.prod-server]
template = "server"
params = { port = "8080", host = "0.0.0.0", env = "production" }
```

When a task applies a template:
1. Parameter values are substituted into the template's fields
2. The task's fields override the template's fields
3. Dependencies, environment variables, and other settings are merged

### Interactive Template Application

Use the `zr template` commands to work with templates:

```bash
# List all available templates
zr template list

# Show detailed information about a template
zr template show test-watch

# Apply a template interactively (prompts for parameter values)
zr template apply server my-task
```

### Template Fields

Templates support the same fields as tasks:

- **Basic**: `cmd`, `description`, `cwd`
- **Dependencies**: `deps`, `deps_serial`, `deps_if`, `deps_optional`
- **Execution**: `timeout`, `allow_failure`, `retry`, `condition`
- **Environment**: `env`, `toolchain`
- **Resources**: `max_cpu`, `max_memory`, `max_concurrent`
- **Cache**: `cache`, `cache_policy`
- **Hooks**: `on_before`, `on_after`, `on_success`, `on_failure`, `on_timeout`

### Complex Template Example

```toml
[templates.microservice-deploy]
description = "Deploy a microservice to Kubernetes"
params = ["service_name", "namespace", "tag"]
cmd = "kubectl apply -f deployment.yaml"
cwd = "./k8s/{{service_name}}"
timeout = "5m"
deps = ["build-{{service_name}}", "test-{{service_name}}"]
env = { IMAGE_TAG = "{{tag}}", NAMESPACE = "{{namespace}}" }
allow_failure = false
retry = { max = 3, delay = "10s", backoff = "exponential" }

# Apply template for different services
[tasks.deploy-api]
template = "microservice-deploy"
params = { service_name = "api", namespace = "production", tag = "v1.2.3" }

[tasks.deploy-worker]
template = "microservice-deploy"
params = { service_name = "worker", namespace = "production", tag = "v1.2.3" }
```

### Template Best Practices

1. **Keep templates generic** — Use parameters for values that vary between instances
2. **Document parameters** — Use descriptive names and add a `description` field
3. **Set sensible defaults** — Provide default values in the template where appropriate
4. **Test templates thoroughly** — Ensure parameter substitution works correctly
5. **Version templates carefully** — Changes to templates affect all tasks using them

### Limitations

- Parameter substitution only works in string fields (not arrays or numbers)
- Templates cannot reference other templates (no template inheritance)
- Parameters must be provided for all declared params (no optional parameters)

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

### Expression Debugging

zr provides expression diagnostics for debugging complex conditional expressions. When an expression fails to evaluate, zr can provide a detailed stack trace showing the evaluation path.

**Expression Stack Traces**

When using the expression evaluator API with `DiagContext`, you get detailed stack traces on errors:

```
Expression evaluation failed: InvalidExpression

Expression evaluation stack:
  at OR: platform.is_linux || file.exists('package.json')
  at AND: file.exists('package.json') && env.CI == 'true'
  at file.exists: file.exists('package.json')
```

**Diagnostic Features**

- **Operator Tracking**: Shows the sequence of OR/AND operators evaluated
- **Function Calls**: Tracks each expression function (file.exists, env, etc.)
- **Platform Predicates**: Logs platform/arch checks
- **Git Predicates**: Tracks git.branch, git.tag, git.dirty evaluations
- **Runtime References**: Shows task/stage reference lookups

**Performance**

Expression diagnostics are opt-in and have minimal overhead:
- Disabled by default (no performance cost)
- Enabled only when `DiagContext` is provided
- Uses lightweight stack frames (expression string + type)
- Automatic cleanup via defer (no memory leaks)

**Usage in Code**

```zig
const expr_diagnostics = @import("config/expr_diagnostics.zig");
var diag = expr_diagnostics.DiagContext.init(allocator);
defer diag.deinit();

const result = evalConditionWithDiag(
    allocator,
    "platform.is_linux && file.exists('data.json')",
    null, // task_env
    null, // runtime_state
    &diag, // diagnostic context
) catch |err| {
    std.debug.print("Error: {}\n", .{err});
    try diag.formatStackTrace(std.io.getStdErr().writer());
    return err;
};
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
