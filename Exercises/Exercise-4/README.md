# Exercise 4: Docker Networking

Run Flask, MySQL and Redis on a custom bridge network, following [Sunag's Exercise 4](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/4-Docker-Networking.md) and its [linked practical guide](https://docs.google.com/document/d/1ue5G-sj02E4G9NW5T5ObmsbdMl4LihUS/edit).

The Flask app serves `/about` on container port 5001. The lab checks name resolution, ping, MySQL and Redis connectivity; the `/about` route itself does not query either server.

## Build and run

Start Docker Desktop with Linux containers. From this folder:

```powershell
docker --version
docker info
docker build -t flask-api:latest .
docker run --rm flask-api:latest python -m unittest -v
.\start.ps1
```

The script creates `my-bridge-net`, tests the Flask image as a standalone container, removes that test container, then starts:

| Container | Network name/alias | Internal port | Published host port |
| --- | --- | ---: | --- |
| exercise4-flask | flask | 5001 | 127.0.0.1:15004 |
| exercise4-mysql | mysql | 3306 | None |
| exercise4-redis | redis | 6379 | None |

The prefixes avoid collisions with other projects. Network aliases keep the guide's `mysql` and `redis` names usable inside Flask. MySQL receives a generated root password and initializes `devopsdb`; no password is saved in the repository or printed by the scripts.

Host port 5001 was already in use on this laptop. The default mapping is therefore `127.0.0.1:15004:5001`. To choose another free host port, use `start.ps1 -HostPort PORT` and the same value for `verify.ps1`.

## Inspect and test

```powershell
docker network ls
docker network inspect my-bridge-net
docker ps --filter label=devops.lab.exercise=4
docker port exercise4-flask
curl.exe http://127.0.0.1:15004/about
docker exec exercise4-flask getent hosts mysql
docker exec exercise4-flask getent hosts redis
docker exec exercise4-flask ping -c 3 mysql
docker exec exercise4-flask ping -c 3 redis
docker exec exercise4-redis redis-cli ping
.\verify.ps1
```

For an interactive shell, use `docker exec -it exercise4-flask bash`. The image includes `iputils-ping`, so no installation is needed after startup.

The verification script checks all three network members, running states, port publishing, DNS, three pings per server, Redis `PONG`, MySQL's TCP handshake and `SHOW DATABASES`, and the host's `/about` response. It uses the MySQL container's password environment internally; it never includes credentials in the report.

Expected `/about` response:

```json
{"description":"This is a simple REST API built with Flask.","name":"Simple REST API","version":"1.0"}
```

Reports are saved under `evidence/`. The measured subnet and container addresses can change between runs; use DNS names rather than hard-coded addresses.

## Clean up

```powershell
.\cleanup.ps1
```

This stops and removes only the labelled Exercise 4 containers, their anonymous lab volumes and `my-bridge-net`. It checks ownership before removal and refuses to touch a network used by other containers. The temporary `devopsdb` data is discarded; images are retained. No system-wide prune is used.

## Lab questions

`--network` selects the network a container joins. On a user-defined bridge, containers can resolve container names and network aliases through Docker DNS. Bridge networking gives containers their own network namespaces; host networking shares the host's network stack. `-p HOST_PORT:CONTAINER_PORT` publishes an entry point for host access, independently of internal container-to-container communication.

## Version notes

The app retains Python 3.9 and Flask 2.0.1 from the source. Werkzeug is pinned to 2.0.3 as required by the linked guide. Flask binds to `0.0.0.0` so published ports can reach it. These older runtime/dependency versions and Flask's development server are for the lab, not production deployment.

See [RESULTS.md](RESULTS.md) for the observed run and cleanup. GitHub Actions builds the image and repeats the standalone, three-container, connectivity and cleanup checks.
