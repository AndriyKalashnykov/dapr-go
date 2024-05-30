#!/bin/bash
# set -x

# minikube defaults
export DEFAULT_MINIKUBE_PROFILE=dapr-go
export DEFAULT_MINIKUBE_NODES=1
export DEFAULT_MINIKUBE_RAM=16000mb
export DEFAULT_MINIKUBE_CPU=4
export DEFAULT_MINIKUBE_DISK=40g
export DEFAULT_MINIKUBE_VM_DRIVER=docker
export DEFAULT_MINIKUBE_STATIC_IP=192.168.200.200

export DEFAULT_TIMEOUT=180s
export DEFAULT_STORAGE_CLASS=standard

export DEFAULT_NS=dapr-go
