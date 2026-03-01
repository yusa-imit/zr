# Bun Elysia Example

This example demonstrates using **zr** with a Bun project featuring:
- Bun runtime for ultra-fast JavaScript/TypeScript execution
- Elysia web framework (Express-like but faster)
- TypeScript with strict mode
- Built-in test runner (bun:test)
- Modern tooling (ESLint, Prettier)

## Project Structure

```
bun-elysia/
├── package.json       # Bun/npm configuration with scripts
├── tsconfig.json      # TypeScript configuration
├── index.ts           # Web server entry point
├── index.test.ts      # Test suite
├── zr.toml            # zr task definitions
└── README.md          # This file
```

## Auto-Detection

When you run `zr init --detect` in a Bun project, zr automatically generates tasks by parsing `package.json` scripts:

```bash
cd examples/bun-elysia
zr init --detect
```

**Detected tasks** (from package.json):
- `dev` — Run with hot reload
- `start` — Run production server
- `test` — Run tests
- `build` — Build for production
- `check` — Type check
- `lint` — Lint code
- `format` — Format code

**Enhanced tasks** (added manually in zr.toml):
- `install` — Install dependencies
- `clean` — Remove artifacts
- `compile` — Compile to standalone executable
- `bench` — Run benchmarks
- `test-watch` — Watch mode for tests
- `outdated` — Check dependency versions

## Quick Start

### 1. Install Bun
```bash
# macOS/Linux
curl -fsSL https://bun.sh/install | bash

# Windows
powershell -c "irm bun.sh/install.ps1 | iex"
```

### 2. Install Dependencies
```bash
zr install
# or
bun install
```

### 3. Run Development Server
```bash
zr dev
```

Visit http://localhost:3000/

### 4. Run Tests
```bash
zr test
```

## Development Workflows

### Pre-Commit Workflow
```bash
zr workflow pre-commit
```
Runs: format → lint → test

### CI Workflow
```bash
zr workflow ci
```
Runs: [format + lint] → check → test → build

### Full Quality Check
```bash
zr workflow full-check
```
Runs: install → [format + lint + check] → test → build

## Bun-Specific Features

### 1. Ultra-Fast Startup
Bun starts ~4x faster than Node.js:
```bash
time zr start  # ~10-20ms
```

### 2. Built-in Test Runner
No need for Jest/Vitest:
```typescript
import { describe, expect, test } from "bun:test";

test("addition", () => {
  expect(1 + 1).toBe(2);
});
```

### 3. Native TypeScript Support
No transpilation needed:
```bash
zr dev  # Directly runs .ts files
```

### 4. Standalone Compilation
Compile to single executable:
```bash
zr compile
# Creates: dist/server (no Bun runtime needed!)
```

### 5. Package Manager
Faster than npm/yarn/pnpm:
```bash
zr install     # Uses bun install
zr outdated    # Check for updates
```

## Performance Comparison

| Task | Node.js | Bun | Speedup |
|------|---------|-----|---------|
| Install deps | 15-30s | 2-5s | **3-6x** |
| Run tests | 500ms | 50ms | **10x** |
| Cold start | 80ms | 15ms | **5x** |
| Hot reload | 200ms | 20ms | **10x** |

## Testing

### Run Tests
```bash
zr test
```

### Watch Mode
```bash
zr test-watch
```

### Run Benchmarks
```bash
zr bench
```

## Building for Production

### Bundle
```bash
zr build
```
Creates optimized bundle in `dist/`.

### Compile to Binary
```bash
zr compile
```
Creates standalone executable (no Bun runtime needed):
```bash
./dist/server  # Run directly
```

## Comparison with package.json Scripts

| Feature | package.json scripts | zr |
|---------|---------------------|-----|
| Basic tasks | ✅ | ✅ |
| Dependencies | ❌ | ✅ |
| Workflows/Pipelines | ❌ | ✅ |
| Parallel execution | ❌ | ✅ |
| Conditional tasks | ❌ | ✅ |
| Cross-platform | ⚠️ (limited) | ✅ |
| Monorepo support | ⚠️ (workspaces only) | ✅ |

## Common Commands

```bash
# Development
zr install          # Install dependencies
zr dev              # Start with hot reload
zr test             # Run tests
zr test-watch       # Tests in watch mode

# Quality Checks
zr check            # Type check
zr lint             # Lint code
zr format           # Format code

# Production
zr build            # Bundle for production
zr compile          # Compile to binary
zr start            # Run production server

# Workflows
zr workflow ci      # Full CI pipeline
zr workflow pre-commit  # Pre-commit checks
```

## Troubleshooting

### Dependency Installation Fails
Clear Bun cache:
```bash
rm -rf node_modules bun.lockb
zr install
```

### Type Errors
Ensure @types/bun is installed:
```bash
bun add -d @types/bun
```

### Port Already in Use
Change port in index.ts:
```typescript
.listen(3000)  // Change to different port
```

### Outdated Bun Version
Update Bun:
```bash
bun upgrade
```

## Elysia Framework Features

Elysia is a Bun-first web framework with excellent ergonomics:

```typescript
import { Elysia } from "elysia";

new Elysia()
  .get("/", () => "Hello!")
  .post("/api/user", ({ body }) => body)
  .listen(3000);
```

**Features:**
- Type-safe routing
- Fast request parsing
- Minimal overhead
- Plugin system
- WebSocket support

## Next Steps

1. Add database integration (Prisma, Drizzle)
2. Implement authentication (JWT, sessions)
3. Add API routes with validation
4. Deploy to production (Fly.io, Railway)

## Learn More

- **Bun Documentation**: https://bun.sh/docs
- **Elysia Framework**: https://elysiajs.com/
- **Bun Examples**: https://github.com/oven-sh/bun/tree/main/examples
- **zr Documentation**: https://github.com/yusa-imit/zr
