# Dockerized Multi-Container Inventory Application

This project implements a Flask CRUD web application backed by MongoDB. The services run in separate Docker containers, communicate through a custom bridge network, and retain database records in a named Docker volume. Python scripts manage the Docker resources and monitor application health.

## Architecture

```text
Browser
   |
   | http://localhost:5000
   v
Flask container  <---- custom bridge network ---->  MongoDB container
                                                        |
                                                        v
                                              named persistent volume
```

## Requirements covered

- Flask web application with Create, Read, Update, and Delete operations
- Separate Flask and MongoDB containers
- Dockerfile for the Flask application
- Persistent MongoDB named volume
- Custom bridge network created and inspected using the Docker SDK for Python
- Python-based container listing and application health monitoring
- Automatic Flask-container restart and console/file alert when unhealthy
- Browser interface and JSON API

## Project structure

```text
assignment-1/
|-- app/
|   |-- app.py
|   |-- Dockerfile
|   |-- requirements.txt
|   |-- static/style.css
|   `-- templates/
|-- scripts/
|   |-- docker_manager.py
|   |-- health_monitor.py
|   `-- requirements.txt
|-- tests/
|   |-- test_app.py
|   `-- requirements.txt
|-- compose.yaml
`-- README.md
```

## Recommended setup: Docker SDK script

The commands below work in PowerShell, Command Prompt, Linux, and macOS terminals after activating the appropriate Python environment.

1. Start Docker Desktop or the Docker daemon.
2. Create a Python virtual environment and install the Docker SDK:

```bash
python -m venv .venv
```

PowerShell activation:

```powershell
.\.venv\Scripts\Activate.ps1
```

Linux/macOS activation:

```bash
source .venv/bin/activate
```

Install the script dependency and start the stack:

```bash
pip install -r scripts/requirements.txt
python scripts/docker_manager.py up
```

Open `http://localhost:5000` and add, edit, and delete inventory items.

## Docker management commands

Inspect both containers and their health states:

```bash
python scripts/docker_manager.py status
```

Inspect the custom bridge network and connected container IP addresses:

```bash
python scripts/docker_manager.py inspect
```

Rebuild the Flask image after changing application code:

```bash
python scripts/docker_manager.py up --rebuild
```

Remove the two containers and custom network while keeping database data:

```bash
python scripts/docker_manager.py down
```

Permanently delete the database volume as well:

```bash
python scripts/docker_manager.py down --remove-volume
```

The last command deletes all stored application records.

## Health monitoring

Run one check:

```bash
python scripts/health_monitor.py --once
```

Continuously check every 15 seconds:

```bash
python scripts/health_monitor.py --interval 15
```

The monitor lists active project containers and reads the Flask container's Docker health state. If the container is stopped or unhealthy, it restarts it and writes an alert to both the terminal and `health-monitor.log`.

Press `Ctrl+C` to stop continuous monitoring.

## Alternative startup with Docker Compose

The SDK-based manager is the primary implementation. Compose is included as a convenient alternative:

```bash
docker compose up --build -d
docker compose ps
docker compose down
```

`docker compose down` preserves the named volume. Add `-v` only when the database data should be deleted.

## JSON API

| Method | Endpoint | Operation |
|---|---|---|
| `GET` | `/api/items` | List all items |
| `POST` | `/api/items` | Create an item |
| `GET` | `/api/items/<id>` | Read one item |
| `PUT` | `/api/items/<id>` | Update an item |
| `DELETE` | `/api/items/<id>` | Delete an item |
| `GET` | `/health` | Verify Flask and MongoDB health |

Example API request:

```bash
curl -X POST http://localhost:5000/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"USB-C hub","description":"Eight port hub","quantity":3}'
```

## Run automated tests

Install the application and test dependencies, then run pytest:

```bash
pip install -r app/requirements.txt -r tests/requirements.txt
pytest -q
```

The tests exercise the health and favicon endpoints, the complete API CRUD flow, input validation, and invalid identifiers using an isolated in-memory MongoDB substitute. See `VALIDATION.md` for the completed runtime checks.

## Demonstration checklist

1. Run `python scripts/docker_manager.py up` and open the application.
2. Create an item and refresh the page to show it was stored.
3. Update its name or quantity, then delete another item.
4. Run `python scripts/docker_manager.py inspect` to show both containers attached to the custom bridge network.
5. Run `python scripts/docker_manager.py status` to show Docker health states.
6. Restart the stack without deleting the volume and show that the saved item still exists.
7. Run `python scripts/health_monitor.py --interval 5`.
8. In a second terminal, simulate a failure with `docker stop assignment1-flask-app`. The monitor detects the stopped container, restarts it, and records an alert.

## Troubleshooting

- **Cannot connect to Docker:** Start Docker Desktop or the Docker daemon and retry.
- **Port 5000 is already in use:** Stop the conflicting process or change `5000` on the host side of the port mapping.
- **Web container remains unhealthy:** Run `docker logs assignment1-flask-app` and `docker logs assignment1-mongodb`.
- **Database name resolution fails:** Run the network inspection command and confirm both named containers appear.
- **PowerShell blocks virtual-environment activation:** Use the environment's Python directly, for example `.\.venv\Scripts\python.exe scripts\docker_manager.py up`.
