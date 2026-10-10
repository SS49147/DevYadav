# Exercise 9 results

Verified on 10 October 2026 with Jenkins 2.580.1 and Python 3.13.5 in the dedicated Exercise 9 controller.

Build 1 obtained `Exercises/Exercise-9/Jenkinsfile` through Git SCM from commit `8e3907911337458ae44914bd7e5ae91831f422f6`. All five required stages finished with SUCCESS. The Build stage installed Flask 2.1.2 and Werkzeug 2.1.2 in a virtual environment, and `pip check` found no broken requirements. Both unit tests passed.

The copied application's source hash matched the original. The recorded PID was 1148 and its command line identified the deployed file. A real request inside the controller returned HTTP 200 with:

```text
Hello, Jenkins Multi-Stage Pipeline!
```

Cleanup stopped that process and removed its PID file. Five evidence checks passed, including the actual stage statuses, live HTTP response, deployment hash, process identity and cleanup. The server was tested on the controller's loopback interface; the localhost URL in its report is not a host-published application endpoint.

- [Actual Jenkins console](evidence/console.txt)
- [Measured verification and stage statuses](evidence/verification.json)
- [Live HTTP proof](evidence/http-response.json)
- [Process cleanup proof](evidence/server-cleanup.json)
- [Successful pipeline stages](evidence/pipeline-stages.png)

The job is at http://127.0.0.1:18009/job/Python-MultiStage-Pipeline/. This is the source's mock file-copy deployment, not deployment to an external server.
