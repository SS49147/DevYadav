import argparse
import logging
import os
import time

import docker
from docker.errors import DockerException, NotFound


APP_CONTAINER = os.getenv("APP_CONTAINER", "assignment1-flask-app")
PROJECT_LABEL = "project=devops-assignment-1"


def configure_logging():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=[logging.StreamHandler(), logging.FileHandler("health-monitor.log")],
    )


def list_active_containers(client):
    containers = client.containers.list(filters={"label": PROJECT_LABEL})
    if containers:
        summary = ", ".join(f"{item.name} ({item.status})" for item in containers)
    else:
        summary = "none"
    logging.info("Active project containers: %s", summary)


def check_and_recover(client):
    list_active_containers(client)
    try:
        container = client.containers.get(APP_CONTAINER)
    except NotFound:
        logging.error("Flask container '%s' was not found.", APP_CONTAINER)
        return False

    container.reload()
    state = container.attrs.get("State", {})
    status = state.get("Status", "unknown")
    health = state.get("Health", {}).get("Status", "unavailable")
    logging.info("Flask container status=%s health=%s", status, health)

    unhealthy = status != "running" or health == "unhealthy"
    if unhealthy:
        logging.warning(
            "Flask container is unhealthy; restarting '%s'.", APP_CONTAINER
        )
        container.restart(timeout=10)
        container.reload()
        new_health = container.attrs.get("State", {}).get("Health", {}).get(
            "Status", "starting"
        )
        logging.warning(
            "ALERT: '%s' was restarted. Current health=%s",
            APP_CONTAINER,
            new_health,
        )
        return False

    if health == "starting":
        logging.info("Health check is still in its startup period.")
    elif health == "unavailable":
        logging.warning("No Docker HEALTHCHECK is available for the Flask container.")
    else:
        logging.info("Flask container is healthy; no action required.")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Monitor the Flask container and restart it when unhealthy."
    )
    parser.add_argument(
        "--interval", type=int, default=15, help="Seconds between checks (default: 15)."
    )
    parser.add_argument(
        "--once", action="store_true", help="Perform one health check and exit."
    )
    args = parser.parse_args()
    configure_logging()

    try:
        client = docker.from_env()
        client.ping()
        while True:
            check_and_recover(client)
            if args.once:
                break
            time.sleep(max(args.interval, 1))
    except KeyboardInterrupt:
        logging.info("Health monitor stopped.")
    except DockerException as exc:
        logging.error("Cannot communicate with Docker: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
