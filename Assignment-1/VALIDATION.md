# Validation Record

The project was validated on Docker Desktop 4.68.0 with Docker Engine 29.3.1.

## Automated tests

```text
.....                                                                    [100%]
5 passed
```

The tests cover the health endpoint, favicon response, full API CRUD flow, input validation, and invalid or unknown identifiers.

## Container health

```text
assignment1-flask-app        status=running    health=healthy
assignment1-mongodb          status=running    health=healthy
```

## Custom network

The Docker SDK manager created `assignment1-network` with the bridge driver. Network inspection confirmed that both containers received addresses on the same `172.18.0.0/16` subnet and could communicate by container name.

## CRUD verification

The live API completed every required operation successfully:

```text
Create:  HTTP 201
Read:    HTTP 200
Update:  HTTP 200
Delete:  HTTP 204
Health:  healthy
```

The browser form was also used to create and delete an inventory item. The page produced no browser-console errors or warnings.

## Persistence verification

An inventory record was created before removing both containers and the custom network. The named volume `assignment1-mongo-data` was preserved. After recreating the complete stack, the same record and MongoDB identifier were retrieved successfully.

## Automatic recovery verification

The health monitor was run at a three-second interval. The Flask container was deliberately stopped. The monitor detected `status=exited` and `health=unhealthy`, restarted the container, emitted an alert, and subsequently observed `health=healthy`.

```text
Flask container is unhealthy; restarting 'assignment1-flask-app'.
ALERT: 'assignment1-flask-app' was restarted. Current health=starting
Flask container is healthy; no action required.
```
