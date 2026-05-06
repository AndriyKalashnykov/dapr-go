#!/bin/bash
# Shared environment variables for dapr-go scripts.

# KinD cluster + namespace defaults.
export KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-dapr-go}"
export KUBECTL_CTX="kind-${KIND_CLUSTER_NAME}"
export DEFAULT_NS="${DEFAULT_NS:-dapr-go}"

# Operational defaults.
export DEFAULT_TIMEOUT="${DEFAULT_TIMEOUT:-180s}"
export DEFAULT_STORAGE_CLASS="${DEFAULT_STORAGE_CLASS:-standard}"

# kubectl wrapped with the KinD cluster context so a sibling project's
# `kubectl config use-context` cannot misroute commands. Use as: "${KUBECTL[@]}".
KUBECTL=(kubectl --context "${KUBECTL_CTX}")
export KUBECTL
