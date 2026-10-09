# Exercise 3 Results

Run date: 9 October 2026. Minikube 1.39.0, Kubernetes 1.37.0 and Docker Engine 29.8.2.

All five container-based Flask tests passed. The image was pushed to `anas2694/flashsale:1.0`; Docker Hub's tag API and the running pods reported the same digest:

```text
sha256:dabbae6390989ce27dec32fcd09102dc574d53f0e35d2dc372efc58c2a9ca2bf
```

## Replica counts and replacement

The initial ReplicaSet reached three ready pods. Scaling `flashsale-rs` to five added exactly two pods, retaining the original three UIDs.

The test deleted `flashsale-rs-77q8v` (UID `eae97428-6653-4293-8654-a3014a8d0dd5`). Kubernetes replaced it with `flashsale-rs-lrg5l` (UID `1ee15832-19bf-4dc9-9fdf-726dcaf3138c`). The ReplicaSet returned to five ready pods. All five ran on the single `devops-exercises` node.

## Service requests

The ClusterIP Service had five ready pod endpoints. Requests to `/` and `/health` returned the expected JSON with HTTP 200. All 100 requests to `/buy?user=lab-test` succeeded, with these observed counts:

| Pod | Requests |
| --- | ---: |
| flashsale-rs-lrg5l | 22 |
| flashsale-rs-n6bjh | 23 |
| flashsale-rs-x8xpw | 22 |
| flashsale-rs-hnnph | 17 |
| flashsale-rs-hvw88 | 16 |

This demonstrates distribution through the Service, not a capacity benchmark or a guarantee of exactly equal traffic. The app only simulates purchases.

Kubernetes accepted the manifest in a server-side dry run. A separate port-forward allowed the browser to display the purchase JSON.

## Evidence

- [Unit test output](evidence/unit-tests.txt)
- [Docker Hub tag and digest](evidence/registry-image.json)
- [Pod UIDs, replica stages, endpoints and HTTP checks](evidence/verification.json)
- [Final resource listing](evidence/resources.txt)
- [ReplicaSet description and events](evidence/replicaset-description.txt)
- [Browser purchase response](evidence/buy-response.png)
