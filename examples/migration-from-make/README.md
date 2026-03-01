# Migrating from Make to zr

This example demonstrates how to migrate a real-world C project from Makefile to zr, showcasing both automated migration and manual enhancements.

## The Original Project

`Makefile.original` shows a typical C project build configuration with:
- Incremental compilation with pattern rules
- Multiple targets (build, test, coverage, lint, format)
- Phony targets for non-file outputs
- Variables for compiler flags and directories

## Step 1: Automated Migration

Run the migration command in your project directory:

```bash
zr init --from-make
```

This analyzes your Makefile and generates `zr.toml` with:
- All targets converted to `[tasks.*]` sections
- Dependencies preserved (e.g., `test` depends on `build`)
- Commands extracted and properly escaped for TOML
- Comments indicating the migration source

### What Gets Converted Automatically

✅ **Simple targets** → `[tasks.name]`
```makefile
# Makefile
test: build
    ./test_runner.sh
```
```toml
# zr.toml
[tasks.test]
deps = ["build"]
cmd = "./test_runner.sh"
```

✅ **Pattern rules** → Inline commands
```makefile
# Makefile
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
    $(CC) $(CFLAGS) -c $< -o $@
```
```toml
# zr.toml (expanded)
[tasks.build]
cmd = """
gcc -Wall -Wextra -O2 -std=c11 -c src/*.c -o build/*.o
"""
```

✅ **Dependencies** → `deps = [...]`
```makefile
# Makefile
all: build test
```
```toml
# zr.toml
[tasks.all]
deps = ["build", "test"]
```

### What Requires Manual Enhancement

❌ **Variables/patterns** — Expanded to concrete values
❌ **Conditional logic** — Use zr expressions instead
❌ **Make-specific features** — Use zr equivalents (matrix, workflows, cache)

## Step 2: Manual Enhancements

After migration, you can leverage zr-specific features that Make doesn't support:

### 1. **Caching** — Speed up repeated builds

```toml
[tasks."build:release"]
description = "Build optimized release binary"
cmd = "gcc -O3 -flto src/*.c -o myapp"
cache = true  # ← Only rebuild if source files change
```

With Make, you need manual `.d` file tracking. With zr, just add `cache = true`.

### 2. **Workflows** — Multi-stage pipelines with approval gates

```toml
[workflow.release]
stages = [
  { name = "quality", tasks = ["lint", "format"], fail_fast = true },
  { name = "test", tasks = ["test", "bench"], fail_fast = true },
  { name = "build", tasks = ["build:release"] },
  { name = "install", tasks = ["install"], approval = true }  # ← Requires confirmation
]
```

Run with: `zr workflow release`

### 3. **Matrix Builds** — Test across multiple configurations

```toml
[matrix.optimization]
values = ["O0", "O1", "O2", "O3"]

[tasks."build:matrix"]
cmd = "gcc -${matrix.optimization} src/*.c -o myapp"
```

Run with: `zr run build:matrix` (generates 4 tasks automatically)

### 4. **Conditional Execution** — Platform-specific builds

```toml
[tasks."build:linux"]
condition = 'platform.is_linux'
cmd = "gcc src/*.c -lm -o myapp"

[tasks."build:macos"]
condition = 'platform.is_macos'
cmd = "gcc src/*.c -framework CoreFoundation -o myapp"
```

Automatically runs the correct variant based on your OS.

### 5. **Watch Mode** — Auto-rebuild on file changes

```bash
zr watch build src/
```

Make requires external tools like `inotifywait`. zr has native filesystem watchers.

### 6. **Interactive TUI** — Visual task selection

```bash
zr interactive
```

Pick tasks with arrow keys, see live logs, cancel with Ctrl+C.

## Comparison: Make vs zr

| Feature | Make | zr |
|---------|------|-----|
| **Learning curve** | Steep (pattern rules, automatic variables) | Gentle (plain TOML) |
| **Caching** | Manual `.d` files | `cache = true` |
| **Watch mode** | External (`inotifywait`) | Built-in |
| **Workflows** | Hack with `.PHONY` chains | First-class `[workflow]` |
| **Matrix builds** | Write loops manually | `[matrix]` auto-expansion |
| **Conditionals** | `ifeq`/`ifdef` (limited) | Full expression engine |
| **Parallelism** | `-j` flag | Worker pool (automatic) |
| **Portability** | GNU Make vs BSD Make | Single binary |
| **Error messages** | Cryptic | User-friendly with hints |

## Migration Checklist

After running `zr init --from-make`, review your `zr.toml`:

- [ ] Verify all targets were converted (compare with `make -p`)
- [ ] Test each task: `zr run <task>`
- [ ] Check dependencies are correct: `zr graph --ascii`
- [ ] Add `cache = true` to expensive builds
- [ ] Group related tasks into workflows
- [ ] Add descriptions for documentation
- [ ] Use matrix for cross-configuration testing
- [ ] Replace `clean` with zr's built-in: `zr clean --cache`
- [ ] Update CI scripts to use `zr run` instead of `make`
- [ ] Add watch mode to development workflow

## Common Issues During Migration

### Issue 1: Pattern Rules Not Expanding

**Problem:** Make pattern rules like `%.o: %.c` don't have direct TOML equivalents.

**Solution:** The migrator expands these to concrete commands. Review and optimize:

```toml
# Auto-generated (verbose)
[tasks.build]
cmd = """
gcc -c src/main.c -o build/main.o
gcc -c src/utils.c -o build/utils.o
gcc build/main.o build/utils.o -o myapp
"""

# Optimized (use shell globbing)
[tasks.build]
cmd = """
mkdir -p build
gcc -c src/*.c
mv *.o build/
gcc build/*.o -o myapp
"""
```

### Issue 2: Make Variables Not Substituted

**Problem:** `$(CC)`, `$(CFLAGS)` are hardcoded in migrated config.

**Solution:** Use zr environment variables:

```toml
[tasks.build]
env = { CC = "gcc", CFLAGS = "-Wall -O2" }
cmd = "${env.CC} ${env.CFLAGS} src/*.c -o myapp"
```

### Issue 3: Recursive Make Calls

**Problem:** Makefiles with `$(MAKE) -C subdir` don't translate well.

**Solution:** Use zr workspace feature:

```toml
# Root zr.toml
[workspace]
members = ["subdir1", "subdir2"]

[tasks.build]
deps = ["@subdir1:build", "@subdir2:build"]
```

Run with: `zr workspace run build`

## Next Steps

1. **Test thoroughly:** Run `zr run <task>` for each migrated target
2. **Leverage new features:** Add caching, workflows, matrix builds
3. **Update CI:** Change GitHub Actions from `make` to `zr run`
4. **Document:** Add `description` fields to all tasks
5. **Share:** Commit `zr.toml` and delete `Makefile`

## Resources

- [zr Configuration Guide](../../docs/guides/configuration.md)
- [zr Workflow Documentation](../../docs/guides/workflows.md)
- [Make to zr Migration Script](../../docs/guides/migration.md)
- [Expression Engine Reference](../../docs/guides/expressions.md)

## Real-World Example

This example is based on common C project patterns seen in:
- GNU coreutils
- Redis
- Nginx
- SQLite build systems

The migration preserves all functionality while adding modern features like caching, watch mode, and cross-platform conditionals.
