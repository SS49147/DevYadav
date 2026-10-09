import json
import socket
import subprocess
import time


def wait_for_server(host, port):
    deadline = time.monotonic() + 180
    while True:
        try:
            with socket.create_connection((host, port), timeout=5) as connection:
                if host == 'redis':
                    connection.sendall(b'*1\r\n$4\r\nPING\r\n')
                    assert connection.recv(128) == b'+PONG\r\n'
                    return {'port': port, 'response': 'PONG'}
                header = connection.recv(4)
                assert len(header) == 4
                payload = connection.recv(1)
                assert payload == b'\x0a', 'Unexpected MySQL handshake protocol'
                return {'port': port, 'protocol': 10}
        except (OSError, AssertionError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(2)


report = {}
for hostname, port in [('mysql', 3306), ('redis', 6379)]:
    address = socket.gethostbyname(hostname)
    result = subprocess.run(['ping', '-c', '3', hostname], check=True, capture_output=True, text=True)
    report[hostname] = {
        'dns_address': address,
        'ping_output': result.stdout,
        'tcp': wait_for_server(hostname, port),
    }
print(json.dumps(report))
