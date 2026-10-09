# Exercise 5 Results

Run date: 9 October 2026.

## Windows host check

The Flask image built on Docker Desktop and both app unit tests passed. Docker Engine 29.8.2 reported `seccomp` and `cgroupns`, but no AppArmor support. No enforcement result is claimed for this Windows host; its capability check is in [windows-host.json](evidence/windows-host.json).

## Linux enforcement run

The actual AppArmor tests passed on an Ubuntu 24.04 GitHub runner in [run 37970300694](https://github.com/Anas2694/DevOps-Lab/actions/runs/37970300694), using commit `bda57dd`.

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

## Direct Docker exec limitation

The separate direct Docker exec test launched Bash with exit code 0 on this runner. Direct `cat /etc/passwd` failed with exit code 1 and `Permission denied`. These measured results are retained in the report; the source's expected direct Bash exit code 126 is not claimed.

The passing binary-execution checks concern a confined Python process spawning those binaries. The lab does not establish a restriction against an administrator controlling the Docker daemon.

## Evidence

- [Local Flask unit tests](evidence/unit-tests.txt)
- [Windows host capability check](evidence/windows-host.json)
- [SDK application, enforce mode and HTTP response](evidence/profile-application.json)
- [Control, denied operations and direct exec observations](evidence/restricted-actions.json)

The Linux JSON reports were downloaded from the successful workflow artifact. The profile needed a matching name, Python runtime/library allowances, plain `x` in deny rules and a datagram socket allowance for Werkzeug startup. These corrections are described in the README.
