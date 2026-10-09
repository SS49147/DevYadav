import docker

from lab_support import client_with_apparmor, remove_container, save_report, start_container, wait_for_http

COMMANDS = {
    'read_etc_passwd': ['python', '-c', "print(len(open('/etc/passwd').read()))"],
    'write_var': ['python', '-c', "open('/var/lab-test', 'w').write('lab')"],
    'execute_bash': ['/bin/bash', '-c', 'exit 0'],
    'execute_cat': ['/usr/bin/cat', '/app/app.py'],
}


def execute(container, command):
    try:
        result = container.exec_run(command)
        return {'exit_code': result.exit_code, 'output': result.output.decode(errors='replace')}
    except docker.errors.APIError as error:
        detail = str(error)
        if 'permission denied' not in detail.lower():
            raise
        return {'exit_code': None, 'api_permission_denied': True, 'output': detail}


def main():
    client = client_with_apparmor()
    active = None
    try:
        active = start_container(client, 'exercise5-control', confined=False)
        wait_for_http(active)
        control = {name: execute(active, command) for name, command in COMMANDS.items()}
        assert all(result['exit_code'] == 0 for result in control.values()), control
        remove_container(active)
        active = None

        active = start_container(client, 'exercise5-restricted')
        http = wait_for_http(active)
        restricted = {name: execute(active, command) for name, command in COMMANDS.items()}
        for name, result in restricted.items():
            assert result.get('api_permission_denied') or (
                result['exit_code'] != 0 and 'permission denied' in result['output'].lower()
            ), (name, result)
        allowed = execute(active, ['python', '-c', "open('/app/allowed-test', 'w').write('lab'); print('allowed')"])
        assert allowed['exit_code'] == 0 and allowed['output'].strip() == 'allowed'
        remove_container(active)
        active = None
        save_report('restricted-actions.json', {'control': control, 'restricted': restricted,
                    'allowed_app_write': allowed, 'http': http, 'containers_removed': True})
    finally:
        if active is not None:
            remove_container(active)
        client.close()


if __name__ == '__main__':
    main()
