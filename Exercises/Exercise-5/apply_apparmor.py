from lab_support import (
    IMAGE, PROFILE, ROOT, client_with_apparmor, remove_container, save_report,
    start_container, wait_for_http,
)


def main():
    client = client_with_apparmor()
    container = None
    try:
        image, _ = client.images.build(path=str(ROOT), tag=IMAGE, rm=True)
        container = start_container(client, 'exercise5-apply')
        http = wait_for_http(container)
        container.reload()
        options = container.attrs['HostConfig']['SecurityOpt']
        actual = container.attrs['AppArmorProfile']
        assert 'apparmor=' + PROFILE in options and actual == PROFILE
        current = container.exec_run(['python', '-c', "print(open('/proc/self/attr/current').read().strip())"])
        assert current.exit_code == 0 and (PROFILE + ' (enforce)') in current.output.decode()
        report = {'image_id': image.id, 'security_options': options, 'apparmor_profile': actual,
                  'process_profile': current.output.decode().strip(), 'http': http}
        remove_container(container)
        container = None
        report['container_removed'] = True
        save_report('profile-application.json', report)
    finally:
        if container is not None:
            remove_container(container)
        client.close()


if __name__ == '__main__':
    main()
