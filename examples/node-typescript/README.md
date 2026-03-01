# Node.js TypeScript Example

This example demonstrates how to use **zr** with Node.js and TypeScript projects, showcasing task auto-detection, modern tooling integration, and development workflows.

## Project Structure

```
node-typescript/
├── package.json        # Node.js dependencies and npm scripts
├── tsconfig.json       # TypeScript configuration
├── vitest.config.ts    # Vitest test configuration
├── .eslintrc.json      # ESLint configuration
├── .prettierrc         # Prettier configuration
├── src/
│   ├── index.ts        # Main application code
│   └── index.test.ts   # Unit tests with Vitest
├── zr.toml             # Task definitions (auto-generated + enhanced)
└── README.md           # This file
```

## Quick Start

### 1. Auto-Detection

Generate a basic `zr.toml` automatically:

```bash
zr init --detect
```

This detects the Node.js project (via `package.json`) and generates tasks for all npm scripts:
- `build` - Compile TypeScript to JavaScript
- `dev` - Run in development mode with watch
- `start` - Start the compiled application
- `test` - Run unit tests
- `lint` - Lint TypeScript code
- `format` - Format code with Prettier
- `typecheck` - Type-check without emitting

### 2. Enhanced Configuration

The provided `zr.toml` extends the auto-detected tasks with:
- **Cache control**: Faster rebuilds with input/output tracking
- **Dependencies**: Automatic task ordering (build before start)
- **Workflows**: CI pipeline, pre-commit checks, release process
- **Cleanup tasks**: Clean build artifacts

### 3. Common Commands

```bash
# Install dependencies
npm install

# List all available tasks
zr list

# Development mode (watch + hot reload)
zr run dev

# Build for production
zr run build

# Run tests
zr run test

# Run tests with coverage
zr run test-coverage

# Lint and format
zr run lint
zr run format

# Type checking
zr run typecheck

# Full CI pipeline
zr workflow ci

# Pre-commit checks
zr workflow pre-commit
```

## TypeScript-Specific Features

### Build Configuration

```toml
[tasks.build]
description = "Compile TypeScript to JavaScript"
cmd = "npm run build"

[tasks.build.cache]
inputs = ["src/**/*.ts", "tsconfig.json"]
outputs = ["dist/"]
```

With caching enabled, rebuilds only happen when source files change.

### Type Checking

```toml
[tasks.typecheck]
description = "Type-check without emitting"
cmd = "npm run typecheck"

[tasks.check-types]
description = "Comprehensive type checking"
cmd = "tsc --noEmit --pretty"
```

Fast type checking without generating JavaScript files.

### Testing with Vitest

```toml
[tasks.test]
description = "Run unit tests"
cmd = "npm run test"

[tasks.test-watch]
description = "Run tests in watch mode"
cmd = "npm run test:watch"

[tasks.test-coverage]
description = "Run tests with coverage report"
cmd = "npm run test:coverage"
```

Vitest provides fast, modern testing with TypeScript support.

### Linting and Formatting

```toml
[tasks.lint]
description = "Lint TypeScript code"
cmd = "npm run lint"

[tasks.lint-fix]
description = "Lint and auto-fix issues"
cmd = "npm run lint:fix"

[tasks.format]
description = "Format code with Prettier"
cmd = "npm run format"

[tasks.format-check]
description = "Check code formatting"
cmd = "npm run format:check"
```

ESLint for code quality, Prettier for formatting.

## Workflows

### CI Pipeline

```bash
zr workflow ci
```

Runs:
1. **Setup**: Install dependencies
2. **Quality**: Format check, lint, typecheck (fail-fast)
3. **Test**: Coverage tests
4. **Build**: TypeScript compilation

### Pre-Commit Hook

```bash
zr workflow pre-commit
```

Quick checks before committing:
1. **Format**: Auto-format code
2. **Check**: Lint, typecheck, test (fail-fast)

Configure with git hooks:

```bash
# .git/hooks/pre-commit
#!/bin/sh
zr workflow pre-commit
```

### Release Workflow

```bash
zr workflow release
```

Full release process:
1. **Verify**: Clean install, full test coverage, lint, typecheck
2. **Build**: Create npm package bundle

## Watch Mode

Use zr's watch mode for rapid development:

```bash
# Rebuild on file changes
zr watch build

# Re-run tests on changes
zr watch test
```

Or use the dev task with built-in watch:

```bash
zr run dev  # Uses tsx watch for hot reload
```

## Caching

Enable caching for faster rebuilds:

```toml
[cache]
enabled = true

[tasks.build.cache]
inputs = ["src/**/*.ts", "tsconfig.json"]
outputs = ["dist/"]
```

zr tracks file changes and skips tasks when inputs haven't changed.

## Integration with Existing Tools

### npm scripts

All npm scripts are automatically detected and wrapped:

```bash
# These are equivalent
npm run build
zr run build
```

Benefits of using zr:
- ✓ Dependency management (run build before start)
- ✓ Parallel execution of independent tasks
- ✓ Caching for faster rebuilds
- ✓ Unified interface across projects

### Migration from npm

```bash
zr init --detect
```

Automatically generates zr.toml from package.json scripts.

## Development Tips

### Source Maps

Enable source maps in `tsconfig.json`:

```json
{
  "compilerOptions": {
    "sourceMap": true
  }
}
```

This allows debugging TypeScript in the browser or with Node.js inspector.

### Declaration Files

Generate type declarations for library projects:

```json
{
  "compilerOptions": {
    "declaration": true,
    "declarationMap": true
  }
}
```

### Incremental Builds

Speed up TypeScript compilation:

```json
{
  "compilerOptions": {
    "incremental": true
  }
}
```

## Common Patterns

### Environment-Specific Builds

```toml
[tasks.build-dev]
description = "Build for development"
cmd = "tsc --sourceMap"
env = { NODE_ENV = "development" }

[tasks.build-prod]
description = "Build for production"
cmd = "tsc --sourceMap false"
env = { NODE_ENV = "production" }
```

### Parallel Linting and Testing

```toml
[workflows.fast-check]
stages = [
    { name = "all", tasks = ["lint", "test", "typecheck"], parallel = true }
]
```

### Matrix Testing (Node Versions)

```toml
[tasks.test]
cmd = "npm test"
matrix.node_version = ["18", "20", "21"]
```

## Troubleshooting

### Issue: "Cannot find module"

Rebuild TypeScript:

```bash
zr run clean
zr run build
```

### Issue: "Type errors in tests"

Ensure vitest types are included:

```json
{
  "compilerOptions": {
    "types": ["vitest/globals"]
  }
}
```

### Issue: ESLint errors

Auto-fix common issues:

```bash
zr run lint-fix
```

### Issue: Slow tests

Use Vitest's watch mode with filters:

```bash
npx vitest --watch --testNamePattern="greet"
```

## Performance

### Build Times

- **Cold build**: ~2-5s (depends on project size)
- **Incremental build**: ~500ms-1s
- **With caching (no changes)**: ~10ms (zr cache hit)

### Test Performance

Vitest is significantly faster than Jest:
- Parallel test execution
- ESM-native (no transpilation needed)
- Fast watch mode with HMR

## Resources

- [TypeScript Documentation](https://www.typescriptlang.org/docs/)
- [Vitest](https://vitest.dev/)
- [ESLint](https://eslint.org/)
- [Prettier](https://prettier.io/)
- [tsx (TypeScript executor)](https://github.com/esbuild-kit/tsx)

## Next Steps

1. **Add more tests**: Increase coverage with unit and integration tests
2. **Set up CI/CD**: Use zr workflows in GitHub Actions
3. **Bundle optimization**: Add esbuild or Vite for smaller bundles
4. **Monorepo**: Use zr's workspace features for multi-package projects

---

**Why zr for Node.js?**

✓ Auto-detects npm scripts and generates tasks
✓ Adds caching for faster builds (not available in npm)
✓ Task dependencies ensure correct execution order
✓ Workflows for complex multi-step operations
✓ Consistent DX across Node, Go, Rust, Python, etc.
✓ Watch mode works across all task types
