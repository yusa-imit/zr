const types = @import("../types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;

pub const docker_push = Template{
    .name = "docker-push",
    .category = .deploy,
    .description = "Build and push Docker image",
    .variables = &[_]TemplateVariable{
        .{ .name = "IMAGE_NAME", .description = "Docker image name", .required = true },
        .{ .name = "TAG", .description = "Image tag", .default = "latest" },
        .{ .name = "REGISTRY", .description = "Docker registry URL", .default = "" },
    },
    .content =
    \\[tasks.docker-build]
    \\cmd = "docker build -t ${IMAGE_NAME}:${TAG} ."
    \\description = "Build Docker image"
    \\
    \\[tasks.docker-push]
    \\cmd = "docker push ${REGISTRY}${IMAGE_NAME}:${TAG}"
    \\description = "Push Docker image to registry"
    \\deps = ["docker-build"]
    \\
    ,
};

pub const k8s_deploy = Template{
    .name = "k8s-deploy",
    .category = .deploy,
    .description = "Deploy to Kubernetes cluster",
    .variables = &[_]TemplateVariable{
        .{ .name = "NAMESPACE", .description = "Kubernetes namespace", .default = "default" },
        .{ .name = "MANIFEST", .description = "Kubernetes manifest file", .default = "k8s/deployment.yaml" },
    },
    .content =
    \\[tasks.deploy]
    \\cmd = "kubectl apply -f ${MANIFEST} -n ${NAMESPACE}"
    \\description = "Deploy to Kubernetes"
    \\
    ,
};

pub const terraform_apply = Template{
    .name = "terraform-apply",
    .category = .deploy,
    .description = "Apply Terraform configuration",
    .variables = &[_]TemplateVariable{
        .{ .name = "TF_DIR", .description = "Terraform directory", .default = "terraform/" },
        .{ .name = "AUTO_APPROVE", .description = "Auto-approve changes", .default = "false" },
    },
    .content =
    \\[tasks.tf-plan]
    \\cmd = "terraform plan"
    \\cwd = "${TF_DIR}"
    \\description = "Plan Terraform changes"
    \\
    \\[tasks.tf-apply]
    \\cmd = "terraform apply${AUTO_APPROVE}"
    \\cwd = "${TF_DIR}"
    \\description = "Apply Terraform configuration"
    \\deps = ["tf-plan"]
    \\
    ,
};

pub const all = [_]Template{
    docker_push,
    k8s_deploy,
    terraform_apply,
};
