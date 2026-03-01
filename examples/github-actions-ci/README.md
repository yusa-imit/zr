# GitHub Actions CI/CD Integration

This example demonstrates how to integrate zr with GitHub Actions for continuous integration and deployment workflows.

## What's Included

### Configuration Files

1. **`zr.toml`** — Task definitions for builds, tests, quality checks, and deployments
2. **`.github/workflows/ci.yml`** — CI workflow for pull requests and branch pushes
3. **`.github/workflows/release.yml`** — Release workflow for tagged versions

### Key Features

- **Fast feedback** — Quality checks run first (lint, format, security scan)
- **Matrix testing** — Tests run on Linux, macOS, and Windows simultaneously
- **Cross-platform builds** — Build binaries for multiple platforms in parallel
- **Conditional deployments** — Auto-deploy to staging (develop) or production (main)
- **Release automation** — Create GitHub releases with artifacts on version tags
- **Artifact management** — Upload/download build artifacts between jobs
- **Environment protection** — Use GitHub environments for deployment approvals

## Workflows

### CI Workflow (`.github/workflows/ci.yml`)

Triggered on:
- Push to `main` or `develop` branches
- Pull requests to `main`

Pipeline stages:
1. **Quality Checks** (parallel)
   - Linter
   - Format checker
   - Type checker
   - Security scan

2. **Tests** (matrix: Linux, macOS, Windows)
   - Unit tests
   - Integration tests
   - E2E tests

3. **Build** (matrix: Linux, macOS, Windows)
   - Platform-specific builds
   - Artifact upload

4. **Deploy** (conditional)
   - Staging: on `develop` branch
   - Production: on `main` branch

### Release Workflow (`.github/workflows/release.yml`)

Triggered on:
- Git tags matching `v*.*.*` (e.g., `v1.0.0`)

Pipeline stages:
1. **Full release workflow** (`zr workflow release`)
   - Quality checks (fail-fast)
   - All tests
   - Multi-platform builds
   - Package artifacts

2. **Create GitHub Release**
   - Generate release notes
   - Attach build artifacts
   - Publish release

## Usage

### Local Development

```bash
# Run CI pipeline locally
zr run ci

# Run quality checks only
zr run quality

# Run tests
zr run test

# Build for current platform
zr run build

# Clean artifacts
zr run clean

# Check environment
zr run doctor
```

### Testing Workflows Locally

```bash
# Simulate CI environment
export GITHUB_ACTIONS=true
export GITHUB_REF_NAME=main

# Run the full release workflow
zr workflow release
```

### Creating a Release

1. **Tag a version:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **GitHub Actions automatically:**
   - Runs quality checks and tests
   - Builds binaries for all platforms
   - Creates a GitHub Release
   - Attaches build artifacts

## GitHub Actions Best Practices

### 1. Caching zr Installation

The workflows install zr in each job. For faster builds, you can cache the binary:

```yaml
- name: Cache zr
  uses: actions/cache@v4
  with:
    path: ~/.zr/bin/zr
    key: zr-${{ runner.os }}-${{ hashFiles('**/zr.toml') }}

- name: Install zr
  if: steps.cache-zr.outputs.cache-hit != 'true'
  run: |
    curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
    echo "$HOME/.zr/bin" >> $GITHUB_PATH
```

### 2. Matrix Strategy for Tests

Use matrix builds to test across multiple dimensions:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    node-version: [18, 20, 22]
    include:
      - os: ubuntu-latest
        node-version: 20
        coverage: true
```

### 3. Conditional Job Execution

Use `if` conditions to control when jobs run:

```yaml
deploy-production:
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
  needs: build
  runs-on: ubuntu-latest
  steps:
    - run: zr run deploy-production
```

### 4. Environment Protection

Use GitHub Environments to require manual approvals for deployments:

```yaml
deploy-production:
  environment:
    name: production
    url: https://example.com
  steps:
    - run: zr run deploy-production
```

Configure environment protection rules in **Settings → Environments**.

### 5. Artifact Retention

Upload artifacts with appropriate retention:

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: build-artifacts
    path: dist/
    retention-days: 7  # Auto-delete after 7 days
```

### 6. Concurrency Control

Prevent redundant workflow runs:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Integration with zr Features

### 1. Using zr's Conditional Execution

zr tasks can check GitHub environment variables:

```toml
[tasks.deploy-production]
cmd = "deploy.sh production"
condition = "env.GITHUB_REF_NAME == 'main'"
```

### 2. Using zr's Parallel Execution

zr automatically parallelizes independent tasks:

```toml
[tasks.ci]
deps = ["lint", "test", "security-scan"]  # All run in parallel
```

This is more efficient than GitHub Actions' job-level parallelism for small, fast tasks.

### 3. Using zr's Cache

Enable caching for expensive operations:

```toml
[tasks.build]
cmd = "cargo build --release"
cache = true  # Skip if inputs unchanged
```

### 4. Using zr Workflows

Complex pipelines can be defined in zr.toml and reused locally and in CI:

```toml
[workflows.release]
description = "Full release pipeline"

[[workflows.release.stages]]
name = "checks"
tasks = ["lint", "test"]
fail_fast = true

[[workflows.release.stages]]
name = "build"
tasks = ["build-linux", "build-macos", "build-windows"]
parallel = true
```

Run with:
```bash
zr workflow release  # Works locally and in CI
```

## Comparison: GitHub Actions vs zr

| Aspect | GitHub Actions | zr |
|--------|----------------|-----|
| **Parallelism** | Job-level (separate VMs) | Task-level (same VM, faster) |
| **Caching** | Manual setup, cache action | Built-in with `cache = true` |
| **Matrix builds** | Native matrix strategy | zr matrix feature |
| **Conditional execution** | `if` conditions in YAML | `condition` field in zr.toml |
| **Local testing** | Requires tools like `act` | Works identically locally |
| **Configuration** | YAML workflow files | TOML task definitions |

**Best practice:** Use GitHub Actions for job orchestration (matrix, artifacts, deployments) and zr for task execution (builds, tests, quality checks).

## Advanced Patterns

### 1. Monorepo CI with Affected Detection

```yaml
- name: Run affected tests
  run: zr run test --affected
```

Only tests packages changed in the PR.

### 2. Deploy Previews for PRs

```yaml
deploy-preview:
  if: github.event_name == 'pull_request'
  runs-on: ubuntu-latest
  steps:
    - name: Deploy preview
      run: zr run deploy-preview
      env:
        PR_NUMBER: ${{ github.event.pull_request.number }}
```

### 3. Scheduled Tasks

```yaml
on:
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight

jobs:
  nightly:
    runs-on: ubuntu-latest
    steps:
      - run: zr run nightly-tests
```

### 4. Manual Workflow Dispatch

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deploy environment'
        required: true
        type: choice
        options:
          - staging
          - production

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: zr run deploy-${{ inputs.environment }}
```

## Troubleshooting

### zr command not found

Make sure to add zr to PATH after installation:

```yaml
- name: Install zr
  run: |
    curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
    echo "$HOME/.zr/bin" >> $GITHUB_PATH
```

### Task fails only in CI

Check for environment differences:

```bash
zr run doctor  # Shows environment info
```

Common issues:
- Missing environment variables
- Different OS/shell behavior
- File paths (use relative paths)

### Workflow takes too long

1. **Use zr's parallel execution:**
   ```toml
   [tasks.ci]
   deps = ["lint", "test", "build"]  # Parallel
   ```

2. **Enable caching:**
   ```toml
   [tasks.build]
   cache = true
   ```

3. **Use GitHub Actions matrix:**
   ```yaml
   strategy:
     matrix:
       os: [ubuntu-latest, macos-latest]
   ```

## Further Reading

- [GitHub Actions Documentation](https://docs.github.com/actions)
- [zr Workflows Guide](../../docs/guides/configuration.md#workflows)
- [zr Conditional Execution](../../docs/guides/configuration.md#conditional-execution)
- [zr Caching](../../docs/guides/configuration.md#caching)

## Next Steps

1. Copy this example to your repository
2. Customize task definitions in `zr.toml`
3. Configure GitHub environments for deployment protection
4. Set up branch protection rules requiring CI to pass
5. Test locally with `zr run ci` before pushing
