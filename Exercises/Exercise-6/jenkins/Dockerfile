FROM docker:29.8.2-cli AS dockercli
FROM jenkins/jenkins:2.580.1-jdk21
USER root
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
USER jenkins
RUN jenkins-plugin-cli --plugins workflow-aggregator pipeline-stage-view git
COPY --chown=jenkins:jenkins init.groovy /usr/share/jenkins/ref/init.groovy.d/lab.groovy
