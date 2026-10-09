# Exercise 7: CI and Jenkins Installation

Follow [Sunag's Jenkins installation exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/7-Jenkins-CI-Automation.md): run the official Jenkins LTS image, unlock the new instance and complete its setup.

## CI concepts

Continuous integration checks changes after they enter a shared repository. A typical cycle is a code push, build, automated tests and a result developers can inspect. Smaller, frequent changes make failures easier to locate. CI verifies changes; continuous delivery adds the steps needed to prepare a release.

In Jenkins, a job defines work, a build is one execution of that job, and a pipeline describes multiple stages. Plugins add functions such as Git checkout and Pipeline support. The controller coordinates jobs; agents provide machines on which builds can run. This small lab uses the built-in node, not a distributed production installation.

## Start and complete setup

Run these commands once for a new installation, using PowerShell 7 from this folder:

```powershell
./start.ps1
./setup.ps1
./verify.ps1
```

`start.ps1` runs `jenkins/jenkins:lts`, waits for the login/unlock page and privately saves the password from `/var/jenkins_home/secrets/initialAdminPassword`. Open http://127.0.0.1:18007 to inspect the UI. To complete setup manually instead of running `setup.ps1`, use that initial password, select plugins, create an administrator and finish the instance configuration. The script and manual route should not be mixed on the same first-run setup.

`setup.ps1` performs the setup wizard's authenticated requests. It installs Git, Pipeline and Pipeline Stage View with their dependencies, creates username `admin` with a generated password, sets the local Jenkins URL and completes installation. The account uses the explicit lab placeholder email `admin@localhost.invalid`; no email integration is configured.

The administrator password and browser session are stored in ignored `.secrets/` files. Do not upload them or include passwords in screenshots. Sign in with username `admin` and the password in `.secrets/admin-password`. Setup is a one-time operation. On subsequent starts, use `start.ps1` and `verify.ps1` without repeating `setup.ps1`.

The source's container ports remain 8080 and 50000. Loopback host ports 18007 and 15007 avoid the earlier labs. Port 50000 is reserved for the source's inbound-agent mapping; this exercise does not connect an agent. The `exercise7_jenkins-home` volume preserves Jenkins configuration and jobs. This instance has no host Docker socket and does not use privileged mode.

## Verify persistence

```powershell
docker compose restart jenkins
./verify.ps1 -Phase restarted
```

The script checks administrator authentication, NORMAL mode, completed setup, active Git/Pipeline plugins and denied anonymous API access. Reports are saved under `evidence/`. The GitHub workflow repeats installation and the restart check on a fresh runner.

Stop this lab while retaining its data:

```powershell
docker compose down
```

Measured results and UI screenshots are in [RESULTS.md](RESULTS.md). The setup sequence follows Jenkins's [Docker and setup-wizard documentation](https://www.jenkins.io/doc/book/installing/docker/#post-installation-setup-wizard).
