# Exercise 7 results

Installed and verified on 10 October 2026 (India time). Report timestamps are UTC.

The official `jenkins/jenkins:lts` image ran Jenkins 2.580.1. The initial password existed at the source's `/var/jenkins_home/secrets/initialAdminPassword` path, and the real unlock page was visible. The password was saved privately, not included in the report or screenshot.

Setup installed Git 5.10.1, Pipeline `608.v67378e9d3db_1` and Pipeline Stage View 2.41 with their dependencies. A generated-password administrator account replaced the temporary first-run credentials, and the authenticated dashboard returned HTTP 200.

Five checks passed after setup and again after restarting the container: administrator authentication, NORMAL mode, completed setup/dashboard availability, active required plugins and HTTP 403 for anonymous API access. The persistent home volume is `exercise7_jenkins-home`.

## Evidence

- [Initial installation report](evidence/installation.json)
- [Installed verification](evidence/verification-installed.json)
- [Post-restart verification](evidence/verification-restarted.json)
- [Unlock screen](evidence/jenkins-unlock.png)
- [Authenticated dashboard](evidence/jenkins-dashboard.png)

Jenkins is reachable locally at http://127.0.0.1:18007. No application build or automatic webhook trigger is claimed by this installation-only exercise.
