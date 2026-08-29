# Execution Results

## 1. Automated tests

```text
.....                                                                    [100%]
5 passed
```

## 2. Container status

```text
Active project containers
------------------------------------------------------------------------
assignment1-flask-app        status=running    health=healthy
assignment1-mongodb          status=running    health=healthy
```

## 3. Network inspection

```text
Network : assignment1-network
Driver  : bridge
Subnet  : 172.18.0.0/16

assignment1-mongodb   172.18.0.2
assignment1-flask-app 172.18.0.3
```

Both containers were attached to the same custom network. The Flask application connected to MongoDB using the database container name.

## 4. CRUD result

```text
Create item : HTTP 201
Read item   : HTTP 200
Update item : HTTP 200
Delete item : HTTP 204
Health      : healthy
```

The CRUD operations were checked through the API and through the browser forms.

## 5. Volume result

An item was inserted before removing both containers and the bridge network. The containers were then recreated while keeping `assignment1-mongo-data`. The same item and MongoDB identifier were present after startup, confirming that the volume retained the database.

## 6. Health-monitor result

The Flask container was stopped manually while the monitor was running.

```text
Flask container status=exited health=unhealthy
Flask container is unhealthy; restarting 'assignment1-flask-app'.
ALERT: 'assignment1-flask-app' was restarted. Current health=starting
Flask container status=running health=healthy
```

The monitor restarted the container and the application returned to a healthy state.
