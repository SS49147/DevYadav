# Assignment 3 Results

## Automated tests

```text
....                                                                     [100%]
4 passed in 0.80s
```

The tests cover missing and invalid uploads, forwarding a JPEG to the supplied service, returning the transformed response and exposing Prometheus metrics.

## Configuration checks

- The Grafana dashboard JSON was parsed successfully.
- Prometheus reported both `visualcraft-api` and `cadvisor` targets as `up`.
- Grafana loaded the provisioned **VisualCraft API Performance** dashboard with request totals, request rate, p95 latency, CPU usage and memory usage.
- The CI and Jenkins pipelines place tests before build or deployment.

## Docker execution

All five services started successfully:

```text
visualcraft-ai-service   Up
visualcraft-api          Up (healthy)
visualcraft-cadvisor     Up (healthy)
visualcraft-grafana      Up
visualcraft-prometheus   Up
```

The sample JPEG was submitted to `/styleTransfer`. The API returned HTTP 200 and wrote a 21,957-byte stylized JPEG. A request without an image returned HTTP 400, and the metrics endpoint exposed separate `200`, `400` and `500` status series.

## Resilience test

The API container's main process was stopped with `SIGTERM`. Docker restarted it automatically with `RestartCount=1`, and `/health` returned `healthy` after the restart.

The input, output and Grafana dashboard are stored in the [evidence](evidence) folder.
