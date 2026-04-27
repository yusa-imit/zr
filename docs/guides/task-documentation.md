# Task Documentation & Rich Help System

> **Feature**: Comprehensive task documentation with rich help formatting, examples, and metadata.
> **Since**: v1.79.0
> **Status**: Stable

## Overview

zr provides a rich task documentation system that goes beyond simple descriptions, allowing you to create comprehensive, user-friendly documentation for your tasks. This guide covers how to document tasks effectively with structured metadata, examples, and cross-references.

## Why Task Documentation?

Well-documented tasks are essential for:
- **Team onboarding**: New developers understand task purpose and usage
- **Self-documenting workflows**: Tasks serve as executable documentation
- **Discoverability**: Related tasks are easy to find
- **Maintenance**: Complex task logic is explained and preserved
- **Consistency**: Standardized documentation format across projects

## Basic Usage

### Simple String Description (Backward Compatible)

The traditional single-line description still works:

```toml
[tasks.build]
description = "Build the project in release mode"
cmd = "zig build -Doptimize=ReleaseFast"
```

### Rich Description

For more complex tasks, use the structured description format:

```toml
[tasks.deploy]
description.short = "Deploy application to cloud"
description.long = """
Deploys the application to the specified environment using
the configured cloud provider. This task:
- Builds the production bundle
- Uploads artifacts to cloud storage
- Updates the cloud function configuration
- Runs smoke tests against deployed endpoints

Requires CLOUD_API_KEY environment variable.
"""
cmd = "scripts/deploy.sh"
```

## Task Examples

Provide concrete usage examples to help users understand how to invoke the task:

```toml
[tasks.test]
description.short = "Run test suite"
examples = [
    "zr run test",
    "zr run test --force",
    "zr run test -- --filter integration"
]
cmd = "zig build test"
```

Examples appear in the help output when users run `zr help test`.

## Output Documentation

Document what files or artifacts a task produces:

```toml
[tasks.build]
description.short = "Build project for all platforms"
outputs.dist = "Compiled binaries for all targets"
outputs."dist/*.wasm" = "WebAssembly modules"
outputs."logs/build.log" = "Build output and warnings"
cmd = "zig build -Dtarget=wasm32-freestanding"
```

When users run `zr help build`, they'll see a clear list of outputs with descriptions.

## Related Tasks (See Also)

Link to related tasks for better discoverability:

```toml
[tasks.test]
description.short = "Run unit tests"
see_also = ["test:integration", "test:bench", "coverage"]
cmd = "zig build test"

[tasks."test:integration"]
description.short = "Run integration tests"
see_also = ["test", "deploy"]
cmd = "zig build integration-test"

[tasks.coverage]
description.short = "Generate test coverage report"
see_also = ["test"]
cmd = "kcov --exclude-pattern=/usr zig-out/coverage/ zig-out/bin/zr"
```

## Parameter Documentation

When using parameterized tasks, document the parameters clearly:

```toml
[tasks.deploy]
description.short = "Deploy to environment"
description.long = """
Deploys the application to the specified environment.
The env parameter controls which configuration is used.
"""
examples = [
    "zr run deploy env=staging",
    "zr run deploy env=production region=us-west-2"
]

[[tasks.deploy.params]]
name = "env"
default = "dev"
description = "Target environment (dev, staging, production)"

[[tasks.deploy.params]]
name = "region"
default = "us-east-1"
description = "Cloud region for deployment"

cmd = "scripts/deploy.sh {{env}} {{region}}"
```

## Help Command

View formatted task documentation with `zr help <task>`:

```bash
$ zr help deploy

deploy — Deploy application to cloud

Description:
  Deploys the application to the specified environment using
  the configured cloud provider. This task:
  - Builds the production bundle
  - Uploads artifacts to cloud storage
  - Updates the cloud function configuration
  - Runs smoke tests against deployed endpoints

  Requires CLOUD_API_KEY environment variable.

Parameters:
  env       Target environment (dev, staging, production) [default: dev]
  region    Cloud region for deployment [default: us-east-1]

Examples:
  zr run deploy env=staging
  zr run deploy env=production region=us-west-2

Dependencies:
  build, test

Outputs:
  dist/bundle.tar.gz    Production application bundle
  logs/deploy.log       Deployment output and errors

See Also:
  rollback, status, logs
```

## Man Page Generation

Generate man page format for offline documentation:

```bash
$ zr man deploy > deploy.1
$ man ./deploy.1
```

This produces standard Unix man page format, useful for:
- Offline documentation
- Integration with system man pages
- Archival and versioning

## Markdown Export

Export all task documentation to markdown:

```bash
$ zr docs --markdown > TASKS.md
```

This creates a markdown file with all task documentation, ideal for:
- Project wikis
- README files
- Static site generators
- Documentation sites

## List Enhancements

The `zr list` command supports documentation display:

```bash
# Show short descriptions (default)
$ zr list

# Show verbose output with full metadata
$ zr list --verbose

# Filter by tasks with documentation
$ zr list --has-docs
```

## Real-World Examples

### Build Pipeline

```toml
[tasks.build]
description.short = "Build project for release"
description.long = """
Compiles the project with optimizations enabled.
Produces stripped binaries for production deployment.
"""
examples = [
    "zr run build",
    "zr run build -- --strip"
]
outputs."zig-out/bin/zr" = "Release binary (optimized)"
outputs."zig-out/lib/libzr.a" = "Static library"
see_also = ["test", "install", "package"]
cmd = "zig build -Doptimize=ReleaseFast"
```

### Test Suite

```toml
[tasks.test]
description.short = "Run full test suite"
description.long = """
Runs unit tests, integration tests, and generates coverage report.
Use --filter to run specific tests.
"""
examples = [
    "zr run test",
    "zr run test -- --filter 'graph*'",
    "zr run test:unit"
]
outputs."zig-out/test-results/" = "Test reports (JUnit XML)"
outputs."coverage/index.html" = "Coverage report (HTML)"
see_also = ["test:unit", "test:integration", "coverage"]
cmd = "zig build test"

[tasks."test:unit"]
description.short = "Run unit tests only"
see_also = ["test", "test:integration"]
cmd = "zig build test-unit"

[tasks."test:integration"]
description.short = "Run integration tests"
description.long = """
Runs black-box CLI integration tests against compiled binary.
Requires zr binary to be built first.
"""
deps = ["build"]
see_also = ["test", "test:unit"]
cmd = "zig build integration-test"
```

### Multi-Environment Deployment

```toml
[tasks.deploy]
description.short = "Deploy to cloud environment"
description.long = """
Deploys the application to the specified environment.
Performs health checks after deployment.

Prerequisites:
- Cloud CLI tools installed
- Valid credentials configured
- Target environment exists

The deployment process:
1. Builds production artifacts
2. Runs pre-deployment tests
3. Uploads and deploys
4. Runs smoke tests
5. Updates DNS if needed
"""

examples = [
    "zr run deploy env=staging",
    "zr run deploy env=production",
    "zr run deploy env=production skip_tests=true"
]

[[tasks.deploy.params]]
name = "env"
description = "Target environment (dev, staging, production)"
required = true

[[tasks.deploy.params]]
name = "skip_tests"
default = "false"
description = "Skip pre-deployment tests (not recommended)"

deps = ["build", "test"]
outputs."logs/deploy-{{env}}.log" = "Deployment logs"
outputs."artifacts/manifest-{{env}}.json" = "Deployment manifest"
see_also = ["rollback", "status", "logs"]

cmd = """
if [ "{{skip_tests}}" = "false" ]; then
  scripts/pre-deploy-checks.sh {{env}}
fi
scripts/deploy.sh {{env}}
scripts/health-check.sh {{env}}
"""
```

### Data Processing Pipeline

```toml
[tasks."data:process"]
description.short = "Process raw data files"
description.long = """
Processes raw data files from input directory and generates
cleaned datasets with statistics and validation reports.

Input format: CSV files with headers
Output format: Parquet files + JSON metadata
"""

examples = [
    "zr run data:process input=./raw output=./processed",
    "zr run data:process input=./raw output=./processed validate=true"
]

[[tasks."data:process".params]]
name = "input"
description = "Directory containing raw CSV files"
required = true

[[tasks."data:process".params]]
name = "output"
description = "Output directory for processed files"
required = true

[[tasks."data:process".params]]
name = "validate"
default = "false"
description = "Run validation checks on processed data"

outputs."{{output}}/*.parquet" = "Processed data in Parquet format"
outputs."{{output}}/metadata.json" = "Dataset metadata and statistics"
outputs."{{output}}/validation.log" = "Validation report (if enabled)"

see_also = ["data:validate", "data:export"]

cmd = "python scripts/process_data.py --input {{input}} --output {{output}} --validate {{validate}}"
```

## Documentation Best Practices

### 1. Write for Your Audience

Consider who will read the documentation:
- **New team members**: Include prerequisites and context
- **Regular users**: Focus on common use cases and examples
- **Maintainers**: Document edge cases and implementation notes

### 2. Use Concise Short Descriptions

The short description appears in `zr list` and search results. Make it:
- Under 60 characters
- Action-oriented (verb first)
- Specific about what the task does

Good examples:
- ✅ `"Deploy application to cloud environment"`
- ✅ `"Run integration tests with coverage"`
- ✅ `"Generate TypeScript type definitions"`

Avoid:
- ❌ `"Deployment"` (too vague)
- ❌ `"This task deploys the application to various cloud environments and runs tests"` (too long)
- ❌ `"Do deployment stuff"` (not professional)

### 3. Provide Context in Long Descriptions

The long description should answer:
- **What**: What does this task do?
- **Why**: When would you use it?
- **How**: What steps does it perform?
- **Prerequisites**: What's needed before running?
- **Post-conditions**: What state changes after running?

### 4. Include Realistic Examples

Examples should:
- Cover common use cases
- Show parameter variations
- Demonstrate advanced usage
- Use real values (not placeholders when possible)

### 5. Document Dependencies

Use the `see_also` field to:
- Link to prerequisite tasks
- Reference related workflows
- Point to alternative approaches
- Connect to post-execution tasks

### 6. Keep Outputs Up-to-Date

When task outputs change:
- Update the `outputs` field immediately
- Document new artifact formats
- Note deprecated outputs
- Include directory structures for complex outputs

### 7. Use Consistent Terminology

Across your project:
- Standardize environment names (dev/staging/prod vs development/test/production)
- Use consistent parameter names
- Follow the same documentation structure
- Maintain a glossary for domain terms

## Interactive Help

The `zr irun` interactive task picker shows task help when browsing:

```bash
$ zr irun
# Use arrow keys to navigate, press 'h' to see help for selected task
```

This allows users to explore tasks and their documentation without leaving the interface.

## Validation and Linting

zr can validate task documentation:

```bash
# Check for missing descriptions
$ zr lint --check-docs

# Show tasks without examples
$ zr list --no-examples

# Find tasks with missing see_also
$ zr list --no-related
```

## Comparison with Other Tools

### vs. Make

Make has minimal documentation support (comments only):

```makefile
# Deploy to production (no structured format)
deploy:
    ./scripts/deploy.sh
```

zr provides structured metadata that tools can parse and display.

### vs. Just

Just supports doc comments but with limited structure:

```just
# Deploy application
# Requires CLOUD_API_KEY
deploy env="dev":
    ./scripts/deploy.sh {{env}}
```

zr adds examples, outputs, and cross-references.

### vs. Task (go-task)

Task supports `desc` and `summary`:

```yaml
tasks:
  deploy:
    desc: "Deploy to cloud"
    summary: |
      Deploys the application...
    cmds:
      - ./scripts/deploy.sh
```

zr adds examples, parameter documentation, outputs, and see_also.

### vs. npm scripts

npm scripts have no built-in documentation:

```json
{
  "scripts": {
    "deploy": "./scripts/deploy.sh"
  }
}
```

Documentation must be in separate README files.

## Migration Guides

### From Make

Convert Make targets with comments:

```makefile
# Before (Makefile)
# Build the project for release
build:
    zig build -Doptimize=ReleaseFast
```

```toml
# After (zr.toml)
[tasks.build]
description.short = "Build project for release"
examples = ["zr run build"]
outputs."zig-out/bin/zr" = "Optimized binary"
cmd = "zig build -Doptimize=ReleaseFast"
```

### From Just

Convert justfile doc comments:

```just
# Before (justfile)
# Deploy to environment
# Usage: just deploy staging
deploy env="dev":
    ./scripts/deploy.sh {{env}}
```

```toml
# After (zr.toml)
[tasks.deploy]
description.short = "Deploy to environment"
examples = [
    "zr run deploy env=staging",
    "zr run deploy env=production"
]

[[tasks.deploy.params]]
name = "env"
default = "dev"
description = "Target environment"

cmd = "./scripts/deploy.sh {{env}}"
```

### From Task (go-task)

Convert Task's desc and summary:

```yaml
# Before (Taskfile.yml)
tasks:
  test:
    desc: Run tests
    summary: |
      Runs the full test suite including
      unit and integration tests.
    cmds:
      - zig build test
```

```toml
# After (zr.toml)
[tasks.test]
description.short = "Run tests"
description.long = """
Runs the full test suite including
unit and integration tests.
"""
examples = ["zr run test", "zr run test -- --filter unit"]
see_also = ["coverage", "bench"]
cmd = "zig build test"
```

## Troubleshooting

### Help Not Showing Examples

**Symptom**: `zr help <task>` doesn't show examples section.

**Cause**: Examples array is empty or not defined.

**Fix**: Add examples to the task definition:

```toml
[tasks.mytask]
description.short = "My task"
examples = ["zr run mytask", "zr run mytask --verbose"]
cmd = "echo hello"
```

### Long Description Not Displaying

**Symptom**: Only short description appears in help.

**Cause**: Using `description = "..."` instead of structured format.

**Fix**: Use the structured description:

```toml
[tasks.mytask]
description.short = "Short version"
description.long = """
Detailed explanation
with multiple lines.
"""
```

### Man Page Generation Fails

**Symptom**: `zr man <task>` returns empty or malformed output.

**Cause**: Missing required fields or special characters in descriptions.

**Fix**: Ensure all descriptions are valid text without control characters. Escape special characters if needed.

### See Also Links Broken

**Symptom**: Related tasks don't exist when clicked/referenced.

**Cause**: Typo in task name or task not defined.

**Fix**: Verify task names match exactly:

```bash
$ zr list  # Check actual task names
```

Update `see_also` to use correct names:

```toml
[tasks.deploy]
see_also = ["build", "test"]  # Exact names from zr list
```

### Outputs Not Showing

**Symptom**: No outputs section in help.

**Cause**: `outputs` field not defined or empty.

**Fix**: Add outputs table:

```toml
[tasks.build]
outputs."dist/app" = "Built application"
outputs."logs/" = "Build logs"
```

## Future Enhancements

Upcoming features in the task documentation system:

- **Type annotations**: Specify param types (string, int, bool, enum)
- **Enum validation**: Restrict param values to predefined set
- **Searchable docs**: `zr search "deploy"` to find tasks by keywords
- **Documentation site**: `zr serve-docs` for browsable web interface
- **Diagrams**: ASCII art or mermaid diagrams in long descriptions
- **Versioning**: Track documentation changes across versions
- **Localization**: Support for multiple languages in descriptions
- **Auto-generation**: Generate docs from comments in scripts

## See Also

- [Parameterized Tasks Guide](./parameterized-tasks.md) — Using parameters in tasks
- [Incremental Builds Guide](./incremental-builds.md) — Understanding task outputs
- [Task Selection Guide](./task-selection.md) — Finding tasks by tags/patterns
- [Environment Management Guide](./environment-management.md) — Task environment setup

## Summary

The task documentation system in zr provides:
- ✅ **Rich descriptions**: Short and long descriptions for context
- ✅ **Examples**: Concrete usage examples in help
- ✅ **Parameter docs**: Clear documentation for task parameters
- ✅ **Output documentation**: What files/artifacts tasks produce
- ✅ **Cross-references**: Related tasks via see_also
- ✅ **Help command**: Formatted help display (`zr help <task>`)
- ✅ **Man pages**: Generate man page format
- ✅ **Markdown export**: Export all docs to markdown
- ✅ **List integration**: Show docs in `zr list --verbose`
- ✅ **Backward compatible**: Simple string descriptions still work

Use this system to create self-documenting task runners that serve as both automation and documentation.
