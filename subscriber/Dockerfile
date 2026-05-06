# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM golang:1.26-alpine@sha256:f85330846cde1e57ca9ec309382da3b8e6ae3ab943d2739500e08c86393a21b1 AS builder
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
