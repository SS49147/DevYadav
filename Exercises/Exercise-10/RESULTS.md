# Exercise 10 results

Verified on 10 October 2026 with Minikube 1.39.0, Kubernetes 1.37.0 and containerd 2.3.4. All three nodes in `devops-multinode` were Ready.

| Node | Catalog replicas | Cart replicas |
| --- | --- | --- |
| devops-multinode | 0 | 1 |
| devops-multinode-m02 | 1 | 1 |
| devops-multinode-m03 | 1 | 1 |

The Deployments' active ReplicaSets had 2/2 and 3/3 ready replicas. Both application images were cached on all three nodes. The registry Deployment and all three registry-proxy pods were running. The catalog Service had two ready endpoints on NodePort 32574; the cart Service had three on NodePort 30489.

Five unit tests passed in each built image. The verification passed 17 cluster and HTTP checks. It confirmed the exact three source products from both catalog pods and through NodePort. Every cart was initially empty, and a NodePort POST of the source's Laptop item returned HTTP 201 with the item.

After that POST, `shopping-cart-8b6ddbb77-4jtqg` held one item; the other two pods still returned empty lists. This demonstrates the source's per-replica in-memory state, not shared cart consistency. The report records the before/after cart contents for all three pods.

One worker's initial networking-image download exceeded the readiness wait. Loading the same kindnet and kube-proxy images through the host cache made all nodes Ready; the startup script includes that recovery path. No cluster was deleted. The earlier `devops-exercises` profile and unrelated applications stayed running, and the active kubectl context remained `kind-treasurebook`.

The Jenkins lab containers from Exercises 6, 7 and 9 were paused to free memory. Their containers, volumes, credentials and jobs were retained. They can be resumed from their own folders with their startup commands; do not repeat Exercise 7's one-time setup.

## Evidence

- [Cluster, replica, image, Service and HTTP verification](evidence/verification.json)
- [Catalog image unit tests](evidence/unit-product.json)
- [Cart image unit tests](evidence/unit-shopping.json)
- [Actual catalog response in the browser](evidence/product-catalog.png)
- [Actual cart response in the browser](evidence/shopping-cart.png)

The verification's temporary forwarding processes were stopped after the checks. Its recorded loopback URLs are historical test URLs; open fresh Service tunnels to access the apps again.

## Rolling update recheck — 20 October 2026

[GitHub Actions run 39306429288](https://github.com/Anas2694/DevOps-Lab/actions/runs/39306429288) repeated the initial deployment checks and then restarted the cart Deployment. All three original pod UIDs were replaced by new pods on three distinct nodes. At least two cart replicas remained available in every sample; the final sample had all three available.

The rollout uses `maxSurge: 0` and `maxUnavailable: 1`, so it completes without needing a fourth node. All new carts were empty, matching the source application's in-memory state behavior. [rollout.json](evidence/rollout.json) contains the measured UIDs, node placement, strategy and availability samples.
