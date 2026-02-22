# Basic Example

This example demonstrates the fundamental features of zr for a simple single-project setup.

## Features Demonstrated

- **Simple task definitions** with commands and descriptions
- **Task dependencies** (e.g., `test` depends on `build`)
- **Environment variables** for tasks
- **Working directory** overrides
- **Matrix expansion** for running similar tasks with different parameters
- **Cache control** to disable caching for specific tasks

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

### Matrix Expansion
Run the same task with different parameters:
```toml
[tasks.lint]
matrix.lang = ["javascript", "python", "rust"]
command = "echo 'Linting ${{lang}}...'"
```

### Cache Control
Disable caching for tasks that should always run:
```toml
[tasks.timestamp]
cache = false
```
