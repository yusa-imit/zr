# Configuration Reference

This document describes the complete `zr.toml` configuration schema.

## Table of Contents

- [Tasks](#tasks)
  - [Execution Hooks](#execution-hooks-v1240)
  - [Remote Execution](#remote-execution-v1460)
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
| `circuit_breaker` | table | ❌ | null | Circuit breaker configuration (v1.30.0, see [Circuit Breaker](#circuit-breaker-v1300)) |
| `checkpoint` | table | ❌ | null | Checkpoint/resume configuration (v1.31.0, see [Checkpoint/Resume](#checkpointresume-v1310)) |
| `remote` | string | ❌ | null | Remote execution target (v1.46.0, see [Remote Execution](#remote-execution-v1460)) |
| `remote_cwd` | string | ❌ | null | Working directory on remote host (v1.46.0) |
| `remote_env` | table | ❌ | {} | Environment variables for remote execution (v1.46.0) |

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

### Circuit Breaker (v1.30.0)

Circuit breakers automatically stop retrying tasks when failure rate exceeds a threshold, preventing retry storms and wasted resources.

```toml
[tasks.external-api]
cmd = "curl https://api.example.com/data"
retry_max = 10
retry_delay_ms = 1000
retry_backoff = true

[tasks.external-api.circuit_breaker]
failure_threshold = 0.5      # Open circuit at 50% failure rate
min_attempts = 3             # Minimum attempts before circuit can open
window_ms = 60000            # 1-minute time window for failure rate calculation
reset_timeout_ms = 30000     # 30-second cooldown before retry attempt (half-open state)
```

**Circuit Breaker Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `failure_threshold` | float | 0.5 | Failure rate (0.0-1.0) that trips the circuit |
| `min_attempts` | integer | 3 | Minimum attempts before circuit can trip |
| `window_ms` | integer | 60000 | Time window in ms for tracking failures |
| `reset_timeout_ms` | integer | 30000 | Cooldown period before half-open retry |

**Circuit States:**

- **Closed**: Normal operation, retries allowed
- **Open**: Circuit tripped, retries blocked (failure rate ≥ threshold)
- **Half-Open**: After reset timeout, one retry attempt allowed to test recovery

**Example: Protecting against flaky external services**

```toml
[tasks.weather-api]
cmd = "curl https://weather-api.example.com/current"
retry_max = 5
retry_delay_ms = 2000
retry_backoff = true

[tasks.weather-api.circuit_breaker]
failure_threshold = 0.6  # Trip at 60% failure rate
min_attempts = 2         # Trip after 2 attempts if both fail
window_ms = 120000       # 2-minute window
reset_timeout_ms = 60000 # 1-minute cooldown
```

With this config:
- If 2 out of 2 attempts fail (100% > 60% threshold), circuit opens
- Circuit stays open for 1 minute (reset_timeout_ms)
- After 1 minute, one retry is attempted (half-open state)
- If retry succeeds, circuit closes; if it fails, circuit reopens

**Note:** Circuit breaker state is per-task and resets between `zr run` invocations. For persistent circuit breaker state across runs, consider using external monitoring tools.

### Checkpoint/Resume (v1.31.0)

Checkpoints allow long-running tasks to save their progress and resume from the last checkpoint if interrupted or restarted.

```toml
[tasks.long-training]
cmd = "./train-model.sh"
timeout_ms = 3600000  # 1 hour

[tasks.long-training.checkpoint]
enabled = true
interval_ms = 60000           # Save checkpoint every 60 seconds
storage = "filesystem"        # Storage backend (only "filesystem" currently)
checkpoint_dir = ".zr/checkpoints"  # Directory for checkpoint files
```

**Checkpoint Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | false | Enable checkpoint/resume for this task |
| `interval_ms` | integer | 60000 | Minimum interval between checkpoints (ms) |
| `storage` | string | "filesystem" | Storage backend (currently only "filesystem") |
| `checkpoint_dir` | string | ".zr/checkpoints" | Directory to store checkpoint files |

**How Checkpointing Works:**

1. **Task Emits Checkpoint Markers**: Your task prints a JSON marker to stdout:
   ```bash
   echo "CHECKPOINT: {\"step\": 42, \"loss\": 0.123}"
   ```

2. **zr Captures and Saves**: The scheduler monitors stdout, parses the marker, and saves the checkpoint to disk (respecting `interval_ms` to avoid excessive I/O).

3. **Resume on Next Run**: When the task runs again, zr loads the last checkpoint and passes it via the `ZR_CHECKPOINT` environment variable:
   ```bash
   # In your script:
   if [ -n "$ZR_CHECKPOINT" ]; then
     # Parse checkpoint JSON and resume
     STEP=$(echo "$ZR_CHECKPOINT" | jq -r '.state.step')
     echo "Resuming from step $STEP"
   else
     echo "Starting fresh"
   fi
   ```

**Example: Machine Learning Training**

```toml
[tasks.train-neural-net]
cmd = "./train.py"
timeout_ms = 7200000  # 2 hours

[tasks.train-neural-net.checkpoint]
enabled = true
interval_ms = 120000  # Checkpoint every 2 minutes
```

Python script (`train.py`):
```python
import json
import os
import sys

# Resume from checkpoint if available
start_epoch = 0
if 'ZR_CHECKPOINT' in os.environ:
    checkpoint = json.loads(os.environ['ZR_CHECKPOINT'])
    start_epoch = checkpoint.get('state', {}).get('epoch', 0)
    print(f"Resuming from epoch {start_epoch}")

for epoch in range(start_epoch, 100):
    # Training logic...
    loss = train_epoch(epoch)

    # Emit checkpoint marker
    checkpoint_data = {"epoch": epoch + 1, "loss": loss}
    print(f"CHECKPOINT: {json.dumps(checkpoint_data)}", flush=True)
```

**Limitations:**

- Checkpoint monitoring only works when `inherit_stdio=false` (default for most tasks)
- Interactive tasks (`inherit_stdio=true`) cannot emit checkpoints
- Checkpoint state is task-local (not shared across different tasks)
- Only JSON format is supported for checkpoint markers

**Note:** The checkpoint marker line is removed from task output to avoid cluttering logs. Only the actual task output is displayed.

### Remote Execution (v1.46.0)

Execute tasks on remote machines via SSH or HTTP workers. This enables distributed builds, offloading resource-intensive tasks, and leveraging remote compute resources.

```toml
[tasks.build-on-server]
cmd = "cargo build --release"
remote = "user@build-server.example.com:22"
remote_cwd = "/home/user/project"
remote_env = { RUST_LOG = "debug" }
```

**Remote Execution Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `remote` | string | null | Remote target specification (SSH or HTTP) |
| `remote_cwd` | string | null | Working directory on remote host (overrides local `cwd`) |
| `remote_env` | table | {} | Additional environment variables for remote execution |

**Supported Target Formats:**

1. **SSH (short format)**: `user@host[:port]`
   ```toml
   remote = "deploy@server.local:22"
   ```

2. **SSH (URI format)**: `ssh://user@host[:port]`
   ```toml
   remote = "ssh://ci@build-01.company.internal:2222"
   ```

3. **HTTP/HTTPS**: `http://host[:port]` or `https://host[:port]`
   ```toml
   remote = "http://worker.example.com:8080"
   ```

**SSH Remote Execution:**

SSH targets execute commands via `ssh user@host 'command'`. Requires:
- SSH key-based authentication (password prompts not supported)
- Remote host in `~/.ssh/known_hosts`
- Necessary permissions on remote machine

```toml
[tasks.deploy]
cmd = "./deploy.sh production"
remote = "deploy@prod-server.example.com"
remote_cwd = "/opt/app"
remote_env = { DEPLOY_ENV = "production", LOG_LEVEL = "info" }
deps = ["build", "test"]  # Run local deps first, then deploy remotely
```

**HTTP Remote Execution:**

HTTP targets POST task metadata as JSON to a remote worker service. The worker must implement the zr remote execution protocol:
- Endpoint: `POST /execute`
- Request: `{ "cmd": "...", "cwd": "...", "env": {...} }`
- Response: `{ "exit_code": 0, "stdout": "...", "stderr": "...", "duration_ms": 123 }`

```toml
[tasks.process-video]
cmd = "./encode.sh input.mp4"
remote = "https://gpu-worker-01.local:443"
remote_env = { GPU_DEVICE = "0" }
timeout_ms = 3600000  # 1 hour
```

**How It Works:**

1. **Local Dependencies**: All dependencies (`deps`, `deps_serial`, etc.) run locally first
2. **Task Serialization**: Task command, environment, and working directory are serialized
3. **Remote Execution**:
   - **SSH**: Command is executed via `ssh -p PORT user@host 'cd CWD && ENV=val CMD'`
   - **HTTP**: JSON payload is POSTed to remote worker endpoint
4. **Output Capture**: stdout/stderr are captured and returned to local zr process
5. **Exit Code**: Remote exit code determines task success/failure

**Error Handling:**

- **Connection Failures**: SSH exit code 255 or HTTP network errors → task fails with error
- **Timeouts**: `timeout_ms` applies to remote execution (includes network latency)
- **Retries**: Use `retry_max` and `retry_delay_ms` for transient network failures

```toml
[tasks.flaky-remote-build]
cmd = "make all"
remote = "builder@ci-agent-pool.local"
timeout_ms = 600000      # 10 minutes
retry_max = 3            # Retry on network failures
retry_delay_ms = 5000    # Wait 5 seconds between retries
```

**Use Cases:**

- **Distributed Builds**: Offload compilation to powerful build servers
- **GPU Processing**: Execute ML training or video encoding on GPU-equipped machines
- **Multi-Platform Testing**: Run tests on different OS/architectures via remote workers
- **CI/CD Pipeline**: Distribute test suite across multiple agents
- **Resource Isolation**: Execute memory/CPU-intensive tasks on dedicated machines

**Limitations:**

- SSH requires key-based authentication (no password prompt support)
- HTTP workers must implement the zr remote execution protocol
- File synchronization not automatic (use `rsync` in task `cmd` or remote cache)
- Interactive tasks (`inherit_stdio=true`) not supported for remote execution
- Remote tasks cannot spawn local subprocesses (all execution is remote)

**Example: Multi-Stage CI with Remote Execution**

```toml
[tasks.test-linux]
cmd = "./run-tests.sh"
remote = "ssh://ci@linux-builder.local:22"
remote_cwd = "/tmp/project"
tags = ["ci", "linux"]

[tasks.test-macos]
cmd = "./run-tests.sh"
remote = "ssh://ci@macos-builder.local:22"
remote_cwd = "/tmp/project"
tags = ["ci", "macos"]

[tasks.test-windows]
cmd = "powershell ./run-tests.ps1"
remote = "http://windows-worker.local:8080"
tags = ["ci", "windows"]

[workflows.ci-full]
stages = [
  ["test-linux", "test-macos", "test-windows"]  # All platforms in parallel
]
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

### Retry Budget (v1.30.0)

Retry budgets limit the total number of retries across all tasks in a workflow, preventing retry storms when multiple tasks fail simultaneously.

```toml
[workflows.integration-tests]
description = "Run integration test suite"
retry_budget = 5  # Maximum 5 total retries across all tasks

[[workflows.integration-tests.stages]]
name = "test"
tasks = ["db-test", "api-test", "ui-test"]
```

**Workflow Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `retry_budget` | integer | null | Maximum total retries across all tasks (null = unlimited) |

**How Retry Budget Works:**

1. Each task in the workflow can have `retry_max` configured
2. Workflow `retry_budget` limits total retries across **all** tasks
3. When a task fails and attempts to retry, it consumes from the workflow budget
4. If budget is exhausted, no more retries are allowed for any task

**Example: Preventing retry storms**

```toml
[workflows.flaky-suite]
description = "Run flaky test suite with retry budget"
retry_budget = 10  # Max 10 retries total

[[workflows.flaky-suite.stages]]
name = "unit-tests"
tasks = ["unit-fast", "unit-slow", "unit-integration"]

[tasks.unit-fast]
cmd = "npm run test:unit:fast"
retry_max = 3  # Can retry up to 3 times

[tasks.unit-slow]
cmd = "npm run test:unit:slow"
retry_max = 5  # Can retry up to 5 times

[tasks.unit-integration]
cmd = "npm run test:integration"
retry_max = 4  # Can retry up to 4 times
```

In this workflow:
- Without retry budget: up to 3+5+4 = 12 total retries possible
- With `retry_budget = 10`: stops at 10 total retries
- If `unit-fast` uses 4 retries and `unit-slow` uses 6 retries, workflow stops (budget exhausted)
- Remaining tasks (`unit-integration`) cannot retry even if they fail

**Use Cases:**

- **CI/CD pipelines**: Limit retry attempts to avoid long-running builds
- **Flaky test suites**: Allow some retries but prevent infinite loops
- **Resource-intensive tasks**: Control total resource consumption from retries
- **External API calls**: Limit total API calls when multiple tasks call the same service

**Note:** Retry budget is enforced per workflow execution. Each `zr workflow <name>` starts with a fresh budget.

**Multi-Stage Workflows (v1.34.0):**

The retry budget is shared across **all stages** in the workflow. For example:

```toml
[workflows.deploy]
retry_budget = 5  # Shared across both stages

[[workflows.deploy.stages]]
name = "build"
tasks = ["compile", "test"]

[[workflows.deploy.stages]]
name = "deploy"
tasks = ["docker-push", "k8s-apply"]
```

If the "build" stage consumes 3 retries, only 2 retries remain for the "deploy" stage. This prevents excessive retries even when failures occur across different stages.

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
- Task threads use **work-stealing** across ALL specified cores (not just the first)
- Enables load balancing while maintaining cache locality
- Validation: warns if CPU IDs exceed available cores, continues best-effort
- Use case: Multi-threaded tasks that benefit from cache locality without single-core pinning
- Example: `[0, 1, 2, 3]` allows task to run on any of cores 0-3 (better than pinning to core 0)

**NUMA Node (`numa_node`):**
- Single NUMA node ID (0-indexed)
- **Fully enforced**: all task-scoped allocations bound to specified NUMA node
- Memory binding via platform-specific APIs (see Platform Support below)
- Best-effort: allocation succeeds even if NUMA binding fails (falls back to default allocator)
- Invalid node IDs are handled gracefully (no task failure)
- Use case: Reduce memory access latency on multi-socket systems by co-locating memory and CPU

**Platform Support:**
- **Linux**: Full support
  - CPU affinity: `sched_setaffinity()` with cpuset mask for all specified cores
  - NUMA: `mbind()` syscall with `MPOL_BIND` policy for memory allocation
- **Windows**: Partial support
  - CPU affinity: `SetThreadAffinityMask()` with bitmask for all specified cores
  - NUMA: Reserved for future `VirtualAllocExNuma` (currently best-effort fallback)
- **macOS**: Best-effort
  - CPU affinity: Thread policy API (advisory, not guaranteed)
  - NUMA: No-op (unified memory architecture, no NUMA support)
- **Other**: Silently ignored (no failures)

**Performance Characteristics:**
- **No overhead when not used**: Tasks without `cpu_affinity` or `numa_node` use default allocator and no affinity calls
- **Overhead when used**:
  - CPU affinity: Single `sched_setaffinity()` call per worker thread (~microseconds)
  - NUMA: `mbind()` syscall on every allocation (~10-100ns per allocation on Linux)
- **Benefits**:
  - CPU affinity: 2-10% speedup for multi-threaded tasks (cache locality)
  - NUMA: 20-50% speedup for memory-intensive tasks on multi-socket systems (reduced memory latency)

**Example Use Cases:**
1. **Database server**: Pin to node 0 with its local memory
2. **Web server**: Pin to node 1 to avoid contention
3. **Build tasks**: Pin to specific cores for reproducible cache behavior
4. **ML training**: Isolate on dedicated cores to avoid interruptions

### NUMA Best Practices

**When to Use NUMA:**
- Multi-socket systems with > 2 NUMA nodes (check with `numactl --hardware` on Linux)
- Memory-intensive tasks (> 1GB allocations)
- Tasks with high memory bandwidth requirements (> 10GB/s)
- Long-running compute tasks (> 10 seconds)

**When NOT to Use NUMA:**
- Single-socket systems (no benefit, adds overhead)
- Short-lived tasks (< 1 second — overhead exceeds benefit)
- I/O-bound tasks (NUMA doesn't improve I/O latency)
- Tasks with small allocations (< 100MB — NUMA overhead dominates)

**Combining CPU Affinity and NUMA:**
```toml
[tasks.optimal_compute]
cmd = "./train-model --threads 4"
cpu_affinity = [0, 1, 2, 3]  # Cores on NUMA node 0
numa_node = 0                 # Memory on NUMA node 0
description = "Optimal: CPU and memory co-located"
```

**Topology Mapping:**
On Linux, check CPU-to-NUMA mapping:
```bash
numactl --hardware
# Example output:
# available: 2 nodes (0-1)
# node 0 cpus: 0 1 2 3
# node 1 cpus: 4 5 6 7
```

**Anti-Patterns:**
```toml
# ❌ BAD: CPU and memory on different nodes (cross-node traffic)
[tasks.bad_split]
cpu_affinity = [0, 1]  # Node 0 cores
numa_node = 1          # Node 1 memory (high latency!)

# ✅ GOOD: Co-locate CPU and memory
[tasks.good_split]
cpu_affinity = [0, 1]  # Node 0 cores
numa_node = 0          # Node 0 memory (low latency)

# ❌ BAD: NUMA for short tasks
[tasks.bad_short]
cmd = "echo hello"
numa_node = 0  # Overhead > task duration

# ✅ GOOD: NUMA for long tasks
[tasks.good_long]
cmd = "./process-large-dataset"
numa_node = 0  # Benefit > overhead
```

**Verification:**
On Linux, verify NUMA binding with:
```bash
# While task is running:
cat /proc/<pid>/numa_maps | grep bind
# Should show "bind:0" for NUMA node 0 allocations
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
