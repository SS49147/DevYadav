import datetime
import json
import pathlib
import time
import urllib.request

import docker

ROOT = pathlib.Path(__file__).resolve().parent
PROFILE = 'my-apparmor-profile'
IMAGE = 'flask-apparmor:latest'
MESSAGE = 'Hello, this is a secure Flask application running inside a Docker container!'


def client_with_apparmor():
    client = docker.from_env()
    info = client.info()
    if not any(option.startswith('name=apparmor') for option in info.get('SecurityOptions', [])):
        client.close()
        raise RuntimeError('Docker does not report AppArmor support. Use an AppArmor-enabled Linux Docker host.')
    return client


def save_report(name, report):
    destination = ROOT / 'evidence'
    destination.mkdir(exist_ok=True)
    report['checked_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (destination / name).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


def start_container(client, name, confined=True):
    return client.containers.run(
        IMAGE,
        name=name,
        labels={'devops.lab.exercise': '5'},
        ports={'5000/tcp': ('127.0.0.1', 15005)},
        security_opt=['apparmor=' + (PROFILE if confined else 'unconfined')],
        detach=True,
    )


def wait_for_http(container):
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        container.reload()
        if container.status != 'running':
            raise RuntimeError('Flask container stopped: ' + container.logs(tail=20).decode())
        try:
            with urllib.request.urlopen('http://127.0.0.1:15005/', timeout=3) as response:
                body = response.read().decode()
                assert response.status == 200 and body == MESSAGE
                return {'url': response.url, 'status': response.status, 'body': body}
        except OSError:
            time.sleep(1)
    raise RuntimeError('Flask did not respond before the timeout.')


def remove_container(container):
    container.reload()
    if container.attrs['Config'].get('Labels', {}).get('devops.lab.exercise') != '5':
        raise RuntimeError('Refusing to remove a container not owned by this lab.')
    container.stop(timeout=10)
    container.remove()
