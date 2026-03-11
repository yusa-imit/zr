# Ruby on Rails Example

This example demonstrates how to use `zr` with a Ruby on Rails project.

## Project Structure

```
ruby-rails/
├── Gemfile            # Ruby gem dependencies
├── zr.toml            # zr task runner configuration
└── README.md          # This file
```

## Prerequisites

- Ruby 3.3.0 or later
- Bundler (`gem install bundler`)
- `zr` installed

## Available Tasks

### Basic Tasks (Auto-detected)

- `install` - Install Ruby gem dependencies
- `update` - Update Ruby gems
- `server` - Start Rails development server
- `console` - Start Rails console
- `db-migrate` - Run database migrations
- `db-seed` - Seed database with initial data
- `db-reset` - Reset database (drop, create, migrate, seed)
- `test` - Run tests with RSpec

### Enhanced Tasks

- `lint` - Run RuboCop linter
- `lint-fix` - Auto-fix RuboCop violations
- `security-check` - Run Brakeman security scanner
- `precompile-assets` - Precompile assets for production
- `routes` - Display application routes
- `coverage` - Generate test coverage report

### Workflows

- `ci` - Full CI pipeline (install → lint → test → coverage)
- `deploy-prep` - Prepare for deployment (migrate → precompile)

## Usage

```bash
# Initialize project (auto-detect tasks)
zr init --detect

# Install dependencies
zr install

# Start development server
zr server

# Run tests
zr test

# Run linter
zr lint

# Run full CI pipeline
zr workflow ci

# Prepare for deployment
zr --profile production workflow deploy-prep
```

## Auto-Detection

The Ruby language provider detects Ruby/Rails projects by looking for:

- `Gemfile` (70 points confidence)
- `Gemfile.lock` (30 points)
- `Rakefile` (40 points)
- `.ruby-version` (30 points)
- `.ruby-gemset` (20 points)
- `config.ru` (25 points - Rack app)
- `bin/rails` (triggers Rails-specific task generation)
- `spec/` directory (triggers RSpec task generation)

When detected, `zr init --detect` automatically generates common Ruby/Rails tasks.

## Environment Profiles

### Development
```bash
zr --profile development server
```

### Test
```bash
zr --profile test test
```

### Production
```bash
zr --profile production precompile-assets
```

## Notes

- The `server` task runs on `http://localhost:3000` by default
- Coverage reports are generated in the `coverage/` directory
- Assets are precompiled to `public/assets/` for production
- RuboCop follows Rails Omakase conventions
- Brakeman performs security analysis on your Rails code
- All database tasks use Bundler's context (`bundle exec`)
