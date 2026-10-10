# Exercise 10: Multi-Node Kubernetes Applications

Implement [Sunag's multi-node exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/10-Minikube-Multi-Node-Multi-App-Minikube-Deployment.md): run a three-node Minikube cluster, deploy the Product Catalog with two replicas and Shopping Cart with three, distribute replicas across nodes and test both NodePort Services.

## Start and verify

Docker and Minikube must be available. Use PowerShell 7 from this folder:

```powershell
./start.ps1
./verify.ps1 -RequireEmptyCarts
```

If Minikube is not on PATH, pass its absolute executable path with `-Minikube`. The scripts use the source's `devops-multinode` profile. A different isolated profile can be supplied with `-ClusterProfile`; do not choose a profile containing unrelated resources. Existing objects with the lab's Deployment or Service names must carry the Exercise 10 ownership label before the script will update them.

The start script creates three Docker-driver nodes with containerd, two CPUs and a 2 GiB memory limit per node. It uses Kubernetes 1.37.0, keeps the current kubectl context unchanged, waits for all nodes, enables the registry addon, builds both source-named images, runs five tests in each image and loads them into the profile. Every kubectl command selects the profile's context explicitly.

The source's Python 3.9 slim base is retained. Flask is pinned to 3.1.3, which supports Python 3.9. Python 3.9 and Flask's development server are used for this lab, not recommended as a new production runtime.

The source's blanket Minikube stop/delete commands are not run. Previous profiles and unrelated applications are preserved. On a limited-memory laptop, pause other lab controllers before starting three nodes, retaining their volumes and jobs.

## Deployment and image distribution

Both Deployments and their Services use `default` on the dedicated profile. The source places the cart Deployment in `devops-exercise` but its Service in `default`; that Service cannot select those pods. Keeping them together fixes the mismatch. Each Deployment retains strict `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity by hostname, so catalog replicas occupy two different nodes and cart replicas occupy all three.

Images retain the source's `product-catalog:latest` and `shopping-cart:latest` names and `imagePullPolicy: Never`. Readiness probes check `/products` and `/cart`; small resource requests and memory limits keep the lab bounded.

The registry addon is enabled as requested. The source's `minikube image load` commands load images into node runtimes; they are not pushes to that registry. The verification checks both cached application images on every node. With containerd, inspect runtime images using `crictl images`, not `docker images` inside a node. See Minikube's [image-loading methods](https://minikube.sigs.k8s.io/docs/handbook/pushing/) and [multi-node tutorial](https://minikube.sigs.k8s.io/docs/tutorials/multi_node/).

## Access both Services

In two separate terminals, keep these commands running on Windows:

```powershell
minikube --profile devops-multinode service product-catalog-service --namespace default --url
minikube --profile devops-multinode service shopping-cart-service --namespace default --url
```

Each command prints its current local URL. Use the catalog URL plus `/products`, and the cart URL plus `/cart`. The exact ports depend on the current forwarding processes; the source's example URLs are not fixed ports for this installation.

To test the cart using the returned URL:

```powershell
$cartUrl = 'http://127.0.0.1:PORT_FROM_CURRENT_TUNNEL'
Invoke-RestMethod "$cartUrl/cart"
Invoke-RestMethod "$cartUrl/cart" -Method Post -ContentType 'application/json' -Body '{"id":1,"name":"Laptop","quantity":1}'
```

The initial cart is empty on a fresh deployment. POST returns HTTP 201 and the updated list from the pod handling that request. `verify.ps1` checks all initial cart replicas when `-RequireEmptyCarts` is set, performs the source's POST through NodePort and records the resulting state per pod. It stops only its own temporary forwarding processes. For subsequent checks with existing cart entries, omit `-RequireEmptyCarts`; the script adds another test item rather than erasing existing carts.

## Limits of the source app

Each cart is a separate in-memory Python list. Three replicas provide multiple running instances, not shared cart storage. A later GET can reach another replica and return a different list. Restarting a cart pod loses that pod's contents. A real cart service would need shared storage and a user/session model; neither is added to this exercise.

Strict anti-affinity also requires three healthy nodes for all three cart replicas. If one node is unavailable, its replacement cannot run alongside another cart on a surviving node. The remaining replicas can serve requests, but this lab does not claim fault-tolerant cart data or simulate a node failure.

Changing a local `latest` image does not automatically restart existing pods. This exercise verifies the fresh deployment; plan any later rollout and its in-memory data loss explicitly.

The GitHub workflow repeats image tests, three-node deployment, distribution checks and actual HTTP requests on a fresh runner. Generated measurements are saved under `evidence/verification.json`.

Measured results and the startup issue actually encountered are in [RESULTS.md](RESULTS.md).
