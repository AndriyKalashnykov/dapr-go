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
  kubectl create namespace ${DAPRGO_NS} --dry-run=client -o yaml | kubectl apply -f -  && \
  kubectl create -n ${DAPRGO_NS} secret generic redis-password-secret --from-literal=redis-password=RedisPassword --save-config --dry-run=client -o yaml | kubectl apply -f - && \
  export REDIS_PASSWORD=$(kubectl get secret --namespace ${DAPRGO_NS} redis-password-secret -o jsonpath="{.data.redis-password}" | base64 -d)  && \
  echo $REDIS_PASSWORD  && \
  helm upgrade --install redis bitnami/redis --wait --namespace ${DAPRGO_NS} \
    --set auth.existingSecret=redis-password-secret \
    --set master.persistence.enabled=true \
    --set master.service.type=LoadBalancer \
    --set architecture=replication \
    --set master.conunt=1 \
    --set replica.replicaCount=1 \
    --set master.disableCommands=null \
    --set master.livenessProbe.initialDelaySeconds=1 \
    --set master.readinessProbe.initialDelaySeconds=1

elif [[ $SCRIPT_ACTION == "undeploy"  ]]; then
	helm uninstall redis --namespace ${DAPRGO_NS} && \
	kubectl delete secret redis-password-secret --namespace ${DAPRGO_NS} --ignore-not-found=true
fi
