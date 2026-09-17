# Assignment 2 Results

## Automated tests

```text
....                                                                     [100%]
4 passed in 1.32s
```

The tests were run against an isolated in-memory MongoDB substitute. They verified node and edge creation, invalid input handling, the health endpoint and Prometheus metrics output.

## Docker execution

Both containers reached healthy status. A `Treasure` node, a `Location` node and a `Hidden-At` edge were created through the running API. The graph response contained two nodes and one edge.

## Traffic simulation

```text
Requests: 1000
Successful: 1000
Elapsed: 3.49 seconds
Throughput: 286.55 requests/second
Mean latency: 126.03 ms
P95 latency: 173.22 ms
```

Resource usage sampled immediately afterward:

```text
treasurebook-api       0.23% CPU   73.04 MiB
treasurebook-mongodb   0.78% CPU   75.08 MiB
```

## Kubernetes execution

The manifests were deployed to a local Kind cluster with Metrics Server enabled. MongoDB reached `1/1` ready and the API reached its initial `3/3` ready state. During sustained traffic, average API CPU reached 68% against the 5% target. The HPA increased the requested replicas from 3 to 10; after traffic stopped, it returned the deployment to the three-pod minimum.

## Observation

MongoDB is exposed only inside the cluster. The API is the public entry point, while every API replica connects to the same `mongodb` service name. This allows the API pods to scale without creating separate copies of the graph data.
