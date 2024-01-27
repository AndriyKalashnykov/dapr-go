#!/bin/bash
# set -x

LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

. $SCRIPT_DIR/env.sh

export TIMEOUT=${DEFAULT_TIMEOUT}
export MINIKUBE_PROFILE=${1:-$DEFAULT_MINIKUBE_PROFILE}
export DAPRGO_NS=${2:-$DEFAULT_NS}
export DAPRGO_APP=${3:-$DEFAULT_APP}

if [ -z "${TIMEOUT}" ]; then
    echo "Provide timeout"
    exit 1
fi

if [ -z "${MINIKUBE_PROFILE}" ]; then
    echo "Provide minikube profile"
    exit 1
fi


if [ -z "${DAPRGO_NS}" ]; then
    echo "Provide DAPRGO namespace"
    exit 1
fi

if [ -z "${DAPRGO_APP}" ]; then
    echo "Provide DAPRGO app"
    exit 1
fi

# load image into minikube if not loaded yet

minikube image load andriykalashnykov/ambient-read-values:0.0.1 --profile ${MINIKUBE_PROFILE}
minikube image load andriykalashnykov/ambient-subscriber:0.0.1 --profile ${MINIKUBE_PROFILE}
minikube image load andriykalashnykov/ambient-write-values:0.0.1 --profile ${MINIKUBE_PROFILE}

# minikube image ls --profile ${MINIKUBE_PROFILE}  --format table

kubectl create namespace ${DAPRGO_NS} --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/dapr --server-side=true --force-conflicts
kubectl apply -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/apps --server-side=true --force-conflicts

#kubectl delete -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/apps