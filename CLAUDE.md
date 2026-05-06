# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Demo of Dapr (Distributed Application Runtime) State Management and Pub/Sub building blocks running on Kubernetes via per-pod **Dapr sidecar injection** (`dapr.io/enabled: "true"` annotations). Four Go services interact through Dapr; none of them talk to Redis or each other directly. Local cluster is **KinD + cloud-provider-kind**, not Minikube.

**Owner:** AndriyKalashnykov/dapr-go

## Architecture

### Data flow

```text
client → write-values  ──SaveState────▶  Redis (statestore)
                       ──PublishEvent──▶  notifications-pubsub / "notifications" topic ──▶ subscriber
client → read-values   ──GetState─────▶  Redis (statestore)         (returns average of stored values)
```

- `write-values` (`POST /?value=N`) appends to a single state-store key `values` (a JSON `MyValues{Values []string}`) AND publishes the raw value on the `notifications` topic.
- `read-values` (`GET /`) reads the `values` key, parses each entry as int, returns the average (count-zero safe; uses `float64(total) / float64(count)` — not the integer-division bug the original code had).
- `subscriber` consumes the `notifications` topic via Dapr-routed POSTs to `/notifications`.
- `state/frontendsvc` is a separate state-management frontend (not part of the read/write/subscribe pipeline).

Each pod that uses Dapr carries `dapr.io/enabled: "true"`, `dapr.io/app-id`, and `dapr.io/app-port` annotations; the Dapr sidecar-injector mutates the pod to add a `daprd` sidecar. All Dapr API calls are made over **localhost gRPC** (port 50001 by default) to that sidecar — never directly to Redis. Components (state store, pub/sub) are configured in `k8s/dapr/components/` and deployed via `make deploy-components`. The Redis password lives in the `redis-password-secret` k8s Secret and is consumed via `secretKeyRef`.

### Multi-module layout (no workspace)

Each service directory is an **independent Go module** with its own `go.mod`/`go.sum`. There is no top-level `go.mod` and no `go.work`. Consequence: tooling that walks "the module" must `cd` into each service. The Makefile resolves `frontendsvc` → `state/frontendsvc` via a single `service_dir` Make function (not bash variable expansion — bash can't put hyphens in variable names, so `SERVICE_DIR_read-values` would fail; the Makefile uses a `case` dispatch in recipe bodies instead).

The CI workflow's `cache-dependency-path` lists each `<svc>/go.sum` explicitly; **`state/frontendsvc/go.sum` (with slash) is correct** — an earlier copy used `state-frontendsvc/go.sum` (with hyphen) which silently disabled module caching for that service.

**`go mod tidy` gotcha**: integration-test deps (`testcontainers-go`, `redis/go-redis/v9`) are imported only from `//go:build integration` files, so a vanilla `go mod tidy` strips them or moves them to `// indirect`. After running tidy you may see `missing go.sum entry for module providing package github.com/redis/go-redis/v9`. Fix: re-run with the build tag — `GOFLAGS='-tags=integration' go mod tidy`. The deps stay non-indirect and `go test -tags=integration` resolves them cleanly. Don't add a tools-import shim file (that pollutes the production binary).

### Service environment variables

| Var | Default | Used by |
|-----|---------|---------|
| `APP_PORT` | `8080` | all services |
| `STATE_STORE_NAME` | `statestore` | read-values, write-values |
| `PUB_SUB_NAME` | `notifications-pubsub` | write-values |
| `PUB_SUB_TOPIC` | `notifications` | write-values |

The Dapr component names (`statestore`, `notifications-pubsub`) must match the names in `k8s/dapr/components/` manifests.

## Build & Test

`make help` lists everything. Non-obvious behaviour:

- `make build` builds for the **current platform**; `make build-linux-amd64` cross-compiles for the alpine container and is what `image-build` depends on.
- `make test` runs `go test -race -cover` inside each service module via a `case`-dispatch loop. Single-service: `cd read-values && go test -race -cover ./...`.
- `make integration-test` runs `go test -tags=integration` per Dapr-using module (write-values, read-values, state/frontendsvc; subscriber is skipped — no Dapr/Redis interaction). Uses Testcontainers Redis to validate JSON wire-format roundtrip + the cross-service contract.
- `make static-check` is the composite gate: lint + vulncheck + diagrams-check + trivy-fs. Run before pushing.
- `make image-build` produces `ghcr.io/andriykalashnykov/dapr-go/<service>:<git-tag-without-v>` — same path/tag shape that `docker/metadata-action` publishes from CI, so KinD-loaded images and `kubectl apply` resolve to identical refs. `IMAGE_REPO_PREFIX` and `IMAGE_TAG` (defaults: `ghcr.io/andriykalashnykov/dapr-go` and `git describe --tags --abbrev=0 \| sed 's/^v//'`) are overridable.
- `make release NEWTAG=vX.Y.Z` is interactive (prompts for confirmation), tags + pushes. Do not invoke without explicit user approval.
- `make ci-run` runs the full GitHub Actions workflow locally via `act`.

## Deploy (KinD)

```text
make deps           # install toolchain via mise + cloud-provider-kind via go install
make kind-deploy    # kind-up → deploy-dapr → deploy-components → deploy-workloads
```

Tear down: `make undeploy-workloads` → `undeploy-components` → `undeploy-dapr` → `make kind-down`.

`kind-down` prunes `kindccm-*` Envoy sidecars before deleting the cluster — they survive `kind delete cluster` and would otherwise inherit stale Envoy config on the next `kind-up` (real-incident pattern from `/makefile` skill canonical recipe).

`cloud-provider-kind` runs as a host-side process (started in the background by `scripts/kind-up.sh`) and assigns external IPs to `LoadBalancer` Services. Logs land at `/tmp/cloud-provider-kind-dapr-go.log`.

All shell scripts use `kubectl --context kind-$(KIND_CLUSTER_NAME)` (the `${KUBECTL[@]}` array idiom) so a sibling project's `kubectl config use-context` cannot misroute commands.

## CI

`.github/workflows/ci.yml` has eight jobs: `changes` (path filter via `dorny/paths-filter`), `static-check`, `build`, `test`, `integration-test` (Testcontainers Redis), `e2e` (KinD + Dapr), `docker` (tag-gated multi-arch publish to GHCR with Trivy + smoke + cosign signing), and a final `ci-pass` aggregator. Triggers: push to `main`, tags `v*`, pull requests, `workflow_call:`. Workflow-level permissions are `contents: read` (least privilege); the `docker` job adds `packages: write` + `id-token: write` at job level.

The `docker` job is a 4-way matrix (read-values, write-values, subscriber, frontendsvc) running the canonical pre-push hardening pipeline: build single-arch for scanning → Trivy CRITICAL/HIGH gate → smoke test → multi-arch push (`provenance: false` + `sbom: false` to keep the GHCR Packages UI "OS / Arch" tab functional) → cosign keyless OIDC signing by digest.

Each service has a multi-stage `Dockerfile` (golang:1.26-alpine builder → alpine:3.23 runtime). The runtime stage runs as non-root UID 10001 with `/app/main` owned by `app:app`. The `BUILDPLATFORM` directive on the builder stage cross-compiles the Go binary to the target platform via `GOOS`/`GOARCH` build args, so a single Dockerfile drives both `linux/amd64` and `linux/arm64` images via QEMU emulation under buildx.

The smoke test pattern differs by service: `subscriber` uses a log-grep boot marker (`Starting Subscriber in Port`); the three Dapr-using services exit fast without a sidecar at `:50001`, so the smoke step instead verifies container shape — UID 10001, `/app/main` is `app:app`-owned and executable. Full Dapr-side validation lives in the `e2e` job.

`.github/workflows/cleanup-runs.yml` prunes old runs on a Sunday cron via native `gh` CLI.

## Toolchain

`.mise.toml` pins `go`, `kind`, `kubectl`, `helm`, and `dapr-cli` (via the `aqua:dapr/cli` backend). Each pin has a `# renovate:` annotation matched by the `customManagers` regex in `renovate.json`. `make deps` bootstraps mise (if absent), runs `mise install`, and `go install`s `cloud-provider-kind`, `golangci-lint`, `govulncheck`.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |
| `docs/diagrams/*.puml` | `/architecture-diagrams` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
