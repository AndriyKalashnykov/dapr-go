#!/bin/bash
# set -x

LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

. $SCRIPT_DIR/env.sh

TIMEOUT=${DEFAULT_TIMEOUT}
SCRIPT_ACTION=${1:-deploy}
MINIKUBE_PROFILE=${2:-$DEFAULT_MINIKUBE_PROFILE}
DAPRGO_NS=${3:-$DEFAULT_NS}

if [[ $SCRIPT_ACTION != "deploy" && $SCRIPT_ACTION != "undeploy" ]]; then
  echo "Error: Action \"$SCRIPT_ACTION\" is not supported. Supported: 'deploy', 'undeploy'"
  exit 1
fi

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

if [[ $SCRIPT_ACTION == "deploy" ]]; then
  # load image into minikube if not loaded yet

  minikube image load andriykalashnykov/dapr-go-read-values:v0.0.1 --profile ${MINIKUBE_PROFILE}
  minikube image load andriykalashnykov/dapr-go-subscriber:v0.0.1 --profile ${MINIKUBE_PROFILE}
  minikube image load andriykalashnykov/dapr-go-write-values:v0.0.1 --profile ${MINIKUBE_PROFILE}
  minikube image load ko.local/dapr-go-frontendsvc:latest --profile ${MINIKUBE_PROFILE}
  minikube image ls --profile ${MINIKUBE_PROFILE}  --format table

  kubectl apply -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/dapr/components --server-side=true --force-conflicts
  kubectl apply -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/apps --server-side=true --force-conflicts

  # kubectl logs -n dapr-go write-values-cf6f6fd76-fxtlp --all-containers=true -f
  # kubectl logs -n dapr-go read-values-55764dcc8d-2s28h --all-containers=true -f
elif [[ $SCRIPT_ACTION == "undeploy"  ]]; then
  kubectl delete --ignore-not-found=true -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/apps && \
  kubectl delete -n ${DAPRGO_NS} --ignore-not-found=true -f $SCRIPT_PARENT_DIR/k8s/dapr/components
fi