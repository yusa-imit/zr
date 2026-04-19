# Configuration Field Reference

Quick reference for all `zr.toml` configuration fields. For detailed examples and explanations, see [Configuration Guide](configuration.md).

## Table of Contents

- [Tasks](#tasks)
- [Workflows](#workflows)
- [Profiles](#profiles)
- [Workspace](#workspace)
- [Cache](#cache)
- [Resource Limits](#resource-limits)
- [Concurrency Groups](#concurrency-groups)
- [Toolchains](#toolchains)
- [Plugins](#plugins)
- [Aliases](#aliases)
- [Mixins](#mixins)
- [Templates](#templates)

---

## Tasks

Defined in `[tasks.<name>]` sections.

### Core Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `cmd` | string | ✅ | — | Shell command to execute |
| `description` | string | ❌ | null | Human-readable description |

### Dependencies

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `deps` | array of strings | `[]` | Parallel dependencies (run before this task) |
| `deps_serial` | array of strings | `[]` | Sequential dependencies (run one at a time) |
| `deps_if` | array of objects | `[]` | Conditional dependencies with `task` and `condition` fields |
| `deps_optional` | array of strings | `[]` | Optional dependencies (ignored if not found) |

Example:
```toml
[tasks.deploy]
deps = ["build", "test"]  # parallel
deps_serial = ["backup-db", "migrate-schema"]  # sequential
deps_if = [{ task = "lint", condition = "env.CI == 'true'" }]
deps_optional = ["format"]  # skip if doesn't exist
```

### Execution Control

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `dir` | string | null | Working directory (alias: `cwd`) |
| `env` | table | `{}` | Environment variable overrides |
| `condition` | string | null | Expression to evaluate before running |
| `allow_failure` | boolean | `false` | Continue if task fails |
| `timeout_ms` | integer | null | Timeout in milliseconds |

### Retry Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `retry_max` | integer | `0` | Maximum retry attempts |
| `retry_delay_ms` | integer | `0` | Base delay between retries (ms) |
| `retry_backoff_multiplier` | float | null | Backoff multiplier (1.0=linear, 2.0=exponential) |
| `retry_jitter` | boolean | `false` | Add ±25% random jitter to retry delays |
| `max_backoff_ms` | integer | `60000` | Maximum retry delay ceiling (ms) |
| `retry_on_codes` | array of ints | `[]` | Only retry on specific exit codes |
| `retry_on_patterns` | array of strings | `[]` | Only retry when output matches patterns |

Example:
```toml
[tasks.fetch-data]
cmd = "curl https://api.example.com/data"
retry_max = 5
retry_delay_ms = 1000
retry_backoff_multiplier = 2.0  # 1s, 2s, 4s, 8s, 16s
retry_jitter = true
max_backoff_ms = 30000
retry_on_codes = [429, 503]  # rate limit, service unavailable
retry_on_patterns = ["timeout", "connection refused"]
```

### Resource Limits

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_concurrent` | integer | `0` | Max concurrent instances (0 = unlimited) |
| `max_cpu` | integer | null | Max CPU cores for this task |
| `max_memory` | integer | null | Max memory in bytes |
| `cpu_affinity` | array of ints | `[]` | Bind to specific CPU cores (e.g., `[0, 1, 2]`) |
| `numa_node` | integer | null | Bind to specific NUMA node |
| `concurrency_group` | string | null | Assign to named concurrency group |

Example:
```toml
[tasks.gpu-training]
cmd = "python train.py"
concurrency_group = "gpu"
max_memory = 8589934592  # 8 GB
cpu_affinity = [0, 1, 2, 3]
numa_node = 0
```

### Caching

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cache` | boolean | `false` | Enable content-based caching |
| `cache_inputs` | array of strings | `[]` | File patterns for cache key (glob patterns) |
| `cache_outputs` | array of strings | `[]` | Files to cache (glob patterns) |

Example:
```toml
[tasks.build]
cmd = "npm run build"
cache = true
cache_inputs = ["src/**/*.ts", "package.json"]
cache_outputs = ["dist/**/*"]
```

### Watch Mode

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `watch` | table | null | Watch mode configuration |
| `watch.paths` | array of strings | `[]` | File patterns to watch (glob) |
| `watch.debounce_ms` | integer | `100` | Debounce delay (ms) |
| `watch.ignore` | array of strings | `[]` | Patterns to ignore |

Example:
```toml
[tasks.dev]
cmd = "npm run dev"
watch = { paths = ["src/**/*.ts"], debounce_ms = 200, ignore = ["**/*.test.ts"] }
```

### Execution Hooks

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hooks` | array of objects | `[]` | Execution lifecycle hooks |

Hook points: `"before"`, `"after"`, `"success"`, `"failure"`

Example:
```toml
[tasks.deploy]
cmd = "./deploy.sh"
hooks = [
  { point = "before", cmd = "echo 'Starting deployment...'" },
  { point = "success", cmd = "./notify-success.sh" },
  { point = "failure", cmd = "./rollback.sh" }
]
```

### Circuit Breaker

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `circuit_breaker` | table | null | Circuit breaker configuration |
| `circuit_breaker.failure_threshold` | integer | `5` | Failures before opening circuit |
| `circuit_breaker.success_threshold` | integer | `2` | Successes to close circuit |
| `circuit_breaker.timeout_ms` | integer | `60000` | Wait before half-open (ms) |

Example:
```toml
[tasks.health-check]
cmd = "./check-service.sh"
circuit_breaker = { failure_threshold = 3, success_threshold = 2, timeout_ms = 30000 }
```

### Remote Execution

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `remote` | string | null | Remote execution target (SSH host or alias) |
| `remote_cwd` | string | null | Working directory on remote host |
| `remote_env` | table | `{}` | Environment variables for remote execution |

Example:
```toml
[tasks.deploy-production]
cmd = "./deploy.sh"
remote = "user@prod-server.example.com"
remote_cwd = "/var/www/app"
remote_env = { DEPLOY_ENV = "production" }
```

### Metadata

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tags` | array of strings | `[]` | Categorization tags for filtering |
| `toolchain` | array of strings | `[]` | Required toolchains (e.g., `["node@20"]`) |
| `mixins` | array of strings | `[]` | Mixins to apply to this task |

Example:
```toml
[tasks.test]
cmd = "npm test"
tags = ["ci", "test", "node"]
toolchain = ["node@20.11.1"]
mixins = ["common-env", "docker-auth"]
```

---

## Workflows

Defined in `[workflows.<name>]` sections.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | ❌ | Human-readable description |
| `stages` | array of objects | ✅ | Sequential stages with parallel tasks |

Stage object fields:
- `tasks`: array of strings (task names to run in parallel)
- `max_concurrent`: integer (optional, limit parallel tasks in this stage)

Example:
```toml
[workflows.ci]
description = "Continuous integration pipeline"
stages = [
  { tasks = ["lint", "fmt"] },                      # Stage 1: parallel
  { tasks = ["test-unit", "test-integration"] },    # Stage 2: parallel
  { tasks = ["build"] },                            # Stage 3: serial
  { tasks = ["deploy-staging"], max_concurrent = 1 } # Stage 4: single task
]
```

---

## Profiles

Defined in `[profiles.<name>]` sections.

| Field | Type | Description |
|-------|------|-------------|
| `env` | table | Environment variable overrides |

Example:
```toml
[profiles.development]
env = { NODE_ENV = "development", DEBUG = "true" }

[profiles.production]
env = { NODE_ENV = "production", OPTIMIZE = "true" }
```

Usage:
```bash
zr run build --profile production
```

---

## Workspace

### Root Configuration

Defined in `[workspace]` section of root `zr.toml`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `members` | array of strings | `[]` | Member directory paths (glob patterns) |
| `multi_repo` | boolean | `false` | Enable multi-repo workspace |
| `default_task` | string | null | Default task for `workspace run` |

Example:
```toml
[workspace]
members = ["packages/*", "apps/*"]
default_task = "build"
```

### Shared Tasks

Defined in `[workspace.shared_tasks.<name>]` sections.

Same fields as regular tasks. Members inherit these tasks automatically.

Example:
```toml
[workspace.shared_tasks.lint]
cmd = "eslint ."
tags = ["ci"]

[workspace.shared_tasks.test]
cmd = "npm test"
deps = ["lint"]
```

### Multi-Repo Configuration

Defined in `[[workspace.repositories]]` sections.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | ✅ | Repository name |
| `url` | string | ✅ | Git clone URL |
| `path` | string | ✅ | Local path for checkout |
| `ref` | string | ❌ | Git ref (branch/tag, default: `main`) |

Example:
```toml
[[workspace.repositories]]
name = "frontend"
url = "https://github.com/org/frontend.git"
path = "repos/frontend"
ref = "develop"

[[workspace.repositories]]
name = "backend"
url = "https://github.com/org/backend.git"
path = "repos/backend"
```

---

## Cache

Defined in `[cache]` section.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable local cache |
| `dir` | string | `.zr/cache` | Local cache directory |
| `remote` | table | null | Remote cache configuration |

### Remote Cache

| Field | Type | Description |
|-------|------|-------------|
| `remote.type` | string | Backend type: `"s3"`, `"gcs"`, `"azure"`, `"http"` |
| `remote.bucket` | string | Bucket/container name |
| `remote.prefix` | string | Key prefix for cache entries |
| `remote.endpoint` | string | Custom endpoint URL (optional) |
| `remote.region` | string | Region (S3/GCS) |

Example:
```toml
[cache]
enabled = true
dir = ".zr/cache"

[cache.remote]
type = "s3"
bucket = "my-build-cache"
prefix = "zr-cache/"
region = "us-east-1"
```

---

## Resource Limits

Defined in `[resource_limits]` section.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_workers` | integer | CPU count | Max parallel tasks globally |
| `max_memory` | integer | null | Max total memory (bytes) |
| `max_cpu` | integer | CPU count | Max total CPU cores |

Example:
```toml
[resource_limits]
max_workers = 8
max_memory = 17179869184  # 16 GB
max_cpu = 12
```

---

## Concurrency Groups

Defined in `[concurrency_groups.<name>]` sections.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `max_workers` | integer | ✅ | Max parallel tasks in this group |
| `description` | string | ❌ | Human-readable description |

Example:
```toml
[concurrency_groups.gpu]
max_workers = 2
description = "GPU-bound tasks"

[concurrency_groups.memory_intensive]
max_workers = 4
description = "High memory tasks"

[tasks.train-model]
cmd = "python train.py"
concurrency_group = "gpu"
```

---

## Toolchains

Defined in `[toolchains]` section.

| Field | Type | Description |
|-------|------|-------------|
| `<language>` | string | Version to install (e.g., `node = "20.11.1"`) |

Supported languages:
- `node` — Node.js
- `python` — Python
- `zig` — Zig
- `go` — Go
- `rust` — Rust
- `ruby` — Ruby
- `java` — Java
- `dotnet` — .NET Core

Example:
```toml
[toolchains]
node = "20.11.1"
python = "3.12.1"
zig = "0.15.2"
go = "1.22.0"
```

Usage:
```bash
zr setup  # Installs all toolchains
```

---

## Plugins

Defined in `[[plugins]]` sections.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | ✅ | Plugin name |
| `type` | string | ✅ | Plugin type: `"native"`, `"wasm"` |
| `path` | string | ✅ | Path to plugin binary or WASM file |
| `enabled` | boolean | ❌ | Enable/disable plugin (default: `true`) |

Example:
```toml
[[plugins]]
name = "custom-reporter"
type = "native"
path = "./plugins/reporter.so"
enabled = true

[[plugins]]
name = "linter"
type = "wasm"
path = "./plugins/linter.wasm"
```

---

## Aliases

Defined in `[aliases]` section.

| Field | Type | Description |
|-------|------|-------------|
| `<alias>` | string | Command to expand (e.g., `dev = "run server --profile dev"`) |

Example:
```toml
[aliases]
dev = "run server --profile dev"
ci = "workflow ci --jobs 4"
deploy = "workflow deploy --profile production"
```

Usage:
```bash
zr dev      # Expands to: zr run server --profile dev
zr ci       # Expands to: zr workflow ci --jobs 4
```

---

## Mixins

Defined in `[mixins.<name>]` sections.

Mixins are reusable partial task definitions. Same fields as tasks (except `cmd` is optional).

Example:
```toml
[mixins.docker-auth]
env = { DOCKER_USER = "${env.CI_DOCKER_USER}", DOCKER_PASS = "${env.CI_DOCKER_PASS}" }
hooks = [{ point = "before", cmd = "docker login -u $DOCKER_USER -p $DOCKER_PASS" }]

[mixins.k8s-deploy]
tags = ["deploy", "k8s"]
timeout_ms = 300000
retry_max = 3

[tasks.deploy-frontend]
cmd = "kubectl apply -f frontend.yaml"
mixins = ["docker-auth", "k8s-deploy"]

[tasks.deploy-backend]
cmd = "kubectl apply -f backend.yaml"
mixins = ["docker-auth", "k8s-deploy"]
```

**Field merging rules**:
- `env`: Child overrides parent (merge)
- `deps`: Concatenate (parent deps run first)
- `tags`: Union (combine all tags)
- Scalars (`cmd`, `timeout_ms`, etc.): Child overrides parent

---

## Templates

Defined in `[templates.<name>]` sections.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | ❌ | Template description |
| `tasks` | table | ✅ | Template task definitions |
| `params` | table | ❌ | Parameter definitions with defaults |

Example:
```toml
[templates.service]
description = "Microservice deployment template"

[templates.service.params]
name = ""
port = "8080"
replicas = "3"

[templates.service.tasks.deploy]
cmd = "kubectl apply -f ${params.name}.yaml"
env = { SERVICE_NAME = "${params.name}", PORT = "${params.port}" }

[templates.service.tasks.scale]
cmd = "kubectl scale --replicas=${params.replicas} deployment/${params.name}"
```

Usage:
```bash
zr add task --from-template service --param name=api --param port=3000
```

---

## Versioning

Defined in `[version]` section.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `current` | string | `"0.0.0"` | Current version (semver) |
| `prefix` | string | `"v"` | Tag prefix (e.g., `v1.0.0`) |
| `commit_message` | string | `"chore: bump version to {version}"` | Commit message template |

Example:
```toml
[version]
current = "1.2.3"
prefix = "v"
commit_message = "release: {version}"
```

Usage:
```bash
zr version --bump patch  # 1.2.3 → 1.2.4
```

---

## Conformance

Defined in `[conformance]` section.

| Field | Type | Description |
|-------|------|-------------|
| `rules` | array of objects | Conformance rules |

Rule object fields:
- `id`: string (unique rule identifier)
- `description`: string (human-readable description)
- `pattern`: string (glob pattern for files to check)
- `check`: string (validation expression)

Example:
```toml
[conformance]
rules = [
  { id = "no-console", pattern = "src/**/*.ts", check = "!contains('console.log')" },
  { id = "has-tests", pattern = "src/**/*.ts", check = "exists('${path}.test.ts')" }
]
```

Usage:
```bash
zr conformance
```

---

## Expressions

zr supports expressions in string fields using `${...}` syntax.

### Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `env.<name>` | Environment variable | `${env.HOME}` |
| `platform.os` | Operating system | `${platform.os}` (linux, macos, windows) |
| `platform.arch` | Architecture | `${platform.arch}` (x86_64, aarch64) |
| `platform.is_linux` | Boolean | `${platform.is_linux}` |
| `platform.is_macos` | Boolean | `${platform.is_macos}` |
| `platform.is_windows` | Boolean | `${platform.is_windows}` |
| `git.branch` | Current git branch | `${git.branch}` |
| `git.commit` | Current commit hash | `${git.commit}` |
| `git.tag` | Current git tag | `${git.tag}` |

### Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equals | `${env.NODE_ENV == "production"}` |
| `!=` | Not equals | `${platform.os != "windows"}` |
| `&&` | Logical AND | `${env.CI == "true" && platform.is_linux}` |
| `\|\|` | Logical OR | `${platform.is_macos \|\| platform.is_linux}` |
| `!` | Logical NOT | `${!platform.is_windows}` |

### Functions

| Function | Description | Example |
|----------|-------------|---------|
| `contains(str)` | Check if contains substring | `${contains("test")}` |
| `exists(path)` | Check if file exists | `${exists("package.json")}` |
| `matches(regex)` | Regex match | `${matches("^v[0-9]+")}` |

Example:
```toml
[tasks.deploy-prod]
cmd = "kubectl apply -f prod.yaml"
condition = "${platform.is_linux} && ${env.CI == 'true'} && ${git.branch == 'main'}"
```

---

## Example Configuration

Complete `zr.toml` example:

```toml
[workspace]
members = ["packages/*", "apps/*"]

[workspace.shared_tasks.lint]
cmd = "eslint ."
tags = ["ci"]

[cache]
enabled = true
[cache.remote]
type = "s3"
bucket = "build-cache"
region = "us-east-1"

[resource_limits]
max_workers = 8

[concurrency_groups.gpu]
max_workers = 2

[toolchains]
node = "20.11.1"
python = "3.12.1"

[tasks.build]
cmd = "npm run build"
deps = ["install"]
cache = true
cache_inputs = ["src/**/*.ts", "package.json"]
cache_outputs = ["dist/**/*"]

[tasks.test]
cmd = "npm test"
deps = ["build"]
retry_max = 3
retry_backoff_multiplier = 2.0

[tasks.deploy]
cmd = "./deploy.sh"
deps_serial = ["build", "test"]
condition = "${git.branch == 'main'}"
remote = "user@prod-server.com"

[workflows.ci]
stages = [
  { tasks = ["lint", "fmt"] },
  { tasks = ["test"] },
  { tasks = ["build"] }
]

[profiles.production]
env = { NODE_ENV = "production" }

[aliases]
dev = "run server --profile development"
```

---

## See Also

- [Configuration Guide](configuration.md) — Detailed explanations and examples
- [Command Reference](command-reference.md) — CLI commands
- [Getting Started](getting-started.md) — Quick start guide
- [Migration Guide](migration.md) — Migrate from other tools
