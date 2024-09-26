#!/bin/bash
# set -x

LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

. $SCRIPT_DIR/env.sh

export SCRIPT_ACTION=${1:-start}
MINIKUBE_PROFILE=${2:-$DEFAULT_MINIKUBE_PROFILE}
MINIKUBE_NODES=${3:-$DEFAULT_MINIKUBE_NODES}
MINIKUBE_RAM=${4:-$DEFAULT_MINIKUBE_RAM}
MINIKUBE_CPU=${5:-$DEFAULT_MINIKUBE_CPU}
MINIKUBE_DISK=${6:-$DEFAULT_MINIKUBE_DISK}
MINIKUBE_VM_DRIVER=${7:-$DEFAULT_MINIKUBE_VM_DRIVER}
MINIKUBE_STATIC_IP=${8:-$DEFAULT_MINIKUBE_STATIC_IP}

if [[ $SCRIPT_ACTION != "start" && $SCRIPT_ACTION != "stop" && $SCRIPT_ACTION != "delete" ]]; then
  echo "Error: Action \"$SCRIPT_ACTION\" is not supported. Supported: 'start', 'delete'"
  exit 1
fi

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

if [[ $SCRIPT_ACTION == "start" ]]; then
  found=$(minikube profile list --output=table | awk -F'[| ]' '{print $3}' | awk '!/Profile|---------/' | grep ^${MINIKUBE_PROFILE}$)
  if [ "${found}" == "" ]; then
    echo "Creating Minikube profile - ${MINIKUBE_PROFILE}"
    ## if not enought CPUs (4 seem to be minimum) or RAM given to minikube won't start saying smth. like "cluster module not found" or so
    ##     --kubernetes-version=v1.30.0 \
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

  # https://serverfault.com/questions/1079642/accessing-mosquitto-mqtt-from-outside-my-kubernetes-cluster

  configure_metallb_for_minikube

  elif [[ $SCRIPT_ACTION == "stop"  ]]; then

    found=$(minikube profile list --output=table | awk -F'[| ]' '{print $3}' | awk '!/Profile|---------/' | grep ^${MINIKUBE_PROFILE}$)
    if [ "${found}" != "" ]; then
      if [ $(minikube profile list --output=table | grep ${MINIKUBE_PROFILE} | awk '{print $14}') == "Running" ]; then
        echo "Stopping Minikube profile - ${MINIKUBE_PROFILE}"
        minikube stop --profile ${MINIKUBE_PROFILE}
      fi
    else
      echo "Minikube profile - '${MINIKUBE_PROFILE}' not found"
    fi

elif [[ $SCRIPT_ACTION == "delete"  ]]; then

  found=$(minikube profile list --output=table | awk -F'[| ]' '{print $3}' | awk '!/Profile|---------/' | grep ^${MINIKUBE_PROFILE}$)
  if [  "${found}" != "" ]; then
    echo "Deleting Minikube profile - ${MINIKUBE_PROFILE}"
    minikube delete --profile ${MINIKUBE_PROFILE}
  else
    echo "Minikube profile - '${MINIKUBE_PROFILE}' not found"
  fi

fi