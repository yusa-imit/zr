# Go Modules Example

This example demonstrates how to use **zr** with Go projects using Go modules, showcasing task auto-detection, development workflows, and cross-platform builds.

## Project Structure

```
go-modules/
├── go.mod              # Go module definition
├── main.go             # Application entry point
├── cmd/                # Command implementations
│   ├── root.go         # Root command with Cobra
│   ├── greet.go        # Example subcommand
│   ├── greet_test.go   # Unit tests
│   └── version.go      # Version command
├── zr.toml             # Task definitions (auto-generated + enhanced)
└── README.md           # This file
```

## Quick Start

### 1. Auto-Detection

Generate a basic `zr.toml` automatically:

```bash
zr init --detect
```

This detects the Go project (via `go.mod`) and generates base tasks:
- `build` - Build the Go project
- `test` - Run Go tests
- `test-verbose` - Run tests with verbose output
- `test-coverage` - Run tests with coverage
- `vet` - Run go vet
- `fmt` - Format Go code
- `mod-tidy` - Tidy dependencies
- `run` - Run the application

### 2. Enhanced Configuration

The provided `zr.toml` extends the auto-detected tasks with:
- **Linting**: `golangci-lint` integration
- **Coverage**: HTML coverage reports
- **Cross-compilation**: Build for Linux, macOS, Windows
- **Workflows**: CI pipeline, pre-commit checks, release process

### 3. Common Commands

```bash
# List all available tasks
zr list

# Run tests
zr run test

# Run tests with coverage
zr run test-coverage

# Format code and run checks
zr run fmt
zr run vet

# Build the application
zr run build

# Run the application
zr run run
# Or with arguments
go run main.go greet --name Alice

# Cross-platform builds
zr run build-all

# Full CI pipeline
zr workflow ci
```

## Go-Specific Features

### Module Management

```toml
[tasks.mod-tidy]
description = "Tidy go.mod dependencies"
cmd = "go mod tidy"

[tasks.mod-verify]
description = "Verify dependencies"
cmd = "go mod verify"
```

### Testing with Coverage

```toml
[tasks.test-coverage]
description = "Run Go tests with coverage"
cmd = "go test -cover ./..."

[tasks.coverage-html]
description = "Generate HTML coverage report"
cmd = """
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
"""
```

### Cross-Compilation

Go makes cross-compilation trivial with `GOOS` and `GOARCH`:

```toml
[tasks.build-all]
description = "Build for multiple platforms"
cmd = """
GOOS=linux GOARCH=amd64 go build -o bin/gocli-linux-amd64
GOOS=darwin GOARCH=amd64 go build -o bin/gocli-darwin-amd64
GOOS=windows GOARCH=amd64 go build -o bin/gocli-windows-amd64.exe
"""
```

### Linting with golangci-lint

Install golangci-lint:

```bash
zr run install-tools
```

Run comprehensive linting:

```bash
zr run golangci-lint
```

## Workflows

### CI Pipeline

```bash
zr workflow ci
```

Runs:
1. **Setup**: Tidy dependencies
2. **Check**: Format, vet, lint (fail-fast)
3. **Test**: Coverage tests
4. **Build**: Create binary

### Pre-Commit Hook

```bash
zr workflow pre-commit
```

Quick checks before committing:
1. **Format**: Auto-format code
2. **Check**: Vet and test (fail-fast)

### Release Workflow

```bash
zr workflow release
```

Full release process:
1. **Verify**: Tidy deps, verbose tests, vet
2. **Build**: Cross-platform binaries

## Integration with Existing Tools

### Using with Make

If you have an existing `Makefile`:

```bash
zr init --from-make
```

Converts Make targets to zr tasks automatically.

### Using with go test

All standard `go test` flags work:

```bash
# Run specific test
go test -run TestGreetCommand ./cmd

# With race detector
zr run test -race

# Benchmark tests
go test -bench=. ./...
```

## Development Tips

### Watch Mode

Rebuild on file changes:

```bash
zr watch build
```

### Parallel Testing

Test multiple packages in parallel:

```bash
go test -p 4 ./...  # 4 parallel processes
```

### Debugging

Build with debug symbols:

```bash
go build -gcflags="all=-N -l" -o bin/gocli-debug
```

## Common Patterns

### Conditional Builds with Tags

```toml
[tasks.build-debug]
description = "Build with debug tags"
cmd = "go build -tags debug -o bin/gocli-debug"

[tasks.build-release]
description = "Build optimized release"
cmd = "go build -ldflags='-s -w' -o bin/gocli"
```

### Vendor Dependencies

```toml
[tasks.vendor]
description = "Vendor dependencies"
cmd = "go mod vendor"

[tasks.build-vendor]
description = "Build using vendored dependencies"
cmd = "go build -mod=vendor -o bin/gocli"
deps = ["vendor"]
```

### Generate Code

```toml
[tasks.generate]
description = "Run go generate"
cmd = "go generate ./..."
```

## Troubleshooting

### Issue: "go.mod not found"

Make sure you're in a Go module directory:

```bash
go mod init github.com/yourname/yourproject
```

### Issue: "golangci-lint command not found"

Install development tools:

```bash
zr run install-tools
```

Or install manually:

```bash
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
```

### Issue: Tests fail on CI

Ensure `go mod tidy` is run:

```bash
zr run mod-tidy
git add go.mod go.sum
git commit -m "chore: tidy dependencies"
```

## Performance

### Build Times

- **Cold build**: ~1-2s (depends on project size)
- **Incremental build**: ~100-500ms
- **With caching**: Near-instant for unchanged code

### Parallel Execution

zr runs independent tasks in parallel:

```toml
[workflows.parallel-checks]
stages = [
    { name = "all", tasks = ["fmt", "vet", "test"], parallel = true }
]
```

## Resources

- [Go Documentation](https://go.dev/doc/)
- [Cobra CLI Framework](https://github.com/spf13/cobra)
- [golangci-lint](https://golangci-lint.run/)
- [Go Testing](https://go.dev/doc/tutorial/add-a-test)

## Next Steps

1. **Customize tasks**: Add project-specific build steps
2. **Add benchmarks**: Use `go test -bench` for performance testing
3. **Set up CI/CD**: Use zr workflows in GitHub Actions
4. **Explore plugins**: Integrate with Docker, databases, cloud services

---

**Why zr for Go?**

✓ Auto-detects Go projects and suggests common tasks
✓ Unified task runner across polyglot projects
✓ Workflow orchestration for complex CI/CD
✓ Faster iteration with watch mode
✓ Consistent DX whether using Go, Rust, Node, Python, etc.
