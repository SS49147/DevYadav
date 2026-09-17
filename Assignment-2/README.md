# Assignment 2: TreasureBook

## Aim

To containerize a graph-based API, deploy it with MongoDB on Kubernetes, and configure horizontal pod autoscaling for increased traffic.

## Application

TreasureBook stores three node types—`Treasure`, `Location` and `Map`—and connects them using `Trail`, `Hidden-At` and `Leads-To` edges. MongoDB stores the graph data.

## API

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/node` | Add a treasure, location or map |
| `GET` | `/node` | List all nodes |
| `GET` | `/node/<id>` | Read one node |
| `POST` | `/edge` | Connect two existing nodes |
| `GET` | `/edge` | List all edges |
| `GET` | `/graph` | Return nodes and edges together |
| `GET` | `/live` | Check that the API process is running |
| `GET` | `/health` | Check the API and MongoDB |
| `GET` | `/metrics` | Prometheus-formatted API metrics |

Example node:

```powershell
$body = '{"Type":"Treasure","name":"Golden Crown"}'
Invoke-RestMethod -Method Post -Uri http://localhost:5002/node -ContentType application/json -Body $body
```

An edge requires the IDs returned when its two nodes are created:

```json
{
  "Type": "Hidden-At",
  "source": "<treasure-id>",
  "target": "<location-id>"
}
```

## Run with Docker Compose

```powershell
docker compose up --build -d
docker compose ps
```

The API is available at <http://localhost:5002>. Stop it with `docker compose down`. The named volume is retained so that graph data is not lost.

## Kubernetes deployment

The manifests create one MongoDB pod, three initial API pods, a NodePort service and a Horizontal Pod Autoscaler. The API resource values match the assignment:

- request: `100m` CPU and `256Mi` memory
- limit: `200m` CPU and `512Mi` memory
- HPA: minimum 3 pods, maximum 10 pods, target CPU utilization 5%

For Docker Desktop Kubernetes, build the local image and apply the manifests:

```powershell
docker build -t treasurebook-api:1.0 app
kubectl apply -f kubernetes/mongodb.yaml
kubectl apply -f kubernetes/api.yaml
kubectl get pods
kubectl get service treasurebook-api
kubectl get hpa treasurebook-api
```

The Metrics Server must be installed in the cluster for CPU-based autoscaling. When using the supplied NodePort, the API is exposed on port `30500` of the cluster node. A local Kind cluster can instead be tested with `kubectl port-forward service/treasurebook-api 5003:5000`.

Before applying the manifests to Kind, load the locally built API image into the cluster:

```powershell
kind load docker-image treasurebook-api:1.0 --name treasurebook
```

## Traffic simulation

Install the small load-test dependency and send concurrent requests:

```powershell
pip install -r scripts/requirements.txt
python scripts/load_test.py --url http://localhost:30500 --requests 1000 --workers 40
```

Observe the deployment in another terminal:

```powershell
kubectl get hpa treasurebook-api --watch
kubectl top pods -l app=treasurebook-api
```

The HPA compares average CPU usage with the requested `100m`. At a 5% target, sustained usage above approximately `5m` per pod can cause a scale-up. The 60-second scale-down stabilization window prevents pods from being removed immediately after traffic falls.

## Tests

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r app/requirements.txt -r tests/requirements.txt
pytest -q
```

The test suite checks health, graph creation, input validation and metrics. Recorded results are in [RESULTS.md](RESULTS.md).

## Screenshots

- [API and MongoDB health](evidence/health.png)
- [TreasureBook graph response](evidence/graph.png)
