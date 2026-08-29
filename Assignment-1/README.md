# Assignment 1: Dockerized Multi-Container Web Application

## Aim

To develop a Python web application with CRUD operations, run the application and database in separate Docker containers, connect them using a custom bridge network, and manage the containers using the Docker SDK for Python.

## Application selected

The selected application is a small inventory system. Each item contains a name, description and quantity. The browser page and the REST API both support Create, Read, Update and Delete operations.

MongoDB was used instead of SQLite because the assignment requires the database to run as a separate container. MongoDB also makes it straightforward to demonstrate container-to-container communication and volume persistence.

## Tools used

- Python and Flask
- MongoDB
- Docker and Docker volumes
- Docker SDK for Python
- HTML and CSS
- Pytest and Mongomock

## Architecture

```text
Browser
   |
   | localhost:5000
   v
Flask container -------- assignment1-network -------- MongoDB container
                                                        |
                                                        v
                                             assignment1-mongo-data
```

The browser communicates only with Flask. Flask connects to MongoDB using the database container name `assignment1-mongodb`. MongoDB stores its files in the named volume `assignment1-mongo-data`, so the records are not lost when the containers are removed.

## Files

```text
Assignment-1/
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
|-- RESULTS.md
`-- README.md
```

## Running the project

The following commands are written for PowerShell. Docker Desktop must be running before executing them.

Create and activate a virtual environment:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r scripts\requirements.txt
```

Build the Flask image and start both containers:

```powershell
python scripts\docker_manager.py up
```

The script performs these operations using the Docker SDK:

1. Creates the `assignment1-network` bridge network.
2. Creates or reuses the `assignment1-mongo-data` volume.
3. Starts the MongoDB container.
4. Builds the Flask image from `app/Dockerfile`.
5. Starts the Flask container on port 5000.
6. Prints the container status and health.

Open the application at <http://localhost:5000>.

## CRUD operations

The web page provides forms for adding, viewing, editing and deleting inventory items. The same operations are available through the API.

| Method | URL | Operation |
|---|---|---|
| `POST` | `/api/items` | Create an item |
| `GET` | `/api/items` | Read all items |
| `GET` | `/api/items/<id>` | Read one item |
| `PUT` | `/api/items/<id>` | Update an item |
| `DELETE` | `/api/items/<id>` | Delete an item |
| `GET` | `/health` | Check Flask and MongoDB |

Example:

```powershell
$body = '{"name":"Keyboard","description":"Lab keyboard","quantity":2}'
Invoke-RestMethod -Method Post -Uri http://localhost:5000/api/items -ContentType application/json -Body $body
```

## Inspecting the containers and network

```powershell
python scripts\docker_manager.py status
python scripts\docker_manager.py inspect
```

The status command lists the Flask and MongoDB containers with their Docker health values. The inspect command prints the bridge driver, subnet and IP address assigned to each container.

## Health monitoring

Run the monitor in a separate terminal:

```powershell
python scripts\health_monitor.py --interval 5
```

The script lists active project containers and checks `assignment1-flask-app`. If the container is stopped or Docker reports it as unhealthy, the script restarts it and writes the event to the terminal and `health-monitor.log`.

To demonstrate the recovery, stop the Flask container from another terminal:

```powershell
docker stop assignment1-flask-app
```

Within the selected interval, the monitor detects the stopped container and starts it again.

## Data persistence demonstration

1. Add an inventory item from the browser.
2. Remove the containers and network without deleting the volume:

```powershell
python scripts\docker_manager.py down
```

3. Recreate the containers:

```powershell
python scripts\docker_manager.py up
```

4. Refresh the browser. The previously added item remains because the MongoDB volume was preserved.

To remove the stored data as well, use:

```powershell
python scripts\docker_manager.py down --remove-volume
```

## Tests

```powershell
pip install -r app\requirements.txt -r tests\requirements.txt
pytest -q
```

Five tests cover the health endpoint, browser favicon request, CRUD API, invalid data and invalid MongoDB identifiers. The completed execution results are recorded in [RESULTS.md](RESULTS.md).

## Problems encountered and fixes

### Flask could not reach MongoDB through localhost

`localhost` inside the Flask container refers to the Flask container itself. The connection string was changed to `mongodb://assignment1-mongodb:27017/assignment1`, where `assignment1-mongodb` is resolved through the custom Docker network.

### Records disappeared after removing the database container

The initial database files existed only inside the MongoDB container. A named volume was mounted at `/data/db`, which keeps the data independent of the container lifecycle.

### Application health remained in the starting state

The Flask health endpoint now sends a ping to MongoDB. Docker uses this endpoint as the container `HEALTHCHECK`, with a startup period to allow the database service to become ready.

### Docker build output failed on some Windows terminals

Some pip progress characters were not supported by the Windows console encoding. The Docker manager replaces unsupported build-output characters before printing them, without changing the build itself.

## Stopping the project

Use the following command to remove the two project containers and their network while retaining MongoDB data:

```powershell
python scripts\docker_manager.py down
```

`compose.yaml` is also included as an alternative way to run the same two services with `docker compose up --build -d`.
