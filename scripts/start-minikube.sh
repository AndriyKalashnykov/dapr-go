#!/bin/bash
# set -x

LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

. $SCRIPT_DIR/env.sh

export MINIKUBE_PROFILE=${1:-$DEFAULT_MINIKUBE_PROFILE}
export MINIKUBE_NODES=${2:-$DEFAULT_MINIKUBE_NODES}
export MINIKUBE_RAM=${3:-$DEFAULT_MINIKUBE_RAM}
export MINIKUBE_CPU=${4:-$DEFAULT_MINIKUBE_CPU}
export MINIKUBE_DISK=${5:-$DEFAULT_MINIKUBE_DISK}
export MINIKUBE_VM_DRIVER=${6:-$DEFAULT_MINIKUBE_VM_DRIVER}
export MINIKUBE_STATIC_IP=${6:-$DEFAULT_MINIKUBE_STATIC_IP}


if [ -z "$MINIKUBE_PROFILE" ]; then
    echo "Provide minikube profile"
    exit 1
fi

if [ -z "${MINIKUBE_NODES}" ]; then
    echo "Provide minikube nodes"
    exit 1
fi

if [ -z "${MINIKUBE_RAM}" ]; then
    echo "Provide minikube RAM"
    exit 1
fi

if [ -z "${MINIKUBE_CPU}" ]; then
    echo "Provide minikube RAM"
    exit 1
fi

if [ -z "${MINIKUBE_DISK}" ]; then
    echo "Provide minikube Disk"
    exit 1
fi

if [ -z "${MINIKUBE_VM_DRIVER}" ]; then
    echo "Provide minikube VM driver"
    exit 1
fi

# minikube addons list

found=$(minikube profile list --output=table | awk -F'[| ]' '{print $3}' | awk '!/Profile|---------/' | grep ^${MINIKUBE_PROFILE}$)
if [ "${found}" == "" ]; then
  echo "Creating Minikube profile - ${MINIKUBE_PROFILE}"
  ## if not enought CPUs (4 seem to be minimum) or RAM given to minikube CDR won't start saying smth. like "cluster module not found" or so
  minikube start \
  --profile ${MINIKUBE_PROFILE} \
  --nodes ${MINIKUBE_NODES} \
  --memory=${MINIKUBE_RAM} \
  --cpus=${MINIKUBE_CPU} \
  --disk-size=${MINIKUBE_DISK} \
  --vm-driver=${MINIKUBE_VM_DRIVER} \
  --static-ip ${MINIKUBE_STATIC_IP} \
  --insecure-registry=localhost:5000 \
  --addons=metallb \
  --addons=ingress \
  --addons=ingress-dns \
  --addons=metrics-server
  # --extra-config=apiserver.anonymous-auth=false
else
  found=$(minikube profile list --output=table | grep ${MINIKUBE_PROFILE} | awk '{print $14}')
  if [  "${found}" == "Stopped" ]; then
    echo "Starting existing Minikube profile - ${MINIKUBE_PROFILE}"
    minikube start --profile=${MINIKUBE_PROFILE}
  else
    echo "Minikube profile - ${MINIKUBE_PROFILE} is running"
    minikube profile list
  fi
fi

eval $(minikube -p minikube docker-env)

# minikube image ls --format table
# minikube delete -p minikube
# minikube delete --all

configure_metallb_for_minikube() {
  # determine load balancer ingress range
  CIDR_BASE_ADDR="$(minikube ip --profile=${MINIKUBE_PROFILE})"
  INGRESS_FIRST_ADDR="$(echo "${CIDR_BASE_ADDR}" | awk -F'.' '{print $1,$2,$3,2}' OFS='.')"
  INGRESS_LAST_ADDR="$(echo "${CIDR_BASE_ADDR}" | awk -F'.' '{print $1,$2,$3,255}' OFS='.')"
  INGRESS_RANGE="${INGRESS_FIRST_ADDR}-${INGRESS_LAST_ADDR}"

  CONFIG_MAP="apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - $INGRESS_RANGE"

  # configure metallb ingress address range
  echo "${CONFIG_MAP}" | kubectl apply -f -
}

configure_metallb_for_minikube
