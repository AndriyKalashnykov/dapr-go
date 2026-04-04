# CLAUDE.md

## Project Overview

Go microservices project demonstrating Dapr (Distributed Application Runtime) building blocks -- State Management and Pub/Sub -- running on Kubernetes with Dapr Ambient proxy. Includes four services: read-values, write-values, subscriber, and a state frontend service.

**Owner:** AndriyKalashnykov/dapr-go

## Tech Stack

- **Language**: Go 1.26.0 (multi-module workspace -- each service has its own `go.mod`)
- **Framework**: Dapr Go SDK, chi (HTTP router)
- **Infrastructure**: Kubernetes, Minikube, Redis (state store), Dapr sidecars / Dapr Ambient
- **Build**: Make (task runner), Docker/Buildx (container images)
- **CI**: GitHub Actions

## Project Structure

```
read-values/       - Reads stored values and returns an average
write-values/      - Writes values to Redis via Dapr Ambient
subscriber/        - Listens for pub/sub notifications from write-values
state/frontendsvc/ - State management frontend service
k8s/               - Kubernetes manifests
scripts/           - Shell scripts for Minikube, Dapr, components, workloads
docs/              - Documentation and architecture diagrams
.github/           - CI workflows
```

Each service directory (`read-values/`, `subscriber/`, `write-values/`, `state/frontendsvc/`) is an independent Go module with its own `go.mod` and `go.sum`.

## Build & Test

```bash
make help              # List all available targets
make build             # Build all service binaries (linux/amd64)
make test              # Run tests for all services
make clean             # Remove compiled binaries
make get               # Download and install dependency packages
make update            # Update dependencies to latest versions
make image-build       # Build Docker images for all services
make version           # Print current version (git tag)
make release           # Create and push a new tag
```

## Deploy

```bash
make minikube-start    # Start Minikube cluster
make minikube-stop     # Stop Minikube
make minikube-delete   # Delete Minikube cluster
make deploy-dapr       # Deploy Dapr to cluster
make undeploy-dapr     # Remove Dapr from cluster
make deploy-components # Deploy Redis, Kafka, etc.
make undeploy-components # Remove components
make deploy-workloads  # Build images and deploy services
make undeploy-workloads  # Remove services
```

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yml`) runs on push to `main`, tags `v*`, and pull requests.

Jobs:
1. **builds** -- Checkout, Setup Go, Build (`make build`), Build images (`make image-build`)
2. **tests** -- Checkout, Setup Go, Test (`make test`)

Both jobs run in parallel. Concurrency is set with `cancel-in-progress: true`. Permissions: `contents: write`, `packages: write`.

A separate cleanup workflow (`.github/workflows/cleanup-runs.yml`) removes old workflow runs weekly (Sunday cron) and supports manual trigger.

## Dependencies

- Go 1.26.0 (version set in each service's `go.mod`)
- Docker with Buildx for container images
- Minikube for local Kubernetes
- Dapr CLI for runtime management
- kubectl and Helm for Kubernetes deployment

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.yml` | `/ci-workflow` |
