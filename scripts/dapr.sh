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
  helm repo add dapr https://dapr.github.io/helm-charts/ && \
  helm repo update && \
  helm upgrade --install dapr dapr/dapr --set version=1.13.4 --namespace dapr-system --create-namespace --wait && \
  helm upgrade --install dapr-dashboard dapr/dapr-dashboard --set version=1.13.4 --namespace dapr-system --set serviceType=LoadBalancer --wait && \
  kubectl create namespace ${DAPRGO_NS} --dry-run=client -o yaml | kubectl apply -f -  && \
  kubectl apply -f $SCRIPT_PARENT_DIR/k8s/dapr/permissions/dapr-permissions.yaml --server-side=true --force-conflicts && \
  kubectl get pods --namespace dapr-system
#  kubectl port-forward -n dapr-system svc/dapr-dashboard 8080:8080
#  xdg-open http://localhost:8080/overview
elif [[ $SCRIPT_ACTION == "undeploy"  ]]; then
  kubectl delete --ignore-not-found=true -n ${DAPRGO_NS} -f ./k8s/dapr/permissions/dapr-permissions.yaml && \
  helm uninstall dapr --namespace dapr-system && \
  helm uninstall dapr-dashboard --namespace dapr-system
fi