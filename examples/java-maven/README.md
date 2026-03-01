# Java Maven Example

This example demonstrates using zr with a Java project built with Maven.

## Features Demonstrated

- **Auto-detected tasks** via `zr init --detect` for Maven projects
- **Maven lifecycle integration** (clean, compile, test, package, install)
- **Wrapper script preference** (uses `./mvnw` if available)
- **Custom build profiles** for different environments
- **Test coverage** with JaCoCo integration

## Setup

This is a minimal Maven project structure:

```
java-maven/
├── pom.xml           # Maven project descriptor
├── mvnw              # Maven wrapper (optional but recommended)
├── src/
│   ├── main/java/    # Application source
│   └── test/java/    # Test source
└── zr.toml           # Task runner configuration
```

## Auto-Generation

To generate a zr.toml for an existing Maven project:

```bash
cd your-maven-project/
zr init --detect
```

This will automatically detect Maven and create tasks for:
- `build` - Clean and package the project
- `test` - Run unit tests
- `clean` - Remove build artifacts
- `install` - Install to local Maven repository
- `verify` - Run integration tests and verification
- `run` - Execute the main class

## Usage

```bash
# List all available tasks
zr list

# Run tests
zr run test

# Build the project (clean + package)
zr run build

# Install to local Maven repository
zr run install

# Run with production profile
zr run build --profile production

# Watch mode - rebuild on file changes
zr watch build
```

## Customization

The auto-generated tasks can be enhanced with:

### Build Profiles

```toml
[profile.production]
[profile.production.env]
MAVEN_OPTS = "-Xmx2048m"

[tasks.build]
env.SPRING_PROFILES_ACTIVE = "prod"  # For Spring Boot apps
```

### Dependencies

```toml
[tasks.package]
description = "Package application"
cmd = "./mvnw package"
deps = ["test"]  # Always run tests before packaging
```

### Custom Goals

```toml
[tasks.coverage]
description = "Generate test coverage report"
cmd = "./mvnw jacoco:report"
deps = ["test"]
outputs = ["target/site/jacoco/"]
```

## Maven vs Gradle

If you use Gradle instead, `zr init --detect` will automatically generate Gradle-specific tasks:
- Uses `./gradlew` instead of `./mvnw`
- Gradle lifecycle tasks (build, test, clean, assemble, check, run)

See the `java-gradle` example for Gradle-specific configuration.

## Benefits of Using zr with Maven

1. **Consistent Interface**: Same `zr run test` command works across Maven, Gradle, and other build tools
2. **Enhanced Caching**: zr's content-based caching is faster than Maven's default caching
3. **Parallel Execution**: Run multiple Maven goals in parallel with `zr run --parallel`
4. **Workflow Integration**: Combine Maven tasks with Docker, deployment, or other workflows
5. **Better Output**: zr provides progress bars, color-coded output, and clearer error messages
