.DEFAULT_GOAL := help

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

# Make sure mise-managed shims and ~/.local/bin are visible to recipes —
# Make spawns a non-interactive shell that does not source ~/.zshrc/~/.bashrc.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# ---------------------------------------------------------------------------
# Pinned tool versions — Renovate-tracked via inline comments
# ---------------------------------------------------------------------------

# renovate: datasource=github-releases depName=jdx/mise
MISE_VERSION := 2025.10.0

# renovate: datasource=github-releases depName=kubernetes-sigs/kind
KIND_VERSION := 0.27.0
# Bumped together with KIND_VERSION per kind release notes.
KIND_NODE_IMAGE := kindest/node:v1.34.0

# renovate: datasource=go depName=sigs.k8s.io/cloud-provider-kind
CLOUD_PROVIDER_KIND_VERSION := v0.7.0

# renovate: datasource=github-releases depName=golangci/golangci-lint
GOLANGCI_VERSION := v2.5.0

# renovate: datasource=go depName=golang.org/x/vuln/cmd/govulncheck
GOVULNCHECK_VERSION := v1.1.4

# renovate: datasource=docker depName=plantuml/plantuml
PLANTUML_VERSION := 1.2025.7

# renovate: datasource=docker depName=aquasec/trivy
TRIVY_VERSION := 0.69.1

# renovate: datasource=github-releases depName=nektos/act
ACT_VERSION := 0.2.87

# ---------------------------------------------------------------------------
# Project metadata
# ---------------------------------------------------------------------------

KIND_CLUSTER_NAME ?= dapr-go
KUBECTL_CTX       := kind-$(KIND_CLUSTER_NAME)
DAPRGO_NS         ?= dapr-go
KUBECTL           := kubectl --context $(KUBECTL_CTX)

CURRENTTAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)
NEWTAG    ?=

IMAGE_REPO_PREFIX ?= andriykalashnykov/dapr-go
IMAGE_TAG         ?= v0.0.1

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
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-22s\033[0m - %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

#deps: @ Full dev environment (toolchain via mise + Go tools + cloud-provider-kind)
deps: deps-tools
	@command -v cloud-provider-kind >/dev/null 2>&1 || { \
		echo "Installing cloud-provider-kind@$(CLOUD_PROVIDER_KIND_VERSION) via go install..."; \
		go install sigs.k8s.io/cloud-provider-kind@$(CLOUD_PROVIDER_KIND_VERSION); \
	}

#deps-tools: @ Install Go tools needed for static-check (mise toolchain + golangci-lint + govulncheck)
deps-tools:
	@command -v mise >/dev/null 2>&1 || { \
		echo "Installing mise (no root required, installs to ~/.local/bin)..."; \
		curl -fsSL https://mise.run | sh; \
	}
	@mise install --yes
	@go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_VERSION)
	@go install golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION)

#deps-act: @ Install act (local GitHub Actions runner)
deps-act:
	@command -v act >/dev/null 2>&1 || \
		go install github.com/nektos/act@$(ACT_VERSION)

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

#lint: @ Run golangci-lint across every service module
lint:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> lint $$dir"; \
		(cd "$$dir" && golangci-lint run ./...); \
	done

#vulncheck: @ Run govulncheck across every service module
vulncheck:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> vulncheck $$dir"; \
		(cd "$$dir" && govulncheck ./...); \
	done

#trivy-fs: @ Trivy filesystem scan (HIGH+CRITICAL, fixed-only)
trivy-fs:
	@docker run --rm -v "$$PWD:/src:ro" -w /src \
		aquasec/trivy:$(TRIVY_VERSION) \
		fs --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 .

#static-check: @ Composite static gate (lint + vulncheck + diagrams-check + trivy-fs)
static-check: deps-tools lint vulncheck diagrams-check trivy-fs

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
			-t $(IMAGE_REPO_PREFIX)-$$svc:$(IMAGE_TAG) .); \
	done

#image-push: @ Build and push multi-arch images (linux/amd64,linux/arm64) to the registry
image-push:
	@for svc in $(SERVICES); do \
		case "$$svc" in frontendsvc) dir=state/frontendsvc ;; *) dir=$$svc ;; esac; \
		echo ">> image-push $$dir"; \
		(cd "$$dir" && DOCKER_BUILDKIT=1 docker buildx build --push \
			--platform linux/amd64,linux/arm64 \
			--provenance=false --sbom=false \
			-t $(IMAGE_REPO_PREFIX)-$$svc:$(IMAGE_TAG) .); \
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

docs/diagrams/out/%.png: docs/diagrams/%.puml
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

#diagrams-check: @ Verify committed PNGs are in sync with .puml sources
diagrams-check:
	@if [ -z "$(DIAGRAM_SOURCES)" ]; then \
		echo "No PlantUML sources under docs/diagrams/; skipping"; \
	else \
		$(MAKE) diagrams; \
		git diff --exit-code docs/diagrams/out || { \
			echo "diagrams-check: rendered PNGs differ from committed copies — run 'make diagrams' and commit." >&2; \
			exit 1; \
		}; \
	fi

# ---------------------------------------------------------------------------
# CI composites
# ---------------------------------------------------------------------------

#ci: @ Full local CI pipeline (deps → static-check → test → integration-test → build → image-build)
ci: deps static-check test integration-test build image-build

#ci-run: @ Run the GitHub Actions workflow locally via act
ci-run: deps-act
	@act push --container-architecture linux/amd64

# ---------------------------------------------------------------------------
# Renovate
# ---------------------------------------------------------------------------

#renovate-validate: @ Validate Renovate configuration
renovate-validate:
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some lookups may fail"; \
		npx --yes renovate --platform=local; \
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
	@echo -n "Are you sure to create and push $(NEWTAG)? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo $(NEWTAG) > version.txt
	@git add version.txt
	@git commit -s -m "Cut $(NEWTAG) release"
	@git tag -a -m "Cut $(NEWTAG) release" $(NEWTAG)
	@git push origin $(NEWTAG)
	@git push

.PHONY: help \
	deps deps-tools deps-act \
	build build-linux-amd64 clean test integration-test lint vulncheck trivy-fs static-check \
	get update \
	image-build image-push \
	kind-up kind-down kind-deploy kind-destroy \
	deploy-dapr undeploy-dapr deploy-components undeploy-components \
	deploy-workloads undeploy-workloads e2e e2e-full \
	diagrams diagrams-clean diagrams-check \
	ci ci-run \
	renovate-validate \
	version release
