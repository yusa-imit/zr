# Contributing to zr

Thank you for your interest in contributing to **zr**! This guide will help you get started.

---

## Quick Start for Contributors

### Prerequisites

- **Zig 0.15.2**: Download from [ziglang.org/download](https://ziglang.org/download/)
- **Git**: For version control
- **GitHub Account**: For pull requests

### Development Setup

```bash
# Clone the repository
git clone https://github.com/yusa-imit/zr.git
cd zr

# Build in debug mode
zig build

# Run tests
zig build test

# Run integration tests
zig build integration-test

# Build optimized binary
zig build -Doptimize=ReleaseSmall
```

---

## Project Structure

```
zr/
├── src/              # Source code
│   ├── cli/          # Command implementations (34 modules)
│   ├── config/       # TOML parsing & validation
│   ├── exec/         # Task execution engine
│   ├── graph/        # DAG & topological sort
│   ├── plugin/       # Plugin system
│   ├── lsp/          # Language Server Protocol
│   ├── mcp/          # Model Context Protocol
│   └── main.zig      # Entry point
├── tests/            # Integration tests (42 test modules)
├── examples/         # Example projects (11 examples)
├── docs/             # Documentation
│   ├── guides/       # User guides (6 guides)
│   └── PRD.md        # Product Requirements Document
└── .claude/          # AI development tools
```

---

## How to Contribute

### 1. Find an Issue

- Browse [open issues](https://github.com/yusa-imit/zr/issues)
- Look for issues tagged `good first issue` or `help wanted`
- Or propose a new feature via [discussions](https://github.com/yusa-imit/zr/discussions)

### 2. Create a Branch

```bash
git checkout -b feat/your-feature-name
# or
git checkout -b fix/bug-description
```

Branch naming:
- `feat/` — New features
- `fix/` — Bug fixes
- `refactor/` — Code refactoring
- `docs/` — Documentation changes
- `test/` — Test additions/improvements

### 3. Make Your Changes

**Coding Standards**:
- Follow Zig conventions: `camelCase` for functions, `PascalCase` for types
- Run `zig fmt` before committing (automatically done via pre-commit hook)
- Add tests for all new functionality
- Ensure all tests pass: `zig build test && zig build integration-test`
- Keep functions under 100 lines; split large functions into helpers
- Add comments only where logic is non-obvious

**Memory Safety**:
- Always use error handling (`try`, `catch`, explicit error unions)
- Never use `catch unreachable` in production code (tests are OK)
- Prefer arena allocators for request-scoped work
- All public functions must have corresponding tests

### 4. Write Tests

**Unit Tests**:
- Add tests in the same file as the code (bottom of file)
- Use descriptive test names: `test "descriptive behavior"`
- Test edge cases, error paths, and typical usage

**Integration Tests**:
- Add to `tests/<feature>_test.zig`
- Use helper functions from `tests/helpers.zig`
- Test CLI behavior end-to-end via `runZr()` helper

Example:
```zig
test "run: executes simple task" {
    const tmp = try helpers.tmpDir();
    defer tmp.cleanup();
    
    const config_path = try helpers.writeTmpConfig(tmp.dir,
        \\[tasks.hello]
        \\cmd = "echo hello"
    );
    defer tmp.allocator.free(config_path);
    
    const result = try helpers.runZr(tmp.allocator, &.{ "run", "hello" }, config_path);
    defer result.deinit();
    
    try std.testing.expectEqual(@as(u32, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}
```

### 5. Commit Your Changes

**Commit Message Format**:
```
<type>: <subject>

<body>

Co-Authored-By: Your Name <your.email@example.com>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`

Example:
```
feat: add --parallel flag to workspace run command

Enables parallel execution of workspace tasks with configurable
concurrency limit. Uses thread pool for efficient task distribution.

- Add --parallel/-p flag to workspace run
- Add --jobs/-j flag to set concurrency (default: CPU count)
- Update integration tests for parallel execution

Co-Authored-By: Jane Doe <jane@example.com>
```

**Commit Guidelines**:
- One logical change per commit
- Keep commits small and focused
- Reference issues: `Fixes #123` or `Closes #456`
- Use imperative mood: "Add feature" not "Added feature"

### 6. Push and Create PR

```bash
git push origin feat/your-feature-name
```

Then create a Pull Request on GitHub:

**PR Title**: Same format as commit message (e.g., `feat: add parallel execution`)

**PR Description**:
```markdown
## Summary
Brief description of what this PR does

## Changes
- Bullet list of specific changes
- Keep it concise

## Test Plan
- [ ] Unit tests pass (`zig build test`)
- [ ] Integration tests pass (`zig build integration-test`)
- [ ] Tested manually with: `zr <command> <args>`
- [ ] Cross-compilation verified (if relevant)

## Related Issues
Fixes #123
Related to #456
```

---

## Development Tips

### Running Specific Tests

```bash
# Run all unit tests
zig build test

# Run specific integration test file
zig test tests/run_test.zig --dep zr -Mroot=/Users/fn/Desktop/codespace/zr/src

# Run integration tests with filter
zig build integration-test -- --test-filter "workspace"
```

### Debugging

```bash
# Build with debug symbols
zig build

# Run with debugger
lldb ./zig-out/bin/zr run task-name

# Print debug info in tests
std.debug.print("value: {any}\n", .{value});
```

### Cross-Platform Considerations

**CRITICAL**: All POSIX calls must go through `src/util/platform.zig` with `comptime` guards.

Example:
```zig
// ❌ Wrong — breaks on Windows
const pid = std.posix.fork();

// ✅ Correct — uses platform wrapper
const pid = try platform.fork();
```

**Windows-specific**:
- Use `std.os.windows.*` APIs directly (built into Zig std)
- For external DLLs, use `@extern` with `.library_name = "kernel32"`
- Never force-link DLLs that might not exist on all Windows versions

### CI/CD

All PRs must pass:
1. **Build** on ubuntu-latest
2. **Unit tests** (670/678, 8 skipped)
3. **Integration tests** (805/805)
4. **Cross-compilation** to 6 targets:
   - `x86_64-linux-gnu`
   - `aarch64-linux-gnu`
   - `x86_64-macos-none`
   - `aarch64-macos-none`
   - `x86_64-windows-msvc`
   - `aarch64-windows-msvc`

CI runs automatically on:
- Push to `main`
- Pull requests to `main`
- Skips runs for `.claude/memory/**`, `docs/**`, `*.md` changes

---

## Code Review Process

### Review Criteria

Reviewers will check for:
1. **Correctness**: Does it solve the problem?
2. **Tests**: Are edge cases covered?
3. **Memory Safety**: No leaks, proper error handling
4. **Performance**: No unnecessary allocations
5. **Cross-platform**: Works on Linux/macOS/Windows
6. **Documentation**: Public APIs documented
7. **Style**: Follows project conventions

### Review Turnaround

- Most PRs reviewed within **24-48 hours**
- Simple fixes: < 24 hours
- Large features: may take up to 1 week

### Addressing Feedback

```bash
# Make requested changes
git add -p
git commit -m "refactor: apply review feedback"

# Or amend last commit (for small changes)
git add .
git commit --amend --no-edit

# Force push (if amended)
git push --force-with-lease
```

---

## Release Process

zr follows [Semantic Versioning](https://semver.org/):
- **MAJOR** (v2.0.0): Breaking changes
- **MINOR** (v1.1.0): New features, backward compatible
- **PATCH** (v1.0.1): Bug fixes

Contributors don't need to worry about versioning — maintainers handle releases.

---

## Getting Help

- **Questions**: [GitHub Discussions](https://github.com/yusa-imit/zr/discussions)
- **Bugs**: [GitHub Issues](https://github.com/yusa-imit/zr/issues)
- **Discord**: (Coming soon)
- **Zig Forum**: [ziggit.dev](https://ziggit.dev) for Zig-specific questions

---

## Additional Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library Docs](https://ziglang.org/documentation/master/std/)
- [TOML Specification](https://toml.io/en/v1.0.0)
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)
- [MCP Specification](https://spec.modelcontextprotocol.io/)

---

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for everyone.

### Expected Behavior

- Be respectful and professional
- Assume good faith in discussions
- Provide constructive feedback
- Focus on what is best for the project

### Unacceptable Behavior

- Harassment, discrimination, or personal attacks
- Trolling, inflammatory comments
- Publishing private information without consent
- Other conduct inappropriate in a professional setting

### Enforcement

Violations can be reported to the maintainers. All complaints will be reviewed and investigated promptly and fairly.

---

## License

By contributing to zr, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

Thank you for contributing to **zr**! 🚀
