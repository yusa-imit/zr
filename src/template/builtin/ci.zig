const types = @import("../types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;

pub const cache_setup = Template{
    .name = "cache-setup",
    .category = .ci,
    .description = "Setup dependency caching for CI",
    .variables = &[_]TemplateVariable{
        .{ .name = "CACHE_KEY", .description = "Cache key pattern", .required = true },
        .{ .name = "CACHE_PATHS", .description = "Paths to cache", .required = true },
    },
    .content =
    \\[tasks.cache-restore]
    \\cmd = "# Restore cache: ${CACHE_KEY}"
    \\description = "Restore dependency cache"
    \\
    \\[tasks.cache-save]
    \\cmd = "# Save cache: ${CACHE_KEY} from ${CACHE_PATHS}"
    \\description = "Save dependency cache"
    \\
    ,
};

pub const artifact_upload = Template{
    .name = "artifact-upload",
    .category = .ci,
    .description = "Upload build artifacts in CI",
    .variables = &[_]TemplateVariable{
        .{ .name = "ARTIFACT_NAME", .description = "Artifact name", .required = true },
        .{ .name = "ARTIFACT_PATH", .description = "Path to artifacts", .required = true },
    },
    .content =
    \\[tasks.upload-artifacts]
    \\cmd = "# Upload ${ARTIFACT_NAME} from ${ARTIFACT_PATH}"
    \\description = "Upload build artifacts"
    \\
    ,
};

pub const parallel_matrix = Template{
    .name = "parallel-matrix",
    .category = .ci,
    .description = "Setup parallel matrix execution for CI",
    .variables = &[_]TemplateVariable{
        .{ .name = "MATRIX_VARS", .description = "Matrix variable names", .default = "os,version" },
    },
    .content =
    \\[workflows.ci-matrix]
    \\description = "Run tests across matrix of ${MATRIX_VARS}"
    \\stages = [
    \\  { parallel = ["build", "test"] }
    \\]
    \\
    \\[workflows.ci-matrix.matrix]
    \\# Define matrix dimensions for ${MATRIX_VARS}
    \\
    ,
};

pub const all = [_]Template{
    cache_setup,
    artifact_upload,
    parallel_matrix,
};
