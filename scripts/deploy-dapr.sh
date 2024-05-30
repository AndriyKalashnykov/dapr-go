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

helm repo add dapr https://dapr.github.io/helm-charts/ && \
helm repo update && \
helm upgrade --install dapr dapr/dapr --set version=1.13.4 --namespace dapr-system --create-namespace --wait && \
helm upgrade --install dapr-dashboard dapr/dapr-dashboard --set version=1.13.4 --namespace dapr-system --set serviceType=LoadBalancer --wait && \
kubectl get pods --namespace dapr-system
