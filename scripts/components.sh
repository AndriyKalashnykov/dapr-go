#!/usr/bin/env bash
# Install or uninstall the Redis state store + pub/sub broker.
# Generates the Redis password client-side and feeds it via stdin so the
# value never lands in argv (no --from-literal=, no echo of the secret).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

SCRIPT_ACTION="${1:-deploy}"
DAPRGO_NS="${2:-${DEFAULT_NS}}"

if [[ "${SCRIPT_ACTION}" != "deploy" && "${SCRIPT_ACTION}" != "undeploy" ]]; then
  echo "Error: Action '${SCRIPT_ACTION}' is not supported. Supported: 'deploy', 'undeploy'" >&2
  exit 1
fi

case "${SCRIPT_ACTION}" in
  deploy)
    "${KUBECTL[@]}" create namespace "${DAPRGO_NS}" --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

    # Reuse the existing Redis password Secret if present; otherwise generate a fresh one.
    # Password value never appears in argv (no --from-literal) — fed via stdin only.
    if ! "${KUBECTL[@]}" get secret --namespace "${DAPRGO_NS}" redis-password-secret >/dev/null 2>&1; then
      REDIS_PASSWORD="$(openssl rand -base64 24)"
      printf '%s' "${REDIS_PASSWORD}" | "${KUBECTL[@]}" create secret generic redis-password-secret \
        --namespace "${DAPRGO_NS}" \
        --from-file=redis-password=/dev/stdin
      unset REDIS_PASSWORD
      echo "Created redis-password-secret in namespace ${DAPRGO_NS}"
    else
      echo "Reusing existing redis-password-secret in namespace ${DAPRGO_NS}"
    fi

    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo update bitnami
    helm upgrade --install redis bitnami/redis \
      --kube-context "${KUBECTL_CTX}" \
      --namespace "${DAPRGO_NS}" \
      --wait \
      --set auth.existingSecret=redis-password-secret \
      --set master.persistence.enabled=true \
      --set master.service.type=ClusterIP \
      --set architecture=replication \
      --set master.count=1 \
      --set replica.replicaCount=1 \
      --set master.disableCommands=null \
      --set master.livenessProbe.initialDelaySeconds=1 \
      --set master.readinessProbe.initialDelaySeconds=1
    ;;
  undeploy)
    helm uninstall redis --kube-context "${KUBECTL_CTX}" --namespace "${DAPRGO_NS}" || true
    "${KUBECTL[@]}" delete secret redis-password-secret \
      --namespace "${DAPRGO_NS}" --ignore-not-found=true
    ;;
esac
