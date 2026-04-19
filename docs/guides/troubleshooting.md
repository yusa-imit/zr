# Troubleshooting & FAQ

Common issues, solutions, and frequently asked questions.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Configuration Errors](#configuration-errors)
- [Task Execution Problems](#task-execution-problems)
- [Performance Issues](#performance-issues)
- [Cache Problems](#cache-problems)
- [Workspace Issues](#workspace-issues)
- [Toolchain Problems](#toolchain-problems)
- [CI/CD Issues](#cicd-issues)
- [Frequently Asked Questions](#frequently-asked-questions)

---

## Installation Issues

### "zr: command not found" after installation

**Problem**: zr installed but not in PATH.

**Solution**:
```bash
# Check if zr binary exists
ls -la ~/.zr/bin/zr

# Add to PATH manually
export PATH="$HOME/.zr/bin:$PATH"

# Make permanent (bash)
echo 'export PATH="$HOME/.zr/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Make permanent (zsh)
echo 'export PATH="$HOME/.zr/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Make permanent (fish)
set -Ua fish_user_paths $HOME/.zr/bin
```

---

### "Permission denied" when running install script

**Problem**: Install script lacks execute permission or needs sudo.

**Solution**:
```bash
# macOS/Linux: Check permissions
ls -la ~/.zr/bin/zr

# Fix permissions
chmod +x ~/.zr/bin/zr

# Install to system directory (requires sudo)
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo sh
```

**Windows**: Run PowerShell as Administrator.

---

### "SSL certificate problem" during download

**Problem**: Corporate proxy or firewall blocking HTTPS.

**Solution**:
```bash
# Option 1: Use HTTP (less secure)
curl -fsSL --insecure https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh

# Option 2: Set proxy
export https_proxy=http://proxy.company.com:8080
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh

# Option 3: Download manually
wget https://github.com/yusa-imit/zr/releases/download/v1.71.0/zr-x86_64-linux
chmod +x zr-x86_64-linux
sudo mv zr-x86_64-linux /usr/local/bin/zr
```

---

### Build from source fails with Zig errors

**Problem**: Wrong Zig version or missing dependencies.

**Solution**:
```bash
# Check Zig version (must be 0.15.2)
zig version

# Install Zig 0.15.2
curl -fsSL https://ziglang.org/download/0.15.2/zig-linux-x86_64-0.15.2.tar.xz | tar -xJ
export PATH="$PWD/zig-linux-x86_64-0.15.2:$PATH"

# Clean and rebuild
rm -rf zig-cache zig-out
zig build -Doptimize=ReleaseSafe
```

---

## Configuration Errors

### "TOML parse error: unexpected token"

**Problem**: Invalid TOML syntax.

**Solution**:
```bash
# Use validate to find syntax errors
zr validate

# Common issues:
# 1. Missing quotes around strings
# Bad:  cmd = echo hello
# Good: cmd = "echo hello"

# 2. Unescaped backslashes (Windows paths)
# Bad:  dir = "C:\Users\name"
# Good: dir = "C:\\Users\\name"
# Or:   dir = 'C:\Users\name'  # Single quotes

# 3. Trailing commas in arrays
# Bad:  deps = ["build", "test",]
# Good: deps = ["build", "test"]

# 4. Missing closing brackets
# Bad:  [tasks.build
# Good: [tasks.build]
```

**Tip**: Use an online TOML validator: https://www.toml-lint.com/

---

### "Dependency cycle detected"

**Problem**: Circular task dependencies.

**Error**:
```
✗ Dependency cycle detected: build → test → build
```

**Solution**:
```bash
# Use validate to see full cycle
zr validate

# Use graph to visualize
zr graph

# Fix: Remove circular dependency
# Bad:
[tasks.build]
deps = ["test"]

[tasks.test]
deps = ["build"]

# Good:
[tasks.build]
deps = []

[tasks.test]
deps = ["build"]
```

---

### "Task not found" error

**Problem**: Referenced task doesn't exist.

**Error**:
```
✗ Task 'biuld' not found

  Did you mean: build?
```

**Solution**:
```bash
# List all tasks
zr list

# Check spelling
zr run build  # Not: zr run biuld

# For workspace members, use full name
zr workspace run test  # Not: zr run test (in root)
```

---

### "Invalid expression" in condition

**Problem**: Syntax error in expression.

**Error**:
```
✗ Invalid expression: ${env.NODE_ENV = "production"}
```

**Solution**:
```toml
# Bad: Single equals (assignment)
condition = "${env.NODE_ENV = 'production'}"

# Good: Double equals (comparison)
condition = "${env.NODE_ENV == 'production'}"

# Bad: Missing quotes
condition = "${platform.os == linux}"

# Good: Quoted string
condition = "${platform.os == 'linux'}"
```

**See**: [Configuration reference on expressions](config-reference.md#expressions)

---

## Task Execution Problems

### Task fails silently with no output

**Problem**: Task output not shown.

**Solution**:
```bash
# Use verbose mode
zr run build --verbose

# Check history for stderr
zr history --failures

# View failure reports
zr failures list

# Live output
zr live build
```

---

### "Command not found" inside task

**Problem**: Command not in PATH or missing toolchain.

**Error**:
```
✗ Task 'build' failed with exit code 127
  sh: npm: command not found
```

**Solution**:
```bash
# Check if command exists
which npm

# Install toolchain
zr tools install node@20.11.1

# Or use zr setup
zr setup

# Check task environment
zr env --task build

# Use absolute path in task
[tasks.build]
cmd = "/usr/local/bin/npm run build"

# Or set PATH in env
[tasks.build]
cmd = "npm run build"
env = { PATH = "/usr/local/bin:${env.PATH}" }
```

---

### Task times out unexpectedly

**Problem**: Task exceeds timeout.

**Error**:
```
✗ Task 'long-task' timed out after 60000ms
```

**Solution**:
```toml
# Increase timeout
[tasks.long-task]
cmd = "./slow-script.sh"
timeout_ms = 600000  # 10 minutes

# Or disable timeout
[tasks.long-task]
cmd = "./slow-script.sh"
timeout_ms = 0  # No timeout
```

---

### Task fails with "Too many open files"

**Problem**: File descriptor limit exceeded.

**Solution**:
```bash
# Check current limit
ulimit -n

# Increase limit (temporary)
ulimit -n 4096

# Make permanent (macOS)
sudo launchctl limit maxfiles 65536 200000

# Make permanent (Linux)
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Reduce parallelism in zr
zr run build --jobs 4  # Instead of default (CPU count)
```

---

### Retry not working as expected

**Problem**: Task doesn't retry on failure.

**Solution**:
```toml
# Check retry configuration
[tasks.flaky-test]
cmd = "./test.sh"
retry_max = 3  # Must be > 0
retry_delay_ms = 1000

# Only retry specific exit codes
retry_on_codes = [1, 2]  # Won't retry exit code 3

# Only retry on output patterns
retry_on_patterns = ["ECONNREFUSED"]  # Won't retry other errors

# Debug: Use verbose mode
# zr run flaky-test --verbose
```

---

## Performance Issues

### Builds are slow despite parallelism

**Problem**: Tasks running serially instead of parallel.

**Solution**:
```bash
# Check dependency graph
zr graph

# Bad: Sequential dependencies
[tasks.ci]
deps_serial = ["lint", "test", "build"]  # 3x slower

# Good: Parallel dependencies
[tasks.ci]
deps = ["lint", "test"]  # Parallel
[tasks.build]
deps = ["ci"]

# Check parallel worker count
zr run build --verbose  # Shows parallelism

# Increase workers
zr run build --jobs 16
```

---

### High memory usage during builds

**Problem**: Too many parallel tasks.

**Solution**:
```bash
# Reduce parallelism
zr run build --jobs 4

# Set global limit
[resource_limits]
max_workers = 8
max_memory = 17179869184  # 16 GB

# Set per-task limit
[tasks.heavy-compile]
max_memory = 4294967296  # 4 GB
max_concurrent = 2  # Max 2 instances

# Use concurrency groups
[concurrency_groups.memory_intensive]
max_workers = 4

[tasks.webpack-build]
concurrency_group = "memory_intensive"
```

---

### Cache not speeding up builds

**Problem**: Cache misses or disabled.

**Solution**:
```bash
# Check cache status
zr cache status

# Enable caching
[tasks.build]
cache = true
cache_inputs = [
  "src/**/*",
  "package.json",
  "package-lock.json"  # Don't forget dependencies!
]

# Clear stale cache
zr cache clear

# Check cache hits in history
zr history --format json | jq '.[] | select(.cached == true)'
```

---

## Cache Problems

### "Cache read error: permission denied"

**Problem**: Cache directory permissions.

**Solution**:
```bash
# Check permissions
ls -la .zr/cache

# Fix permissions
chmod -R u+rwX .zr/cache

# Delete and recreate
rm -rf .zr/cache
mkdir -p .zr/cache
```

---

### Remote cache upload fails

**Problem**: Missing AWS credentials or network issues.

**Solution**:
```bash
# Check AWS credentials
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY

# Test S3 access
aws s3 ls s3://my-build-cache/

# Use verbose mode
zr run build --verbose

# Check cache config
[cache.remote]
type = "s3"
bucket = "my-build-cache"
region = "us-east-1"  # Must match bucket region

# Use HTTP cache instead (simpler)
[cache.remote]
type = "http"
endpoint = "https://cache.example.com"
```

---

### Cache grows too large

**Problem**: Old cache entries not cleaned up.

**Solution**:
```bash
# Check cache size
du -sh .zr/cache

# Clear old entries (manual)
zr cache clear

# Use TTL in remote cache (S3 lifecycle policy)
# AWS Console → S3 → Bucket → Management → Lifecycle rules
# Delete objects older than 30 days
```

---

## Workspace Issues

### "No workspace members found"

**Problem**: Glob pattern doesn't match any directories.

**Solution**:
```bash
# Check glob pattern
[workspace]
members = ["packages/*", "apps/*"]

# Test glob manually
ls -d packages/* apps/*

# Common issues:
# 1. Wrong path (relative to root zr.toml)
# Bad:  members = ["./packages/*"]  # Don't use ./
# Good: members = ["packages/*"]

# 2. Missing subdirectory zr.toml
# Each member must have its own zr.toml
ls packages/frontend/zr.toml

# Debug: List members
zr workspace list
```

---

### Workspace tasks not inheriting

**Problem**: Shared tasks not visible in members.

**Solution**:
```toml
# Root zr.toml
[workspace.shared_tasks.test]  # Not [tasks.test]
cmd = "npm test"

# Member can override
# packages/frontend/zr.toml
[tasks.test]
cmd = "vitest run"  # Overrides workspace shared task
```

---

### Affected detection not working

**Problem**: All tasks run, not just affected.

**Solution**:
```bash
# Check git status
git status
git diff origin/main --name-only

# Ensure correct base branch
zr affected test --base origin/main

# Debug: See affected members
zr affected test --dry-run

# Common issues:
# 1. Uncommitted changes
git add -A && git commit -m "WIP"

# 2. Wrong base branch
git branch -r  # List remote branches
```

---

## Toolchain Problems

### Toolchain install fails

**Problem**: Network error or unsupported version.

**Solution**:
```bash
# Check version availability
zr tools list node  # Shows installed versions

# Try different version
zr tools install node@20  # Latest 20.x

# Manual installation
# Node.js: https://nodejs.org/
# Python: https://python.org/
# Add to PATH manually

# Check toolchain registry
cat ~/.zr/toolchains/registry.json
```

---

### "Toolchain not found" during task execution

**Problem**: Toolchain not installed or wrong version.

**Solution**:
```bash
# Check required toolchains
zr validate

# Install all toolchains
zr setup

# Check task toolchain requirements
[tasks.build]
toolchain = ["node@20.11.1"]  # Exact version

# Use version range
toolchain = ["node@20"]  # Any 20.x
```

---

### Multiple Node.js versions conflict

**Problem**: System Node.js vs zr-managed Node.js.

**Solution**:
```bash
# Check which Node.js is active
which node
node --version

# Use zr-managed toolchain explicitly
[tasks.build]
cmd = "npm run build"
env = { PATH = "$HOME/.zr/toolchains/node/20.11.1/bin:${env.PATH}" }

# Or disable system Node.js
export PATH="$HOME/.zr/toolchains/node/20.11.1/bin:$PATH"
```

---

## CI/CD Issues

### CI runs fail with "zr: command not found"

**Problem**: zr not installed in CI environment.

**Solution**:
```yaml
# GitHub Actions
- name: Install zr
  run: |
    curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
    echo "$HOME/.zr/bin" >> $GITHUB_PATH

# GitLab CI
before_script:
  - curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
  - export PATH="$HOME/.zr/bin:$PATH"

# CircleCI
- run:
    name: Install zr
    command: |
      curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
      echo 'export PATH="$HOME/.zr/bin:$PATH"' >> $BASH_ENV
```

---

### Remote cache not working in CI

**Problem**: Missing credentials or wrong permissions.

**Solution**:
```yaml
# GitHub Actions: Set secrets
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

# GitLab CI: Use CI variables
variables:
  AWS_ACCESS_KEY_ID: $CI_AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY: $CI_AWS_SECRET_ACCESS_KEY

# Test cache access
- run: aws s3 ls s3://build-cache/
```

---

### Parallel CI jobs have cache conflicts

**Problem**: Multiple runners writing to same cache keys.

**Solution**:
```toml
# Use unique cache prefix per job
[cache.remote]
prefix = "zr-cache/${env.CI_JOB_ID}/"

# Or use job-specific workspace
[cache]
dir = ".zr/cache-${env.CI_JOB_ID}"
```

---

## Frequently Asked Questions

### How do I migrate from Make/Just/Task?

See [Migration Guide](migration.md) for detailed instructions.

```bash
# Quick migration
zr init --from-make   # Makefile → zr.toml
zr init --from-just   # justfile → zr.toml
zr init --from-task   # Taskfile.yml → zr.toml
zr init --from-npm    # package.json → zr.toml
```

---

### Can zr replace Docker Compose?

No, but they complement each other.

**Use Docker Compose for**:
- Multi-container orchestration
- Service networking
- Volume management

**Use zr for**:
- Building Docker images
- Running tests
- CI/CD pipelines
- Task dependencies

**Example**:
```toml
[tasks.docker-build]
cmd = "docker build -t myapp ."

[tasks.docker-up]
cmd = "docker compose up -d"
deps = ["docker-build"]

[tasks.test]
cmd = "docker compose exec app npm test"
deps = ["docker-up"]
```

---

### How do I run tasks on remote machines?

Use the `remote` field.

```toml
[tasks.deploy-prod]
cmd = "./deploy.sh"
remote = "user@prod-server.example.com"
remote_cwd = "/var/www/app"
remote_env = { DEPLOY_ENV = "production" }
```

**Requirements**:
- SSH access to remote host
- zr installed on remote (optional, runs via SSH)
- SSH key authentication (passwordless)

---

### Can I use zr with Docker?

Yes, three ways:

**1. Run zr inside Docker**:
```dockerfile
FROM zig:0.15.2 as builder
COPY . .
RUN zig build -Doptimize=ReleaseSmall

FROM alpine:latest
COPY --from=builder /app/zig-out/bin/zr /usr/local/bin/zr
CMD ["zr", "run", "server"]
```

**2. Run Docker from zr tasks**:
```toml
[tasks.docker-build]
cmd = "docker build -t myapp ."

[tasks.docker-run]
cmd = "docker run -p 3000:3000 myapp"
deps = ["docker-build"]
```

**3. Use zr as task runner, Docker for runtime**:
```toml
[tasks.dev]
cmd = "docker compose up"

[tasks.test]
cmd = "docker compose exec app npm test"
```

---

### How do I debug tasks?

Multiple approaches:

```bash
# 1. Verbose mode
zr run build --verbose

# 2. Dry-run (see execution plan)
zr run deploy --dry-run

# 3. Live logs
zr live build

# 4. History
zr history --failures

# 5. Failure reports
zr failures list

# 6. Environment inspection
zr env --task build

# 7. Interactive run (pause, retry, skip)
zr interactive-run build
```

---

### Can I use environment variables from .env files?

Yes, zr reads `.env` files automatically (via shell).

```bash
# .env
API_KEY=secret123
NODE_ENV=development

# Use in tasks
[tasks.start]
cmd = "node server.js"
env = { API_KEY = "${env.API_KEY}" }
```

**Or use direnv** (recommended):
```bash
# .envrc
export API_KEY=secret123
export NODE_ENV=development

# Enable direnv
direnv allow
```

---

### How do I share tasks across projects?

Use git submodules or includes.

**Git submodule**:
```bash
git submodule add https://github.com/org/zr-tasks.git tasks
```

```toml
# zr.toml
[tasks.lint]
cmd = "./tasks/lint.sh"

[tasks.deploy]
cmd = "./tasks/deploy.sh"
```

**Plugin** (coming soon):
```toml
[[plugins]]
name = "company-tasks"
type = "native"
path = "https://github.com/org/zr-plugin-tasks.git"
```

---

### How do I handle secrets?

**Never commit secrets**. Use environment variables.

```toml
# Bad
[tasks.deploy]
env = { API_KEY = "secret123" }

# Good
[tasks.deploy]
env = { API_KEY = "${env.DEPLOY_API_KEY}" }
```

**In CI** (GitHub Actions):
```yaml
env:
  DEPLOY_API_KEY: ${{ secrets.DEPLOY_API_KEY }}
```

**Locally**:
```bash
# .env (gitignored)
DEPLOY_API_KEY=secret123

# Load with direnv or export
export DEPLOY_API_KEY=secret123
```

---

### Can I use zr without installing Zig?

Yes! Pre-built binaries require no dependencies.

```bash
# Download binary (no Zig needed)
curl -L https://github.com/yusa-imit/zr/releases/latest/download/zr-x86_64-linux -o zr
chmod +x zr
sudo mv zr /usr/local/bin/
```

Zig is only needed for building from source.

---

### How do I contribute or report bugs?

- **Bugs**: [GitHub Issues](https://github.com/yusa-imit/zr/issues)
- **Feature requests**: [GitHub Discussions](https://github.com/yusa-imit/zr/discussions)
- **Documentation**: Submit pull requests to `docs/`

---

## Still Need Help?

1. **Check error codes**: See [Error Codes Reference](error-codes.md)
2. **Run diagnostics**: `zr doctor`
3. **Search issues**: [GitHub Issues](https://github.com/yusa-imit/zr/issues)
4. **Ask the community**: [GitHub Discussions](https://github.com/yusa-imit/zr/discussions)
5. **Report bugs**: [New Issue](https://github.com/yusa-imit/zr/issues/new)

---

## Diagnostic Commands

```bash
# Check zr version
zr --version

# Validate configuration
zr validate

# Run diagnostics
zr doctor

# List installed toolchains
zr tools list

# Check cache status
zr cache status

# View recent history
zr history

# See task details
zr show <task>

# Test environment
zr env --task <task>
```
