#!/usr/bin/env bash
# Bring up a KinD cluster + cloud-provider-kind LB controller for dapr-go.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.36.1}"

if kind get clusters 2>/dev/null | grep -qx "${KIND_CLUSTER_NAME}"; then
  echo "KinD cluster '${KIND_CLUSTER_NAME}' already exists; skipping create"
else
  echo "Creating KinD cluster '${KIND_CLUSTER_NAME}' (image: ${KIND_NODE_IMAGE})"
  # Self-heal: an interrupted prior run can leave a stray "<name>-control-plane"
  # Docker container behind without `kind get clusters` listing it, which makes
  # `kind create cluster` fail with a name conflict. Delete-then-create so a
  # rerun after an interrupted run works.
  kind delete cluster --name "${KIND_CLUSTER_NAME}" >/dev/null 2>&1 || true
  kind create cluster \
    --name "${KIND_CLUSTER_NAME}" \
    --image "${KIND_NODE_IMAGE}" \
    --config "${SCRIPT_DIR}/kind-config.yaml" \
    --wait 120s
fi

# Pin kubectl to the KinD context for any tooling that reads the kubeconfig.
kubectl config use-context "${KUBECTL_CTX}"

# Start cloud-provider-kind in the background so type=LoadBalancer Services
# get external IPs. cloud-provider-kind must be installed via `make deps`.
if ! pgrep -fa cloud-provider-kind >/dev/null 2>&1; then
  if ! command -v cloud-provider-kind >/dev/null 2>&1; then
    echo "ERROR: cloud-provider-kind not on PATH. Run 'make deps' first." >&2
    exit 1
  fi
  echo "Starting cloud-provider-kind in background (logs: /tmp/cloud-provider-kind-${KIND_CLUSTER_NAME}.log)"
  nohup cloud-provider-kind \
    > "/tmp/cloud-provider-kind-${KIND_CLUSTER_NAME}.log" 2>&1 &
  disown
else
  echo "cloud-provider-kind already running"
fi

"${KUBECTL[@]}" cluster-info
echo "KinD cluster '${KIND_CLUSTER_NAME}' ready"
