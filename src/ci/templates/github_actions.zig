const types = @import("types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;
const Platform = types.Platform;
const TemplateType = types.TemplateType;

/// Basic CI template for GitHub Actions
pub const basic_ci = Template.init(
    .github_actions,
    .basic_ci,
    "GitHub Actions Basic CI",
    "Basic continuous integration workflow with zr",
    \\name: CI
    \\
    \\on:
    \\  push:
    \\    branches: [ ${DEFAULT_BRANCH} ]
    \\  pull_request:
    \\    branches: [ ${DEFAULT_BRANCH} ]
    \\
    \\jobs:
    \\  build:
    \\    runs-on: ${RUNNER}
    \\    steps:
    \\      - uses: actions/checkout@v4
    \\
    \\      - name: Install zr
    \\        run: |
    \\          curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-${{ runner.os }}-${{ runner.arch }}.tar.gz | tar xz
    \\          sudo mv zr /usr/local/bin/
    \\
    \\      - name: Setup project
    \\        run: zr setup
    \\
    \\      - name: Run build
    \\        run: zr run ${BUILD_TASK}
    \\
    \\      - name: Run tests
    \\        run: zr run ${TEST_TASK}
,
    &[_]TemplateVariable{
        TemplateVariable.init("DEFAULT_BRANCH", "Default branch name", "main", false),
        TemplateVariable.init("RUNNER", "GitHub Actions runner", "ubuntu-latest", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
    },
);

/// Monorepo CI template with affected detection
pub const monorepo = Template.init(
    .github_actions,
    .monorepo,
    "GitHub Actions Monorepo CI",
    "Monorepo workflow with affected builds and caching",
    \\name: Monorepo CI
    \\
    \\on:
    \\  push:
    \\    branches: [ ${DEFAULT_BRANCH} ]
    \\  pull_request:
    \\    branches: [ ${DEFAULT_BRANCH} ]
    \\
    \\jobs:
    \\  affected:
    \\    runs-on: ${RUNNER}
    \\    outputs:
    \\      projects: ${{ steps.affected.outputs.projects }}
    \\    steps:
    \\      - uses: actions/checkout@v4
    \\        with:
    \\          fetch-depth: 0
    \\
    \\      - name: Install zr
    \\        run: |
    \\          curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-${{ runner.os }}-${{ runner.arch }}.tar.gz | tar xz
    \\          sudo mv zr /usr/local/bin/
    \\
    \\      - name: Detect affected projects
    \\        id: affected
    \\        run: |
    \\          PROJECTS=$(zr affected --json | jq -c '.projects')
    \\          echo "projects=$PROJECTS" >> $GITHUB_OUTPUT
    \\
    \\  build:
    \\    needs: affected
    \\    if: needs.affected.outputs.projects != '[]'
    \\    runs-on: ${RUNNER}
    \\    strategy:
    \\      matrix:
    \\        project: ${{ fromJson(needs.affected.outputs.projects) }}
    \\    steps:
    \\      - uses: actions/checkout@v4
    \\
    \\      - name: Install zr
    \\        run: |
    \\          curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-${{ runner.os }}-${{ runner.arch }}.tar.gz | tar xz
    \\          sudo mv zr /usr/local/bin/
    \\
    \\      - name: Cache zr dependencies
    \\        uses: actions/cache@v4
    \\        with:
    \\          path: ~/.zr/cache
    \\          key: ${{ runner.os }}-zr-${{ hashFiles('**/zr.toml') }}
    \\
    \\      - name: Build project
    \\        run: zr run ${BUILD_TASK} --workspace=${{ matrix.project }}
    \\
    \\      - name: Test project
    \\        run: zr run ${TEST_TASK} --workspace=${{ matrix.project }}
,
    &[_]TemplateVariable{
        TemplateVariable.init("DEFAULT_BRANCH", "Default branch name", "main", false),
        TemplateVariable.init("RUNNER", "GitHub Actions runner", "ubuntu-latest", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
    },
);

/// Release automation template
pub const release = Template.init(
    .github_actions,
    .release,
    "GitHub Actions Release",
    "Automated release workflow with versioning and publishing",
    \\name: Release
    \\
    \\on:
    \\  push:
    \\    tags:
    \\      - 'v*'
    \\
    \\jobs:
    \\  release:
    \\    runs-on: ${RUNNER}
    \\    permissions:
    \\      contents: write
    \\    steps:
    \\      - uses: actions/checkout@v4
    \\
    \\      - name: Install zr
    \\        run: |
    \\          curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-${{ runner.os }}-${{ runner.arch }}.tar.gz | tar xz
    \\          sudo mv zr /usr/local/bin/
    \\
    \\      - name: Setup project
    \\        run: zr setup
    \\
    \\      - name: Build release
    \\        run: zr run ${BUILD_TASK} --profile=release
    \\
    \\      - name: Run tests
    \\        run: zr run ${TEST_TASK}
    \\
    \\      - name: Publish
    \\        run: zr run ${PUBLISH_TASK}
    \\        env:
    \\          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    \\
    \\      - name: Create GitHub Release
    \\        uses: softprops/action-gh-release@v1
    \\        with:
    \\          files: ${ARTIFACTS_PATH}
,
    &[_]TemplateVariable{
        TemplateVariable.init("RUNNER", "GitHub Actions runner", "ubuntu-latest", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
        TemplateVariable.init("PUBLISH_TASK", "Publish task name", "publish", false),
        TemplateVariable.init("ARTIFACTS_PATH", "Artifacts path", "dist/*", false),
    },
);

/// All GitHub Actions templates
pub const templates = [_]Template{
    basic_ci,
    monorepo,
    release,
};
