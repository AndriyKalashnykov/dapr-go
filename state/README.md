# state/frontendsvc — Dapr State Management demo

`frontendsvc` is one of the four services in this repo (see the top-level
[README](../README.md) and [CLAUDE.md](../CLAUDE.md)). It is an **independent**
demo of Dapr's [State Management](https://docs.dapr.io/developing-applications/building-blocks/state-management/)
building block — separate from the `write-values`/`read-values`/`subscriber`
pipeline — showing a plain `net/http` service that stores and retrieves orders
through the Dapr sidecar rather than talking to Redis directly.

## Endpoints

| Method + path | Behaviour |
|---------------|-----------|
| `POST /orders/new` | Decode an order JSON body, generate a `crypto/rand` order ID, `SaveState` it to the `statestore` component, return `{"order":"…","status":"received"}`. `400` on a malformed body. |
| `GET /orders/order/{id}` | `GetState` the order by ID; `404` if not found. |
| `GET /health/{readiness\|liveness}` | k8s probes. Readiness is `503` until the Dapr client connects, then `200`; liveness is always `200` (see the sidecar-startup-race note in [CLAUDE.md](../CLAUDE.md)). |

All Dapr calls go over the injected sidecar's localhost gRPC API using
`github.com/dapr/go-sdk`. The state-store component name (`statestore`) is
defined in [`k8s/dapr/components/statestore.yaml`](../k8s/dapr/components/statestore.yaml)
and backed by the `redis-master` Deployment ([`k8s/redis/redis.yaml`](../k8s/redis/redis.yaml)).

## Build & deploy

There is **no standalone build for this service** — it is built and deployed as
part of the whole project, using the repo-root `Makefile`:

```bash
make image-build      # builds ghcr.io/andriykalashnykov/dapr-go/frontendsvc:<version.txt>
make kind-deploy      # kind-up → deploy-dapr → deploy-components → deploy-workloads
make e2e              # exercises the frontendsvc CRUD path end-to-end
```

`deploy-workloads` applies [`k8s/apps/frontend.yaml`](../k8s/apps/frontend.yaml)
(the `frontendsvc` Deployment + `frontend-svc` LoadBalancer Service, carrying the
`dapr.io/enabled`/`dapr.io/app-id`/`dapr.io/app-port` annotations that trigger
sidecar injection) and `kind load`s the locally-built image. See the top-level
README's Deploy section for the full lifecycle and teardown.

## Try it

`frontendsvc` is fronted by a `LoadBalancer` Service (`cloud-provider-kind`
assigns the external IP). Resolve it, then:

```bash
IP=$(kubectl --context kind-dapr-go -n dapr-go get svc frontend-svc \
       -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -s -XPOST "http://$IP:8080/orders/new" \
  -H 'Content-Type: application/json' -d '{"items":["automobile"]}'
# -> {"order":"order-8008026f","status":"received"}

curl -s "http://$IP:8080/orders/order/order-8008026f"
# -> {"ID":"order-8008026f","Items":["automobile"],"Completed":true}
```

## Troubleshooting

```bash
kubectl --context kind-dapr-go -n dapr-go logs -l app=frontendsvc -c daprd -f       # sidecar
kubectl --context kind-dapr-go -n dapr-go logs -l app=frontendsvc -c frontendsvc -f  # app
```
