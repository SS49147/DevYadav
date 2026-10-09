# Exercise 2: Flask on Minikube

Deploy the Flask app from [Sunag's Exercise 2](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/2-Minikube-Kubectl-Flask.md), first without a Service, then expose it through a NodePort Service.

The app returns `Hello from Flask on Kubernetes!` on `/` and listens on container port `15000`. The Deployment has one replica and uses `flask-app:latest` with `imagePullPolicy: Never`.

## Run

Start Docker Desktop with Linux containers. Run these PowerShell commands from this folder with Minikube and kubectl on PATH:

```powershell
minikube start --profile devops-exercises --driver docker --cpus 2 --memory 2048 --keep-context --preload=false
docker build -t flask-app:latest .
docker run --rm flask-app:latest python -m unittest -v
minikube --profile devops-exercises image load flask-app:latest
kubectl --context devops-exercises create namespace exercise2
kubectl --context devops-exercises apply -f flask-deployment.yaml
kubectl --context devops-exercises -n exercise2 rollout status deployment/flask-app --timeout=180s
kubectl --context devops-exercises -n exercise2 get deployments,pods -o wide
kubectl --context devops-exercises -n exercise2 describe deployment flask-app
kubectl --context devops-exercises -n exercise2 logs deployment/flask-app
kubectl --context devops-exercises -n exercise2 get services
curl.exe --max-time 3 http://127.0.0.1:15000/
```

On the first run, there is no Service in `exercise2`. The host request should fail if nothing else is listening on host port 15000: `containerPort` does not publish a port on the laptop.

Now create the Service:

```powershell
kubectl --context devops-exercises apply -f flask-service.yaml
kubectl --context devops-exercises -n exercise2 get services
minikube --profile devops-exercises service flask-app-service --namespace exercise2 --url
```

Open the printed URL in a browser or use it with `curl.exe` in another terminal. Keep the Minikube terminal open while using the Windows tunnel. The response should be `Hello from Flask on Kubernetes!`.

```powershell
.\verify.ps1 -ServiceUrl http://127.0.0.1:PRINTED_PORT/
```

Replace `PRINTED_PORT` with the actual port. The script checks the Deployment, image/pull policy, pod, Service, ready endpoint and HTTP response. It saves the measured values to `evidence/verification.json`.

## Notes

The source uses `docker-env` to build inside Minikube. That command failed here with `SSH_AGENT_START` on Windows with the containerd runtime. Building with Docker Desktop and using `minikube image load` puts the same image into the cluster's image store. This is a [documented Minikube method](https://minikube.sigs.k8s.io/docs/handbook/pushing/).

The Deployment and Service are in separate YAML files so the before/after Service check can be repeated in order. Their settings match the source; namespace `exercise2` isolates this exercise from Exercise 1 and the existing assignments.

Service `port: 15000` is the cluster-facing port; `targetPort: 15000` is the pod's listening port. A NodePort Service also receives a node port in the `30000–32767` range. On this Windows Docker setup, use the URL from `minikube service`, not host `localhost:15000`.

The Dockerfile retains the source's Python 3.8 image and Flask development server for this lab. Python 3.8 is end-of-life; this image and server are not intended for production.

See [RESULTS.md](RESULTS.md) for the recorded run. GitHub Actions builds and tests the image, deploys it on a fresh Minikube cluster, checks the absence of host exposure, and verifies the Service response.
