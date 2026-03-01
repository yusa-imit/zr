# Docker/Kubernetes Workflow Example

This example demonstrates how to use `zr` to orchestrate Docker and Kubernetes workflows for a containerized Node.js application.

## Overview

This example shows:

- **Docker Build Automation**: Multi-stage builds with version tagging
- **Docker Compose**: Local development with multiple services
- **Kubernetes Deployment**: Production-grade manifests and deployment workflows
- **Security Scanning**: Container vulnerability scanning
- **Multi-stage Workflows**: From development to production deployment
- **Environment Management**: Dev, staging, and production configurations
- **Multi-architecture Builds**: Support for AMD64 and ARM64

## Project Structure

```
docker-kubernetes/
├── Dockerfile              # Multi-stage Docker build
├── docker-compose.yml      # Local development stack
├── deployment.yaml         # Kubernetes manifests
├── zr.toml                # Task and workflow definitions
├── package.json           # Node.js dependencies
└── src/
    └── server.js          # Example Express server
```

## Quick Start

### 1. Local Development with Docker Compose

Start the complete development stack (app + database + cache):

```bash
zr workflow local-dev
```

This workflow:
1. Starts PostgreSQL and Redis containers
2. Builds and starts the application
3. Verifies health checks

View logs:

```bash
zr compose-logs
```

Stop the stack:

```bash
zr compose-down
```

### 2. Build and Test Docker Image

Build the Docker image:

```bash
zr docker-build
```

This creates two tags:
- `myapp:latest`
- `myapp:<git-commit-hash>`

Scan for vulnerabilities:

```bash
zr docker-scan
```

Run integration tests:

```bash
zr integration-test
```

### 3. Deploy to Kubernetes

**Staging Deployment:**

```bash
zr workflow deploy-staging
```

This workflow:
1. Builds production-optimized image
2. Pushes to registry
3. Validates Kubernetes manifests
4. Deploys (with approval gate)

**Production Deployment:**

```bash
zr workflow deploy-production
```

This workflow includes:
1. Build and security scan
2. Registry push
3. Manifest validation
4. Pre-deployment status check with approval
5. Deployment with rollout status
6. Post-deployment verification
7. Automatic rollback on failure

## Available Tasks

### Docker Tasks

| Task | Description |
|------|-------------|
| `docker-build` | Build Docker image with version tags |
| `docker-build-prod` | Build with production optimizations and cache |
| `docker-scan` | Scan image for security vulnerabilities |
| `docker-push` | Push image to container registry |
| `docker-buildx` | Build multi-architecture image (AMD64 + ARM64) |

### Docker Compose Tasks

| Task | Description |
|------|-------------|
| `compose-up` | Start all services in background |
| `compose-down` | Stop all services |
| `compose-logs` | View service logs (set `SERVICE=app` for specific service) |
| `compose-ps` | List running services |
| `compose-restart` | Restart a service |
| `compose-build` | Build all services in parallel |

### Kubernetes Tasks

| Task | Description |
|------|-------------|
| `k8s-validate` | Validate manifests without applying |
| `k8s-deploy` | Deploy to cluster with rollout status |
| `k8s-rollback` | Rollback to previous deployment |
| `k8s-scale` | Scale deployment (set `REPLICAS=5`) |
| `k8s-logs` | View pod logs |
| `k8s-exec` | Execute command in pod (set `COMMAND=bash`) |
| `k8s-status` | Check deployment, pods, and services |
| `k8s-delete` | Delete deployment from cluster |

### Environment-Specific Deployment

| Task | Description | Environment |
|------|-------------|-------------|
| `deploy-dev` | Deploy to dev namespace | 1 replica |
| `deploy-staging` | Deploy to staging namespace | 2 replicas |
| `deploy-prod` | Deploy to production namespace | 3 replicas |

### Development Tasks

| Task | Description |
|------|-------------|
| `dev-setup` | Start database and cache for local development |
| `dev-teardown` | Stop and remove all volumes |
| `health-check` | Verify application health endpoint |
| `integration-test` | Run integration tests against Docker Compose stack |

## Workflows

### local-dev

Local development setup with health checks.

```bash
zr workflow local-dev
```

Stages:
1. **setup**: Start database and cache
2. **run**: Start application
3. **verify**: Check health endpoints

### ci-build

CI/CD build and test pipeline.

```bash
zr workflow ci-build
```

Stages:
1. **build**: Build Docker image
2. **scan**: Security vulnerability scan
3. **test**: Integration tests

Fails fast on any stage failure.

### deploy-staging

Deploy to staging environment with validation.

```bash
zr workflow deploy-staging
```

Stages:
1. **build**: Production-optimized build
2. **push**: Push to registry
3. **validate**: Kubernetes manifest validation
4. **deploy**: Deploy with approval gate

### deploy-production

Production deployment with safety checks and rollback.

```bash
zr workflow deploy-production
```

Stages:
1. **build**: Production build with optimizations
2. **scan**: Security scan
3. **push**: Push to registry
4. **validate**: Manifest validation
5. **pre-deploy**: Status check with approval
6. **deploy**: Deploy to cluster
7. **verify**: Post-deployment verification

On failure: Automatic rollback to previous deployment.

## Environment Variables

Control behavior with environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `VERSION` | `latest` | Image version tag |
| `REGISTRY` | `docker.io` | Container registry URL |
| `SERVICE` | `app` | Service name for compose-logs |
| `REPLICAS` | `3` | Number of replicas for k8s-scale |
| `COMMAND` | `sh` | Command for k8s-exec |
| `ENVIRONMENT` | - | Deployment environment (dev/staging/prod) |

Examples:

```bash
# Build with specific version
VERSION=1.2.3 zr docker-build

# Push to custom registry
REGISTRY=gcr.io/myproject zr docker-push

# Scale to 10 replicas
REPLICAS=10 zr k8s-scale

# View logs for specific service
SERVICE=db zr compose-logs
```

## Multi-Architecture Builds

Build images for multiple architectures using Docker Buildx:

```bash
zr docker-buildx
```

This builds and pushes images for:
- `linux/amd64` (Intel/AMD)
- `linux/arm64` (Apple Silicon, ARM servers)

The task uses zr's matrix feature to parallelize builds across architectures.

## Docker Features Demonstrated

### Multi-stage Build

The Dockerfile uses two stages:

1. **builder**: Installs dependencies and prepares application
2. **production**: Minimal runtime image with non-root user

Benefits:
- Smaller final image (~50MB vs ~500MB)
- Better security (non-root user)
- Faster deployments
- Reduced attack surface

### Build Arguments

```bash
docker build \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg VCS_REF=$(git rev-parse HEAD) \
  .
```

These are embedded as labels for traceability.

### Health Checks

Both Dockerfile and docker-compose.yml include health checks:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s \
  CMD node -e "require('http').get('http://localhost:3000/health', ...)"
```

Docker uses this to:
- Mark containers as healthy/unhealthy
- Delay traffic until ready
- Restart unhealthy containers

## Kubernetes Features Demonstrated

### Deployment

`deployment.yaml` includes:

- **3 replicas** for high availability
- **Resource limits** (CPU/memory)
- **Liveness probes** (restart unhealthy pods)
- **Readiness probes** (delay traffic until ready)
- **ConfigMaps** for configuration
- **Secrets** for sensitive data

### Service

LoadBalancer service exposes the application:

```yaml
type: LoadBalancer
ports:
- port: 80
  targetPort: http
```

### Probes

**Liveness Probe** (restart if failing):
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10
```

**Readiness Probe** (remove from service if failing):
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and Test
        run: |
          zr workflow ci-build
      - name: Deploy to Staging
        if: github.ref == 'refs/heads/main'
        run: |
          VERSION=${{ github.sha }} zr workflow deploy-staging
```

### GitLab CI Example

```yaml
stages:
  - build
  - deploy

build:
  stage: build
  script:
    - zr workflow ci-build

deploy-staging:
  stage: deploy
  script:
    - VERSION=$CI_COMMIT_SHA zr workflow deploy-staging
  only:
    - main
```

## Troubleshooting

### Docker Build Failures

**Problem**: "ERROR: failed to solve"

**Solution**: Clear build cache
```bash
docker builder prune
zr docker-build
```

### Container Won't Start

**Problem**: Container exits immediately

**Solution**: Check logs
```bash
zr compose-logs
# or
docker logs <container-id>
```

### Kubernetes Pod CrashLoopBackOff

**Problem**: Pod keeps restarting

**Solution**: Check pod logs and events
```bash
zr k8s-logs
kubectl describe pod <pod-name>
```

### Health Check Failures

**Problem**: Container marked as unhealthy

**Solution**: Test health endpoint manually
```bash
zr health-check
# or
curl http://localhost:3000/health
```

### Image Pull Errors

**Problem**: "ImagePullBackOff" in Kubernetes

**Solution**: Verify image exists in registry
```bash
docker images | grep myapp
# Ensure image is pushed
zr docker-push
```

## Performance Optimization

### Build Cache

Use BuildKit cache for faster builds:

```bash
export DOCKER_BUILDKIT=1
zr docker-build-prod
```

The `docker-build-prod` task uses:
- `--cache-from` to reuse previous builds
- `--build-arg BUILDKIT_INLINE_CACHE=1` to export cache

### Layer Caching

Order Dockerfile instructions for optimal caching:

1. Copy `package.json` first (changes rarely)
2. Run `npm install` (cached if package.json unchanged)
3. Copy source code (changes frequently)

### Multi-stage Benefits

- **Build stage**: All build tools and dependencies
- **Production stage**: Only runtime dependencies

Result: 90% smaller final image.

## Security Best Practices

### 1. Non-root User

```dockerfile
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001
USER nodejs
```

Containers run as user `nodejs` (UID 1001), not root.

### 2. Security Scanning

```bash
zr docker-scan
```

Uses Docker Scout to detect:
- CVEs in dependencies
- Outdated packages
- Security misconfigurations

### 3. Secrets Management

Never hardcode secrets in:
- Dockerfile
- docker-compose.yml
- zr.toml

Use:
- Kubernetes Secrets
- Environment variables
- Secret management tools (Vault, AWS Secrets Manager)

### 4. Resource Limits

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
```

Prevents:
- Resource exhaustion
- Noisy neighbor problems
- Uncontrolled scaling costs

## Next Steps

1. **Customize**: Adapt `zr.toml` for your application
2. **Add Tests**: Integrate your test suite into workflows
3. **Set up Registry**: Configure your container registry (Docker Hub, ECR, GCR)
4. **Configure Kubernetes**: Update `deployment.yaml` with your cluster settings
5. **Integrate CI/CD**: Add zr workflows to your CI pipeline
6. **Monitor**: Add monitoring and logging (Prometheus, ELK stack)

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Compose](https://docs.docker.com/compose/)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

## When to Use This Pattern

✅ **Good fit:**
- Microservices architecture
- Cloud-native applications
- Multi-environment deployments (dev/staging/prod)
- Teams using Kubernetes
- Projects requiring container orchestration

❌ **Not ideal for:**
- Simple scripts without containerization needs
- Monolithic applications not using Docker
- Projects without Kubernetes infrastructure
