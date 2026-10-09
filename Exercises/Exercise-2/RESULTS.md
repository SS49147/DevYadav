# Exercise 2 Results

Run date: 9 October 2026.

The app ran on the single-node `devops-exercises` Minikube profile in namespace `exercise2`. Versions: Docker Desktop 4.94.0, Docker Engine 29.8.2, Minikube 1.39.0 and Kubernetes 1.37.0.

## Image and deployment

The image built successfully from `python:3.8-slim`; pip selected Flask 3.0.3. Both container-based unit tests passed: the home route returned the required message and an unknown route returned 404.

After loading `flask-app:latest` into Minikube and applying the Deployment, it reached one ready and available replica:

```text
POD                          READY   STATUS    RESTARTS   IP           NODE
flask-app-59f7cdccb4-j6fch     1/1     Running   0          10.244.0.4   devops-exercises
```

The pod logs showed Flask listening on port 15000. The Deployment description recorded `Host Port: 0/TCP` and `imagePullPolicy: Never` is recorded in [verification.json](evidence/verification.json).

## Before and after the Service

Before creating the Service, the namespace had zero Services. A request to `http://127.0.0.1:15000/` failed with curl exit code 7 (connection refused). The measured result is in [before-service.json](evidence/before-service.json).

After applying `flask-service.yaml`, the NodePort Service had ClusterIP `10.109.59.252`, service port `15000`, target port `15000` and node port `31393`. Its ready endpoint was `10.244.0.4:15000`, matching the Flask pod.

The Windows Minikube tunnel printed `http://127.0.0.1:63020/`. That URL returned HTTP 200 and exactly:

```text
Hello from Flask on Kubernetes!
```

All six deployment/HTTP checks passed. Kubernetes accepted both manifests in a server-side dry run. The browser displayed the same response:

![Flask response through the Minikube Service](evidence/flask-response.png)

The tunnel port is specific to this run. Start `minikube service` again to obtain a current URL.

## Recorded output

- [Unit tests](evidence/unit-tests.txt)
- [Deployment and pod listing](evidence/deployment.txt)
- [Deployment description](evidence/deployment-description.txt)
- [Flask startup logs](evidence/flask-startup.txt)
- [Service and endpoint listing](evidence/service.txt)
- [Verification report](evidence/verification.json)

The failed `docker-env` attempt was a Windows SSH-agent limitation. Building on the host and loading the image into Minikube avoided that step without changing the required app or Kubernetes settings.
