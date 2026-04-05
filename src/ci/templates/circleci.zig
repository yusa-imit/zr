const types = @import("types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;
const Platform = types.Platform;
const TemplateType = types.TemplateType;

/// Basic CI template for CircleCI
pub const basic_ci = Template.init(
    .circleci,
    .basic_ci,
    "CircleCI Basic CI",
    "Basic continuous integration workflow with zr",
    \\version: 2.1
    \\
    \\orbs:
    \\  zr: circleci/zr@1.0
    \\
    \\executors:
    \\  zr-executor:
    \\    docker:
    \\      - image: ${IMAGE}
    \\    resource_class: ${RESOURCE_CLASS}
    \\
    \\commands:
    \\  install_zr:
    \\    steps:
    \\      - run:
    \\          name: Install zr
    \\          command: |
    \\            curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-linux-x86_64.tar.gz | tar xz
    \\            sudo mv zr /usr/local/bin/
    \\            zr --version
    \\
    \\jobs:
    \\  build:
    \\    executor: zr-executor
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - restore_cache:
    \\          keys:
    \\            - zr-cache-{{ checksum "zr.toml" }}
    \\            - zr-cache-
    \\      - run:
    \\          name: Build
    \\          command: zr run ${BUILD_TASK}
    \\      - save_cache:
    \\          key: zr-cache-{{ checksum "zr.toml" }}
    \\          paths:
    \\            - ~/.zr/cache
    \\      - persist_to_workspace:
    \\          root: .
    \\          paths:
    \\            - ${ARTIFACTS_PATH}
    \\
    \\  test:
    \\    executor: zr-executor
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - attach_workspace:
    \\          at: .
    \\      - run:
    \\          name: Test
    \\          command: zr run ${TEST_TASK}
    \\
    \\workflows:
    \\  version: 2
    \\  build_and_test:
    \\    jobs:
    \\      - build
    \\      - test:
    \\          requires:
    \\            - build
,
    &[_]TemplateVariable{
        TemplateVariable.init("IMAGE", "Docker image to use", "cimg/base:stable", false),
        TemplateVariable.init("RESOURCE_CLASS", "Resource class", "medium", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
        TemplateVariable.init("ARTIFACTS_PATH", "Artifacts path", "zig-out", false),
    },
);

/// Monorepo CI template with affected detection
pub const monorepo = Template.init(
    .circleci,
    .monorepo,
    "CircleCI Monorepo CI",
    "Monorepo workflow with affected builds and matrix execution",
    \\version: 2.1
    \\
    \\executors:
    \\  zr-executor:
    \\    docker:
    \\      - image: ${IMAGE}
    \\    resource_class: ${RESOURCE_CLASS}
    \\
    \\commands:
    \\  install_zr:
    \\    steps:
    \\      - run:
    \\          name: Install zr
    \\          command: |
    \\            curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-linux-x86_64.tar.gz | tar xz
    \\            sudo mv zr /usr/local/bin/
    \\            zr --version
    \\
    \\jobs:
    \\  detect_affected:
    \\    executor: zr-executor
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - run:
    \\          name: Detect affected projects
    \\          command: |
    \\            zr affected --json > .affected.json
    \\            cat .affected.json
    \\      - persist_to_workspace:
    \\          root: .
    \\          paths:
    \\            - .affected.json
    \\
    \\  build_project:
    \\    executor: zr-executor
    \\    parameters:
    \\      project:
    \\        type: string
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - restore_cache:
    \\          keys:
    \\            - zr-cache-<< parameters.project >>-{{ checksum "zr.toml" }}
    \\            - zr-cache-<< parameters.project >>-
    \\      - run:
    \\          name: Build << parameters.project >>
    \\          command: zr run ${BUILD_TASK} --workspace=projects/<< parameters.project >>
    \\      - save_cache:
    \\          key: zr-cache-<< parameters.project >>-{{ checksum "zr.toml" }}
    \\          paths:
    \\            - ~/.zr/cache
    \\      - persist_to_workspace:
    \\          root: .
    \\          paths:
    \\            - projects/<< parameters.project >>/${ARTIFACTS_PATH}
    \\
    \\  test_project:
    \\    executor: zr-executor
    \\    parameters:
    \\      project:
    \\        type: string
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - attach_workspace:
    \\          at: .
    \\      - run:
    \\          name: Test << parameters.project >>
    \\          command: zr run ${TEST_TASK} --workspace=projects/<< parameters.project >>
    \\
    \\workflows:
    \\  version: 2
    \\  monorepo_ci:
    \\    jobs:
    \\      - detect_affected
    \\      - build_project:
    \\          name: build_project_a
    \\          project: a
    \\          requires:
    \\            - detect_affected
    \\      - test_project:
    \\          name: test_project_a
    \\          project: a
    \\          requires:
    \\            - build_project_a
    \\      - build_project:
    \\          name: build_project_b
    \\          project: b
    \\          requires:
    \\            - detect_affected
    \\      - test_project:
    \\          name: test_project_b
    \\          project: b
    \\          requires:
    \\            - build_project_b
,
    &[_]TemplateVariable{
        TemplateVariable.init("IMAGE", "Docker image to use", "cimg/base:stable", false),
        TemplateVariable.init("RESOURCE_CLASS", "Resource class", "medium", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
        TemplateVariable.init("ARTIFACTS_PATH", "Artifacts path", "zig-out", false),
    },
);

/// Release automation template
pub const release = Template.init(
    .circleci,
    .release,
    "CircleCI Release",
    "Automated release workflow with versioning and publishing",
    \\version: 2.1
    \\
    \\executors:
    \\  zr-executor:
    \\    docker:
    \\      - image: ${IMAGE}
    \\    resource_class: ${RESOURCE_CLASS}
    \\
    \\commands:
    \\  install_zr:
    \\    steps:
    \\      - run:
    \\          name: Install zr
    \\          command: |
    \\            curl -fsSL https://github.com/yusa-imit/zr/releases/latest/download/zr-linux-x86_64.tar.gz | tar xz
    \\            sudo mv zr /usr/local/bin/
    \\            zr --version
    \\
    \\jobs:
    \\  build_release:
    \\    executor: zr-executor
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - run:
    \\          name: Build Release
    \\          command: zr run ${BUILD_TASK} --profile=release
    \\      - persist_to_workspace:
    \\          root: .
    \\          paths:
    \\            - ${ARTIFACTS_PATH}
    \\
    \\  test_release:
    \\    executor: zr-executor
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - attach_workspace:
    \\          at: .
    \\      - run:
    \\          name: Test Release
    \\          command: zr run ${TEST_TASK}
    \\
    \\  publish:
    \\    executor: zr-executor
    \\    steps:
    \\      - checkout
    \\      - install_zr
    \\      - attach_workspace:
    \\          at: .
    \\      - run:
    \\          name: Publish Release
    \\          command: zr run ${PUBLISH_TASK}
    \\
    \\  create_github_release:
    \\    docker:
    \\      - image: cimg/base:stable
    \\    steps:
    \\      - checkout
    \\      - attach_workspace:
    \\          at: .
    \\      - run:
    \\          name: Create GitHub Release
    \\          command: |
    \\            curl -X POST \
    \\              -H "Authorization: token $GITHUB_TOKEN" \
    \\              -H "Accept: application/vnd.github.v3+json" \
    \\              "https://api.github.com/repos/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/releases" \
    \\              -d "{
    \\                \"tag_name\":\"${CIRCLE_TAG}\",
    \\                \"name\":\"Release ${CIRCLE_TAG}\",
    \\                \"draft\":false,
    \\                \"prerelease\":false
    \\              }"
    \\
    \\workflows:
    \\  version: 2
    \\  release:
    \\    jobs:
    \\      - build_release:
    \\          filters:
    \\            tags:
    \\              only: /^v.*/
    \\            branches:
    \\              ignore: /.*/
    \\      - test_release:
    \\          requires:
    \\            - build_release
    \\          filters:
    \\            tags:
    \\              only: /^v.*/
    \\            branches:
    \\              ignore: /.*/
    \\      - publish:
    \\          requires:
    \\            - test_release
    \\          filters:
    \\            tags:
    \\              only: /^v.*/
    \\            branches:
    \\              ignore: /.*/
    \\      - create_github_release:
    \\          requires:
    \\            - publish
    \\          filters:
    \\            tags:
    \\              only: /^v.*/
    \\            branches:
    \\              ignore: /.*/
,
    &[_]TemplateVariable{
        TemplateVariable.init("IMAGE", "Docker image to use", "cimg/base:stable", false),
        TemplateVariable.init("RESOURCE_CLASS", "Resource class", "medium", false),
        TemplateVariable.init("BUILD_TASK", "Build task name", "build", false),
        TemplateVariable.init("TEST_TASK", "Test task name", "test", false),
        TemplateVariable.init("PUBLISH_TASK", "Publish task name", "publish", false),
        TemplateVariable.init("ARTIFACTS_PATH", "Artifacts path", "zig-out", false),
    },
);

/// All CircleCI templates
pub const templates = [_]Template{
    basic_ci,
    monorepo,
    release,
};
