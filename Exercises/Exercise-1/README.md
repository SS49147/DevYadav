# Exercise 1: Kubernetes Getting Started

Run the `nginx` image as a Kubernetes pod, expose it through a NodePort service and open the Nginx welcome page.

Reference: [SunagP's Exercise 1](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/1-Kubernetes-Getting-Started.md).

## Setup and execution

Install Minikube and start Docker Desktop with Linux containers. Run these commands in PowerShell:

```powershell
minikube start --profile devops-exercises --driver docker --cpus 2 --memory 2048 --keep-context --preload=false
minikube --profile devops-exercises kubectl -- --context devops-exercises create namespace exercise1
minikube --profile devops-exercises kubectl -- --context devops-exercises -n exercise1 run hello-k8s --image=nginx --port=80
minikube --profile devops-exercises kubectl -- --context devops-exercises -n exercise1 wait --for=condition=Ready pod/hello-k8s --timeout=180s
minikube --profile devops-exercises kubectl -- --context devops-exercises -n exercise1 get pods
minikube --profile devops-exercises kubectl -- --context devops-exercises -n exercise1 expose pod hello-k8s --type=NodePort --port=80
minikube --profile devops-exercises service hello-k8s --namespace exercise1 --url
```

Open the URL printed by the last command in a browser. Keep that terminal open: on Windows with Docker, `minikube service` maintains the tunnel needed to reach the NodePort service. Press Ctrl+C when finished.

The named profile keeps the exercises separate from the earlier assignments. `--keep-context` preserves the current Kubernetes context, and namespace `exercise1` isolates this pod and service. `minikube kubectl --` runs the kubectl version matching the cluster; `--context devops-exercises` selects the intended cluster explicitly. With a compatible standalone kubectl, the equivalent commands are `kubectl --context devops-exercises -n exercise1 ...`.

The imperative commands above demonstrate the steps in the source exercise. To recreate the same resources from this folder, use the included manifest instead:

```powershell
minikube --profile devops-exercises kubectl -- --context devops-exercises apply -f hello-k8s.yaml
minikube --profile devops-exercises kubectl -- --context devops-exercises -n exercise1 wait --for=condition=Ready pod/hello-k8s --timeout=180s
```

## Verify

In a second PowerShell terminal, pass the actual URL printed by `minikube service`:

```powershell
$serviceUrl = Read-Host 'Paste the URL printed by minikube service'
.\verify.ps1 -ServiceUrl $serviceUrl
```

The script checks the pod's readiness, image and port, the NodePort service, its ready endpoint and the HTTP response. It writes the measured results and response HTML under `evidence/`. If Minikube is not on PATH, pass its executable with `-Minikube 'C:\path\to\minikube.exe'`.

## Notes

[RESULTS.md](RESULTS.md) contains the recorded execution and browser screenshot. GitHub Actions repeats the manifest deployment and the five verification checks in a fresh Minikube cluster.

A pod runs the container. The service selects the pod using its `run: hello-k8s` label and forwards port 80 to Nginx. The assigned NodePort and Windows tunnel port are different and can change between runs.

This exercise uses a standalone pod, as specified in the source. It has no Deployment or ReplicaSet to replace the pod if it is deleted. Those controllers are covered in later exercises. The unpinned `nginx` image follows the reference; the resolved image digest is recorded in the verification output.

To stop the local cluster without deleting its resources:

```powershell
minikube stop --profile devops-exercises
```
