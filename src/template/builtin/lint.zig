const types = @import("../types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;

pub const eslint = Template{
    .name = "eslint",
    .category = .lint,
    .description = "Run ESLint for JavaScript/TypeScript",
    .variables = &[_]TemplateVariable{
        .{ .name = "PATHS", .description = "Paths to lint", .default = "src/" },
        .{ .name = "FIX", .description = "Auto-fix issues (true/false)", .default = "false" },
    },
    .content =
    \\[tasks.lint]
    \\cmd = "eslint ${PATHS}${FIX}"
    \\description = "Lint JavaScript/TypeScript with ESLint"
    \\
    ,
};

pub const clippy = Template{
    .name = "clippy",
    .category = .lint,
    .description = "Run Clippy linter for Rust",
    .variables = &[_]TemplateVariable{
        .{ .name = "DENY_WARNINGS", .description = "Treat warnings as errors", .default = "false" },
    },
    .content =
    \\[tasks.lint]
    \\cmd = "cargo clippy -- ${DENY_WARNINGS}"
    \\description = "Lint Rust code with Clippy"
    \\
    ,
};

pub const golangci_lint = Template{
    .name = "golangci-lint",
    .category = .lint,
    .description = "Run golangci-lint for Go",
    .variables = &[_]TemplateVariable{
        .{ .name = "CONFIG", .description = "Config file path", .default = ".golangci.yml" },
    },
    .content =
    \\[tasks.lint]
    \\cmd = "golangci-lint run --config ${CONFIG}"
    \\description = "Lint Go code with golangci-lint"
    \\
    ,
};

pub const ruff = Template{
    .name = "ruff",
    .category = .lint,
    .description = "Run Ruff linter for Python",
    .variables = &[_]TemplateVariable{
        .{ .name = "PATHS", .description = "Paths to lint", .default = "." },
        .{ .name = "FIX", .description = "Auto-fix issues (--fix)", .default = "" },
    },
    .content =
    \\[tasks.lint]
    \\cmd = "ruff check ${PATHS}${FIX}"
    \\description = "Lint Python code with Ruff"
    \\
    ,
};

pub const all = [_]Template{
    eslint,
    clippy,
    golangci_lint,
    ruff,
};
