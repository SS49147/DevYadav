import docker

from lab_support import client_with_apparmor, remove_container, save_report, start_container, wait_for_http

COMMANDS = {
    'read_etc_passwd': ['python', '-c', "print(len(open('/etc/passwd').read()))"],
    'write_var': ['python', '-c', "open('/var/lab-test', 'w').write('lab')"],
    'execute_bash': ['python', '-c', "import subprocess; subprocess.run(['/bin/bash', '-c', 'exit 0'], check=True)"],
    'execute_cat': ['python', '-c', "import subprocess; subprocess.run(['/usr/bin/cat', '/app/app.py'], check=True)"],
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


def require_denial(name, result):
    bash_loader_denied = (
        name in ('direct_bash', 'direct_bash_command') and result['exit_code'] == 127
        and 'libtinfo.so' in result['output'] and 'cannot open shared object file' in result['output']
    )
    assert result.get('api_permission_denied') or (
        result['exit_code'] != 0 and 'permission denied' in result['output'].lower()
    ) or bash_loader_denied, (name, result)


def main():
    client = client_with_apparmor()
    active = None
    try:
        active = start_container(client, 'exercise5-control', confined=False)
        wait_for_http(active)
        control = {name: execute(active, command) for name, command in COMMANDS.items()}
        assert all(result['exit_code'] == 0 for result in control.values()), control
        direct_commands = {
            'bash': ['/bin/bash'],
            'bash_command': ['/bin/bash', '-c', 'exit 0'],
            'cat_passwd': ['/usr/bin/cat', '/etc/passwd'],
        }
        direct_control = {name: execute(active, command) for name, command in direct_commands.items()}
        assert all(result['exit_code'] == 0 for result in direct_control.values()), direct_control
        remove_container(active)
        active = None

        active = start_container(client, 'exercise5-restricted')
        http = wait_for_http(active)
        direct_exec = {name: execute(active, command) for name, command in direct_commands.items()}
        for name, result in direct_exec.items():
            require_denial('direct_' + name, result)
        current = execute(active, ['python', '-c', "print(open('/proc/self/attr/current').read().strip())"])
        assert current['exit_code'] == 0 and 'my-apparmor-profile (enforce)' in current['output']
        restricted = {name: execute(active, command) for name, command in COMMANDS.items()}
        for name, result in restricted.items():
            require_denial(name, result)
        allowed = execute(active, ['python', '-c', "open('/app/allowed-test', 'w').write('lab'); print('allowed')"])
        assert allowed['exit_code'] == 0 and allowed['output'].strip() == 'allowed'
        remove_container(active)
        active = None
        save_report('restricted-actions.json', {'control': control, 'direct_control': direct_control, 'restricted': restricted,
                    'direct_docker_exec': direct_exec, 'process_profile': current['output'].strip(),
                    'allowed_app_write': allowed, 'http': http, 'containers_removed': True})
    finally:
        if active is not None:
            remove_container(active)
        client.close()


if __name__ == '__main__':
    main()
