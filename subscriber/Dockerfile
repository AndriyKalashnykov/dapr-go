# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM golang:1.26-alpine@sha256:3ad57304ad93bbec8548a0437ad9e06a455660655d9af011d58b993f6f615648 AS builder
WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

COPY . .
ARG TARGETOS TARGETARCH
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/main .

FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS runtime
# Pull baked-in OS packages up to the latest in the pinned alpine:3.23 branch
# at BUILD time, so a CVE Alpine has already fixed clears immediately instead
# of waiting on the upstream base rebuild (the alpine analogue of the
# Go-stdlib lag). Real fix (vulnerable package removed), not a .trivyignore
# waiver. As root, before addgroup/adduser and before USER.
#
# APK_UPGRADE_BUST busts Docker's layer cache for the RUN below under
# cache-from/cache-to: type=gha — without it, `apk --no-cache upgrade` only
# clears CVEs on the build that first populates the cache and replays a stale
# layer forever after. CI should pass a fresh value per build (e.g.
# --build-arg APK_UPGRADE_BUST=${{ github.run_id }}); the default below covers
# a plain local `docker build` where no CI value is supplied.
ARG APK_UPGRADE_BUST=manual
RUN apk --no-cache upgrade
RUN addgroup -S -g 10001 app \
    && adduser  -S -u 10001 -G app -h /app -D app

WORKDIR /app
COPY --from=builder --chown=app:app /out/main /app/main

LABEL org.opencontainers.image.source="https://github.com/AndriyKalashnykov/dapr-go"
LABEL org.opencontainers.image.title="dapr-go-subscriber"
LABEL org.opencontainers.image.description="Receives Dapr-routed pub/sub events on /notifications."
LABEL org.opencontainers.image.licenses="Apache-2.0"

USER 10001:10001
ENTRYPOINT ["/app/main"]
