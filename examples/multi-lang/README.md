# Multi-Language Project Example

This example demonstrates how to use zr to orchestrate builds and tests across a polyglot codebase with multiple programming languages.

## Project Structure

```
polyglot-app/
├── zr.toml                 # Orchestrates all languages
├── frontend/               # TypeScript/Node.js
│   ├── package.json
│   └── src/
├── backend/                # Python
│   ├── requirements.txt
│   └── src/
├── infra/                  # Go
│   ├── go.mod
│   └── cmd/
├── cli-tool/               # Rust
│   ├── Cargo.toml
│   └── src/
└── Dockerfile
```

## Languages Supported in This Example

- **TypeScript/Node.js** - Frontend application
- **Python** - Backend API
- **Go** - Infrastructure tooling
- **Rust** - CLI utilities
- **SQL** - Database migrations

## Features Demonstrated

- **Language-agnostic task orchestration** - Run tasks in any language
- **Per-directory execution** - Each task runs in its language-specific directory
- **Dependency management** - Install dependencies before build/test
- **Cross-language dependencies** - Frontend depends on backend API types
- **Unified CI pipeline** - Single command runs all linters, tests, builds

## Usage

```bash
# Build all components (TypeScript, Go, Rust)
zr run build

# Test all components
zr run test

# Run full CI pipeline (lint + test + build)
zr run ci

# Build specific component
zr run frontend-build
zr run backend-test
zr run cli-build

# Docker build (includes all build steps)
zr run docker-build
```

## Benefits Over Language-Specific Tools

Instead of running:
```bash
cd frontend && npm run build && cd ..
cd backend && source venv/bin/activate && pytest && cd ..
cd infra && go build ./... && cd ..
cd cli-tool && cargo build --release && cd ..
```

You run:
```bash
zr run build
zr run test
```

## Parallel Execution

zr automatically runs independent tasks in parallel:

```bash
# These run in parallel:
# - frontend-build
# - infra-build
# - cli-build
zr run build
```

## Caching

Each language's build outputs are tracked:
- `frontend/dist/` - Frontend build artifacts
- `infra/bin/` - Go binaries
- `cli-tool/target/release/` - Rust binaries

zr skips rebuilds if inputs haven't changed.

## Adding a New Language

To add support for another language (e.g., Java):

```toml
[tasks.java-build]
command = "mvn clean package"
description = "Build Java service"
cwd = "./java-service"
outputs = ["java-service/target/"]

[tasks.build]
deps = ["frontend-build", "java-build", "infra-build", "cli-build"]
```

## Environment Variables

Set language-specific environment variables:

```toml
[tasks.backend-test]
env = {
    PYTHONPATH = "src/",
    TESTING = "true"
}
```
