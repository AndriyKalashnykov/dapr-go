#!/usr/bin/env bash
# Load locally-built service images into the KinD cluster and apply manifests.
# `kind load docker-image` is the KinD analogue of `minikube image load`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

IMAGE_TAG="${IMAGE_TAG:-v0.0.1}"
IMAGE_REPO_PREFIX="${IMAGE_REPO_PREFIX:-andriykalashnykov/dapr-go}"
SERVICES=(read-values subscriber write-values frontendsvc)

SCRIPT_ACTION="${1:-deploy}"
DAPRGO_NS="${2:-${DEFAULT_NS}}"

if [[ "${SCRIPT_ACTION}" != "deploy" && "${SCRIPT_ACTION}" != "undeploy" ]]; then
  echo "Error: Action '${SCRIPT_ACTION}' is not supported. Supported: 'deploy', 'undeploy'" >&2
  exit 1
fi

case "${SCRIPT_ACTION}" in
  deploy)
    for svc in "${SERVICES[@]}"; do
      kind load docker-image \
        "${IMAGE_REPO_PREFIX}-${svc}:${IMAGE_TAG}" \
        --name "${KIND_CLUSTER_NAME}"
    done

    "${KUBECTL[@]}" apply -n "${DAPRGO_NS}" \
      -f "${SCRIPT_PARENT_DIR}/k8s/dapr/components" \
      --server-side --force-conflicts
    "${KUBECTL[@]}" apply -n "${DAPRGO_NS}" \
      -f "${SCRIPT_PARENT_DIR}/k8s/apps" \
      --server-side --force-conflicts
    ;;
  undeploy)
    "${KUBECTL[@]}" delete --ignore-not-found=true -n "${DAPRGO_NS}" \
      -f "${SCRIPT_PARENT_DIR}/k8s/apps"
    "${KUBECTL[@]}" delete --ignore-not-found=true -n "${DAPRGO_NS}" \
      -f "${SCRIPT_PARENT_DIR}/k8s/dapr/components"
    ;;
esac
