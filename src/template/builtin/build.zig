const types = @import("../types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;

pub const go_build = Template{
    .name = "go-build",
    .category = .build,
    .description = "Build Go project with customizable output path",
    .variables = &[_]TemplateVariable{
        .{ .name = "PROJECT_NAME", .description = "Project name", .required = true },
        .{ .name = "OUTPUT_DIR", .description = "Output directory for binary", .default = "./bin" },
        .{ .name = "CGO_ENABLED", .description = "Enable CGO (0 or 1)", .default = "0" },
    },
    .content =
    \\[tasks.build]
    \\cmd = "go build -o ${OUTPUT_DIR}/${PROJECT_NAME} ."
    \\description = "Build ${PROJECT_NAME} binary"
    \\env = { CGO_ENABLED = "${CGO_ENABLED}" }
    \\
    ,
};

pub const cargo_build = Template{
    .name = "cargo-build",
    .category = .build,
    .description = "Build Rust project with Cargo",
    .variables = &[_]TemplateVariable{
        .{ .name = "PROFILE", .description = "Build profile (dev, release)", .default = "release" },
        .{ .name = "FEATURES", .description = "Cargo features to enable", .default = "" },
    },
    .content =
    \\[tasks.build]
    \\cmd = "cargo build --profile ${PROFILE}${FEATURES}"
    \\description = "Build Rust project (${PROFILE} mode)"
    \\
    ,
};

pub const npm_build = Template{
    .name = "npm-build",
    .category = .build,
    .description = "Build JavaScript/TypeScript project with npm",
    .variables = &[_]TemplateVariable{
        .{ .name = "BUILD_SCRIPT", .description = "npm script to run", .default = "build" },
        .{ .name = "NODE_ENV", .description = "Node environment", .default = "production" },
    },
    .content =
    \\[tasks.build]
    \\cmd = "npm run ${BUILD_SCRIPT}"
    \\description = "Build project with npm"
    \\env = { NODE_ENV = "${NODE_ENV}" }
    \\
    ,
};

pub const zig_build = Template{
    .name = "zig-build",
    .category = .build,
    .description = "Build Zig project with specified optimization mode",
    .variables = &[_]TemplateVariable{
        .{ .name = "OPTIMIZE", .description = "Optimization mode (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall)", .default = "ReleaseSafe" },
        .{ .name = "TARGET", .description = "Target triple (optional)", .default = "" },
    },
    .content =
    \\[tasks.build]
    \\cmd = "zig build -Doptimize=${OPTIMIZE}${TARGET}"
    \\description = "Build Zig project (${OPTIMIZE})"
    \\
    ,
};

pub const maven_build = Template{
    .name = "maven-build",
    .category = .build,
    .description = "Build Java project with Maven",
    .variables = &[_]TemplateVariable{
        .{ .name = "SKIP_TESTS", .description = "Skip tests during build", .default = "false" },
        .{ .name = "PROFILES", .description = "Maven profiles to activate", .default = "" },
    },
    .content =
    \\[tasks.build]
    \\cmd = "mvn clean package -DskipTests=${SKIP_TESTS}${PROFILES}"
    \\description = "Build Java project with Maven"
    \\
    ,
};

pub const dotnet_build = Template{
    .name = "dotnet-build",
    .category = .build,
    .description = "Build .NET project",
    .variables = &[_]TemplateVariable{
        .{ .name = "CONFIGURATION", .description = "Build configuration (Debug, Release)", .default = "Release" },
        .{ .name = "FRAMEWORK", .description = "Target framework (optional)", .default = "" },
    },
    .content =
    \\[tasks.build]
    \\cmd = "dotnet build --configuration ${CONFIGURATION}${FRAMEWORK}"
    \\description = "Build .NET project (${CONFIGURATION})"
    \\
    ,
};

pub const all = [_]Template{
    go_build,
    cargo_build,
    npm_build,
    zig_build,
    maven_build,
    dotnet_build,
};
