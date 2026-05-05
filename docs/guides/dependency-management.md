# Dependency Management & Version Constraints

**zr** provides declarative dependency management for external tools with version constraint enforcement, automatic lock file generation, and upgrade detection. This ensures consistent toolchain versions across team members and CI environments, similar to package.json's `engines` field or Cargo's version requirements.

## Overview

Declare tool version requirements in your task configuration:

```toml
[tasks.lint]
cmd = "eslint src/"
requires = { node = ">=18.0.0", npm = "^8.0.0" }

[tasks.build]
cmd = "python setup.py build"
requires = { python = "^3.11.0", pip = ">=22.0.0" }
```

zr validates installed versions before task execution and provides commands to check, install, and track dependencies.

**Key features**:
- **Version constraints**: Semver ranges (`^`, `~`, `>=`, `<`, `||`) with flexible syntax
- **Constraint validation**: Automatic pre-flight checks before task execution
- **Lock file generation**: Reproducible builds with `.zr-lock.toml`
- **Upgrade detection**: `zr deps outdated` finds available updates
- **Conflict detection**: Identify incompatible constraints across tasks
- **Workspace inheritance**: Shared constraints in workspace config

---

## Version Constraint Syntax

### Exact Version

Pin to a specific version:

```toml
requires = { node = "18.17.0" }
requires = { python = "=3.11.5" }  # explicit = prefix optional
```

**When to use**: Reproducible CI/CD builds, legacy compatibility.

### Caret Range (`^`)

Allow patch and minor updates, lock major version:

```toml
requires = { node = "^18.0.0" }  # matches >=18.0.0 <19.0.0
requires = { zig = "^0.11.0" }   # matches >=0.11.0 <0.12.0
```

**Semantic**:
- `^1.2.3` → `>=1.2.3 <2.0.0` (allow minor/patch)
- `^0.2.3` → `>=0.2.3 <0.3.0` (major 0 locks minor)
- `^0.0.3` → `=0.0.3` (exact match for 0.0.x)

**When to use**: Default for libraries, balance stability and updates.

### Tilde Range (`~`)

Allow patch updates only, lock minor version:

```toml
requires = { python = "~3.11.0" }  # matches >=3.11.0 <3.12.0
requires = { ruby = "~2.7.5" }     # matches >=2.7.5 <2.8.0
```

**Semantic**:
- `~1.2.3` → `>=1.2.3 <1.3.0` (patch updates only)
- `~1.2` → `>=1.2.0 <1.3.0`

**When to use**: Conservative updates, bug fixes without feature changes.

### Comparison Operators

Explicit version bounds:

```toml
requires = { gcc = ">=9.0.0" }        # minimum version
requires = { cmake = ">=3.20.0 <4.0.0" }  # range (AND logic)
requires = { go = ">1.20.0" }         # strictly greater than
requires = { rust = "<=1.70.0" }      # maximum version
```

**When to use**: Known incompatibilities, platform-specific requirements.

### Wildcard Versions

Match major or minor series:

```toml
requires = { node = "18.x" }    # any 18.x.x version
requires = { python = "3.11.x" } # any 3.11.x version
```

**Semantic**:
- `1.x` → `>=1.0.0 <2.0.0`
- `1.2.x` → `>=1.2.0 <1.3.0`

**When to use**: Flexible internal tools, documentation examples.

### Alternative Ranges (OR Logic)

Accept multiple version ranges:

```toml
requires = { node = "18.x || 20.x" }           # Node 18 or 20
requires = { python = "^3.10.0 || ^3.11.0" }  # Python 3.10 or 3.11
```

**When to use**: Migration periods, multi-version support.

---

## CLI Commands

### Check Dependencies

Validate all dependencies satisfy constraints:

```bash
zr deps check
```

**Output** (all satisfied):
```
✓ node: 18.17.0 satisfies >=18.0.0
✓ python: 3.11.5 satisfies ^3.11.0
All 2 dependencies satisfied
```

**Output** (constraint violation):
```
✗ node: 16.20.0 does not satisfy >=18.0.0
  Required by: tasks.lint

  Hint: Upgrade to node 18.0.0 or later
1 dependency constraint violated
```

**Exit code**: 0 (all satisfied), 1 (violations detected)

**Flags**:
- `--task=<name>` — Check only specified task's dependencies
- `--json` — Machine-readable JSON output

### Check Single Task

```bash
zr deps check --task=build
```

**Use case**: Pre-flight validation in CI pipelines.

### Install Dependencies

Show installation instructions for missing or outdated tools:

```bash
zr deps install
```

**Output**:
```
Missing dependencies:
  node >=18.0.0
    Install: curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    Or: nvm install 18

Outdated dependencies:
  python: 3.10.12 installed, ^3.11.0 required
    Upgrade: pyenv install 3.11.5 && pyenv global 3.11.5
```

**Note**: zr does not auto-install tools (security best practice). Use your preferred version manager (nvm, pyenv, asdf, mise).

### Check for Updates

Find newer versions within constraint ranges:

```bash
zr deps outdated
```

**Output**:
```
Outdated dependencies:
  node: 18.17.0 installed → 18.20.0 available (within ^18.0.0)
  npm: 8.19.0 installed → 8.19.4 available (within ^8.0.0)

Up to date:
  python: 3.11.5 (latest for ^3.11.0)
```

### Generate Lock File

Create `.zr-lock.toml` with resolved versions:

```bash
zr deps lock
```

**Generated file**:
```toml
[metadata]
generated = "2026-05-06T10:30:00Z"
zr_version = "1.82.0"

[[dependencies]]
tool = "node"
constraint = ">=18.0.0"
resolved = "18.17.0"
detected_at = "2026-05-06T10:30:00Z"

[[dependencies]]
tool = "python"
constraint = "^3.11.0"
resolved = "3.11.5"
detected_at = "2026-05-06T10:30:00Z"
```

**Use case**: Commit `.zr-lock.toml` to version control for reproducible builds.

---

## Conflict Detection

zr detects incompatible constraints across tasks:

```toml
[tasks.legacy]
cmd = "ruby old_script.rb"
requires = { ruby = "^2.7.0" }

[tasks.modern]
cmd = "ruby new_script.rb"
requires = { ruby = "^3.0.0" }
```

**Output**:
```
✗ Conflicting constraints for ruby:
  tasks.legacy requires: ^2.7.0 (matches 2.7.x)
  tasks.modern requires: ^3.0.0 (matches 3.x.x)

  These constraints cannot be satisfied simultaneously.
```

**Resolution strategies**:
1. **Separate environments**: Use Docker containers or separate workflows
2. **Relax constraints**: `ruby = "^2.7.0 || ^3.0.0"` (if tools are compatible)
3. **Upgrade legacy**: Migrate old code to new runtime

---

## Workspace-Level Constraints

Define shared constraints in workspace config:

```toml
[workspace]
name = "my-monorepo"
requires = { node = "^18.0.0", python = "^3.11.0" }

[workspace.members]
api = "packages/api"
web = "packages/web"
```

**Inheritance**:
- Member tasks inherit workspace constraints
- Task-level constraints override workspace defaults
- Validation runs against merged constraint set

---

## Integration with Task Execution

Constraints are validated automatically before task execution:

```bash
zr run build
```

**Pre-flight validation**:
1. Parse task's `requires` field
2. Query installed tool versions
3. Check each version satisfies constraints
4. Execute task if all satisfied, fail with error otherwise

**Error output** (constraint violation):
```
✗ Cannot run task 'build': dependency constraint violated

  python: 3.10.12 does not satisfy ^3.11.0

  Run 'zr deps check --task=build' for details.
```

**Disable validation**: `zr run build --skip-deps` (for debugging)

---

## Real-World Examples

### Node.js Monorepo

```toml
[workspace]
name = "acme-corp"
requires = { node = "^18.0.0", npm = "^8.0.0" }

[tasks.lint]
cmd = "eslint src/"
requires = { eslint = "^8.50.0" }

[tasks.test]
cmd = "jest"
requires = { jest = "^29.0.0" }

[tasks.build]
cmd = "webpack"
requires = { webpack = "^5.0.0" }
```

### Multi-Language Project

```toml
[tasks.api]
cmd = "python -m uvicorn main:app"
requires = { python = "^3.11.0", pip = ">=22.0.0" }

[tasks.frontend]
cmd = "npm run dev"
requires = { node = "^18.0.0", npm = "^8.0.0" }

[tasks.database]
cmd = "psql -f schema.sql"
requires = { postgresql = ">=14.0.0" }

[tasks.full-stack]
deps = ["api", "frontend", "database"]
```

### CI/CD with Lock File

**.github/workflows/ci.yml**:
```yaml
jobs:
  build:
    steps:
      - uses: actions/checkout@v3
      - name: Validate dependencies
        run: zr deps check
      - name: Verify lock file
        run: |
          zr deps lock --check  # fail if lock file out of date
      - name: Run tests
        run: zr run test
```

**zr.toml**:
```toml
[tasks.test]
cmd = "pytest tests/"
requires = { python = "^3.11.0", pytest = "^7.0.0" }
```

Commit `.zr-lock.toml` to ensure CI uses exact versions.

---

## Migration from Other Tools

### From package.json `engines`

**Before** (package.json):
```json
{
  "engines": {
    "node": ">=18.0.0",
    "npm": "^8.0.0"
  }
}
```

**After** (zr.toml):
```toml
[workspace]
requires = { node = ">=18.0.0", npm = "^8.0.0" }

[tasks.install]
cmd = "npm install"

[tasks.build]
cmd = "npm run build"
```

### From Cargo

**Before** (Cargo.toml):
```toml
[package]
rust-version = "1.70.0"
```

**After** (zr.toml):
```toml
[tasks.build]
cmd = "cargo build --release"
requires = { rust = "^1.70.0" }
```

### From .tool-versions (asdf)

**Before** (.tool-versions):
```
nodejs 18.17.0
python 3.11.5
```

**After** (zr.toml):
```toml
[workspace]
requires = { node = "18.17.0", python = "3.11.5" }
```

**Advantage**: Version constraints (not just exact pins), validation before execution.

---

## Best Practices

### Use Caret for Libraries

```toml
requires = { react = "^18.0.0" }  # allow minor/patch updates
```

**Why**: Balance security patches with stability.

### Use Tilde for Runtimes

```toml
requires = { node = "~18.17.0" }  # patch updates only
```

**Why**: Runtime behavior changes in minor versions can break apps.

### Exact Versions for CI

```toml
# Development: flexible
requires = { python = "^3.11.0" }

# CI: pin with lock file
$ zr deps lock  # generates .zr-lock.toml
```

**Why**: Reproducible builds, prevent "works on my machine" issues.

### Document Migration Paths

```toml
[tasks.legacy]
description = "Runs on Ruby 2.7 (deprecated, migrate to 3.x)"
requires = { ruby = "^2.7.0" }

[tasks.modern]
description = "Runs on Ruby 3.x (preferred)"
requires = { ruby = "^3.0.0" }
```

### Validate Before Deploy

```bash
# Pre-deployment check
zr deps check --task=deploy || exit 1
zr run deploy
```

### Use Alternatives for Transition Periods

```toml
# During migration from Node 16 → 18
requires = { node = "16.x || 18.x" }

# After 6 months
requires = { node = "^18.0.0" }
```

---

## Troubleshooting

### Error: "Tool version not detected"

**Symptom**:
```
✗ Could not detect version for 'ruby'
  Command: ruby --version
  Output: (none)
```

**Causes**:
1. Tool not in PATH
2. Tool doesn't support `--version` flag
3. Non-standard version output format

**Solution**:
```bash
# Check PATH
which ruby

# Test version command manually
ruby --version

# For non-standard tools, use exact version
requires = { custom_tool = "1.0.0" }  # skips validation
```

### Error: "Constraint cannot be satisfied"

**Symptom**:
```
✗ node: 16.20.0 does not satisfy >=18.0.0
```

**Solutions**:
1. Upgrade tool: `nvm install 18`
2. Relax constraint: `requires = { node = ">=16.0.0" }` (if compatible)
3. Use container: `docker run -v $(pwd):/app node:18 zr run build`

### Lock File Out of Sync

**Symptom**:
```
Warning: .zr-lock.toml resolved versions differ from current
  node: locked 18.17.0, installed 18.20.0
```

**Solution**:
```bash
# Regenerate lock file
zr deps lock

# Or use locked versions
nvm use 18.17.0  # match lock file
```

### Conflicting Constraints

**Symptom**:
```
✗ Conflicting constraints for python:
  tasks.api requires: ^3.11.0
  tasks.legacy requires: ^3.8.0
```

**Solutions**:
1. **Upgrade legacy**: Migrate to Python 3.11
2. **Separate workflows**: Don't run both tasks in same environment
3. **Use OR constraint**: `python = "^3.8.0 || ^3.11.0"` (if both compatible)

---

## Advanced Usage

### Per-Task Overrides

```toml
[workspace]
requires = { node = "^18.0.0" }

[tasks.legacy-build]
cmd = "gulp build"
requires = { node = "16.x" }  # overrides workspace constraint
```

### Optional Dependencies

```toml
[tasks.build]
cmd = "make"
requires = { gcc = ">=9.0.0" }

# Optional linting (doesn't block build if missing)
[tasks.lint]
cmd = "cppcheck src/"
requires = { cppcheck = "^2.0.0" }
silent_on_missing = true  # proposed future feature
```

### Multi-Tool Constraints

```toml
[tasks.cross-compile]
cmd = "zig build -Dtarget=x86_64-linux"
requires = {
  zig = "^0.11.0",
  gcc = ">=9.0.0",      # for linking
  cmake = "~3.20.0"     # for build system
}
```

---

## Comparison with Other Tools

| Feature | zr | package.json | Cargo | asdf |
|---------|-----|--------------|-------|------|
| Constraint syntax | Semver (^~>=<) | Yes | Yes | No (exact only) |
| Conflict detection | Yes | No | Yes | No |
| Lock files | .zr-lock.toml | package-lock.json | Cargo.lock | No |
| Multi-language | Yes | No (Node only) | No (Rust only) | Yes |
| Validation | Pre-execution | Manual (npm ci) | Pre-build | Manual |
| Outdated detection | `zr deps outdated` | `npm outdated` | `cargo outdated` | Manual |

**Why zr**:
- **Universal**: Works with any language/tool (not ecosystem-locked)
- **Pre-flight**: Validates before execution (fail fast)
- **Lightweight**: No runtime dependencies (single binary)
- **Task-scoped**: Different tasks can have different requirements

---

## Summary

**Dependency management in zr**:
1. Declare `requires = { tool = "constraint" }` in tasks or workspace
2. Run `zr deps check` to validate constraints
3. Use `zr deps lock` to pin versions for reproducibility
4. Constraints are validated automatically before task execution
5. Use `zr deps outdated` to find available updates

**Next steps**:
- [Configuration Reference](config-reference.md) — Complete `requires` field syntax
- [Incremental Builds](incremental-builds.md) — Combine with up-to-date detection
- [CI/CD Integration](commands.md#cicd) — Lock files in continuous deployment

**Questions?** See [troubleshooting](#troubleshooting) or run `zr deps --help`.
