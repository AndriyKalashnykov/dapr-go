#!/bin/bash
# set -x

LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

. $SCRIPT_DIR/env.sh

export MINIKUBE_PROFILE=${1:-$DEFAULT_MINIKUBE_PROFILE}

if [ -z "$MINIKUBE_PROFILE" ]; then
    echo "Provide minikube profile"
    exit 1
fi

found=$(minikube profile list --output=table | awk -F'[| ]' '{print $3}' | awk '!/Profile|---------/' | grep ^${MINIKUBE_PROFILE}$)
if [  "${found}" != "" ]; then
  echo "Deleting Minikube profile - ${MINIKUBE_PROFILE}"
  minikube delete --profile ${MINIKUBE_PROFILE}
else
  echo "Minikube profile - '${MINIKUBE_PROFILE}' not found"
fi
