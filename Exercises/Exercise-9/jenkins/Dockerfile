FROM jenkins/jenkins:2.580.1-jdk21
USER root
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
USER jenkins
RUN jenkins-plugin-cli --plugins workflow-aggregator pipeline-stage-view git
COPY --chown=jenkins:jenkins init.groovy /usr/share/jenkins/ref/init.groovy.d/lab.groovy
