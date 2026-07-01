[![CI](https://github.com/AndriyKalashnykov/dapr-go/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/dapr-go/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/dapr-go.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/dapr-go/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-brightgreen.svg)](https://opensource.org/licenses/Apache-2.0)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/dapr-go)

# dapr-go

Reference implementation of four Go microservices using two Dapr building blocks — State Management and Pub/Sub — running on Kubernetes via per-pod Dapr sidecar injection (`dapr.io/enabled` annotations). Redis backs both the state store and pub/sub broker; KinD with `cloud-provider-kind` provides the local Kubernetes cluster and `LoadBalancer` IPs.

<p align="center"><img src="docs/diagrams/out/c4-container.png" alt="C4 Container — dapr-go" width="800"></p>

| Component | Technology |
|-----------|-----------|
| Language | Go 1.26.4 (multi-module — one `go.mod` per service) |
| HTTP routers | [chi](https://github.com/go-chi/chi) v5 (read-values, write-values, subscriber); `net/http` (frontendsvc) |
| Dapr client | [dapr/go-sdk](https://github.com/dapr/go-sdk) |
| Runtime | Dapr 1.15.10 — sidecar-injection model |
| State store + pub/sub broker | Redis (Bitnami Helm chart, replication architecture) |
| Local cluster | [KinD](https://kind.sigs.k8s.io/) v0.27 + [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) |
| Toolchain manager | [mise](https://mise.jdx.dev/) (`.mise.toml` pins go, kind, kubectl, helm, dapr-cli) |
| Container build | Docker Buildx |
| CI | GitHub Actions |

## Quick Start

```bash
make deps                 # install toolchain via mise + cloud-provider-kind
make kind-deploy          # kind-up → deploy-dapr → deploy-components → deploy-workloads
```

`kind-deploy` brings up a complete environment: KinD cluster, Dapr control plane, Redis state store + pub/sub broker, and all four services with sidecars injected. `cloud-provider-kind` runs in the background and assigns external IPs to the `LoadBalancer` Services automatically.

Tear down in reverse:

```bash
make undeploy-workloads   # remove application workloads
make undeploy-components  # remove Redis + the Secret
make undeploy-dapr        # remove the Dapr control plane
make kind-down            # delete the cluster + prune kindccm-* orphan sidecars
```

Smoke-test the deployed services after `kubectl --context kind-dapr-go -n dapr-go get svc` lists assigned LoadBalancer IPs:

```bash
curl -X POST 'http://<write-values-ip>/?value=90'   # publish a value
curl 'http://<read-values-ip>/'                      # returns running average
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Git](https://git-scm.com/) | latest | Version control |
| [Docker](https://www.docker.com/) | latest | Container builds + KinD nodes + cloud-provider-kind |
| [mise](https://mise.jdx.dev/) | latest | Pins go, kind, kubectl, helm, dapr-cli per `.mise.toml` (auto-installed by `make deps`) |

`make deps` bootstraps mise (if absent), runs `mise install` against `.mise.toml`, and `go install`s `cloud-provider-kind`, `golangci-lint`, and `govulncheck`.

## Architecture

Four independent Go services interact only through Dapr — none of them call Redis or each other directly. Every service-to-Dapr call goes via the per-pod `daprd` sidecar over localhost gRPC.

```text
client ── POST ─▶ write-values  ── SaveState ────▶  Redis (statestore key "values")
                                ── PublishEvent ─▶  notifications-pubsub / topic "notifications" ──▶ subscriber

client ── GET ──▶ read-values   ── GetState ─────▶  Redis (statestore key "values")  → returns integer average
```

| Service | Endpoint | Behaviour |
|---------|----------|-----------|
| `write-values` | `POST /?value=N` | Appends `N` to JSON `MyValues{Values []string}` at key `values`; publishes raw `N` on the `notifications` topic. |
| `read-values` | `GET /` | Reads `values`, parses each entry as `int`, returns the integer average (count-zero safe). |
| `subscriber` | `POST /notifications` | Receives every event from the `notifications` topic via the Dapr `Subscription` CR. |
| `state/frontendsvc` | `POST /orders/new`, `GET /orders/order/{id}` | Standalone state-management demo; not part of the read/write pipeline. |

Component manifests live in `k8s/dapr/components/` (Redis-backed `statestore` and `notifications-pubsub`); workload manifests live in `k8s/apps/`. The Redis password is held in the `redis-password-secret` k8s Secret and consumed by the components via `secretKeyRef`.

Source diagrams in `docs/diagrams/`; regenerate with `make diagrams`.

### Service environment variables

All services read configuration via `GetenvOrDefault`:

| Variable | Default | Used by |
|----------|---------|---------|
| `APP_PORT` | `8080` | all services |
| `STATE_STORE_NAME` | `statestore` | read-values, write-values |
| `PUB_SUB_NAME` | `notifications-pubsub` | write-values |
| `PUB_SUB_TOPIC` | `notifications` | write-values |

## Available Make Targets

Run `make help` to see all targets.

### Build & Test

The project uses a three-layer test pyramid:

- **`make test`** (seconds, no Docker) — unit tests with `-race -cover`. Fakes the Dapr client via a minimal interface defined at the use site, exhausts handler logic and error branches.
- **`make integration-test`** (~10s, Docker required) — Testcontainers Redis + go-redis. Validates JSON wire-format roundtrip and the cross-service contract between write-values' producer shape and read-values' parser. Build-tagged `integration` so unit runs stay fast.
- **`make e2e`** (minutes, requires KinD + Docker) — runs `e2e/e2e-test.sh` against an already-running cluster: state roundtrip, pub/sub roundtrip, frontendsvc CRUD, and a 404 negative case. Use `make e2e-full` from a fresh checkout to bring up the cluster and run e2e in one command.

| Target | Description |
|--------|-------------|
| `make build` | Build all service binaries for the current platform |
| `make build-linux-amd64` | Cross-compile for `linux/amd64` (used by `image-build`) |
| `make test` | Run unit tests with `-race -cover` in every service module |
| `make integration-test` | Run integration tests against Testcontainers Redis (`-tags=integration`) |
| `make lint` | Run golangci-lint across every service module |
| `make vulncheck` | Run govulncheck across every service module |
| `make trivy-fs` | Trivy filesystem scan (HIGH+CRITICAL, fixed-only) |
| `make static-check` | Composite gate (lint + vulncheck + diagrams-check + trivy-fs) |
| `make get` / `make update` | `go mod tidy` / `go get -u` in every module |
| `make clean` | Remove compiled binaries |

### Container images

| Target | Description |
|--------|-------------|
| `make image-build` | Build local images for all services (`linux/amd64`, `--load`) |
| `make image-push` | Build and push multi-arch images (`linux/amd64,linux/arm64`) |

### KinD cluster + Dapr lifecycle

| Target | Description |
|--------|-------------|
| `make kind-up` / `make kind-down` | Create / delete the KinD cluster (with `cloud-provider-kind`) |
| `make kind-deploy` | Full bring-up: `kind-up` → `deploy-dapr` → `deploy-components` → `deploy-workloads` |
| `make kind-destroy` | Alias for `kind-down` |
| `make deploy-dapr` / `make undeploy-dapr` | Install / uninstall the Dapr control plane |
| `make deploy-components` / `make undeploy-components` | Install / uninstall Redis + the password Secret |
| `make deploy-workloads` / `make undeploy-workloads` | Build images, load into KinD, apply manifests / remove |
| `make e2e` | End-to-end smoke test against a running cluster (`e2e/e2e-test.sh`) |
| `make e2e-full` | Convenience: `kind-deploy` + `e2e` in one command (fresh-checkout flow) |

### Diagrams

| Target | Description |
|--------|-------------|
| `make diagrams` | Render `docs/diagrams/*.puml` to `docs/diagrams/out/*.png` via pinned `plantuml/plantuml` Docker image |
| `make diagrams-check` | Verify rendered PNGs match committed copies (wired into `static-check`) |
| `make diagrams-clean` | Remove rendered PNGs |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Full local pipeline: `deps` → `static-check` → `test` → `build` → `image-build` |
| `make ci-run` | Run the GitHub Actions workflow locally via [act](https://github.com/nektos/act) |
| `make renovate-validate` | Validate `renovate.json` via `npx renovate --platform=local` |

### Release

| Target | Description |
|--------|-------------|
| `make version` | Print the current git tag |
| `make release NEWTAG=vX.Y.Z` | Tag a new release (interactive confirmation) |

## CI/CD

`.github/workflows/ci.yml` runs on push to `main`, tags `v*`, pull requests, and via `workflow_call`:

| Job | Triggers | Steps |
|-----|----------|-------|
| `changes` | every event | `dorny/paths-filter` — emits `code=true` for non-doc-only changes |
| `static-check` | when `code=true` | `make static-check` (lint, vulncheck, diagrams-check, trivy-fs) |
| `build` | after `static-check` | `make build` + `make image-build` |
| `test` | after `static-check` | `make test` |
| `integration-test` | after `static-check` | `make integration-test` (Testcontainers Redis) |
| `e2e` | after `build`, `test`, `integration-test` | `make kind-deploy` → `make e2e` → `make kind-down` (always); diagnostic dump on failure |
| `docker` | tag-gated (`v*` only); after `build`, `test`, `integration-test`, `e2e` | Per-service matrix: build for scan → Trivy → smoke → multi-arch push → cosign sign |
| `ci-pass` | always | Aggregator — fails if any required upstream job failed/cancelled |

### Pre-push image hardening

The `docker` job runs the following gates **before** any image is pushed to GHCR. Any failure blocks the release for that service. Runs as a 4-way matrix (read-values, write-values, subscriber, frontendsvc).

| # | Gate | Catches | Tool |
|---|------|---------|------|
| 1 | Build local single-arch image (linux/amd64, `--load`) | Build regressions on the runner architecture; multi-stage Go build inside the container | `docker/build-push-action` with `load: true` |
| 2 | **Trivy image scan** (CRITICAL/HIGH, fixed only) | CVEs in the alpine base, Go binary, and transitive deps | `aquasecurity/trivy-action` with `image-ref:` |
| 3 | **Smoke test** | Image boots correctly on its own. `subscriber` uses a boot-marker probe; the Dapr-using services (which `dapr.NewClient()` upstream and exit without a sidecar) use a container-shape probe asserting UID 10001 + `/app/main` is owned by `app:app` and executable. | `docker run` |
| 4 | Multi-arch build + push | Publishes for both `linux/amd64` and `linux/arm64` | `docker/build-push-action` with `provenance: false` + `sbom: false` |
| 5 | **Cosign keyless OIDC signing** | Sigstore signature on the manifest digest | `sigstore/cosign-installer` + `cosign sign --yes` |

Buildkit in-manifest attestations (`provenance` + `sbom`) are deliberately disabled so the image index stays free of `unknown/unknown` platform entries — that lets the GHCR Packages UI render the "OS / Arch" tab for the multi-arch manifest. Cosign keyless signing still provides Sigstore signature for supply-chain verification.

Verify a published image's signature with:

```bash
cosign verify ghcr.io/andriykalashnykov/dapr-go/<svc>:<tag> \
  --certificate-identity-regexp 'https://github\.com/AndriyKalashnykov/dapr-go/\.github/workflows/ci\.yml@refs/tags/v.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Concurrency uses `cancel-in-progress: true`. Permissions default to `contents: read` (least privilege).

`.github/workflows/cleanup-runs.yml` prunes old workflow runs every Sunday (cron) and supports manual dispatch.

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.

## References

- [Dapr arguments and annotations overview](https://docs.dapr.io/reference/arguments-annotations-overview/)
- [Reference secrets in components — non-default namespaces](https://docs.dapr.io/operations/components/component-secrets/#non-default-namespaces)
- [dapr/go-sdk pubsub examples](https://github.com/dapr/go-sdk/tree/main/examples/pubsub)

## License

Licensed under the [Apache License 2.0](LICENSE).
