# Exercise 5 Results

Reverified: 20 October 2026 (Asia/Kolkata).

## Windows host check

The Flask image built on Docker Desktop and both app unit tests passed. Docker Engine 29.8.2 reported `seccomp` and `cgroupns`, but no AppArmor support. No enforcement result is claimed for this Windows host; its capability check is in [windows-host.json](evidence/windows-host.json).

## Linux enforcement run

The AppArmor tests and kernel-denial check passed on an Ubuntu 24.04 GitHub runner in [run 39306337127](https://github.com/Anas2694/DevOps-Lab/actions/runs/39306337127), using commit `125c4d4`.

The profile loaded as `my-apparmor-profile (enforce)`. The Docker SDK built and started the image with the named profile. Docker inspection and `/proc/self/attr/current` confirmed the applied profile, and Flask returned HTTP 200 with the required message.

All four operations succeeded in the unconfined control. From the confined Python process:

| Operation | Exit code | Observed result |
| --- | ---: | --- |
| Read `/etc/passwd` | 1 | Permission denied |
| Write `/var/lab-test` | 1 | Permission denied |
| Spawn `/bin/bash` | 1 | Permission denied |
| Spawn `/usr/bin/cat` | 1 | Permission denied |
| Write `/app/allowed-test` | 0 | Allowed |

The test containers were stopped and removed, and the workflow unloaded the lab profile.

## Direct Docker exec checks

| Command | Unconfined | With profile | Observed result |
| --- | ---: | ---: | --- |
| `/bin/bash` | 0 | 127 | Shell startup blocked |
| `/bin/bash -c 'exit 0'` | 0 | 127 | Shell startup blocked |
| `/usr/bin/cat /etc/passwd` | 0 | 1 | Permission denied |

Bash's loader reports that `libtinfo.so.6` cannot be opened. The [kernel log](evidence/apparmor-denials.log) proves that the library access was denied by `my-apparmor-profile`; the same Bash commands work in the control image. The profile now explicitly denies that library, preventing direct shell startup as well as the separately tested Python child-process execution. The source's example exit code 126 is not substituted for the measured 127.

The [original 9 October measurement](evidence/restricted-actions-2026-10-09.json) is preserved: direct Bash returned 0 before the library restriction. The tests now fail if those direct attempts succeed. A Docker administrator can still choose an unconfined container; this is application confinement, not a restriction on daemon administrators.

## Evidence

- [Local Flask unit tests](evidence/unit-tests.txt)
- [Windows host capability check](evidence/windows-host.json)
- [SDK application, enforce mode and HTTP response](evidence/profile-application.json)
- [Control, denied operations and direct exec observations](evidence/restricted-actions.json)
- [Kernel proof of denied Bash library access](evidence/apparmor-denials.log)

The Linux JSON reports were downloaded from the successful workflow artifact. The profile needed a matching name, Python runtime/library allowances, plain `x` in deny rules and a datagram socket allowance for Werkzeug startup. These corrections are described in the README.
