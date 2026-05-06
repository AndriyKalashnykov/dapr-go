#!/usr/bin/env bash
# Install or uninstall the Dapr control plane on the dapr-go KinD cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

DAPR_VERSION="${DAPR_VERSION:-1.15.10}"
DAPR_DASHBOARD_VERSION="${DAPR_DASHBOARD_VERSION:-1.15.0}"

SCRIPT_ACTION="${1:-deploy}"
DAPRGO_NS="${2:-${DEFAULT_NS}}"

if [[ "${SCRIPT_ACTION}" != "deploy" && "${SCRIPT_ACTION}" != "undeploy" ]]; then
  echo "Error: Action '${SCRIPT_ACTION}' is not supported. Supported: 'deploy', 'undeploy'" >&2
  exit 1
fi

case "${SCRIPT_ACTION}" in
  deploy)
    helm repo add dapr https://dapr.github.io/helm-charts/ 2>/dev/null || true
    helm repo update dapr
    helm upgrade --install dapr dapr/dapr \
      --kube-context "${KUBECTL_CTX}" \
      --version "${DAPR_VERSION}" \
      --namespace dapr-system \
      --create-namespace \
      --wait
    helm upgrade --install dapr-dashboard dapr/dapr-dashboard \
      --kube-context "${KUBECTL_CTX}" \
      --version "${DAPR_DASHBOARD_VERSION}" \
      --namespace dapr-system \
      --set serviceType=LoadBalancer \
      --wait
    "${KUBECTL[@]}" create namespace "${DAPRGO_NS}" --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
    "${KUBECTL[@]}" apply -f "${SCRIPT_PARENT_DIR}/k8s/dapr/permissions/dapr-permissions.yaml" \
      --server-side --force-conflicts
    "${KUBECTL[@]}" get pods --namespace dapr-system
    ;;
  undeploy)
    "${KUBECTL[@]}" delete --ignore-not-found=true \
      -f "${SCRIPT_PARENT_DIR}/k8s/dapr/permissions/dapr-permissions.yaml"
    helm uninstall dapr-dashboard --kube-context "${KUBECTL_CTX}" --namespace dapr-system || true
    helm uninstall dapr --kube-context "${KUBECTL_CTX}" --namespace dapr-system || true
    ;;
esac
