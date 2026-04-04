const types = @import("types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;
const Platform = types.Platform;
const TemplateType = types.TemplateType;

/// Basic CI template for GitLab CI
pub const basic_ci = Template.init(
    .gitlab_ci,
    .basic_ci,
    "GitLab CI Basic CI",
    "Basic continuous integration workflow with zr",
    \\stages:
    \\  - build
    \\  - test
    \\
    \\variables:
    \\  ZR_VERSION: "${ZR_VERSION}"
    \\
    \\cache:
    \\  key:
    \\    files:
    \\      - zr.toml
    \\  paths:
    \\    - .zr/cache
    \\
    \\before_script:
    \\  - curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-linux-x86_64.tar.gz | tar xz
    \\  - export PATH=$PWD:$PATH
    \\
    \\build:
    \\  stage: build
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${BUILD_TASK}
    \\  artifacts:
    \\    paths:
    \\      - zig-out/
    \\    expire_in: 1 week
    \\
    \\test:
    \\  stage: test
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${TEST_TASK}
    \\  dependencies:
    \\    - build
,
    &[_]TemplateVariable{
        TemplateVariable.init("IMAGE", "Docker image to use", "ubuntu:latest", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
        TemplateVariable.init("ZR_VERSION", "zr version", "latest", false),
    },
);

/// Monorepo CI template with affected detection
pub const monorepo = Template.init(
    .gitlab_ci,
    .monorepo,
    "GitLab CI Monorepo CI",
    "Monorepo workflow with affected builds and caching",
    \\stages:
    \\  - detect
    \\  - build
    \\  - test
    \\
    \\variables:
    \\  ZR_VERSION: "${ZR_VERSION}"
    \\
    \\cache:
    \\  key:
    \\    files:
    \\      - zr.toml
    \\  paths:
    \\    - .zr/cache
    \\    - node_modules/
    \\
    \\before_script:
    \\  - curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-linux-x86_64.tar.gz | tar xz
    \\  - export PATH=$PWD:$PATH
    \\
    \\detect_affected:
    \\  stage: detect
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr affected --json > .affected.json
    \\  artifacts:
    \\    paths:
    \\      - .affected.json
    \\    expire_in: 1 day
    \\
    \\build_project_a:
    \\  stage: build
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${BUILD_TASK} --workspace=projects/a
    \\  artifacts:
    \\    paths:
    \\      - projects/a/zig-out/
    \\    expire_in: 1 week
    \\  rules:
    \\    - changes:
    \\        - projects/a/**/*
    \\        - zr.toml
    \\
    \\test_project_a:
    \\  stage: test
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${TEST_TASK} --workspace=projects/a
    \\  dependencies:
    \\    - build_project_a
    \\  rules:
    \\    - changes:
    \\        - projects/a/**/*
    \\        - zr.toml
    \\
    \\build_project_b:
    \\  stage: build
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${BUILD_TASK} --workspace=projects/b
    \\  artifacts:
    \\    paths:
    \\      - projects/b/zig-out/
    \\    expire_in: 1 week
    \\  rules:
    \\    - changes:
    \\        - projects/b/**/*
    \\        - zr.toml
    \\
    \\test_project_b:
    \\  stage: test
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${TEST_TASK} --workspace=projects/b
    \\  dependencies:
    \\    - build_project_b
    \\  rules:
    \\    - changes:
    \\        - projects/b/**/*
    \\        - zr.toml
,
    &[_]TemplateVariable{
        TemplateVariable.init("IMAGE", "Docker image to use", "ubuntu:latest", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
        TemplateVariable.init("ZR_VERSION", "zr version", "latest", false),
    },
);

/// Release automation template
pub const release = Template.init(
    .gitlab_ci,
    .release,
    "GitLab CI Release",
    "Automated release workflow with versioning and publishing",
    \\stages:
    \\  - build
    \\  - test
    \\  - publish
    \\  - release
    \\
    \\variables:
    \\  ZR_VERSION: "${ZR_VERSION}"
    \\
    \\cache:
    \\  key:
    \\    files:
    \\      - zr.toml
    \\  paths:
    \\    - .zr/cache
    \\
    \\before_script:
    \\  - curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-linux-x86_64.tar.gz | tar xz
    \\  - export PATH=$PWD:$PATH
    \\
    \\build_release:
    \\  stage: build
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${BUILD_TASK} --profile=release
    \\  artifacts:
    \\    paths:
    \\      - zig-out/
    \\    expire_in: 1 week
    \\  only:
    \\    - tags
    \\
    \\test_release:
    \\  stage: test
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${TEST_TASK}
    \\  dependencies:
    \\    - build_release
    \\  only:
    \\    - tags
    \\
    \\publish:
    \\  stage: publish
    \\  image: ${IMAGE}
    \\  script:
    \\    - zr run ${PUBLISH_TASK}
    \\  dependencies:
    \\    - test_release
    \\  env:
    \\    GITHUB_TOKEN: $GITHUB_TOKEN
    \\  only:
    \\    - tags
    \\
    \\create_release:
    \\  stage: release
    \\  image: curlimages/curl:latest
    \\  script:
    \\    - |
    \\      curl -X POST \
    \\        -H "Authorization: token $GITHUB_TOKEN" \
    \\        -H "Accept: application/vnd.github.v3+json" \
    \\        "https://api.github.com/repos/$CI_PROJECT_PATH/releases" \
    \\        -d "{
    \\          \"tag_name\":\"$CI_COMMIT_TAG\",
    \\          \"name\":\"Release $CI_COMMIT_TAG\",
    \\          \"draft\":false,
    \\          \"prerelease\":false
    \\        }"
    \\  only:
    \\    - tags
,
    &[_]TemplateVariable{
        TemplateVariable.init("IMAGE", "Docker image to use", "ubuntu:latest", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
        TemplateVariable.init("PUBLISH_TASK", "Publish task name", "publish", false),
        TemplateVariable.init("ZR_VERSION", "zr version", "latest", false),
    },
);

/// All GitLab CI templates
pub const templates = [_]Template{
    basic_ci,
    monorepo,
    release,
};
