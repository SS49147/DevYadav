# Exercise 9: Jenkins Multi-Stage Flask Pipeline

Implement [Sunag's Python pipeline exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Exercises/9-Jenkins-Multi-Stage-Pipeline.md): build dependencies, test Flask, copy it to a mock deployment directory, start it and test the application.

The application's `/` response is exactly `Hello, Jenkins Multi-Stage Pipeline!`. Flask remains pinned to the source's 2.1.2 version, with compatible Werkzeug 2.1.2. This is a teaching example using older dependencies and Flask's development server, not a production deployment.

## Run

Use PowerShell 7 from this folder. Push the application and Jenkinsfile first so Jenkins can obtain them through Git SCM.

```powershell
./start.ps1
./run_pipeline.ps1
```

Jenkins is at http://127.0.0.1:18009. Sign in as `admin` using the generated password in the ignored `.secrets/jenkins-admin` file. This exercise has its own controller and home volume, separate from Exercises 7 and 8. The image installs Python and virtual-environment support before startup, then runs Jenkins as its non-root user. No host Docker socket or privileged container is used.

`job.xml` configures `Python-MultiStage-Pipeline` as Pipeline script from SCM, using this repository's `main` branch and `Exercises/Exercise-9/Jenkinsfile`. It keeps the application in `DevOps-Lab` rather than creating another sample repository.

## Pipeline stages

| Stage | Actual operation |
| --- | --- |
| Build | Create `.venv`, install requirements and run `pip check` |
| Test | Run the source's exact home-response test and an unknown-route test |
| Deploy | Copy `app.py` to `$WORKSPACE/python-app-deploy` and compare it with the source |
| Run Application | Start that copied file with `nohup` and record its PID |
| Test Application | Send a real HTTP request to the running server and require HTTP 200 with the exact response |

The last test also verifies that the recorded PID runs the deployed file and that its hash matches the source. Post-build cleanup checks the process command before stopping it, removes its PID file and archives the application log and measured reports. The mock deployed file remains in the Jenkins workspace; the test server does not remain running after the build.

## Corrections to the source example

The source's Build stage only echoes a message although the expected outcome requires dependency installation. This pipeline performs the installation in a virtual environment. Python and venv support are installed reproducibly in the Jenkins image instead of manually changing a running container.

The source's Test Application stage repeats a test-client unit test. Here it checks the actual deployed HTTP server. Debug mode and the reload subprocess are disabled so the recorded PID identifies one server. A lab-specific Jenkins process cookie lets that process survive between stages, and explicit cleanup prevents it from interfering with another build.

The deployment directory follows the source Jenkinsfile's workspace path, not the conflicting `/tmp` path in its expected-output paragraph. This is a mock file-copy deployment, not deployment to an external server. Optional lint, Docker deployment and external notifications are not added.

The runner saves real console output, five-stage results, HTTP proof and cleanup proof under `evidence/`. GitHub Actions repeats the pipeline on a fresh runner. Stop the local controller without deleting its volume using `docker compose down`.
