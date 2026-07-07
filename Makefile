.DEFAULT_GOAL := help

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

# Make sure mise-managed shims and ~/.local/bin are visible to recipes —
# Make spawns a non-interactive shell that does not source ~/.zshrc/~/.bashrc.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# ---------------------------------------------------------------------------
# Pinned tool versions — Renovate-tracked via inline comments
# ---------------------------------------------------------------------------
#
# Lint/vuln/CLI toolchain (golangci-lint, govulncheck, act, gitleaks,
# actionlint, shellcheck, cloud-provider-kind, kind, kubectl, helm, dapr,
# go) all live in .mise.toml — tracked by Renovate's native `mise` manager,
# no inline annotations needed here. Only tools this project invokes via
# `docker run` (never installed on the host) keep a Makefile constant:

# renovate: datasource=docker depName=plantuml/plantuml
PLANTUML_VERSION := 1.2025.7

# renovate: datasource=docker depName=aquasec/trivy
# Docker-invoked exception (like plantuml above) — trivy IS mise-installable
# (aqua:aquasecurity/trivy) but trivy-fs runs via `docker run` for a
# hermetic, host-independent scan; keep this pin rather than migrating.
TRIVY_VERSION := 0.69.1

# renovate: datasource=docker depName=catthehacker/ubuntu versioning=loose
ACT_UBUNTU_VERSION := act-latest-20260629

# renovate: datasource=docker depName=kindest/node
KIND_NODE_IMAGE := kindest/node:v1.34.0@sha256:7416a61b42b1662ca6ca89f02028ac133a309a2a30ba309614e8ec94d976dc5a

# ---------------------------------------------------------------------------
# Project metadata
# ---------------------------------------------------------------------------

KIND_CLUSTER_NAME ?= dapr-go
KUBECTL_CTX       := kind-$(KIND_CLUSTER_NAME)
DAPRGO_NS         ?= dapr-go
KUBECTL           := kubectl --context $(KUBECTL_CTX)

CURRENTTAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)
NEWTAG    ?=

# Match what `docker/metadata-action` publishes to GHCR — same path so the
# manifest in k8s/apps/*.yaml resolves the same image whether it's loaded
# into KinD locally (`make deploy-workloads` → `kind load docker-image`)
# or pulled from the registry by a non-KinD deploy.
# `:=` (not `?=`) — a stray same-named env var must not silently repoint
# every image reference; override explicitly via `make IMAGE_REPO_PREFIX=... `.
IMAGE_REPO_PREFIX := ghcr.io/andriykalashnykov/dapr-go
# Strip the `v` prefix from the latest git tag (metadata-action's
# semver pattern emits 0.1.0 for tag v0.1.0). Falls back to 0.0.0 on a
# fresh checkout with no tags.
IMAGE_TAG         ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)

SERVICES := read-values subscriber write-values frontendsvc

# Resolve a service name to its source directory. The frontendsvc service
# lives at state/frontendsvc; the others are named after their directory.
define service_dir
$(if $(filter frontendsvc,$(1)),state/frontendsvc,$(1))
endef

GOFLAGS := -mod=mod

# ---------------------------------------------------------------------------
# Help (canonical portfolio pattern)
# ---------------------------------------------------------------------------

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z0-9\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-22s\033[0m - %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

#deps: @ Full dev environment (all tools via mise — see .mise.toml)
deps: deps-tools

#deps-tools: @ Install the mise-managed toolchain (Go, kind, kubectl, helm, dapr, golangci-lint, govulncheck, gitleaks, actionlint, shellcheck, act, cloud-provider-kind)
deps-tools:
	@command -v mise >/dev/null 2>&1 || { \
		echo "Installing mise (no root required, installs to ~/.local/bin)..."; \
		curl -fsSL https://mise.run | sh; \
	}
	@mise install --yes

#deps-act: @ Install act (local GitHub Actions runner) — mise-managed; alias for deps-tools
deps-act: deps-tools

# ---------------------------------------------------------------------------
# Build / test / lint
# ---------------------------------------------------------------------------

#build: @ Build all service binaries for the current platform
build:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> build $$dir"; \
		(cd "$$dir" && GOFLAGS=$(GOFLAGS) CGO_ENABLED=0 go build -o main .); \
	done

#build-linux-amd64: @ Cross-compile all services for linux/amd64 (used by image-build)
build-linux-amd64:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> build (linux/amd64) $$dir"; \
		(cd "$$dir" && GOFLAGS=$(GOFLAGS) CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o main .); \
	done

#clean: @ Remove compiled binaries
clean:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		rm -f "$$dir/main"; \
	done

#test: @ Run unit tests (-race -cover) for every service module
test:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> test $$dir"; \
		(cd "$$dir" && GOFLAGS=$(GOFLAGS) go test -race -cover $$(go list ./...)); \
	done

#integration-test: @ Run integration tests against real Redis via Testcontainers (requires Docker)
integration-test:
	@for svc in $(SERVICES); do \
		case "$$svc" in \
			subscriber) echo ">> integration-test $$svc (skipped — no Dapr/Redis interaction)" ;; \
			frontendsvc) dir=state/frontendsvc ;; \
			*) dir=$$svc ;; \
		esac; \
		if [ "$$svc" = "subscriber" ]; then continue; fi; \
		echo ">> integration-test $$dir"; \
		(cd "$$dir" && GOFLAGS=$(GOFLAGS) go test -tags=integration -race -count=1 -timeout 300s ./...); \
	done

#check-toolchain-alignment: @ Verify Go version matches across every go.mod, .mise.toml, and Dockerfile (prevents Renovate split-PR deadlock)
check-toolchain-alignment:
	@set -e; \
	misefile=$$(grep -oP '^go\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+' .mise.toml); \
	misemajmin=$$(echo "$$misefile" | grep -oP '^[0-9]+\.[0-9]+'); \
	mismatch=0; \
	for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		gomod=$$(grep -oP '^go \K[0-9]+\.[0-9]+\.[0-9]+' "$$dir/go.mod"); \
		dockerfile=$$(grep -oP 'golang:\K[0-9]+\.[0-9]+' "$$dir/Dockerfile" | head -1); \
		if [ "$$gomod" != "$$misefile" ]; then \
			echo "ERROR: Go version mismatch — $$dir/go.mod ($$gomod) != .mise.toml go ($$misefile)"; \
			mismatch=1; \
		fi; \
		if [ "$$dockerfile" != "$$misemajmin" ]; then \
			echo "ERROR: Go version mismatch — $$dir/Dockerfile (golang:$$dockerfile) != .mise.toml minor ($$misemajmin)"; \
			mismatch=1; \
		fi; \
	done; \
	if [ "$$mismatch" -ne 0 ]; then \
		echo "check-toolchain-alignment: FAILED — see errors above." >&2; \
		exit 1; \
	fi; \
	echo "check-toolchain-alignment: OK (go $$misefile across 4x go.mod + .mise.toml; golang:$$misemajmin across 4x Dockerfile)"

#lint: @ Run golangci-lint across every service module (includes gocritic, gosec via .golangci.yml)
lint: deps-tools
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> lint $$dir"; \
		(cd "$$dir" && golangci-lint run ./...); \
	done

#lint-ci: @ Lint GitHub Actions workflows (actionlint; uses shellcheck for embedded run: blocks)
lint-ci: deps-tools
	@actionlint

#vulncheck: @ Run govulncheck across every service module
vulncheck: deps-tools
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> vulncheck $$dir"; \
		(cd "$$dir" && govulncheck ./...); \
	done

#secrets: @ Scan for hardcoded secrets (gitleaks)
secrets: deps-tools
	@gitleaks detect --source . --verbose --redact

#trivy-fs: @ Trivy filesystem scan (vuln+secret+misconfig; HIGH+CRITICAL, fixed-only)
trivy-fs:
	@docker run --rm -v "$$PWD:/src:ro" -w /src \
		aquasec/trivy:$(TRIVY_VERSION) \
		fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 .

#static-check: @ Composite static gate (toolchain alignment + lint-ci + lint + vulncheck + secrets + diagrams-check + trivy-fs)
static-check: check-toolchain-alignment lint-ci lint vulncheck secrets diagrams-check trivy-fs

# ---------------------------------------------------------------------------
# Dependency hygiene
# ---------------------------------------------------------------------------

#get: @ Download dependencies + go mod tidy in every service module
get:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		(cd "$$dir" && GOFLAGS=$(GOFLAGS) go get . && go mod tidy); \
	done

#update: @ Update dependencies to latest versions in every service module
update:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		(cd "$$dir" && GOFLAGS=$(GOFLAGS) go get -u ./... && go mod tidy); \
	done

# ---------------------------------------------------------------------------
# Container images
# ---------------------------------------------------------------------------

#image-build: @ Build local Docker images for all services (linux/amd64, --load) — Dockerfile does its own Go build
image-build:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> image-build $$dir"; \
		(cd "$$dir" && DOCKER_BUILDKIT=1 docker buildx build --load \
			--platform linux/amd64 \
			-t $(IMAGE_REPO_PREFIX)/$$svc:$(IMAGE_TAG) .); \
	done

#image-push: @ Build and push multi-arch images (linux/amd64,linux/arm64) to the registry
image-push:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> image-push $$dir"; \
		(cd "$$dir" && DOCKER_BUILDKIT=1 docker buildx build --push \
			--platform linux/amd64,linux/arm64 \
			--provenance=false --sbom=false \
			-t $(IMAGE_REPO_PREFIX)/$$svc:$(IMAGE_TAG) .); \
	done

# ---------------------------------------------------------------------------
# KinD cluster + Dapr deploy lifecycle
# ---------------------------------------------------------------------------

#kind-up: @ Create the KinD cluster + start cloud-provider-kind
kind-up:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) KIND_NODE_IMAGE=$(KIND_NODE_IMAGE) \
		./scripts/kind-up.sh

#kind-down: @ Delete the KinD cluster + prune kindccm-* orphan sidecars
kind-down:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) ./scripts/kind-down.sh

#kind-deploy: @ Full bring-up — kind-up → deploy-dapr → deploy-components → deploy-workloads
kind-deploy: kind-up deploy-dapr deploy-components deploy-workloads

#kind-destroy: @ Tear everything down (alias for kind-down)
kind-destroy: kind-down

#deploy-dapr: @ Install the Dapr control plane on the KinD cluster
deploy-dapr:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) DAPRGO_NS=$(DAPRGO_NS) \
		./scripts/dapr.sh deploy

#undeploy-dapr: @ Remove the Dapr control plane
undeploy-dapr:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) DAPRGO_NS=$(DAPRGO_NS) \
		./scripts/dapr.sh undeploy

#deploy-components: @ Deploy Redis (state store + pub/sub broker) + redis-password-secret
deploy-components:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) DAPRGO_NS=$(DAPRGO_NS) \
		./scripts/components.sh deploy

#undeploy-components: @ Remove Redis + the secret
undeploy-components:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) DAPRGO_NS=$(DAPRGO_NS) \
		./scripts/components.sh undeploy

#deploy-workloads: @ Build images, load into KinD, apply k8s manifests
deploy-workloads: image-build
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) DAPRGO_NS=$(DAPRGO_NS) \
		IMAGE_REPO_PREFIX=$(IMAGE_REPO_PREFIX) IMAGE_TAG=$(IMAGE_TAG) \
		./scripts/workloads.sh deploy

#undeploy-workloads: @ Remove the application workloads
undeploy-workloads:
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) DAPRGO_NS=$(DAPRGO_NS) \
		./scripts/workloads.sh undeploy

# ---------------------------------------------------------------------------
# E2E
# ---------------------------------------------------------------------------

#e2e: @ End-to-end smoke test on a running KinD cluster (state + pubsub roundtrip + frontendsvc CRUD)
e2e:
	@if [ ! -x e2e/e2e-test.sh ]; then \
		echo "e2e/e2e-test.sh not found or not executable." >&2; \
		exit 1; \
	fi
	@KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) DAPRGO_NS=$(DAPRGO_NS) ./e2e/e2e-test.sh

#e2e-full: @ Convenience: kind-up → deploy-dapr → deploy-components → deploy-workloads → e2e (fresh-checkout flow)
e2e-full: kind-deploy e2e

# ---------------------------------------------------------------------------
# Diagrams
# ---------------------------------------------------------------------------

DIAGRAM_SOURCES := $(wildcard docs/diagrams/*.puml)
DIAGRAM_OUTPUTS := $(patsubst docs/diagrams/%.puml,docs/diagrams/out/%.png,$(DIAGRAM_SOURCES))

#diagrams: @ Render all PlantUML sources to docs/diagrams/out/*.png
diagrams: $(DIAGRAM_OUTPUTS)

# Renderer-version stamp — Make's dependency graph is purely source-mtime
# based and has no notion of "the tool that rendered this target changed",
# so a PLANTUML_VERSION bump alone would never re-trigger the PNG rule
# below. Depending on a version-named stamp file forces a rebuild: the
# stamp for the OLD version already exists (nothing to do), but the stamp
# for a NEW version doesn't, so Make (re)creates it — touching it newer
# than the committed PNGs — which in turn makes the PNG rule's prerequisite
# stale and forces a re-render.
docs/diagrams/out/.plantuml-$(PLANTUML_VERSION).stamp:
	@mkdir -p docs/diagrams/out
	@rm -f docs/diagrams/out/.plantuml-*.stamp
	@touch $@

docs/diagrams/out/%.png: docs/diagrams/%.puml docs/diagrams/out/.plantuml-$(PLANTUML_VERSION).stamp
	@mkdir -p docs/diagrams/out
	@docker run --rm \
		--user $$(id -u):$$(id -g) \
		-e _JAVA_OPTIONS=-Duser.home=/tmp \
		-v "$$PWD:/work" -w /work \
		plantuml/plantuml:$(PLANTUML_VERSION) \
		-tpng -o "/work/docs/diagrams/out" "/work/$<"

#diagrams-clean: @ Remove rendered diagram PNGs
diagrams-clean:
	@rm -rf docs/diagrams/out

#diagrams-check: @ Verify committed PNGs are in sync with .puml sources (fails on untracked drift too)
diagrams-check:
	@if [ -z "$(DIAGRAM_SOURCES)" ]; then \
		echo "No PlantUML sources under docs/diagrams/; skipping"; \
	else \
		$(MAKE) diagrams; \
		drift=$$(git status --porcelain --untracked-files=all -- docs/diagrams/out); \
		if [ -n "$$drift" ]; then \
			echo "diagrams-check: rendered PNGs differ from committed copies (including untracked new files) — run 'make diagrams' and commit." >&2; \
			echo "$$drift" >&2; \
			exit 1; \
		fi; \
	fi

# ---------------------------------------------------------------------------
# CI composites
# ---------------------------------------------------------------------------

#ci: @ Full local CI pipeline (deps → static-check → test → integration-test → build → image-build)
ci: deps static-check test integration-test build image-build

#ci-run: @ Run the GitHub Actions workflow locally via act (jobs serialized)
ci-run: deps-act
	@docker container prune -f 2>/dev/null || true
	@# Jobs are invoked one at a time via `act --job`. On real GitHub runners
	@# parallel jobs each get their own VM; under act they share the host
	@# Docker daemon, so serializing keeps `ci-run` honest without host-port
	@# collisions between jobs.
	@#
	@# Skipped jobs:
	@#   - e2e:      Docker-in-Docker KinD doesn't run cleanly under act.
	@#   - docker:   tag-gated (`if: startsWith(github.ref, 'refs/tags/')`);
	@#               our synthetic push event carries no tag ref, so the job
	@#               would just no-op — verify via a real tag push instead.
	@#   - ci-pass:  aggregator over e2e/docker; only meaningful on real CI.
	@if [ -z "$${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then \
		export GITHUB_TOKEN="$$(gh auth token 2>/dev/null)"; \
	fi; \
	secret_args=(); \
	[ -n "$${GITHUB_TOKEN:-}" ] && secret_args+=(--secret GITHUB_TOKEN); \
	evt=$$(mktemp /tmp/act-push-event.XXXXXX.json); \
	printf '{"ref":"refs/heads/main","repository":{"default_branch":"main","name":"dapr-go","full_name":"andriykalashnykov/dapr-go"}}' >"$$evt"; \
	ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_PATH=$$(mktemp -d -t act-artifacts.XXXXXX); \
	rc=0; \
	for j in static-check build test integration-test; do \
		echo "==== act push --job $$j ===="; \
		act push --job "$$j" --container-architecture linux/amd64 \
			-P ubuntu-latest=catthehacker/ubuntu:$(ACT_UBUNTU_VERSION) \
			--pull=false \
			--eventpath "$$evt" \
			--artifact-server-port "$$ACT_PORT" \
			--artifact-server-path "$$ARTIFACT_PATH" \
			"$${secret_args[@]}" || { rc=1; break; }; \
	done; \
	rm -f "$$evt"; \
	exit $$rc

# ---------------------------------------------------------------------------
# Renovate
# ---------------------------------------------------------------------------

#renovate-validate: @ Validate Renovate configuration
renovate-validate:
	@if [ -n "$${GH_ACCESS_TOKEN:-}" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate@latest --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some lookups may fail"; \
		npx --yes renovate@latest --platform=local; \
	fi

# ---------------------------------------------------------------------------
# Release
# ---------------------------------------------------------------------------

#version: @ Print current version (git tag)
version:
	@echo $(CURRENTTAG)

#release: @ Tag a new release (NEWTAG=vX.Y.Z make release)
release:
	@if [ -z "$(NEWTAG)" ]; then \
		echo "Provide NEWTAG (current: $(CURRENTTAG))" >&2; exit 1; \
	fi
	@if git rev-parse -q --verify "refs/tags/$(NEWTAG)" >/dev/null 2>&1; then echo "ERROR: tag $(NEWTAG) already exists locally. Pick a new version or delete it: git tag -d $(NEWTAG)"; exit 1; fi
	@if git ls-remote --exit-code --tags origin "refs/tags/$(NEWTAG)" >/dev/null 2>&1; then echo "ERROR: tag $(NEWTAG) already exists on origin. Pick a new version."; exit 1; fi
	@echo -n "Are you sure to create and push $(NEWTAG)? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo $(NEWTAG) > version.txt
	@git add version.txt
	@git commit -s -m "Cut $(NEWTAG) release"
	@git tag -a -m "Cut $(NEWTAG) release" $(NEWTAG)
	@git push origin $(NEWTAG)
	@git push

.PHONY: help \
	deps deps-tools deps-act \
	build build-linux-amd64 clean test integration-test check-toolchain-alignment \
	lint lint-ci vulncheck secrets trivy-fs static-check \
	get update \
	image-build image-push \
	kind-up kind-down kind-deploy kind-destroy \
	deploy-dapr undeploy-dapr deploy-components undeploy-components \
	deploy-workloads undeploy-workloads e2e e2e-full \
	diagrams diagrams-clean diagrams-check \
	ci ci-run \
	renovate-validate \
	version release
