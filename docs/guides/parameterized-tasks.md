# Parameterized Tasks Guide

## Overview

Parameterized tasks allow you to define reusable task templates that accept runtime arguments, eliminating the need to duplicate task definitions for different environments, configurations, or inputs. Similar to `just`'s recipe parameters and `make`'s variables, zr enables flexible task execution with default values and runtime overrides.

When you parameterize a task, you can:
1. Define parameters with default values
2. Override defaults at runtime via CLI arguments
3. Require mandatory parameters that must be provided
4. Use parameter values in task commands and environment variables

This is especially powerful for deployment tasks (dev/staging/prod), test configurations, or any scenario where you need the same logic with different inputs.

---

## Basic Usage

### Defining Parameters

Add a `params` field to your task definition with an array of parameter objects:

```toml
[tasks.deploy]
cmd = "kubectl apply -f deploy-{{env}}.yaml"
params = [
  { name = "env", default = "dev", description = "Target environment" }
]
description = "Deploy application to Kubernetes"
```

Each parameter has:
- **name** (required): Parameter identifier used in `{{name}}` interpolation
- **default** (optional): Default value if not provided at runtime
- **description** (optional): Help text shown in `zr run <task> --help`

### Using Parameter Values

Reference parameters in your task definition using `{{param_name}}` syntax:

```toml
[tasks.deploy]
cmd = "echo Deploying to {{env}} in region {{region}}"
params = [
  { name = "env", default = "dev" },
  { name = "region", default = "us-east-1" }
]
```

Parameters can be used in:
- `cmd` field: `"build --target {{target}}"`
- `env` field: `{ API_URL = "https://{{env}}.example.com" }`

### Running with Parameters

Three CLI syntaxes are supported for providing parameter values:

```bash
# 1. Positional arguments (order matches params array)
zr run deploy prod us-west-2

# 2. Named arguments (key=value pairs)
zr run deploy env=prod region=us-west-2

# 3. --param flag syntax (explicit, can be mixed)
zr run deploy --param env=prod --param region=us-west-2

# Using defaults (no arguments needed if all params have defaults)
zr run deploy
# ↳ Uses env=dev, region=us-east-1
```

All three syntaxes produce the same result. Choose based on preference and context.

---

## Required Parameters

Parameters without a `default` value are **required** and must be provided at runtime:

```toml
[tasks.deploy]
cmd = "kubectl apply -f deploy-{{env}}.yaml --namespace={{namespace}}"
params = [
  { name = "env", description = "Target environment (required)" },
  { name = "namespace", default = "default", description = "Kubernetes namespace" }
]
```

Running without the required `env` parameter fails with a clear error:

```bash
$ zr run deploy
✗ Task 'deploy' requires parameter 'env' but no value was provided

  Hint: Provide the parameter using one of these syntaxes:
    zr run deploy <value>
    zr run deploy env=<value>
    zr run deploy --param env=<value>
```

---

## Multiple Parameters

Tasks can accept multiple parameters, combining required and optional:

```toml
[tasks.test]
cmd = "pytest tests/{{suite}} --verbose={{verbose}} --workers={{workers}}"
params = [
  { name = "suite", default = "unit", description = "Test suite to run" },
  { name = "verbose", default = "false", description = "Enable verbose output" },
  { name = "workers", default = "4", description = "Number of parallel workers" }
]
```

Usage examples:

```bash
# Run with all defaults
zr run test
# ↳ pytest tests/unit --verbose=false --workers=4

# Override specific parameters (mix named + positional)
zr run test integration verbose=true
# ↳ pytest tests/integration --verbose=true --workers=4

# Override all parameters
zr run test suite=e2e verbose=true workers=8
# ↳ pytest tests/e2e --verbose=true --workers=8
```

---

## Environment Variables

Parameters can be interpolated into environment variables:

```toml
[tasks.api-test]
cmd = "curl $API_URL/health"
env = { API_URL = "https://api-{{env}}.example.com" }
params = [
  { name = "env", default = "dev" }
]
```

```bash
$ zr run api-test env=staging
# Executes: curl https://api-staging.example.com/health
```

This is especially useful for configuring different backends, database URLs, or feature flags per environment.

---

## Parameter Values with Spaces

Values containing spaces must be quoted:

```bash
# Named syntax with quotes
zr run notify message="Deployment complete"

# --param syntax with quotes
zr run notify --param message="Deployment complete"

# Positional syntax with quotes
zr run notify "Deployment complete"
```

The quotes are stripped before interpolation:

```toml
[tasks.notify]
cmd = "echo {{message}}"
params = [{ name = "message" }]
```

```bash
$ zr run notify "Hello World"
Hello World
```

---

## Help Integration

View available parameters and their defaults/descriptions:

```bash
$ zr run deploy --help
Task: deploy
Deploy application to Kubernetes

Parameters:
  env       Target environment (default: dev)
  region    AWS region (default: us-east-1)

Usage:
  zr run deploy [env] [region]
  zr run deploy env=<value> region=<value>
  zr run deploy --param env=<value> --param region=<value>
```

The `--help` flag shows parameter information inline with the task description.

---

## Task List Display

The `zr list` command shows tasks with their parameters:

```bash
$ zr list
Available tasks:
  deploy(env="dev", region="us-east-1")  Deploy application to Kubernetes
  test(suite="unit", workers=4)          Run test suite
  notify(message)                         Send notification (message required)
```

Parameters are displayed in function-call style with defaults shown in quotes.

---

## History Tracking

Execution history records the actual parameter values used:

```bash
$ zr history
Recent executions:
  deploy env=prod region=us-west-2  (2026-04-23 14:30:15)  ✓ 5.2s
  deploy env=staging                (2026-04-23 12:15:08)  ✓ 4.8s
  deploy                            (2026-04-23 10:05:23)  ✓ 5.1s
```

This helps track which configurations were used for each execution, useful for auditing deployments.

---

## Workflow Integration

Workflows can pass parameters to tasks:

```toml
[workflows.deploy-all]
tasks = [
  { name = "deploy", params = { env = "staging" } },
  { name = "deploy", params = { env = "prod" } }
]
```

```bash
$ zr workflow deploy-all
✓ deploy env=staging (5.1s)
✓ deploy env=prod (5.3s)
```

This enables orchestrating the same task with different configurations in a single workflow.

---

## Interactive Mode

When using `zr irun` (interactive mode), zr prompts for required parameters:

```bash
$ zr irun deploy
? Select parameter 'env': [dev, staging, prod] › dev
? Select parameter 'region': [us-east-1, us-west-2, eu-west-1] › us-east-1
✓ deploy env=dev region=us-east-1 (5.0s)
```

Optional parameters with defaults are skipped unless explicitly requested.

---

## Task Dependencies

Tasks with parameters can depend on other tasks, and dependencies can pass parameters:

```toml
[tasks.build]
cmd = "zig build -Dtarget={{target}}"
params = [{ name = "target", default = "native" }]

[tasks.test]
cmd = "zig build test"
deps = ["build"]
params = [{ name = "target", default = "native" }]
```

When running `zr run test target=x86_64-linux`, the `build` dependency also receives `target=x86_64-linux`.

**Parameter inheritance rules:**
- Dependencies inherit parameters from the parent task **if they have matching param names**
- Dependencies with their own defaults use those defaults if parent doesn't provide the param
- Required params in dependencies must be satisfied by parent or fail

Example:

```toml
[tasks.compile]
cmd = "gcc -o {{output}} {{input}}"
params = [
  { name = "input", description = "Source file (required)" },
  { name = "output", default = "a.out" }
]

[tasks.run-compiled]
cmd = "./{{output}}"
deps = ["compile"]
params = [
  { name = "input", description = "Source file (required)" },
  { name = "output", default = "a.out" }
]
```

```bash
$ zr run run-compiled input=main.c output=myapp
# 1. Runs: gcc -o myapp main.c
# 2. Runs: ./myapp
```

---

## Validation

zr validates parameters at runtime:

### Unknown Parameter

```bash
$ zr run deploy env=prod typo=value
✗ Unknown parameter 'typo' for task 'deploy'

  Available parameters: env, region

  Hint: Check the parameter name for typos
```

### Type Validation

Currently all parameters are treated as strings. Future versions may add typed parameters (bool, number, enum) with validation.

---

## Comparison with Other Tools

### vs. just (recipe parameters)

**just:**
```just
deploy env="dev":
  kubectl apply -f deploy-{{env}}.yaml
```

**zr equivalent:**
```toml
[tasks.deploy]
cmd = "kubectl apply -f deploy-{{env}}.yaml"
params = [{ name = "env", default = "dev" }]
```

Both support default values and `{{var}}` interpolation. zr adds:
- Parameter descriptions for `--help`
- Multiple syntax options (positional, named, `--param`)
- Workflow integration with param passing
- History tracking with param values

### vs. make (variables)

**make:**
```make
ENV ?= dev
deploy:
	kubectl apply -f deploy-$(ENV).yaml
```

**zr equivalent:**
```toml
[tasks.deploy]
cmd = "kubectl apply -f deploy-{{env}}.yaml"
params = [{ name = "env", default = "dev" }]
```

make uses `?=` for defaults and `$(VAR)` syntax. zr's advantages:
- Scoped to individual tasks (no global variable pollution)
- Required vs. optional distinction built-in
- Better error messages for missing parameters
- Parameter metadata (descriptions, help)

### vs. Task (vars)

**Task (taskfile.yml):**
```yaml
tasks:
  deploy:
    vars:
      ENV: '{{.ENV | default "dev"}}'
    cmds:
      - kubectl apply -f deploy-{{.ENV}}.yaml
```

**zr equivalent:**
```toml
[tasks.deploy]
cmd = "kubectl apply -f deploy-{{env}}.yaml"
params = [{ name = "env", default = "dev" }]
```

Task uses `.VAR` syntax with template functions. zr is more concise and declarative.

---

## Migration Guides

### From just

Replace just recipes:

```just
# Before (just)
deploy env="dev" region="us-east-1":
  kubectl apply -f deploy-{{env}}.yaml --region={{region}}
```

```toml
# After (zr)
[tasks.deploy]
cmd = "kubectl apply -f deploy-{{env}}.yaml --region={{region}}"
params = [
  { name = "env", default = "dev" },
  { name = "region", default = "us-east-1" }
]
```

CLI usage remains similar:
```bash
# just
just deploy prod us-west-2

# zr
zr run deploy prod us-west-2
```

### From make

Replace make variables:

```make
# Before (make)
ENV ?= dev
deploy:
	kubectl apply -f deploy-$(ENV).yaml
```

```toml
# After (zr)
[tasks.deploy]
cmd = "kubectl apply -f deploy-{{env}}.yaml"
params = [{ name = "env", default = "dev" }]
```

CLI invocation:
```bash
# make
make deploy ENV=prod

# zr
zr run deploy env=prod
```

---

## Real-World Examples

### Multi-Environment Deployment

```toml
[tasks.deploy]
cmd = """
docker build -t myapp:{{env}} . && \
docker push myapp:{{env}} && \
kubectl apply -f k8s/{{env}}.yaml
"""
env = {
  DOCKER_REGISTRY = "gcr.io/{{project}}",
  KUBECONFIG = "~/.kube/{{env}}.yaml"
}
params = [
  { name = "env", description = "Environment (required - dev/staging/prod)" },
  { name = "project", default = "my-gcp-project" }
]
description = "Build, push, and deploy to Kubernetes"
```

Usage:
```bash
# Deploy to staging
zr run deploy staging

# Deploy to prod with different GCP project
zr run deploy env=prod project=prod-gcp-project
```

### Test Matrix

```toml
[tasks.test]
cmd = "pytest tests/{{suite}} --cov={{coverage}} -n {{workers}}"
params = [
  { name = "suite", default = "unit", description = "Test suite (unit/integration/e2e)" },
  { name = "coverage", default = "true", description = "Enable coverage reporting" },
  { name = "workers", default = "auto", description = "Parallel workers (number or 'auto')" }
]
```

Usage:
```bash
# Quick unit tests without coverage
zr run test unit false

# Full e2e tests with max parallelism
zr run test suite=e2e workers=16
```

### Database Operations

```toml
[tasks.db-migrate]
cmd = "diesel migration run --database-url={{db_url}}"
env = { DATABASE_URL = "{{db_url}}" }
params = [
  { name = "db_url", description = "Database URL (required)" }
]

[tasks.db-rollback]
cmd = "diesel migration revert --database-url={{db_url}}"
env = { DATABASE_URL = "{{db_url}}" }
params = [
  { name = "db_url", description = "Database URL (required)" }
]
```

Usage:
```bash
# Migrate staging database
zr run db-migrate db_url=postgres://staging.example.com/mydb

# Rollback production (with confirmation)
zr run db-rollback db_url=postgres://prod.example.com/mydb
```

### Feature Flag Testing

```toml
[tasks.test-feature]
cmd = "npm test -- --grep={{feature}}"
env = {
  FEATURE_{{feature}} = "true",
  TEST_ENV = "{{env}}"
}
params = [
  { name = "feature", description = "Feature flag to test (required)" },
  { name = "env", default = "dev" }
]
```

Usage:
```bash
# Test new-checkout feature in staging
zr run test-feature feature=new-checkout env=staging
```

---

## Best Practices

### 1. Use Descriptive Parameter Names

```toml
# ❌ Bad: Unclear names
params = [
  { name = "e" },  # What is 'e'?
  { name = "r" }   # What is 'r'?
]

# ✅ Good: Self-documenting
params = [
  { name = "environment", description = "Target environment" },
  { name = "region", description = "AWS region" }
]
```

### 2. Provide Sensible Defaults

```toml
# ✅ Good: Safe defaults for development
params = [
  { name = "env", default = "dev" },      # Default to least destructive
  { name = "dry_run", default = "true" }, # Default to safe mode
  { name = "workers", default = "4" }     # Default to reasonable parallelism
]
```

### 3. Document Required Parameters

```toml
# ✅ Good: Clear descriptions for required params
params = [
  { name = "db_url", description = "Database URL (required - postgres://...)" },
  { name = "api_key", description = "API key for external service (required)" }
]
```

### 4. Validate Critical Parameters in Task

For sensitive operations, add validation in the task itself:

```toml
[tasks.delete-prod]
cmd = """
if [ "{{env}}" != "prod" ]; then
  echo "This task only runs in prod environment"
  exit 1
fi
echo "Are you sure? Press Ctrl+C to abort..."
sleep 5
# ... actual deletion logic
"""
params = [
  { name = "env", description = "Must be 'prod'" }
]
```

### 5. Use Workflows for Common Parameter Sets

```toml
[tasks.deploy]
cmd = "kubectl apply -f k8s/{{env}}.yaml"
params = [{ name = "env" }]

[workflows.deploy-all-envs]
tasks = [
  { name = "deploy", params = { env = "dev" } },
  { name = "deploy", params = { env = "staging" } },
  { name = "deploy", params = { env = "prod" } }
]
```

### 6. Combine with Task Dependencies

```toml
[tasks.build]
cmd = "zig build -Doptimize={{optimize}}"
params = [{ name = "optimize", default = "Debug" }]

[tasks.test]
cmd = "zig build test"
deps = ["build"]
params = [{ name = "optimize", default = "Debug" }]

[tasks.deploy]
cmd = "./scripts/deploy.sh {{env}}"
deps = ["build", "test"]
params = [
  { name = "env", description = "Target environment (required)" },
  { name = "optimize", default = "ReleaseSafe" }
]
```

Running `zr run deploy env=prod` ensures:
1. Build runs with `optimize=ReleaseSafe` (inherited from deploy)
2. Tests run with `optimize=ReleaseSafe` (inherited from deploy)
3. Deploy runs with `env=prod`

---

## Troubleshooting

### "Unknown parameter" error but parameter exists

**Symptom:**
```bash
$ zr run deploy environment=prod
✗ Unknown parameter 'environment' for task 'deploy'
```

**Cause:** Parameter name mismatch (task defines `env`, you passed `environment`)

**Solution:** Check parameter names with `zr run deploy --help`

---

### Parameter not interpolated (literal {{param}} in output)

**Symptom:**
```bash
$ zr run deploy env=prod
Deploying to {{env}}  # Expected: Deploying to prod
```

**Cause:** Missing parameter definition or typo in `{{param}}` syntax

**Solution:**
1. Ensure `params = [{ name = "env" }]` is defined
2. Check for typos: `{{env}}` not `{{Env}}` or `{{ env }}`
3. Parameters are case-sensitive

---

### Required parameter not detected

**Symptom:**
```bash
$ zr run deploy
# Runs successfully but uses empty/broken value
```

**Cause:** Parameter has a `default = ""` (empty string is still a default)

**Solution:** Remove the `default` field entirely for required parameters:
```toml
# ✅ Required (no default field)
params = [{ name = "env", description = "Environment (required)" }]

# ❌ Not required (empty default still satisfies requirement)
params = [{ name = "env", default = "", description = "..." }]
```

---

### Parameter values with special characters

**Symptom:**
```bash
$ zr run deploy env=prod-us-east-1
# Breaks if task uses {{env}} in shell command
```

**Cause:** Special characters like `-` may need quoting depending on context

**Solution:** Quote parameter values in the task definition if used in shell contexts:
```toml
cmd = "kubectl apply -f 'deploy-{{env}}.yaml'"
#                        ^                   ^
```

Or use safer file naming conventions (underscores instead of hyphens).

---

## Roadmap

Future enhancements planned for parameterized tasks:

- **Typed parameters**: `type = "bool"`, `type = "number"`, `type = "enum"` with validation
- **Enum constraints**: `choices = ["dev", "staging", "prod"]` for restricted values
- **Parameter groups**: `[param_groups.aws]` for organizing related parameters
- **Conditional parameters**: `if = "{{env}} == prod"` for context-dependent params
- **Template tasks**: `[task_templates.deploy]` for generating multiple tasks from one template
- **Dynamic task generation**: `zr generate tasks --from-template --params matrix.json`

See `docs/milestones.md` for tracking and timelines.

---

## See Also

- [Configuration Guide](configuration.md) — Full TOML schema reference
- [Workflow Integration](commands.md#workflow) — Using params in workflows
- [Migration Guide](migration.md) — Migrating from just/make/Task
- [Best Practices](best-practices.md) — Task design patterns
