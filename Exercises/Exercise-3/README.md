# Exercise 3: Scaling Flask with a ReplicaSet

Implement [Sunag's ReplicaSet exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/3-Minikube-Scaling-Flask-App-with-Replicasets.md): run three Flash Sale pods on one node, scale to five, delete one pod and check that Kubernetes replaces it.

The Flask app has `/`, `/buy` and `/health` routes. `/buy?user=123` returns a simulated purchase, including the pod that handled it. It does not store orders or process payments.

## Build and publish

Run from this folder with Docker Desktop running:

```powershell
docker build -t anas2694/flashsale:1.0 .
docker run --rm anas2694/flashsale:1.0 python -m unittest -v
docker push anas2694/flashsale:1.0
```

Publishing requires login to the `anas2694` Docker Hub account. The public image is [anas2694/flashsale](https://hub.docker.com/r/anas2694/flashsale). For your own account, change the image tag in both the build commands and manifest.

## Deploy and scale

```powershell
minikube start --profile devops-exercises --nodes=1 --driver docker --cpus 2 --memory 2048 --keep-context --preload=false
kubectl --context devops-exercises get nodes
kubectl --context devops-exercises apply -f flashsale-replicaset.yaml
kubectl --context devops-exercises -n exercise3 wait --for=condition=Ready pod -l app=flashsale --timeout=180s
kubectl --context devops-exercises -n exercise3 get rs,pods -o wide
kubectl --context devops-exercises -n exercise3 scale rs flashsale-rs --replicas=5
kubectl --context devops-exercises -n exercise3 wait --for=condition=Ready pod -l app=flashsale --timeout=180s
kubectl --context devops-exercises -n exercise3 get rs,pods -o wide
```

Choose one pod from the listing and delete it:

```powershell
kubectl --context devops-exercises -n exercise3 delete pod POD_NAME
kubectl --context devops-exercises -n exercise3 get pods -o wide
kubectl --context devops-exercises -n exercise3 describe rs flashsale-rs
```

Wait until five pods are ready again. The replacement has a new name and UID; all five remain on the single node.

The Service is `ClusterIP`, with port 80 forwarding to port 5000. For browser access, open a separate terminal:

```powershell
kubectl --context devops-exercises -n exercise3 port-forward service/flashsale-svc 15003:80
```

Open `http://127.0.0.1:15003/` or `/buy?user=123`. A port-forward targets one pod; it is not a load-distribution test. The verification script tests distribution using the cluster Service directly.

## Repeat the verification

Applying the manifest resets the ReplicaSet to three replicas. The script then scales it to five, deletes one pod owned by `flashsale-rs`, waits for its replacement and makes 100 purchase requests through Service DNS from inside a pod:

```powershell
kubectl --context devops-exercises apply -f flashsale-replicaset.yaml
.\verify.ps1
```

It checks the image, probes, resource settings, one-node layout, replica counts, pod UIDs, five ready service endpoints and all three routes. Measured output is saved to `evidence/verification.json`. GitHub Actions repeats this sequence on a fresh single-node cluster, loading its newly built image locally without requiring registry credentials.

## Source corrections

The source Dockerfile copies `ex3-flash-sale.py` but runs `app:app`. Here the module is consistently named `app.py`. Its commands alternate between `flask-app-rs` and `flashsale-rs`; this folder consistently uses the manifest's `flashsale-rs`. The image is the published `anas2694/flashsale:1.0`, rather than the unrelated `flask-app` tag in one source command.

Namespace `exercise3` keeps the lab separate without deleting the cluster or the earlier exercises. The readiness/liveness probes and CPU/memory requests and limits retain the source values.

See [RESULTS.md](RESULTS.md) for the observed scaling and replacement.
