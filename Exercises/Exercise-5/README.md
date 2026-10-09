# Exercise 5: Docker Security with AppArmor

Implement [Sunag's AppArmor exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/5-Docker-Security-AppArmor.md): containerize the Flask app, apply a profile through the Docker SDK for Python, and test denied file access and binary execution.

## Host requirement

AppArmor must be enabled on the Linux host running Docker, and the named profile must be loaded in enforce mode. Check:

```bash
docker info --format '{{json .SecurityOptions}}'
sudo aa-status
```

The Docker Desktop engine on this Windows laptop does not report AppArmor support. Building and testing Flask locally is possible, but the restriction tests must run on a supported Linux Docker host. The scripts refuse to run those tests without reported AppArmor support. The GitHub workflow uses Ubuntu 24.04 for actual enforcement tests.

## Build and load the profile on Linux

Run from this folder on the supported host:

```bash
sudo apt-get update
sudo apt-get install -y apparmor-utils
python3 -m venv .venv
.venv/bin/pip install -r requirements-host.txt
docker build -t flask-apparmor:latest .
docker run --rm flask-apparmor:latest python -m unittest -v
sudo install -m 644 my-apparmor-profile /etc/apparmor.d/my-apparmor-profile
sudo apparmor_parser -r -W /etc/apparmor.d/my-apparmor-profile
sudo aa-status
```

Do not replace an existing profile of the same name without inspecting it first. The app listens on container port 5000 and returns the source exercise's message.

## Apply through the SDK and test

```bash
.venv/bin/python apply_apparmor.py
.venv/bin/python test_restricted_actions.py
```

`apply_apparmor.py` builds the image using the SDK, starts the container with `apparmor=my-apparmor-profile`, checks the HTTP response, Docker's `AppArmorProfile` field and `/proc/self/attr/current`, then stops and removes its container.

`test_restricted_actions.py` first checks the same operations in an unconfined control container. It then requires the confined container to deny reading `/etc/passwd`, writing under `/var`, running `/bin/bash` and running `/usr/bin/cat`. Reading `/etc/passwd` is tested with Python directly so a denied `cat` execution cannot be mistaken for a denied file read. A write under `/app` must still succeed and Flask must remain reachable. Both containers are removed after the tests.

The scripts publish `127.0.0.1:15005` to container port 5000, avoiding the earlier assignment's host port. Reports are saved under `evidence/`; GitHub Actions also uploads the Linux reports as an artifact.

For the CLI equivalent, while no SDK test is running:

```bash
docker run -d --name exercise5-cli --label devops.lab.exercise=5 --security-opt apparmor=my-apparmor-profile -p 127.0.0.1:15005:5000 flask-apparmor:latest
curl http://127.0.0.1:15005/
docker inspect --format '{{.AppArmorProfile}}' exercise5-cli
docker stop exercise5-cli
docker rm exercise5-cli
```

After all lab containers are removed, unload only this lab's profile:

```bash
sudo apparmor_parser -R /etc/apparmor.d/my-apparmor-profile
```

## Profile corrections and limits

The source declares a path profile for `/usr/bin/python3` but selects `my-apparmor-profile` in Docker. This file declares that exact profile name and allows the official Python image's interpreter under `/usr/local/bin`. Python and shared-library read/mapping rules let Flask start while retaining the source's `/etc`, `/var`, `/bin`, `/usr/bin` and `sys_admin` denials.

The parser rejected the source's `deny ... rmix` syntax: deny rules use plain `x`, not an execution transition such as `ix`. The corresponding rules use `rmx` here.

The rules permit TCP stream sockets; they do not filter traffic specifically to port 5000. AppArmor adds confinement, not a complete production security policy. An inspection field alone proves configuration, so the tests also require enforce mode and observed permission denials. This follows Docker's [profile-loading and verification guidance](https://docs.docker.com/engine/security/apparmor/).

The Python 3.8 image and Flask development server are retained for the lab, not production use. Local app-test output and the Windows capability check are in `evidence/`; Linux enforcement results will be recorded after the workflow passes.
