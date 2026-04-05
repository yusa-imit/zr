const types = @import("../types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;

pub const semantic_release = Template{
    .name = "semantic-release",
    .category = .release,
    .description = "Semantic versioning and automated releases",
    .variables = &[_]TemplateVariable{
        .{ .name = "VERSION_FILE", .description = "File containing version", .default = "VERSION" },
        .{ .name = "CHANGELOG", .description = "Changelog file", .default = "CHANGELOG.md" },
    },
    .content =
    \\[tasks.version-bump]
    \\cmd = "# Bump version in ${VERSION_FILE}"
    \\description = "Increment version number"
    \\
    \\[tasks.changelog]
    \\cmd = "# Update ${CHANGELOG} with latest changes"
    \\description = "Update changelog"
    \\deps = ["version-bump"]
    \\
    \\[tasks.tag-release]
    \\cmd = "git tag -a v$(cat ${VERSION_FILE}) -m 'Release v$(cat ${VERSION_FILE})'"
    \\description = "Create release tag"
    \\deps = ["changelog"]
    \\
    ,
};

pub const cargo_publish = Template{
    .name = "cargo-publish",
    .category = .release,
    .description = "Publish Rust crate to crates.io",
    .variables = &[_]TemplateVariable{
        .{ .name = "DRY_RUN", .description = "Dry run mode (--dry-run)", .default = "" },
    },
    .content =
    \\[tasks.publish]
    \\cmd = "cargo publish${DRY_RUN}"
    \\description = "Publish crate to crates.io"
    \\deps = ["test", "build"]
    \\
    ,
};

pub const npm_publish = Template{
    .name = "npm-publish",
    .category = .release,
    .description = "Publish package to npm registry",
    .variables = &[_]TemplateVariable{
        .{ .name = "REGISTRY", .description = "npm registry URL", .default = "" },
        .{ .name = "TAG", .description = "npm dist-tag", .default = "latest" },
    },
    .content =
    \\[tasks.publish]
    \\cmd = "npm publish --tag ${TAG}${REGISTRY}"
    \\description = "Publish to npm"
    \\deps = ["test", "build"]
    \\
    ,
};

pub const all = [_]Template{
    semantic_release,
    cargo_publish,
    npm_publish,
};
