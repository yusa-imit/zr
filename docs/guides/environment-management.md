# Environment Variable Management in zr

## Overview

zr provides powerful environment variable management through `.env` files, enabling you to:

- Load environment variables from external files instead of hardcoding them in `zr.toml`
- Use variable interpolation with `${VAR}` and `$VAR` syntax
- Define environment hierarchies with multiple files and clear priority rules
- Debug runtime environment with `--show-env` flag
- Share common variables across tasks and workspaces

**Why use `env_file`?**

- **Security**: Keep secrets out of version control (`.env` in `.gitignore`)
- **Flexibility**: Switch environments (dev/staging/prod) without editing `zr.toml`
- **DRY**: Define shared variables once, reference them everywhere
- **Clarity**: Separate configuration from task definitions
- **Portability**: Standard `.env` format works with other tools

## Basic Usage

### Single .env File

Define environment variables in a file:

```bash
# .env
DATABASE_URL=postgres://localhost/mydb
API_KEY=sk_test_123456
LOG_LEVEL=debug
```

Reference it in your task:

```toml
[task.migrate]
cmd = "npx prisma migrate deploy"
env_file = ".env"
```

When `migrate` runs, `DATABASE_URL`, `API_KEY`, and `LOG_LEVEL` are loaded into the task's environment.

### Multiple Files (Priority Order)

Load from multiple `.env` files with clear override rules:

```toml
[task.deploy]
cmd = "docker compose up -d"
env_file = [
    ".env.defaults",  # Base values
    ".env.local",     # Local overrides
    ".env.secrets"    # Sensitive data (not committed)
]
```

**Priority**: Later files override earlier files. In this example:
1. `.env.defaults` loads first (lowest priority)
2. `.env.local` overrides `.env.defaults`
3. `.env.secrets` overrides both (highest priority)

### Task-Level env Field (Highest Priority)

Task-level `env` always takes precedence:

```toml
[task.test]
cmd = "pytest"
env_file = ".env"
env = { ENVIRONMENT = "test" }  # Always "test", even if .env has different value
```

**Final priority order** (highest to lowest):
1. Task `env` field (inline in `zr.toml`)
2. `env_file` values (later files override earlier)
3. System environment variables

## File Format

zr supports standard `.env` file syntax:

### Basic Syntax

```bash
# Comments start with #
KEY=value
ANOTHER_KEY=another value

# Quotes (single or double) are stripped
QUOTED="value with spaces"
SINGLE='single quoted'

# Blank lines are ignored

MULTILINE="first line
second line"  # Not recommended, use escaping instead
```

### Supported Features

- **Comments**: Lines starting with `#` are ignored
- **Blank lines**: Skipped during parsing
- **Quotes**: Single (`'`) or double (`"`) quotes are removed from values
- **Spaces**: Values can contain spaces (with or without quotes)
- **No exports**: Use `KEY=value`, not `export KEY=value`

### Unsupported Features

- **Multiline values**: Use escaped newlines (`\n`) instead of literal newlines
- **Inline comments**: `KEY=value # comment` treats `# comment` as part of the value
- **Command substitution**: `$(command)` is treated as literal text
- **Special escapes**: `\t`, `\n`, etc. are not interpreted (use literal values)

## Variable Interpolation

zr supports shell-style variable interpolation within `.env` files and task `env` values.

### Basic Interpolation

Reference other variables with `${VAR}` or `$VAR`:

```bash
# .env
BASE_URL=https://api.example.com
API_ENDPOINT=${BASE_URL}/v2
WEBHOOK_URL=$BASE_URL/webhooks
```

Result:
- `BASE_URL` = `https://api.example.com`
- `API_ENDPOINT` = `https://api.example.com/v2`
- `WEBHOOK_URL` = `https://api.example.com/webhooks`

### Syntax Variants

Both `${VAR}` and `$VAR` are supported:

```bash
PATH_A=${HOME}/bin      # Braces (recommended for clarity)
PATH_B=$HOME/bin        # No braces (shorter)
PATH_C=${HOME}_suffix   # Braces required for suffix
```

**When to use braces**:
- Required: `${VAR}_suffix` (variable name adjacent to other text)
- Optional: `${VAR}/path` or `$VAR/path` (both work)
- Recommended: Always use braces for consistency

### Recursive Expansion

Variables can reference other variables, which can reference others:

```bash
# .env
ENVIRONMENT=production
REGION=us-west-2
CLUSTER=${ENVIRONMENT}-${REGION}
ENDPOINT=https://${CLUSTER}.example.com
```

Result:
- `CLUSTER` = `production-us-west-2`
- `ENDPOINT` = `https://production-us-west-2.example.com`

**Expansion rules**:
- Variables are expanded in the order they're defined
- Forward references work: `A=${B}` where `B` is defined later
- Circular references are detected and cause errors (see Troubleshooting)

### Cross-File Interpolation

Variables can reference values from earlier files:

```bash
# .env.defaults
DATABASE_HOST=localhost
DATABASE_PORT=5432

# .env.local (loaded after .env.defaults)
DATABASE_URL=postgres://${DATABASE_HOST}:${DATABASE_PORT}/mydb
```

Result: `DATABASE_URL` = `postgres://localhost:5432/mydb`

**File order matters**: Variables are expanded after all files are loaded and merged.

### System Environment Variables

Reference existing system environment variables:

```bash
# .env
HOME_BIN=${HOME}/bin
USER_CONFIG=/Users/${USER}/.config
```

If `HOME=/Users/alice` and `USER=alice` in system env:
- `HOME_BIN` = `/Users/alice/bin`
- `USER_CONFIG` = `/Users/alice/.config`

### Escaping Dollar Signs

Use `$$` to include a literal `$` in the value:

```bash
# .env
PRICE=$$99.99
REGEX=^[a-z]$$
```

Result:
- `PRICE` = `$99.99`
- `REGEX` = `^[a-z]$`

### Default Values (Not Supported)

zr does **not** support bash-style default values like `${VAR:-default}`. Use explicit fallback files instead:

```toml
# Instead of ${VAR:-default}
env_file = [".env.defaults", ".env"]  # .env overrides defaults
```

## .env File Locations

### Relative Paths

Paths in `env_file` are resolved relative to the **task's workspace**, not zr's working directory:

```toml
# zr.toml in /project
[task.build]
cmd = "make"
env_file = ".env"  # Resolves to /project/.env

[workspace.backend]
dir = "backend"

[workspace.backend.task.test]
cmd = "pytest"
env_file = ".env"  # Resolves to /project/backend/.env
```

### Absolute Paths

Use absolute paths for shared files outside the workspace:

```toml
[task.deploy]
cmd = "ansible-playbook deploy.yml"
env_file = [
    "/etc/app/secrets.env",  # System-wide secrets
    ".env.local"             # Workspace-specific overrides
]
```

### Workspace Inheritance

Tasks in workspaces can reference parent directory files:

```toml
# Root zr.toml
[workspace.services]
dir = "services"

[workspace.services.task.start]
cmd = "docker compose up"
env_file = [
    "../.env.shared",  # /project/.env.shared
    ".env"             # /project/services/.env
]
```

## Priority & Merging

Environment variables are merged in this order (later overrides earlier):

1. **System environment** (from parent process)
2. **env_file** values (in array order)
3. **Task env field** (highest priority)

### Example: Three-Layer Override

```bash
# System environment
DATABASE_URL=postgres://prod-db/app

# .env.defaults
DATABASE_URL=postgres://localhost/app
LOG_LEVEL=info

# .env.local
LOG_LEVEL=debug
API_KEY=local_key
```

```toml
[task.test]
cmd = "npm test"
env_file = [".env.defaults", ".env.local"]
env = { DATABASE_URL = "postgres://test-db/app" }
```

**Final environment**:
- `DATABASE_URL` = `postgres://test-db/app` (from task `env`, highest priority)
- `LOG_LEVEL` = `debug` (from `.env.local`, overrides `.env.defaults`)
- `API_KEY` = `local_key` (from `.env.local`)

### Array Order Matters

```toml
# Order 1: defaults then overrides
env_file = [".env.defaults", ".env.prod"]  # .env.prod wins

# Order 2: overrides then defaults (WRONG)
env_file = [".env.prod", ".env.defaults"]  # .env.defaults wins (unexpected!)
```

**Best practice**: List files from most general to most specific (defaults → environment → secrets).

## CLI Integration

### --show-env Flag

Debug environment variables with `--show-env`:

```bash
# Show environment for a specific task
zr list build --show-env

# Output:
# build
#   Command: npm run build
#   Environment:
#     NODE_ENV=production (from .env.prod)
#     API_URL=https://api.example.com (from .env.prod)
#     BUILD_ID=abc123 (from task env)

# Show environment for all tasks
zr list --show-env
```

**Use cases**:
- Verify which file provided each variable
- Debug interpolation issues
- Check priority order before running tasks
- Audit secrets before committing

### --show-env with run Command

Preview environment before execution:

```bash
# Dry-run: show environment without executing
zr run deploy --show-env --dry-run

# Execute and log environment to stderr
zr run deploy --show-env 2> env.log
```

## Real-World Examples

### Multi-Environment Deployment

```bash
# .env.defaults
APP_NAME=myapp
REGION=us-west-2
REPLICAS=1

# .env.staging
ENVIRONMENT=staging
DATABASE_URL=postgres://staging-db.internal/app
REPLICAS=2

# .env.production
ENVIRONMENT=production
DATABASE_URL=postgres://prod-db.internal/app
REPLICAS=5
```

```toml
[task.deploy-staging]
cmd = "kubectl apply -f deployment.yml"
env_file = [".env.defaults", ".env.staging"]

[task.deploy-production]
cmd = "kubectl apply -f deployment.yml"
env_file = [".env.defaults", ".env.production"]
env = { REPLICAS = "10" }  # Override for prod
```

### Secrets Management

```bash
# .env.public (committed to git)
API_ENDPOINT=https://api.example.com
LOG_LEVEL=info
TIMEOUT=30

# .env.secrets (in .gitignore)
API_KEY=sk_live_abc123
DATABASE_PASSWORD=super_secret
STRIPE_SECRET=rk_live_xyz789
```

```toml
[task.api-server]
cmd = "npm start"
env_file = [".env.public", ".env.secrets"]
```

**.gitignore**:
```
.env.secrets
.env.local
.env*.local
```

### Docker Compose Integration

```bash
# .env.docker
COMPOSE_PROJECT_NAME=myapp
POSTGRES_VERSION=15-alpine
REDIS_VERSION=7-alpine

# .env.docker.local (developer overrides)
POSTGRES_VERSION=14-alpine  # Use older version locally
DEBUG=1
```

```toml
[task.docker-up]
cmd = "docker compose up -d"
env_file = [".env.docker", ".env.docker.local"]

[task.docker-logs]
cmd = "docker compose logs -f ${SERVICE}"
env_file = ".env.docker"
params = [{ name = "SERVICE", required = true }]
```

### Monorepo Shared Variables

```bash
# /monorepo/.env.shared
GITHUB_ORG=mycompany
NPM_REGISTRY=https://npm.pkg.github.com
NODE_VERSION=20.11.0

# /monorepo/packages/frontend/.env
PUBLIC_API_URL=https://api.${GITHUB_ORG}.com
VITE_APP_NAME=${GITHUB_ORG}-frontend

# /monorepo/packages/backend/.env
DATABASE_URL=postgres://localhost/db
API_PORT=3000
CORS_ORIGIN=${PUBLIC_API_URL}  # Cross-package reference (won't work)
```

```toml
# /monorepo/zr.toml
[workspace.frontend]
dir = "packages/frontend"

[workspace.frontend.task.dev]
cmd = "vite"
env_file = ["../../.env.shared", ".env"]

[workspace.backend]
dir = "packages/backend"

[workspace.backend.task.dev]
cmd = "node server.js"
env_file = ["../../.env.shared", ".env"]
```

**Note**: Variables from `frontend/.env` are **not** available in `backend/.env`. Each task loads its own `env_file` independently.

### Dynamic Configuration with Interpolation

```bash
# .env.base
ENV=production
REGION=us-west-2
APP_NAME=myapp

# .env.computed (uses interpolation)
CLUSTER_NAME=${APP_NAME}-${ENV}-${REGION}
ECR_REPO=123456789.dkr.ecr.${REGION}.amazonaws.com
IMAGE_URI=${ECR_REPO}/${APP_NAME}:${VERSION}
DEPLOYMENT_URL=https://${CLUSTER_NAME}.example.com
```

```toml
[task.build-image]
cmd = "docker build -t ${IMAGE_URI} ."
env_file = [".env.base", ".env.computed"]
env = { VERSION = "v1.2.3" }
```

Result:
- `CLUSTER_NAME` = `myapp-production-us-west-2`
- `IMAGE_URI` = `123456789.dkr.ecr.us-west-2.amazonaws.com/myapp:v1.2.3`
- `DEPLOYMENT_URL` = `https://myapp-production-us-west-2.example.com`

## Best Practices

### 1. Never Commit Secrets

Keep sensitive data out of version control:

```gitignore
# .gitignore
.env.secrets
.env.local
.env*.local
*.key
*.pem
```

Use naming convention: `*.local` = not committed, `*.defaults` = safe to commit.

### 2. Use Hierarchical File Structure

Organize files by priority:

```
.env.defaults      # Committed, base values
.env.development   # Committed, dev environment
.env.staging       # Committed, staging environment
.env.production    # Committed, prod environment (no secrets)
.env.secrets       # NOT committed, sensitive keys
.env.local         # NOT committed, developer overrides
```

### 3. Document Required Variables

Create `.env.example` as a template:

```bash
# .env.example
# Copy to .env.secrets and fill in real values

API_KEY=sk_test_your_key_here
DATABASE_PASSWORD=your_password_here
STRIPE_SECRET=rk_test_your_secret_here
```

Developers copy and customize:
```bash
cp .env.example .env.secrets
# Edit .env.secrets with real credentials
```

### 4. Validate Environment Variables

Use a validation task:

```toml
[task.validate-env]
cmd = """
#!/bin/bash
set -e
required=(API_KEY DATABASE_URL STRIPE_SECRET)
for var in "${required[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: $var is not set"
    exit 1
  fi
done
echo "All required variables are set"
"""
env_file = [".env.public", ".env.secrets"]

[task.deploy]
cmd = "kubectl apply -f deployment.yml"
deps = ["validate-env"]  # Fail fast if env is invalid
env_file = [".env.public", ".env.secrets"]
```

### 5. Use Descriptive Names

Follow naming conventions:

```bash
# Good (clear purpose)
DATABASE_URL=postgres://localhost/mydb
API_BASE_URL=https://api.example.com
SMTP_HOST=smtp.gmail.com

# Bad (ambiguous)
DB=postgres://localhost/mydb
URL=https://api.example.com
HOST=smtp.gmail.com
```

### 6. Prefer Braces for Interpolation

Always use `${VAR}` over `$VAR` for clarity:

```bash
# Good (clear boundaries)
IMAGE_TAG=${VERSION}-${BUILD_ID}
PATH=${HOME}/bin:${PATH}

# Bad (ambiguous)
IMAGE_TAG=$VERSION-$BUILD_ID  # Is it VERSION-BUILD_ID or VERSION_BUILD_ID?
```

## Troubleshooting

### Missing .env File

**Error**:
```
Error: Failed to load env file '.env.secrets': FileNotFound
```

**Cause**: File doesn't exist at the resolved path.

**Solutions**:
1. Create the file: `touch .env.secrets`
2. Check working directory: `pwd` vs task `dir` field
3. Use absolute path: `/etc/app/secrets.env`
4. Check `.gitignore`: Did you forget to create local file?

**Debugging**:
```bash
# Check resolved path
zr list task --show-env  # Shows file locations

# Test with explicit path
zr run task --env-file=/absolute/path/.env
```

### Circular Reference

**Error**:
```
Error: Circular reference detected in environment variable expansion: A -> B -> A
```

**Cause**: Variables reference each other in a loop.

**Example**:
```bash
# .env (BAD)
A=${B}
B=${A}
```

**Solution**: Break the cycle by using a base value:
```bash
# .env (GOOD)
BASE=/usr/local
A=${BASE}/bin
B=${BASE}/lib
```

### Undefined Variable

**Behavior**: `${VAR}` expands to empty string if `VAR` is not defined.

**Example**:
```bash
# .env
API_URL=https://${SUBDOMAIN}.example.com
```

If `SUBDOMAIN` is not defined:
- `API_URL` = `https://.example.com` (broken URL)

**Solutions**:
1. Define the variable:
   ```bash
   SUBDOMAIN=api
   API_URL=https://${SUBDOMAIN}.example.com
   ```

2. Use defaults file:
   ```bash
   # .env.defaults
   SUBDOMAIN=api

   # .env
   API_URL=https://${SUBDOMAIN}.example.com
   ```

3. Check with `--show-env`:
   ```bash
   zr list task --show-env | grep SUBDOMAIN
   ```

### Escaping Issues

**Problem**: Dollar signs in values break interpolation.

**Example**:
```bash
# .env (BAD)
PRICE=$99.99  # Tries to expand $99
REGEX=^[a-z]$  # Tries to expand $
```

**Solution**: Use `$$` to escape:
```bash
# .env (GOOD)
PRICE=$$99.99
REGEX=^[a-z]$$
```

### Quotes Not Stripped

**Problem**: Quotes appear in the final value.

**Cause**: Quotes inside interpolated values are not stripped during expansion.

**Example**:
```bash
# .env
QUOTED="my value"
DERIVED=${QUOTED}_suffix
```

Result: `DERIVED` = `"my value"_suffix` (quotes included)

**Solution**: Don't use quotes for intermediate values:
```bash
# .env
BASE=my value  # No quotes
DERIVED=${BASE}_suffix  # Result: my value_suffix
```

### Variable Not Overriding

**Problem**: Expected file to override variable, but it didn't.

**Cause**: File order is wrong.

**Example**:
```toml
# Wrong order
env_file = [".env.local", ".env.defaults"]
```

`.env.defaults` loads last, overriding `.env.local` (opposite of intent).

**Solution**: Reverse the order:
```toml
# Correct order
env_file = [".env.defaults", ".env.local"]
```

**Debugging**:
```bash
zr list task --show-env  # Shows which file provided each variable
```

## Comparison with Other Tools

### vs dotenv Libraries (Node.js, Python, Ruby)

| Feature | zr env_file | dotenv Libraries |
|---------|-------------|------------------|
| File format | Standard `.env` | Standard `.env` |
| Priority | env_file → system → task | `.env` → system |
| Multiple files | ✅ Array with order | ❌ Single file |
| Interpolation | ✅ `${VAR}`, `$VAR` | ❌ (most libs) |
| Cross-file refs | ✅ Supported | ❌ |
| CLI debugging | ✅ `--show-env` | ❌ |
| Scope | Per-task | Process-wide |

**When to use dotenv**: Application runtime (load once at startup)
**When to use zr**: Build/deploy workflows (different env per task)

### vs docker-compose .env

| Feature | zr env_file | docker-compose |
|---------|-------------|----------------|
| File name | Any name | `.env` only |
| Multiple files | ✅ Array | ❌ Single `.env` |
| Interpolation | ✅ Recursive | ✅ Basic `$VAR` |
| Priority | Configurable | `.env` → system |
| Override | Task `env` field | `environment:` in YAML |
| CLI preview | `--show-env` | ❌ |

**When to use docker-compose**: Docker container orchestration
**When to use zr**: Multi-step builds across tools (docker, npm, kubectl, etc.)

### vs make Variables

| Feature | zr env_file | make |
|---------|-------------|------|
| Syntax | `.env` files | `VAR := value` in Makefile |
| External files | ✅ `env_file` | `include .env` |
| Interpolation | ✅ `${VAR}` | ✅ `$(VAR)` |
| Scope | Per-task | Global or target |
| Override | CLI + env_file | CLI only |
| Cross-platform | ✅ | ⚠️ (GNU vs BSD) |

**When to use make**: C/C++ builds, Makefile ecosystems
**When to use zr**: Modern multi-language workflows (Node, Python, Rust, etc.)

### vs just/Task

| Feature | zr env_file | just | Task (go-task) |
|---------|-------------|------|----------------|
| .env support | ✅ Array | ✅ Single | ✅ `.env` auto-load |
| Interpolation | ✅ Recursive | ✅ Basic | ✅ Template `{{.VAR}}` |
| Priority control | ✅ Explicit | ❌ Fixed | ⚠️ Limited |
| Multiple files | ✅ | ❌ | ⚠️ Via includes |
| CLI preview | `--show-env` | ❌ | ❌ |

**When to use just**: Simple command aliases (make alternative)
**When to use Task**: Go-based workflows, Taskfile.yml preference
**When to use zr**: Complex DAGs, multi-workspace monorepos, advanced env management

## Migration Guide

### From Inline env Maps

**Before** (inline in `zr.toml`):
```toml
[task.deploy]
cmd = "kubectl apply -f deployment.yml"
env = {
    ENVIRONMENT = "production",
    DATABASE_URL = "postgres://prod-db/app",
    API_KEY = "sk_live_abc123",  # Secret in version control (BAD)
    REGION = "us-west-2"
}
```

**After** (using `env_file`):
```bash
# .env.production (committed)
ENVIRONMENT=production
REGION=us-west-2

# .env.secrets (NOT committed)
DATABASE_URL=postgres://prod-db/app
API_KEY=sk_live_abc123
```

```toml
[task.deploy]
cmd = "kubectl apply -f deployment.yml"
env_file = [".env.production", ".env.secrets"]
```

**Benefits**:
- Secrets no longer in git history
- Environment-specific values easily switchable
- Shared variables extracted to `.env.defaults`

### From docker-compose .env

**Before** (`docker-compose.yml`):
```yaml
services:
  app:
    image: myapp:latest
    env_file: .env
```

**After** (`zr.toml`):
```toml
[task.docker-up]
cmd = "docker compose up -d"
env_file = ".env"

[task.docker-logs]
cmd = "docker compose logs -f"
env_file = ".env"
```

**No changes needed**: `.env` file works as-is.

### From make include

**Before** (`Makefile`):
```makefile
include .env.production

deploy:
	kubectl apply -f deployment.yml
```

**After** (`zr.toml`):
```toml
[task.deploy]
cmd = "kubectl apply -f deployment.yml"
env_file = ".env.production"
```

**Migration steps**:
1. Convert `VAR := value` to `VAR=value` in `.env`
2. Remove `export` statements
3. Replace `$(VAR)` with `${VAR}` in `.env` (if using interpolation)

### From Shell Scripts

**Before** (`deploy.sh`):
```bash
#!/bin/bash
source .env.production
source .env.secrets

kubectl apply -f deployment.yml
```

**After** (`zr.toml`):
```toml
[task.deploy]
cmd = "kubectl apply -f deployment.yml"
env_file = [".env.production", ".env.secrets"]
```

**Benefits**:
- No need to maintain shell script
- Dependency graph (if deploy depends on build)
- Cross-platform (works on Windows)

---

## Summary

zr's `env_file` feature provides enterprise-grade environment variable management:

- **Flexible**: Single file, multiple files, arrays, hierarchies
- **Secure**: Keep secrets out of git, use `.env.local` pattern
- **Powerful**: Variable interpolation, cross-file references, recursive expansion
- **Debuggable**: `--show-env` shows sources and final values
- **Compatible**: Standard `.env` format works with existing tools

**Quick Reference**:
```toml
# Single file
env_file = ".env"

# Multiple files (priority: right overrides left)
env_file = [".env.defaults", ".env.local"]

# Task env always wins
env_file = ".env"
env = { KEY = "override" }
```

**Interpolation**:
```bash
BASE=/usr/local
BIN=${BASE}/bin     # /usr/local/bin
LIB=$BASE/lib       # /usr/local/lib
DOLLAR=$$99.99      # $99.99
```

**Debugging**:
```bash
zr list task --show-env     # Show environment sources
zr run task --show-env      # Preview before execution
```

For advanced use cases, see [Parameterized Tasks](parameterized-tasks.md) and [Incremental Builds](incremental-builds.md).
