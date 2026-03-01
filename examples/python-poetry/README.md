# Python Poetry Example

This example demonstrates using **zr** with a Python project managed by [Poetry](https://python-poetry.org/). It showcases auto-detection capabilities and integration with Python development tools.

## Features Demonstrated

- ✅ **Auto-detection** via `zr init --detect` — detects pyproject.toml and generates tasks
- ✅ **Poetry integration** — install, run, test, build commands
- ✅ **Quality tools** — pytest, black, ruff, mypy
- ✅ **Workflows** — CI pipeline with parallel execution
- ✅ **Coverage reporting** — HTML and terminal coverage reports

## Project Structure

```
python-poetry/
├── pyproject.toml       # Poetry configuration with dependencies
├── zr.toml              # Task definitions (auto-generated)
├── src/
│   └── myapp/
│       ├── __init__.py
│       ├── cli.py       # Click CLI application
│       └── calculator.py
└── tests/
    └── test_calculator.py
```

## Quick Start

### 1. Auto-generate zr.toml

If you have an existing Python/Poetry project, you can generate `zr.toml` automatically:

```bash
cd your-python-project/
zr init --detect
```

This will:
- Detect `pyproject.toml` (Poetry configuration)
- Extract Poetry scripts as zr tasks
- Generate standard Python tasks (test, lint, format, typecheck)
- Add any Poetry scripts defined in `[tool.poetry.scripts]`

### 2. View Available Tasks

```bash
$ zr list
Tasks:
  → install      Install dependencies using Poetry
  → test         Run tests with pytest
  → test-cov     Run tests with coverage report
  → lint         Run code quality checks
  → format       Format code with black
  → format-check Check code formatting
  → typecheck    Run type checking with mypy
  → run          Run the application
  → clean        Clean build artifacts and cache
  → build        Build distribution package

Workflows:
  → ci           Complete CI pipeline
  → check        Quick local checks before commit
```

### 3. Run Tasks

```bash
# Install dependencies
zr run install

# Run tests with coverage
zr run test-cov

# Format and lint
zr run format
zr run lint

# Run the full CI pipeline
zr workflow ci
```

## Enhanced Tasks Beyond Auto-detection

While `zr init --detect` generates basic tasks, this example includes enhanced versions:

### Coverage Reporting

```toml
[tasks.test-cov]
description = "Run tests with coverage report"
cmd = "poetry run pytest --cov=myapp --cov-report=html --cov-report=term"
deps = ["install"]
```

Generates both HTML (`htmlcov/index.html`) and terminal coverage reports.

### CI Workflow

```toml
[workflows.ci]
description = "Complete CI pipeline"
stages = [
  { tasks = ["install"] },
  { tasks = ["format-check", "lint", "typecheck"], parallel = true },
  { tasks = ["test-cov"] }
]
```

Runs:
1. Install dependencies
2. Parallel quality checks (format, lint, typecheck)
3. Tests with coverage

### Pre-commit Checks

```toml
[workflows.check]
description = "Quick local checks before commit"
stages = [
  { tasks = ["format", "lint", "typecheck", "test"], parallel = false }
]
```

## Comparison: Before and After zr

### Before (traditional approach)

```bash
# Install
poetry install

# Run all checks manually
poetry run black src tests
poetry run ruff check src tests
poetry run mypy src
poetry run pytest --cov=myapp

# Remember order matters, forget dependencies
```

### After (with zr)

```bash
# Single command, correct order, parallelization
zr workflow check

# Or run CI pipeline
zr workflow ci
```

## Integration with Poetry Scripts

If your `pyproject.toml` has Poetry scripts:

```toml
[tool.poetry.scripts]
myapp = "myapp.cli:main"
serve = "myapp.server:run"
```

`zr init --detect` automatically generates:

```toml
[tasks.myapp]
cmd = "poetry run myapp"

[tasks.serve]
cmd = "poetry run serve"
```

## Testing the Example

1. **Setup** (requires Python 3.9+ and Poetry):
   ```bash
   cd examples/python-poetry
   poetry install
   ```

2. **Run tests**:
   ```bash
   zr run test-cov
   ```

3. **Run the app**:
   ```bash
   zr run run
   # Or with arguments:
   zr run run -- --name "zr user"
   ```

4. **Full CI pipeline**:
   ```bash
   zr workflow ci
   ```

## Why Use zr with Python?

1. **Unified tooling** — One command for all project tasks (Python, Node, Rust, etc.)
2. **Dependency management** — Tasks automatically run dependencies in order
3. **Parallelization** — Run independent checks concurrently (lint + typecheck + format)
4. **Reproducibility** — `zr.toml` is version-controlled, explicit, and portable
5. **No scripting** — Declarative TOML instead of complex Makefiles or shell scripts
6. **Fast** — ~5ms startup (vs tox ~500ms, nox ~200ms)

## Common Python Patterns

### Matrix Testing (Multiple Python Versions)

```toml
[tasks.test-matrix]
cmd = "poetry run pytest"
matrix.python = ["3.9", "3.10", "3.11", "3.12"]
toolchain.python = "${python}"
```

### Environment-Specific Tasks

```toml
[tasks.test-integration]
cmd = "poetry run pytest tests/integration/"
env = { DATABASE_URL = "postgresql://localhost/test_db" }

[tasks.test-e2e]
cmd = "poetry run pytest tests/e2e/"
env = { API_URL = "http://localhost:8000" }
```

### Conditional Execution

```toml
[tasks.deploy]
cmd = "poetry run python scripts/deploy.py"
condition = "platform.is_linux && env.CI == 'true'"
```

## Next Steps

- Read the [Configuration Guide](../../docs/guides/configuration.md) for advanced features
- See [Workflows](../../docs/guides/getting-started.md#workflows) for complex pipelines
- Explore [Matrix Expansion](../../docs/guides/configuration.md#matrix) for multi-version testing
- Check [Monorepo Support](../workspace/) for multi-package Python projects

## Troubleshooting

**Q: zr doesn't detect my Python project**

A: Ensure you have one of:
- `pyproject.toml` (Poetry, PEP 621)
- `setup.py`
- `requirements.txt`

**Q: Tasks fail with "poetry: command not found"**

A: Install Poetry first:
```bash
curl -sSL https://install.python-poetry.org | python3 -
```

Or use zr's toolchain management (future feature):
```bash
zr tools install python@3.11
```

**Q: Want to use pip instead of Poetry?**

A: Edit the generated tasks to use `pip` and `python -m`:
```toml
[tasks.install]
cmd = "pip install -r requirements.txt"

[tasks.test]
cmd = "python -m pytest"
```
