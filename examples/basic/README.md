# Basic Example

This example demonstrates the fundamental features of zr for a simple single-project setup.

## Features Demonstrated

- **Simple task definitions** with commands and descriptions
- **Task dependencies** (e.g., `test` depends on `build`)
- **Environment variables** for tasks
- **Working directory** overrides
- **Matrix expansion** for running similar tasks with different parameters
- **Cache control** to disable caching for specific tasks
- **Desktop notifications** when tasks complete (v1.83.0+)
- **Required env vars** that fail fast if missing (v1.84.0+)
- **Task aliases** for short command variants (v1.73.0+)

## Usage

```bash
# List all tasks
zr list

# Run a single task
zr run hello

# Run a task with dependencies (will run build first)
zr run test

# Deploy (will run test, which runs build)
zr run deploy

# Run matrix task (will run lint for each language)
zr run lint

# Clean artifacts
zr run clean

# Run release (requires REGISTRY and API_TOKEN env vars)
REGISTRY=my-registry.example.com API_TOKEN=secret zr run release

# Use task aliases
zr run format   # same as zr run fmt
zr run f        # same as zr run fmt

# Skip a specific task in a pipeline
zr run deploy --skip=lint

# Enable desktop notifications for a task run
zr run deploy --notify
```

## Key Concepts

### Task Dependencies
Tasks can depend on other tasks using the `deps` array. Dependencies run before the task:
```toml
[tasks.test]
deps = ["build"]  # build runs first
```

### Environment Variables
Set environment variables for specific tasks:
```toml
[tasks.deploy]
env = { ENV = "production" }
```

### Desktop Notifications
Get notified when tasks complete, even in the background:
```toml
[tasks.deploy]
notify = true
notify_on = "always"   # "success", "failure", or "always"
notify_title = "Deployment"
```

### Required Environment Variables
Fail fast if required env vars are missing before running a task:
```toml
[tasks.release]
required_env = ["REGISTRY", "API_TOKEN"]
```

### Matrix Expansion
Run the same task with different parameters:
```toml
[tasks.lint]
matrix.lang = ["javascript", "python", "rust"]
cmd = "echo 'Linting ${{lang}}...'"
```

### Cache Control
Disable caching for tasks that should always run:
```toml
[tasks.timestamp]
cache = false
```

### Task Aliases
Define short names for tasks to save typing:
```toml
[tasks.fmt]
aliases = ["format", "f"]
```
