#!/usr/bin/env bash
# Install or uninstall the Redis state store + pub/sub broker.
# Generates the Redis password client-side and feeds it via stdin so the
# value never lands in argv (no --from-literal=, no echo of the secret).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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

    "${KUBECTL[@]}" apply -n "${DAPRGO_NS}" -f "${SCRIPT_PARENT_DIR}/k8s/redis/"
    "${KUBECTL[@]}" rollout status deployment/redis-master -n "${DAPRGO_NS}" --timeout=120s
    ;;
  undeploy)
    "${KUBECTL[@]}" delete -n "${DAPRGO_NS}" -f "${SCRIPT_PARENT_DIR}/k8s/redis/" --ignore-not-found=true
    "${KUBECTL[@]}" delete secret redis-password-secret \
      --namespace "${DAPRGO_NS}" --ignore-not-found=true
    ;;
esac
