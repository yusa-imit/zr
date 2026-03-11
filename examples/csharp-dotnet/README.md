# C# (.NET) Example

This example demonstrates how to use `zr` with a .NET project.

## Project Structure

```
csharp-dotnet/
├── HelloWorld.csproj  # .NET project file
├── zr.toml            # zr task runner configuration
└── README.md          # This file
```

## Prerequisites

- .NET SDK 9.0 or later
- `zr` installed

## Available Tasks

### Basic Tasks (Auto-detected)

- `build` - Build project with .NET SDK
- `test` - Run tests with .NET
- `clean` - Clean build artifacts
- `restore` - Restore NuGet packages
- `run` - Run the .NET application
- `publish` - Publish release build

### Enhanced Tasks

- `watch` - Run with hot reload
- `format` - Format code with dotnet format
- `lint` - Run code analysis
- `coverage` - Generate test coverage report
- `package` - Create NuGet package

### Workflows

- `ci` - Full CI pipeline (restore → lint → test → publish)

## Usage

```bash
# Initialize project (auto-detect tasks)
zr init --detect

# Build the project
zr build

# Run tests
zr test

# Run with hot reload
zr watch

# Run full CI pipeline
zr workflow ci

# Publish for production
zr --profile production publish
```

## Auto-Detection

The C# language provider detects .NET projects by looking for:

- `*.csproj` files (70 points confidence)
- `*.sln` solution files (60 points)
- `global.json` (30 points)
- `nuget.config` (20 points)

When detected, `zr init --detect` automatically generates common .NET tasks.

## Environment Profiles

### Development
```bash
zr --profile development run
```

### Production
```bash
zr --profile production publish
```

## Notes

- The `watch` task uses `dotnet watch run` for hot reload during development
- Coverage reports are generated in the `TestResults/` directory
- Package artifacts are output to `bin/Release/*.nupkg`
- All tasks respect .NET's existing build caching
