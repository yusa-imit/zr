# Migrating to zr

This guide helps you migrate from Make, Just, or Task (go-task) to zr with automated conversion tools.

## Quick Start

zr provides automatic migration from popular task runners:

```bash
# From package.json (npm scripts)
zr init --from-npm

# From Makefile
zr init --from-make

# From Justfile
zr init --from-just

# From Taskfile.yml
zr init --from-task
```

These commands parse your existing configuration and generate a `zr.toml` file with equivalent task definitions.

---

## Migrating from npm (package.json)

### Prerequisites

- You have a `package.json` with a `scripts` section in your project directory
- Run `zr init --from-npm` from the same directory

### What Gets Converted

The migration tool extracts:

| package.json Feature | zr Equivalent | Notes |
|---------------------|---------------|-------|
| Script definitions | `[tasks.*]` | Each script becomes a task |
| `npm run` dependencies | `deps = [...]` | Auto-detected from command patterns |
| Pre/post hooks | `deps = [...]` | `prebuild` → dependency, `postbuild` → separate task |
| `run-s` / `run-p` | `deps = [...]` | Sequential patterns converted to deps |
| Environment variables | Manual conversion | Add `env = {...}` as needed |

### Example

**Before (package.json):**

```json
{
  "name": "my-app",
  "scripts": {
    "clean": "rm -rf dist",
    "compile": "tsc",
    "prebuild": "npm run clean",
    "build": "npm run compile",
    "postbuild": "npm run copy-assets",
    "test": "jest",
    "dev": "vite"
  }
}
```

**After (zr.toml):**

```toml
# zr.toml — migrated from package.json by `zr init --from-npm`

[global]
shell = "bash"

[tasks.clean]
cmd = "rm -rf dist"

[tasks.compile]
cmd = "tsc"

[tasks.prebuild]
cmd = "npm run clean"

[tasks.build]
deps = ["prebuild"]
cmd = "npm run compile"

[tasks.postbuild]
deps = ["build"]
cmd = "npm run copy-assets"

[tasks.test]
cmd = "jest"

[tasks.dev]
cmd = "vite"
```

### Dependency Detection

The migration tool automatically detects task dependencies from command patterns:

**Pattern 1: `npm run` commands**

```json
{
  "scripts": {
    "build": "npm run clean && npm run compile"
  }
}
```

Converts to:

```toml
[tasks.build]
deps = ["clean", "compile"]
cmd = "npm run clean && npm run compile"
```

**Pattern 2: `npm-run-all` sequential**

```json
{
  "scripts": {
    "build": "run-s clean compile test"
  }
}
```

Converts to:

```toml
[tasks.build]
deps = ["clean", "compile", "test"]
cmd = "run-s clean compile test"
```

**Pattern 3: Pre/post hooks**

```json
{
  "scripts": {
    "prebuild": "npm run lint",
    "build": "tsc",
    "postbuild": "npm run minify"
  }
}
```

Converts to:

```toml
[tasks.prebuild]
cmd = "npm run lint"

[tasks.build]
deps = ["prebuild"]
cmd = "tsc"

[tasks.postbuild]
deps = ["build"]
cmd = "npm run minify"
```

### Manual Adjustments

After migration, you may want to:

1. **Add descriptions** for better documentation:
   ```toml
   [tasks.build]
   description = "Build the TypeScript project"
   deps = ["prebuild"]
   cmd = "tsc"
   ```

2. **Replace `npm run` with direct commands** for better performance:
   ```toml
   # Before (keeps npm run wrapper)
   [tasks.test]
   deps = ["build"]
   cmd = "npm run test"

   # After (direct command)
   [tasks.test]
   deps = ["build"]
   cmd = "jest"
   ```

3. **Convert parallel patterns to zr's native parallelism**:
   ```json
   // package.json (npm-run-all parallel)
   {
     "scripts": {
       "watch": "run-p watch:*"
     }
   }
   ```

   Becomes:
   ```toml
   # zr.toml (zr runs deps in parallel by default)
   [tasks.watch]
   deps = ["watch-ts", "watch-css", "watch-js"]
   cmd = "echo 'All watchers started'"

   [tasks.watch-ts]
   cmd = "tsc --watch"

   [tasks.watch-css]
   cmd = "sass --watch src:dist"

   [tasks.watch-js]
   cmd = "rollup --watch"
   ```

4. **Add environment variables**:
   ```toml
   [tasks.build]
   env = { NODE_ENV = "production", INLINE_RUNTIME_CHUNK = "false" }
   cmd = "react-scripts build"
   ```

5. **Enable features not available in npm scripts**:
   ```toml
   [tasks.build]
   description = "Build for production"
   cache = { inputs = ["src/**/*.ts", "package.json"], outputs = ["dist/"] }
   cmd = "tsc"

   [tasks.dev]
   description = "Development server with hot reload"
   watch = ["src/**/*.ts", "!**/*.test.ts"]
   cmd = "vite"
   ```

### Known Limitations

- **Complex npm-run-all patterns**: Wildcards like `run-p watch:*` require manual expansion
- **Custom npm lifecycle hooks**: Hooks like `prepare`, `preinstall` are not migrated (use zr's hooks system)
- **npm variables**: `$npm_package_version` etc. must be converted to expressions or env vars
- **Conditional scripts**: Scripts with `&&` / `||` logic may need review for proper dependency ordering

### Migration from Monorepo Tools

If you're using npm workspaces with **Turborepo** or **Lerna**, consider these approaches:

**Turborepo pipeline.json:**

```json
{
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**"]
    }
  }
}
```

**zr workspace equivalent:**

```toml
# root zr.toml
[workspace]
members = ["packages/*"]

[workspace.shared_tasks.build]
description = "Build package"
cmd = "tsc"
cache = { outputs = ["dist/"] }
```

**Lerna scripts:**

Convert lerna commands to zr workspace commands:

```bash
# Before
lerna run build --stream

# After
zr workspace run build
```

---

## Migrating from Make

### Prerequisites

- You have a `Makefile` in your project directory
- Run `zr init --from-make` from the same directory

### What Gets Converted

The migration tool extracts:

| Makefile Feature | zr Equivalent | Notes |
|-----------------|---------------|-------|
| Target definitions | `[tasks.*]` | Each target becomes a task |
| Dependencies | `deps = [...]` | Prerequisites are converted to deps |
| Commands | `cmd = "..."` | Single or multi-line commands |
| `.PHONY` targets | Preserved | Automatically recognized as tasks |
| Variables | `env = {...}` | Some variables may need manual conversion |

### Example

**Before (Makefile):**

```makefile
.PHONY: build test clean

build: deps
	npm run build

test: build
	npm test

clean:
	rm -rf dist/
```

**After (zr.toml):**

```toml
# zr.toml — migrated from Makefile by `zr init --from-make`

[global]
shell = "bash"

[tasks.build]
deps = ["deps"]
cmd = "npm run build"

[tasks.test]
deps = ["build"]
cmd = "npm test"

[tasks.clean]
cmd = "rm -rf dist/"
```

### Manual Adjustments

After migration, you may want to:

1. **Add descriptions** for better documentation:
   ```toml
   [tasks.build]
   description = "Build the project"
   deps = ["deps"]
   cmd = "npm run build"
   ```

2. **Convert Make variables** to environment variables:
   ```toml
   [tasks.deploy]
   env = { VERSION = "1.0.0", ENV = "production" }
   cmd = "deploy.sh ${VERSION} ${ENV}"
   ```

3. **Use zr expressions** for conditional logic:
   ```toml
   [tasks.build]
   skip_if = "os.platform() == 'windows'"
   cmd = "make native"
   ```

### Known Limitations

- **Complex shell syntax**: Make's shell features (subshells, conditionals) may need manual conversion
- **Pattern rules** (`%.o: %.c`): Not auto-converted, use matrix tasks instead
- **Recursive Make**: Convert to zr workspace configuration
- **Special variables** (`$@`, `$<`, `$^`): Must be manually converted to shell equivalents

---

## Migrating from Just

### Prerequisites

- You have a `justfile` or `Justfile` in your project directory
- Run `zr init --from-just` from the same directory

### What Gets Converted

| Justfile Feature | zr Equivalent | Notes |
|-----------------|---------------|-------|
| Recipe definitions | `[tasks.*]` | Each recipe becomes a task |
| Dependencies | `deps = [...]` | Recipe dependencies preserved |
| Commands | `cmd = "..."` | Recipe body converted to command |
| Shebang recipes | `cmd = "..."` | Shebang line preserved in command |
| Parameters | Manual conversion | See below for alternatives |

### Example

**Before (justfile):**

```just
# Build the project
build:
    cargo build --release

# Run tests
test: build
    cargo test

# Clean build artifacts
clean:
    cargo clean
```

**After (zr.toml):**

```toml
# zr.toml — migrated from justfile by `zr init --from-just`

[global]
shell = "bash"

[tasks.build]
description = "Build the project"
cmd = "cargo build --release"

[tasks.test]
description = "Run tests"
deps = ["build"]
cmd = "cargo test"

[tasks.clean]
description = "Clean build artifacts"
cmd = "cargo clean"
```

### Handling Recipe Parameters

Just recipes with parameters need manual conversion to zr's approach:

**Just with parameters:**

```just
deploy environment version:
    scp ./app {{environment}}-server:/apps/{{version}}/
```

**zr alternatives:**

**Option 1: Environment variables**

```toml
[tasks.deploy]
description = "Deploy to server"
cmd = "scp ./app ${ENVIRONMENT}-server:/apps/${VERSION}/"
```

Usage: `ENVIRONMENT=staging VERSION=1.2.0 zr run deploy`

**Option 2: Task matrix**

```toml
[tasks.deploy]
description = "Deploy to server"
cmd = "scp ./app ${ENVIRONMENT}-server:/apps/${VERSION}/"

[[tasks.deploy.matrix]]
ENVIRONMENT = ["staging", "production"]
VERSION = ["1.2.0", "1.3.0"]
```

Usage: `zr run deploy --matrix`

**Option 3: Workflow stages**

```toml
[workflows.deploy]
description = "Deployment pipeline"

[[workflows.deploy.stages]]
name = "Set environment"
tasks = ["set-env"]

[[workflows.deploy.stages]]
name = "Deploy"
tasks = ["deploy"]

[tasks.set-env]
cmd = "export ENVIRONMENT=staging VERSION=1.2.0"

[tasks.deploy]
cmd = "scp ./app ${ENVIRONMENT}-server:/apps/${VERSION}/"
```

---

## Migrating from Task (go-task)

### Prerequisites

- You have a `Taskfile.yml` in your project directory
- Run `zr init --from-task` from the same directory

### What Gets Converted

| Task Feature | zr Equivalent | Notes |
|-------------|---------------|-------|
| Task definitions | `[tasks.*]` | Each task converts 1:1 |
| Dependencies | `deps = [...]` | `deps:` array preserved |
| Commands | `cmd = "..."` | Multi-command tasks joined with `;` or `&&` |
| Environment variables | `env = {...}` | `env:` map converted |
| `desc` field | `description` | Task descriptions preserved |
| `silent` flag | Manual conversion | Use `2>/dev/null` in command or zr's `quiet` option |
| `sources` / `generates` | Manual conversion | Use zr's `watch` mode or cache |

### Example

**Before (Taskfile.yml):**

```yaml
version: '3'

tasks:
  build:
    desc: Build the application
    cmds:
      - go build -o bin/app .
    env:
      CGO_ENABLED: "0"

  test:
    desc: Run tests
    deps: [build]
    cmds:
      - go test ./...

  clean:
    desc: Remove build artifacts
    cmds:
      - rm -rf bin/
```

**After (zr.toml):**

```toml
# zr.toml — migrated from Taskfile.yml by `zr init --from-task`

[global]
shell = "bash"

[tasks.build]
description = "Build the application"
env = { CGO_ENABLED = "0" }
cmd = "go build -o bin/app ."

[tasks.test]
description = "Run tests"
deps = ["build"]
cmd = "go test ./..."

[tasks.clean]
description = "Remove build artifacts"
cmd = "rm -rf bin/"
```

### Handling Advanced Task Features

**Multi-command tasks** — Task YAML with multiple `cmds` entries:

```yaml
# Taskfile.yml
tasks:
  deploy:
    cmds:
      - docker build -t myapp .
      - docker push myapp:latest
      - kubectl apply -f k8s/
```

Converts to sequential execution:

```toml
# zr.toml
[tasks.deploy]
cmd = "docker build -t myapp . && docker push myapp:latest && kubectl apply -f k8s/"
```

Or split into separate tasks for better granularity:

```toml
[tasks.build-image]
cmd = "docker build -t myapp ."

[tasks.push-image]
deps = ["build-image"]
cmd = "docker push myapp:latest"

[tasks.deploy-k8s]
deps = ["push-image"]
cmd = "kubectl apply -f k8s/"

[workflows.deploy]
description = "Full deployment pipeline"
stages = [
  { name = "Build", tasks = ["build-image"] },
  { name = "Push", tasks = ["push-image"] },
  { name = "Deploy", tasks = ["deploy-k8s"] },
]
```

**File watching** — Task's `sources` / `generates`:

Task doesn't auto-convert watch patterns. Use zr's native watch mode:

```toml
[tasks.build]
cmd = "go build ."
watch = ["**/*.go", "!**/*_test.go"]
debounce_ms = 500
```

Run with: `zr run build --watch`

---

## Post-Migration Checklist

After running the migration command, review your generated `zr.toml`:

- [ ] **Test all tasks**: Run `zr list` and verify all expected tasks appear
- [ ] **Check dependencies**: Ensure `deps` arrays are correct with `zr graph <task>`
- [ ] **Add descriptions**: Enhance with human-readable descriptions
- [ ] **Validate syntax**: Run `zr validate` to check for errors
- [ ] **Update CI/CD**: Replace old tool commands with `zr run <task>`
- [ ] **Enable features**: Consider adding:
  - `watch` mode for development tasks
  - `cache` for expensive build tasks
  - `profiles` for different environments
  - `workflows` for multi-stage pipelines
  - `matrix` for parameterized tasks

---

## Troubleshooting

### Migration Command Fails

**Error**: `init: Makefile not found: FileNotFound`

**Solution**: Ensure you're running the command from the directory containing your Makefile/Justfile/Taskfile.yml.

---

### Tasks Not Running After Migration

**Error**: `run: Task 'xyz' not found`

**Solution**: Check that task names were converted correctly:

```bash
# List all migrated tasks
zr list

# View task definition
zr show xyz
```

Some tools allow special characters in task names that zr doesn't support. Rename them manually:

```toml
# Before (invalid)
[tasks."ci:build"]

# After (valid)
[tasks.ci-build]
```

---

### Environment Variables Not Working

**Problem**: Variables from Makefile/Taskfile not carrying over

**Solution**: Explicitly define environment in zr.toml:

```toml
[global.env]
NODE_ENV = "production"

[tasks.build]
env = { BUILD_VERSION = "1.0.0" }
cmd = "npm run build"
```

Or use `zr env set`:

```bash
zr env set NODE_ENV production
zr env set BUILD_VERSION 1.0.0
```

---

### Dependencies Not Executing in Order

**Problem**: Tasks run in parallel when they should be sequential

**Solution**: Use `deps_serial` for strict ordering:

```toml
[tasks.deploy]
deps_serial = ["lint", "test", "build"]
cmd = "kubectl apply -f k8s/"
```

---

## Getting Help

- **Documentation**: Check other guides in `docs/guides/`
- **Configuration Reference**: `docs/guides/configuration.md`
- **Command Reference**: `docs/guides/commands.md`
- **Issues**: [GitHub Issues](https://github.com/yusa-imit/zr/issues)
- **Examples**: See `examples/` directory for real-world zr.toml files

---

## Next Steps

After successful migration:

1. **Read the Getting Started guide**: `docs/guides/getting-started.md`
2. **Explore zr features** that your old tool didn't have:
   - Workflow pipelines with stages
   - Expression engine for conditional execution
   - Resource limits and monitoring
   - Interactive TUI mode
   - Plugin system
   - MCP/LSP integration for AI tools

3. **Optimize your setup**:
   - Enable caching for slow tasks
   - Add watch mode for development
   - Configure profiles for different environments
   - Set up hooks for pre/post task execution

Welcome to zr! 🚀
