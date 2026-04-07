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
  - [Root Configuration](#root-configuration)
  - [Member Configuration](#member-configuration)
  - [Workspace-Level Task Inheritance](#workspace-level-task-inheritance-v1630)
- [Resource Limits](#resource-limits)
- [Concurrency Groups](#concurrency-groups-v1620)
- [Toolchains](#toolchains)
- [Plugins](#plugins)
- [Aliases](#aliases)
- [Schedules](#schedules)
- [Mixins](#mixins-v1670)
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
| `retry_backoff` | boolean | ❌ | false | **DEPRECATED** v1.47.0: Use `retry_backoff_multiplier` instead |
| `retry_backoff_multiplier` | float | ❌ | null | Backoff multiplier (1.0=linear, 2.0=exponential, v1.47.0) |
| `retry_jitter` | boolean | ❌ | false | Add ±25% jitter to retry delays (v1.47.0) |
| `max_backoff_ms` | integer | ❌ | 60000 | Maximum retry delay ceiling (v1.47.0) |
| `retry_on_codes` | array | ❌ | [] | Only retry on specific exit codes (v1.47.0) |
| `retry_on_patterns` | array | ❌ | [] | Only retry when output contains patterns (v1.47.0) |
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

zr provides sophisticated retry mechanisms with exponential backoff, conditional retry, jitter, and failure hooks to handle transient failures gracefully.

#### Basic Retry Configuration

```toml
[tasks.flaky-test]
cmd = "npm test"
timeout_ms = 60000        # 1 minute timeout
retry_max = 3             # Retry up to 3 times
retry_delay_ms = 1000     # Base delay: 1 second
retry_backoff = true      # DEPRECATED: Use retry_backoff_multiplier instead
```

**Basic Retry Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `retry_max` | integer | 0 | Maximum retry attempts (0 = no retry) |
| `retry_delay_ms` | integer | 0 | Base delay between retries in milliseconds |
| `retry_backoff` | boolean | false | **DEPRECATED** in v1.47.0. Use `retry_backoff_multiplier` instead |

#### Advanced Retry Strategies (v1.47.0)

```toml
[tasks.api-request]
cmd = "curl https://api.example.com/data"
retry_max = 5
retry_delay_ms = 1000
retry_backoff_multiplier = 2.0  # Exponential: 1s, 2s, 4s, 8s, 16s
retry_jitter = true              # Add ±25% random variance
max_backoff_ms = 30000           # Cap delays at 30 seconds
retry_on_codes = [1, 2, 7]       # Only retry on specific exit codes
retry_on_patterns = ["timeout", "Connection refused", "503"]  # Or on output patterns
```

**Advanced Retry Fields (v1.47.0):**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `retry_backoff_multiplier` | float | null | Backoff multiplier: 1.0=linear (constant), 2.0=exponential (double), 1.5=moderate. If null, uses legacy `retry_backoff` (2.0 if true, 1.0 if false) |
| `retry_jitter` | boolean | false | Add ±25% random jitter to delays (prevents thundering herd) |
| `max_backoff_ms` | integer | null | Maximum delay ceiling in milliseconds (default: 60000ms/60s) |
| `retry_on_codes` | array | [] | Only retry if exit code matches these codes (empty = retry on any code) |
| `retry_on_patterns` | array | [] | Only retry if stdout/stderr contains these patterns (empty = retry on any output) |

#### Backoff Strategies

**Linear backoff (constant delay):**
```toml
retry_delay_ms = 5000
retry_backoff_multiplier = 1.0  # Delays: 5s, 5s, 5s, 5s, ...
```

**Exponential backoff (doubles each retry):**
```toml
retry_delay_ms = 1000
retry_backoff_multiplier = 2.0  # Delays: 1s, 2s, 4s, 8s, 16s, 32s, 60s (capped)
max_backoff_ms = 60000          # Cap at 60 seconds
```

**Moderate backoff (1.5x growth):**
```toml
retry_delay_ms = 2000
retry_backoff_multiplier = 1.5  # Delays: 2s, 3s, 4.5s, 6.75s, 10.1s, ...
```

**Aggressive backoff (3x growth):**
```toml
retry_delay_ms = 1000
retry_backoff_multiplier = 3.0  # Delays: 1s, 3s, 9s, 27s, 60s (capped)
max_backoff_ms = 60000
```

#### Conditional Retry

**Retry only on specific exit codes (network errors):**
```toml
[tasks.download]
cmd = "wget https://example.com/file.zip"
retry_max = 5
retry_delay_ms = 2000
retry_backoff_multiplier = 2.0
retry_on_codes = [1, 2, 3, 4, 5, 6, 7, 8]  # wget network error codes
```

**Retry only when output matches patterns:**
```toml
[tasks.flaky-service]
cmd = "./run-integration-tests.sh"
retry_max = 3
retry_delay_ms = 5000
retry_on_patterns = [
    "Connection refused",
    "timeout",
    "503 Service Unavailable",
    "ECONNRESET"
]
```

**Combined conditions (exit code AND pattern must match):**
```toml
[tasks.api-call]
cmd = "curl -f https://api.example.com/v1/data"
retry_max = 5
retry_delay_ms = 1000
retry_backoff_multiplier = 2.0
retry_on_codes = [7, 28]          # curl: failed to connect, timeout
retry_on_patterns = ["timeout"]   # AND output contains "timeout"
```

**Note:** If both `retry_on_codes` and `retry_on_patterns` are specified, **both** conditions must be met for retry to occur (AND logic). If either list is empty, that condition is ignored (always true).

#### Jitter for Thundering Herd Prevention

When multiple tasks retry simultaneously (e.g., after a service outage), synchronized retries can overwhelm the recovering service. Jitter adds random variance to delays:

```toml
[tasks.shared-resource]
cmd = "access-shared-db.sh"
retry_max = 10
retry_delay_ms = 1000
retry_backoff_multiplier = 2.0
retry_jitter = true  # Adds ±25% random variance to each delay
```

With `retry_jitter = true`, a calculated delay of 8000ms becomes 6000-10000ms (random within ±25%).

#### Failure Hooks

Execute commands when tasks fail (notifications, cleanup, logging):

```toml
[tasks.critical-job]
cmd = "./run-critical-task.sh"
retry_max = 3
retry_delay_ms = 5000
retry_backoff_multiplier = 2.0

hooks = [
    { point = "failure", cmd = "notify-slack.sh 'Critical job failed'", failure_strategy = "continue_task" }
]
```

**Hook Points:**
- `before` — Execute before task starts
- `after` — Execute after task completes (any status)
- `success` — Execute only on successful completion
- `failure` — Execute only on failure (after all retries exhausted)
- `timeout` — Execute only on timeout

See [Execution Hooks](#execution-hooks-v1240) for detailed hook configuration.

#### Smart Retry Decisions

zr automatically skips retry for known-fatal errors to save time:

**Fatal errors (no retry by default):**
- Permission denied (exit code 126, 127)
- Command not found (exit code 127)
- Syntax errors in scripts (exit code 2 for bash)
- SIGKILL, SIGSEGV (signals 9, 11)

**Retriable errors (retry by default):**
- Network timeouts (exit code 124, curl 7/28)
- Connection refused (curl 7, wget 4)
- Service unavailable (HTTP 503, exit code varies)
- Resource temporarily unavailable (EAGAIN)

**Override smart defaults with conditional retry:**
```toml
# Force retry even on permission errors (not recommended)
retry_on_codes = [126]

# Or be explicit about what to retry
retry_on_codes = [1, 7, 28]  # Only network-related errors
```

#### Retry with Circuit Breaker

Combine retry with circuit breaker to prevent retry storms:

```toml
[tasks.external-api]
cmd = "curl https://api.example.com/data"
retry_max = 10
retry_delay_ms = 1000
retry_backoff_multiplier = 2.0
retry_jitter = true

[tasks.external-api.circuit_breaker]
failure_threshold = 0.5      # Stop retrying at 50% failure rate
min_attempts = 3
window_ms = 60000
reset_timeout_ms = 30000
```

See [Circuit Breaker](#circuit-breaker-v1300) for details.

#### Retry Statistics in History

Retry attempts are tracked in execution history:

```bash
$ zr history
2026-04-07 12:34:56  api-request  FAIL  45s  (3 retries)  exit code: 7
2026-04-07 12:30:12  flaky-test   OK    12s  (1 retry)
2026-04-07 12:25:00  stable-task  OK    5s   (0 retries)
```

**History fields:**
- `retry_count` — Total retry attempts across all tasks in the run
- Displayed after duration in parentheses when > 0

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

### Concurrency Groups (v1.62.0)

Concurrency groups allow fine-grained control over parallel execution for heterogeneous workloads. Define named groups with independent worker limits, then assign tasks to groups.

**Use Cases:**
- GPU-bound tasks limited to GPU count (e.g., max_workers = 2)
- Network tasks limited by rate limit or connection pool (e.g., max_workers = 10)
- Database operations limited by connection count (e.g., max_workers = 5)
- Memory-intensive tasks limited by available RAM

**Basic Example:**

```toml
# Define concurrency groups
[concurrency_groups.gpu]
max_workers = 2  # Only 2 GPU tasks can run concurrently

[concurrency_groups.network]
max_workers = 10  # Up to 10 network tasks can run concurrently

[concurrency_groups.database]
max_workers = 5  # Limit database connections

# Assign tasks to groups
[tasks.train_model]
cmd = "./train.py --gpu"
concurrency_group = "gpu"  # Uses gpu group limit (2)

[tasks.fetch_data]
cmd = "curl https://api.example.com/data"
concurrency_group = "network"  # Uses network group limit (10)

[tasks.migrate_db]
cmd = "./migrate.sh"
concurrency_group = "database"  # Uses database group limit (5)

[tasks.regular_task]
cmd = "echo hello"
# No concurrency_group = uses default max_workers
```

**Concurrency Group Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_workers` | integer | null | Maximum concurrent tasks in this group. `null` or `0` means use global `max_workers` (default CPU count). |

**Task Assignment:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `concurrency_group` | string | null | Name of the concurrency group for this task. If `null`, uses default global worker pool. If the specified group doesn't exist, falls back to global pool. |

**Behavior:**
- Tasks without `concurrency_group` share the default worker pool (controlled by global `max_workers` or `--jobs` flag)
- Tasks in a group share that group's worker pool independently of other groups
- Groups run concurrently with each other (e.g., 2 GPU tasks + 10 network tasks can run simultaneously)
- Worker limits are per-group, not global (group A limit=1, group B limit=1 → 2 tasks total can run in parallel)

**Advanced Example: Mixed Workload:**

```toml
[concurrency_groups.gpu]
max_workers = 2

[concurrency_groups.api_calls]
max_workers = 50  # High limit for I/O-bound work

[tasks.preprocess]
cmd = "./preprocess.sh"
# No group = uses default pool

[tasks.train_fast]
cmd = "./train.py --mode fast"
concurrency_group = "gpu"

[tasks.train_accurate]
cmd = "./train.py --mode accurate"
concurrency_group = "gpu"

[tasks.upload_results]
cmd = "curl -X POST https://api.example.com/results"
concurrency_group = "api_calls"
retry_max = 3  # Retries work with groups

[tasks.notify_slack]
cmd = "./notify.sh"
concurrency_group = "api_calls"
```

**Integration with Other Features:**
- Works with dependencies (`deps`, `deps_serial`, `deps_if`)
- Compatible with `retry_max`, `cache`, `max_concurrent` (per-task limit)
- Respects `cpu_affinity` and `numa_node` hints
- Works in workflows and stages
- Independent of `--jobs` flag (groups have their own limits)

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

### Workspace-Level Task Inheritance (v1.63.0)

Define common tasks in the workspace root that all members inherit automatically. This reduces duplication for tasks like linting, testing, and formatting.

**Root `zr.toml`:**

```toml
[workspace]
members = ["packages/*", "apps/*"]

# Shared tasks inherited by all members
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

**Member behavior:**

- **Automatic inheritance**: Members automatically receive all workspace shared tasks
- **Override semantics**: If a member defines a task with the same name, it completely replaces the workspace task (no merging)
- **Visibility**: Run `zr list` in a member directory to see inherited tasks marked with `(inherited)`
- **Dependencies**: Inherited tasks can depend on member-local tasks via standard DAG resolution

**Example member override** (`packages/api/zr.toml`):

```toml
# Override workspace test task with custom command
[tasks.test]
cmd = "cargo test"  # Replaces workspace "jest" command
description = "Run Rust tests"

# Inherit lint and format tasks from workspace (no override)
```

**Usage:**

```bash
cd packages/api
zr list              # Shows: lint (inherited), test (local), format (inherited)
zr run lint          # Runs workspace lint command
zr run test          # Runs member-specific cargo test
```

**Benefits:**

- **DRY principle**: Define common tasks once in workspace root
- **Consistency**: All members use the same lint/test/format commands by default
- **Flexibility**: Members can override any shared task when needed
- **Discoverability**: `(inherited)` marker shows which tasks come from workspace

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

## Mixins (v1.67.0)

Mixins enable task reusability through composition, reducing duplication beyond workspace inheritance. A mixin is a partial task definition that can be applied to multiple tasks, with fields merged according to clear semantics.

### Why Mixins?

**Before mixins** (repetitive configuration):
```toml
[tasks.deploy-frontend]
cmd = "kubectl apply -f frontend.yaml"
env = { KUBECONFIG = "/home/user/.kube/prod", REGION = "us-west-2" }
deps = ["docker-login", "validate-config"]
tags = ["deploy", "production"]
retry_max = 3
retry_backoff_multiplier = 2.0

[tasks.deploy-backend]
cmd = "kubectl apply -f backend.yaml"
env = { KUBECONFIG = "/home/user/.kube/prod", REGION = "us-west-2" }
deps = ["docker-login", "validate-config"]
tags = ["deploy", "production"]
retry_max = 3
retry_backoff_multiplier = 2.0

[tasks.deploy-database]
cmd = "kubectl apply -f database.yaml"
env = { KUBECONFIG = "/home/user/.kube/prod", REGION = "us-west-2" }
deps = ["docker-login", "validate-config"]
tags = ["deploy", "production"]
retry_max = 3
retry_backoff_multiplier = 2.0
```

**After mixins** (DRY and maintainable):
```toml
[mixins.k8s-deploy]
env = { KUBECONFIG = "/home/user/.kube/prod", REGION = "us-west-2" }
deps = ["docker-login", "validate-config"]
tags = ["deploy", "production"]
retry_max = 3
retry_backoff_multiplier = 2.0

[tasks.deploy-frontend]
cmd = "kubectl apply -f frontend.yaml"
mixins = ["k8s-deploy"]

[tasks.deploy-backend]
cmd = "kubectl apply -f backend.yaml"
mixins = ["k8s-deploy"]

[tasks.deploy-database]
cmd = "kubectl apply -f database.yaml"
mixins = ["k8s-deploy"]
```

### Basic Mixin Definition

Mixins are defined using `[mixins.NAME]` sections with partial task fields:

```toml
[mixins.common-env]
env = { NODE_ENV = "production", LOG_LEVEL = "info" }

[mixins.docker-auth]
deps = ["docker-login"]
tags = ["docker"]
```

### Applying Mixins to Tasks

Tasks reference mixins via the `mixins` field (array of mixin names):

```toml
[tasks.build-image]
cmd = "docker build -t myapp ."
mixins = ["common-env", "docker-auth"]
```

### Field Merging Semantics

When a task applies mixins, fields are merged according to these rules:

| Field Type | Merge Strategy | Example |
|------------|----------------|---------|
| **env** | Merged (task overrides) | Mixin: `{A=1, B=2}` + Task: `{B=3, C=4}` → `{A=1, B=3, C=4}` |
| **deps** | Concatenated (mixin first) | Mixin: `[a, b]` + Task: `[c]` → `[a, b, c]` |
| **deps_serial** | Concatenated (mixin first) | Same as deps |
| **deps_optional** | Concatenated (mixin first) | Same as deps |
| **deps_if** | Concatenated (mixin first) | Same as deps |
| **tags** | Union (deduplicated) | Mixin: `[docker, ci]` + Task: `[ci, test]` → `[docker, ci, test]` |
| **hooks** | Concatenated (mixin first) | Mixin hooks run before task hooks |
| **cmd** | Override (task wins) | Task `cmd` always used if set |
| **cwd** | Override (task wins) | Task `cwd` used if set, else mixin's |
| **description** | Override (task wins) | Same override logic |
| **timeout_ms** | Override (task wins) | Task value preferred if set |
| **retry_*** | Override (task wins) | All retry fields follow override logic |

### Multiple Mixins Composition

Tasks can apply multiple mixins, which are processed **left-to-right**:

```toml
[mixins.base]
env = { LOG_LEVEL = "info" }
tags = ["base"]

[mixins.docker]
deps = ["docker-login"]
tags = ["docker"]

[mixins.prod]
env = { NODE_ENV = "production", LOG_LEVEL = "error" }
tags = ["production"]

[tasks.deploy]
cmd = "deploy.sh"
mixins = ["base", "docker", "prod"]  # Applied in order
env = { DEPLOY_REGION = "us-west" }
tags = ["critical"]
```

**Result**:
- `env`: `{LOG_LEVEL="error", NODE_ENV="production", DEPLOY_REGION="us-west"}` (prod overrides base, task adds DEPLOY_REGION)
- `deps`: `["docker-login"]` (from docker mixin)
- `tags`: `["base", "docker", "production", "critical"]` (union of all)

### Nested Mixins

Mixins can reference other mixins, enabling composition hierarchies:

```toml
[mixins.retry-policy]
retry_max = 3
retry_backoff_multiplier = 2.0
retry_jitter = true

[mixins.docker-auth]
deps = ["docker-login"]
tags = ["docker"]

[mixins.k8s-deploy]
mixins = ["retry-policy", "docker-auth"]  # Inherits from other mixins
env = { KUBECONFIG = "/home/user/.kube/prod" }
tags = ["k8s"]

[tasks.deploy-app]
cmd = "kubectl apply -f app.yaml"
mixins = ["k8s-deploy"]  # Transitively gets retry-policy + docker-auth
```

**Nested Resolution Order**:
1. `retry-policy` applied first
2. `docker-auth` applied second
3. `k8s-deploy`'s own fields applied last
4. Task fields override all

**Cycle Detection**: Circular mixin references are detected and return `error.CircularMixin`:
```toml
[mixins.a]
mixins = ["b"]

[mixins.b]
mixins = ["a"]  # ERROR: Circular mixin reference detected
```

### Mixin Fields Reference

Mixins support these partial task fields:

| Field | Type | Description |
|-------|------|-------------|
| `env` | table | Environment variables (merged) |
| `deps` | array | Parallel dependencies (concatenated) |
| `deps_serial` | array | Sequential dependencies (concatenated) |
| `deps_optional` | array | Optional dependencies (concatenated) |
| `deps_if` | array | Conditional dependencies (concatenated) |
| `tags` | array | Task tags (union) |
| `cmd` | string | Default command (overridden by task) |
| `cwd` | string | Working directory (overridden by task) |
| `description` | string | Description (overridden by task) |
| `timeout_ms` | integer | Timeout (overridden by task) |
| `retry_max` | integer | Max retries (overridden by task) |
| `retry_delay_ms` | integer | Retry delay (overridden by task) |
| `retry_backoff_multiplier` | float | Backoff multiplier (overridden by task) |
| `retry_jitter` | boolean | Retry jitter (overridden by task) |
| `max_backoff_ms` | integer | Max backoff ceiling (overridden by task) |
| `hooks` | array | Execution hooks (concatenated) |
| `template` | string | Template reference (overridden by task) |
| `mixins` | array | Nested mixin references |

### Real-World Use Cases

**1. CI Pipeline Configurations**
```toml
[mixins.ci-base]
env = { CI = "true" }
tags = ["ci"]
timeout_ms = 300000  # 5 minutes

[mixins.test-coverage]
env = { COVERAGE = "true" }
deps = ["build"]

[tasks.unit-tests]
cmd = "npm test"
mixins = ["ci-base", "test-coverage"]

[tasks.integration-tests]
cmd = "npm run test:integration"
mixins = ["ci-base", "test-coverage"]
```

**2. Multi-Environment Deployments**
```toml
[mixins.deploy-base]
deps = ["build", "test"]
retry_max = 3
retry_backoff_multiplier = 2.0

[mixins.staging-env]
env = { ENVIRONMENT = "staging", API_URL = "https://api.staging.example.com" }
tags = ["staging"]

[mixins.production-env]
env = { ENVIRONMENT = "production", API_URL = "https://api.example.com" }
tags = ["production"]

[tasks.deploy-staging]
cmd = "./deploy.sh"
mixins = ["deploy-base", "staging-env"]

[tasks.deploy-production]
cmd = "./deploy.sh"
mixins = ["deploy-base", "production-env"]
```

**3. Language-Specific Tooling**
```toml
[mixins.node-project]
env = { NODE_ENV = "production" }
toolchain = ["node@20"]
tags = ["node"]

[mixins.python-project]
env = { PYTHONUNBUFFERED = "1" }
toolchain = ["python@3.12"]
tags = ["python"]

[tasks.frontend-build]
cmd = "npm run build"
mixins = ["node-project"]

[tasks.backend-test]
cmd = "pytest"
mixins = ["python-project"]
```

**4. Resource Constraints**
```toml
[mixins.heavy-cpu]
max_cpu = 8
max_memory = 8589934592  # 8GB
tags = ["high-resource"]

[mixins.light-cpu]
max_cpu = 2
max_memory = 2147483648  # 2GB
tags = ["low-resource"]

[tasks.compile-rust]
cmd = "cargo build --release"
mixins = ["heavy-cpu"]

[tasks.format-code]
cmd = "prettier --write ."
mixins = ["light-cpu"]
```

### Benefits

1. **DRY Principle**: Define common configurations once, reuse everywhere
2. **Consistency**: Changes to a mixin automatically apply to all tasks using it
3. **Maintainability**: Update retry policies, env vars, or tags in one place
4. **Composability**: Combine multiple mixins for flexible configurations
5. **Type Safety**: Cycle detection prevents infinite loops
6. **Clear Semantics**: Explicit merge rules (override, concatenate, union)

### Comparison with Other Features

| Feature | Use Case | Example |
|---------|----------|---------|
| **Mixins** | Reusable partial task configs across tasks | Common env vars, retry policies, tags |
| **Templates** | Parameterized task blueprints with placeholders | Deploy with `{{service_name}}`, `{{region}}` |
| **Workspace Shared Tasks** | Monorepo task inheritance from root to members | Root defines `build`, all members inherit it |
| **Profiles** | Environment-specific overrides (dev/prod) | Override `cmd` or `env` per profile |

**When to use mixins**: When you have common configuration shared by multiple tasks that doesn't fit into a single template or workspace pattern.

### Error Handling

**Undefined Mixin**:
```bash
$ zr run deploy
error: Mixin 'nonexistent' referenced by task 'deploy' not found
```

**Circular Reference**:
```bash
$ zr run deploy
error: Circular mixin reference detected involving 'mixin-a'
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
