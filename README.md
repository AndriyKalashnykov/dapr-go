# dapr-go

This repository aims to show how to use Dapr Ambient and Dapr building blocks (State management and Pub/Sub) with multiples services into a cluster kubernetes.

## Architecture
Below, you can see a high-level and simple architecture used on this example.

![architecture](./docs/img/architecture.png)

### subscriber

Subscriber just listen by notifications sent from [write-values](#write-values). This component receives all notifications and requests from `dapr` through `dapr-ambient` proxy.

### write-values

Write-values is responsible for save values into `redis` through `dapr-ambient`.

```
curl -X POST http://<host>:<port>?value=90
```

### read-values

Read-values reads all values created by `write-values` and returns an average.

```
curl http://<host>:<port>
```

## Installation

### minikube

```bash
make start-minikube
```

### [Dapr](https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-deploy/) 
```bash
helm repo add dapr https://dapr.github.io/helm-charts/
helm repo update
helm search repo dapr --devel --versions
helm upgrade --install dapr dapr/dapr \
    --version=1.12.4 \
    --namespace dapr-system \
    --create-namespace \
    --wait
# Dapr Dashboard    
helm install dapr-dashboard dapr/dapr-dashboard --namespace dapr-system    
kubectl get pods --namespace dapr-system
kubectl port-forward -n dapr-system svc/dapr-dashboard 8080:8080
xdg-open http://localhost:8080/overview
```

Uninstall
```bash
helm uninstall dapr --namespace dapr-system
helm uninstall dapr-dashboard --namespace dapr-system   
```

### Redis

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create ns dapr-go
export REDIS_PASSWORD=$(kubectl get secret --namespace dapr-go redis-password-secret -o jsonpath="{.data.redis-password}" | base64 -d)
echo $REDIS_PASSWORD
helm upgrade --install redis bitnami/redis --namespace ${DAPRGO_NS} --set auth.existingSecret=redis-password-secret --set architecture=standalone --set replica.replicaCount=1
kubectl run --namespace dapr-go redis-client --restart='Never'  --env REDIS_PASSWORD=$REDIS_PASSWORD  --image docker.io/bitnami/redis:7.2.5-debian-12-r0 --command -- sleep infinity
kubectl exec --tty -i redis-client --namespace dapr-go -- bash
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h redis-master

kubectl port-forward --namespace dapr-go svc/redis-master 6379:6379 &
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379


```

Uninstall
```bash
helm uninstall redis --namespace dapr-go
```

### Referencec

[go-sdk examples](https://github.com/dapr/go-sdk/tree/main/examples/pubsub)
[dapr-shared-examples](https://github.com/salaboy/dapr-shared-examples)