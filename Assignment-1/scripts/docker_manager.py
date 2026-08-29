import argparse
import json
import os
import sys
import time

import docker
from docker.errors import APIError, BuildError, DockerException, NotFound


NETWORK_NAME = os.getenv("DOCKER_NETWORK", "assignment1-network")
VOLUME_NAME = os.getenv("MONGO_VOLUME", "assignment1-mongo-data")
MONGO_CONTAINER = os.getenv("MONGO_CONTAINER", "assignment1-mongodb")
APP_CONTAINER = os.getenv("APP_CONTAINER", "assignment1-flask-app")
APP_IMAGE = os.getenv("APP_IMAGE", "assignment1-flask:latest")
MONGO_IMAGE = os.getenv("MONGO_IMAGE", "mongo:7.0")


def client():
    docker_client = docker.from_env()
    docker_client.ping()
    return docker_client


def get_or_create_network(docker_client):
    try:
        network = docker_client.networks.get(NETWORK_NAME)
        print(f"Using existing network: {NETWORK_NAME}")
    except NotFound:
        network = docker_client.networks.create(
            NETWORK_NAME,
            driver="bridge",
            labels={"project": "devops-assignment-1"},
        )
        print(f"Created bridge network: {NETWORK_NAME}")
    return network


def get_or_create_volume(docker_client):
    try:
        volume = docker_client.volumes.get(VOLUME_NAME)
        print(f"Using existing volume: {VOLUME_NAME}")
    except NotFound:
        volume = docker_client.volumes.create(
            VOLUME_NAME, labels={"project": "devops-assignment-1"}
        )
        print(f"Created persistent volume: {VOLUME_NAME}")
    return volume


def remove_named_container(docker_client, name):
    try:
        container = docker_client.containers.get(name)
        print(f"Removing existing container: {name}")
        container.remove(force=True)
    except NotFound:
        pass


def ensure_running(container):
    container.reload()
    if container.status != "running":
        container.start()
        print(f"Started existing container: {container.name}")
    else:
        print(f"Container already running: {container.name}")


def connect_if_needed(network, container):
    network.reload()
    connected_ids = network.attrs.get("Containers", {})
    if container.id not in connected_ids:
        network.connect(container)
        print(f"Connected {container.name} to {network.name}")


def print_build_line(line):
    output_encoding = sys.stdout.encoding or "utf-8"
    safe_line = line.encode(output_encoding, errors="replace").decode(output_encoding)
    print(safe_line)


def start_stack(docker_client, app_directory, rebuild=False):
    network = get_or_create_network(docker_client)
    volume = get_or_create_volume(docker_client)

    try:
        mongo = docker_client.containers.get(MONGO_CONTAINER)
        ensure_running(mongo)
        connect_if_needed(network, mongo)
    except NotFound:
        print(f"Pulling database image if needed: {MONGO_IMAGE}")
        docker_client.images.pull(MONGO_IMAGE)
        mongo = docker_client.containers.run(
            MONGO_IMAGE,
            name=MONGO_CONTAINER,
            detach=True,
            restart_policy={"Name": "unless-stopped"},
            network=NETWORK_NAME,
            volumes={volume.name: {"bind": "/data/db", "mode": "rw"}},
            healthcheck={
                "test": [
                    "CMD",
                    "mongosh",
                    "--quiet",
                    "--eval",
                    "db.adminCommand('ping').ok",
                ],
                "interval": 10_000_000_000,
                "timeout": 5_000_000_000,
                "retries": 5,
                "start_period": 10_000_000_000,
            },
            labels={"project": "devops-assignment-1", "service": "database"},
        )
        print(f"Started database container: {mongo.name}")

    if rebuild:
        remove_named_container(docker_client, APP_CONTAINER)

    try:
        web = docker_client.containers.get(APP_CONTAINER)
        ensure_running(web)
        connect_if_needed(network, web)
    except NotFound:
        print(f"Building Flask image: {APP_IMAGE}")
        image, logs = docker_client.images.build(
            path=app_directory,
            tag=APP_IMAGE,
            rm=True,
            labels={"project": "devops-assignment-1"},
        )
        for entry in logs:
            line = entry.get("stream", "").strip()
            if line:
                print_build_line(line)
        web = docker_client.containers.run(
            image.id,
            name=APP_CONTAINER,
            detach=True,
            restart_policy={"Name": "unless-stopped"},
            network=NETWORK_NAME,
            environment={
                "MONGO_URI": f"mongodb://{MONGO_CONTAINER}:27017/assignment1"
            },
            ports={"5000/tcp": 5000},
            labels={"project": "devops-assignment-1", "service": "web"},
        )
        print(f"Started Flask container: {web.name}")

    print("Waiting briefly for container health checks...")
    time.sleep(3)
    show_status(docker_client)
    print("Application URL: http://localhost:5000")


def show_status(docker_client):
    print("\nActive project containers")
    print("-" * 72)
    containers = docker_client.containers.list(
        all=True, filters={"label": "project=devops-assignment-1"}
    )
    if not containers:
        print("No project containers found.")
        return
    for container in containers:
        container.reload()
        health = container.attrs.get("State", {}).get("Health", {}).get("Status", "n/a")
        print(f"{container.name:<28} status={container.status:<10} health={health}")


def inspect_network(docker_client):
    try:
        network = docker_client.networks.get(NETWORK_NAME)
    except NotFound:
        print(f"Network not found: {NETWORK_NAME}")
        return
    network.reload()
    details = {
        "name": network.name,
        "id": network.id[:12],
        "driver": network.attrs.get("Driver"),
        "scope": network.attrs.get("Scope"),
        "subnets": network.attrs.get("IPAM", {}).get("Config", []),
        "containers": [],
    }
    for container_id, connection in network.attrs.get("Containers", {}).items():
        details["containers"].append(
            {
                "id": container_id[:12],
                "name": connection.get("Name"),
                "ipv4": connection.get("IPv4Address"),
                "mac": connection.get("MacAddress"),
            }
        )
    print(json.dumps(details, indent=2))


def stop_stack(docker_client, remove_volume=False):
    for name in (APP_CONTAINER, MONGO_CONTAINER):
        try:
            container = docker_client.containers.get(name)
            container.remove(force=True)
            print(f"Removed container: {name}")
        except NotFound:
            print(f"Container already absent: {name}")

    try:
        docker_client.networks.get(NETWORK_NAME).remove()
        print(f"Removed network: {NETWORK_NAME}")
    except NotFound:
        print(f"Network already absent: {NETWORK_NAME}")

    if remove_volume:
        try:
            docker_client.volumes.get(VOLUME_NAME).remove()
            print(f"Removed persistent volume: {VOLUME_NAME}")
        except NotFound:
            print(f"Volume already absent: {VOLUME_NAME}")
    else:
        print(f"Preserved persistent volume: {VOLUME_NAME}")


def main():
    parser = argparse.ArgumentParser(
        description="Manage the Assignment 1 containers and custom Docker network."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    up_parser = subparsers.add_parser("up", help="Build and start the complete stack.")
    up_parser.add_argument("--rebuild", action="store_true", help="Rebuild the Flask image.")
    subparsers.add_parser("status", help="List project containers and health state.")
    subparsers.add_parser("inspect", help="Inspect the custom bridge network.")
    down_parser = subparsers.add_parser("down", help="Remove containers and network.")
    down_parser.add_argument(
        "--remove-volume",
        action="store_true",
        help="Also permanently remove the MongoDB data volume.",
    )
    args = parser.parse_args()

    try:
        docker_client = client()
        if args.command == "up":
            app_directory = os.path.abspath(
                os.path.join(os.path.dirname(__file__), "..", "app")
            )
            start_stack(docker_client, app_directory, args.rebuild)
        elif args.command == "status":
            show_status(docker_client)
        elif args.command == "inspect":
            inspect_network(docker_client)
        elif args.command == "down":
            stop_stack(docker_client, args.remove_volume)
    except (DockerException, APIError, BuildError) as exc:
        print(f"Docker operation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
