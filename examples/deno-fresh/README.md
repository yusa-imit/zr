# Deno Fresh Example

This example demonstrates using **zr** with a Deno project featuring:
- Modern Deno runtime with JSR imports
- HTTP server using @std/http
- TypeScript with strict mode
- Test suite with @std/assert
- Built-in formatting and linting

## Project Structure

```
deno-fresh/
├── deno.json          # Deno configuration with tasks and imports
├── main.ts            # HTTP server entry point
├── main_test.ts       # Test suite
├── zr.toml            # zr task definitions
└── README.md          # This file
```

## Auto-Detection

When you run `zr init --detect` in a Deno project, zr automatically generates tasks by parsing `deno.json`:

```bash
cd examples/deno-fresh
zr init --detect
```

**Detected tasks** (from deno.json):
- `dev` — Run with hot reload
- `start` — Run production server
- `test` — Run tests
- `fmt` — Format code
- `lint` — Lint code
- `check` — Type check

**Enhanced tasks** (added manually in zr.toml):
- `cache` — Cache dependencies with --reload
- `bundle` — Bundle to single file
- `compile` — Compile to native binary
- `bench` — Run benchmarks
- `coverage` — Generate test coverage report

## Quick Start

### 1. Install Dependencies (automatic with Deno)
Deno automatically caches dependencies on first use.

### 2. Run Development Server
```bash
zr dev
# or
zr run dev
```

Visit http://localhost:8000/

### 3. Run Tests
```bash
zr test
```

### 4. Format and Lint
```bash
zr fmt
zr lint
```

## Development Workflows

### Pre-Commit Workflow
```bash
zr workflow pre-commit
```
Runs: fmt → lint → test

### CI Workflow
```bash
zr workflow ci
```
Runs: [fmt + lint] → check → test

### Build for Production
```bash
zr workflow build
```
Runs: cache → check → test → [bundle + compile]

## Deno-Specific Features

### 1. Permission System
Deno requires explicit permissions:
```toml
[tasks.start]
cmd = "deno run --allow-net --allow-read main.ts"
```

### 2. JSR Imports
Modern Deno uses JSR (JavaScript Registry):
```json
"imports": {
  "@std/http": "jsr:@std/http@^1.0.0"
}
```

### 3. Native Compilation
Compile to standalone binary:
```bash
zr compile
# Creates: dist/server (no Deno runtime needed!)
```

### 4. Built-in Tools
Deno includes formatter, linter, and test runner:
```bash
zr fmt      # deno fmt
zr lint     # deno lint
zr test     # deno test
zr check    # deno check (type checking)
```

## Caching and Performance

### Cache Dependencies
```bash
zr cache
```
Downloads and caches all dependencies with --reload flag.

### Incremental Type Checking
```bash
zr check
```
Type checks without execution (fast).

## Testing

### Run Tests
```bash
zr test
```

### With Coverage
```bash
zr coverage
```

### Run Benchmarks
```bash
zr bench
```

## Comparison with deno.json Tasks

| Feature | deno.json tasks | zr |
|---------|----------------|-----|
| Basic tasks | ✅ | ✅ |
| Dependencies | ❌ | ✅ |
| Workflows/Pipelines | ❌ | ✅ |
| Parallel execution | ❌ | ✅ |
| Conditional tasks | ❌ | ✅ |
| Cross-platform | ❌ | ✅ |
| Monorepo support | ❌ | ✅ |

## Common Commands

```bash
# Development
zr dev              # Start with hot reload
zr test             # Run tests
zr fmt              # Format code
zr lint             # Lint code

# Production Build
zr bundle           # Bundle to single file
zr compile          # Compile to binary

# Quality Checks
zr check            # Type check
zr coverage         # Test coverage

# Workflows
zr workflow ci      # Full CI pipeline
zr workflow build   # Build pipeline
```

## Troubleshooting

### Permission Errors
If you get permission errors, check the `--allow-*` flags in tasks:
```toml
cmd = "deno run --allow-net --allow-read main.ts"
```

### Cache Issues
Clear Deno cache and reload:
```bash
rm -rf ~/.cache/deno
zr cache
```

### Import Errors
Ensure imports are in deno.json:
```json
"imports": {
  "@std/http": "jsr:@std/http@^1.0.0"
}
```

## Next Steps

1. Explore more Deno standard library: https://jsr.io/@std
2. Add database integration (Postgres, MongoDB)
3. Implement middleware and routing
4. Deploy to Deno Deploy: https://deno.com/deploy

## Learn More

- **Deno Manual**: https://docs.deno.com/
- **Deno Standard Library**: https://jsr.io/@std
- **zr Documentation**: https://github.com/yusa-imit/zr
