const types = @import("../types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;

pub const go_test = Template{
    .name = "go-test",
    .category = .testing,
    .description = "Run Go tests with coverage",
    .variables = &[_]TemplateVariable{
        .{ .name = "COVERAGE_OUT", .description = "Coverage output file", .default = "coverage.out" },
        .{ .name = "TEST_FLAGS", .description = "Additional test flags", .default = "-v" },
    },
    .content =
    \\[tasks.test]
    \\cmd = "go test ${TEST_FLAGS} -coverprofile=${COVERAGE_OUT} ./..."
    \\description = "Run Go tests with coverage"
    \\
    ,
};

pub const cargo_test = Template{
    .name = "cargo-test",
    .category = .testing,
    .description = "Run Rust tests with Cargo",
    .variables = &[_]TemplateVariable{
        .{ .name = "TEST_THREADS", .description = "Number of test threads", .default = "" },
        .{ .name = "FEATURES", .description = "Features to test with", .default = "" },
    },
    .content =
    \\[tasks.test]
    \\cmd = "cargo test${TEST_THREADS}${FEATURES}"
    \\description = "Run Rust tests"
    \\
    ,
};

pub const npm_test = Template{
    .name = "npm-test",
    .category = .testing,
    .description = "Run JavaScript/TypeScript tests",
    .variables = &[_]TemplateVariable{
        .{ .name = "TEST_SCRIPT", .description = "npm test script", .default = "test" },
        .{ .name = "COVERAGE", .description = "Generate coverage report", .default = "false" },
    },
    .content =
    \\[tasks.test]
    \\cmd = "npm run ${TEST_SCRIPT}"
    \\description = "Run tests with npm"
    \\
    ,
};

pub const pytest = Template{
    .name = "pytest",
    .category = .testing,
    .description = "Run Python tests with pytest",
    .variables = &[_]TemplateVariable{
        .{ .name = "TEST_PATH", .description = "Path to test directory", .default = "tests/" },
        .{ .name = "MARKERS", .description = "pytest markers to run", .default = "" },
        .{ .name = "VERBOSE", .description = "Verbose output (-v, -vv)", .default = "-v" },
    },
    .content =
    \\[tasks.test]
    \\cmd = "pytest ${VERBOSE} ${TEST_PATH}${MARKERS}"
    \\description = "Run Python tests with pytest"
    \\
    ,
};

pub const zig_test = Template{
    .name = "zig-test",
    .category = .testing,
    .description = "Run Zig tests",
    .variables = &[_]TemplateVariable{
        .{ .name = "TEST_FILTER", .description = "Test name filter (optional)", .default = "" },
    },
    .content =
    \\[tasks.test]
    \\cmd = "zig build test${TEST_FILTER}"
    \\description = "Run Zig tests"
    \\
    ,
};

pub const maven_test = Template{
    .name = "maven-test",
    .category = .testing,
    .description = "Run Java tests with Maven",
    .variables = &[_]TemplateVariable{
        .{ .name = "TEST_GROUP", .description = "Test group to run (optional)", .default = "" },
    },
    .content =
    \\[tasks.test]
    \\cmd = "mvn test${TEST_GROUP}"
    \\description = "Run Java tests with Maven"
    \\
    ,
};

pub const all = [_]Template{
    go_test,
    cargo_test,
    npm_test,
    pytest,
    zig_test,
    maven_test,
};
