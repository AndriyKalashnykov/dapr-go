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

#minikube image load andriykalashnykov/dapr-go-read-values:v0.0.1 --profile ${MINIKUBE_PROFILE}
#minikube image load andriykalashnykov/dapr-go-subscriber:v0.0.1 --profile ${MINIKUBE_PROFILE}
#minikube image load andriykalashnykov/dapr-go-write-values:v0.0.1 --profile ${MINIKUBE_PROFILE}

# minikube image ls --profile ${MINIKUBE_PROFILE}  --format table

kubectl create namespace ${DAPRGO_NS} --dry-run=client -o yaml | kubectl apply -f -
#kubectl apply -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/redis-password.yaml --server-side=true --force-conflicts
kubectl create -n ${DAPRGO_NS} secret generic redis-password-secret --from-literal=redis-password=RedisPassword
export REDIS_PASSWORD=$(kubectl get secret --namespace dapr-go redis-password-secret -o jsonpath="{.data.redis-password}" | base64 -d)
echo $REDIS_PASSWORD
helm upgrade --install redis bitnami/redis --namespace ${DAPRGO_NS} --set auth.existingSecret=redis-password-secret --set architecture=standalone --set replica.replicaCount=1

#kubectl apply -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/dapr --server-side=true --force-conflicts
#kubectl apply -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/apps --server-side=true --force-conflicts

#kubectl delete -n ${DAPRGO_NS} -f $SCRIPT_PARENT_DIR/k8s/apps

