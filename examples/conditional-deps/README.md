# Conditional Dependencies Example

This example demonstrates the use of `deps_if` and `deps_optional` features introduced in v1.10.0.

## Features Demonstrated

### 1. Conditional Dependencies (`deps_if`)

Run dependencies only when certain conditions are met:

```toml
[tasks.build]
cmd = "echo 'Building application...'"
deps_if = [
  { task = "lint", condition = "env.CI == 'true'" },
  { task = "type-check", condition = "env.STRICT == 'true'" }
]
```

Use cases:
- Run linting only in CI environments
- Enable strict type checking based on environment variable
- Skip expensive checks in development mode

### 2. Optional Dependencies (`deps_optional`)

Gracefully handle dependencies that may or may not exist:

```toml
[tasks.deploy]
cmd = "echo 'Deploying...'"
deps_optional = ["build", "test", "security-scan"]
```

Use cases:
- Run security scans if configured, skip if not
- Allow optional build steps for multi-environment setups
- Gracefully degrade when optional tools aren't available

### 3. Combined Dependencies

Use all dependency types together:

```toml
[tasks.release]
cmd = "echo 'Creating release...'"
deps = ["build"]                    # Always run
deps_serial = ["test"]              # Run after all parallel deps
deps_if = [
  { task = "lint", condition = "env.SKIP_LINT != 'true'" }
]
deps_optional = ["docs"]            # Run if exists
```

## Running the Examples

```bash
# Run build (linting depends on CI env var)
CI=true zr run build

# Run build without linting
zr run build

# Run deploy (gracefully skips missing tasks)
zr run deploy

# Run release with all features
SKIP_LINT=false zr run release
```

## Key Benefits

1. **Environment-aware workflows**: Different behavior in CI vs local
2. **Graceful degradation**: Optional dependencies don't break builds
3. **Flexible task composition**: Mix required, conditional, and optional deps
4. **Better developer experience**: Clear intent in configuration
