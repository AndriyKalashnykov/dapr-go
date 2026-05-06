#!/usr/bin/env bash
# Tear down the dapr-go KinD cluster, cloud-provider-kind, and orphaned
# kindccm-* Envoy sidecars (which otherwise hold IPs in the kind subnet
# and stale-Envoy-config the next cluster).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

# Stop cloud-provider-kind first so it doesn't fight the cluster delete.
if pgrep -fa cloud-provider-kind >/dev/null 2>&1; then
  echo "Stopping cloud-provider-kind"
  pkill -f cloud-provider-kind || true
  sleep 1
fi

# Prune kindccm-* Envoy sidecars BEFORE deleting the cluster — these survive
# `kind delete cluster` and a subsequent `kind-up` can inherit their stale
# IPs/Envoy config (real incident, see /makefile skill canonical kind-destroy).
ORPHANS=$(docker ps -aq --filter name=kindccm- 2>/dev/null || true)
if [ -n "${ORPHANS}" ]; then
  echo "Pruning kindccm-* orphan sidecars"
  # shellcheck disable=SC2086
  docker rm -f ${ORPHANS}
fi

if kind get clusters 2>/dev/null | grep -qx "${KIND_CLUSTER_NAME}"; then
  echo "Deleting KinD cluster '${KIND_CLUSTER_NAME}'"
  kind delete cluster --name "${KIND_CLUSTER_NAME}"
else
  echo "KinD cluster '${KIND_CLUSTER_NAME}' not found; nothing to delete"
fi
