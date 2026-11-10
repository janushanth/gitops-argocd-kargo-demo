# Local demo image. install/install.ps1 builds this on the laptop.
# Plugins are copied in from jenkins/plugins. Downloading them here fails
# the company TLS inspection (PKIX).
FROM jenkins/jenkins:2.541.3-lts-jdk17

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY plugins/ /usr/share/jenkins/ref/plugins/
RUN chown -R jenkins:jenkins /usr/share/jenkins/ref/plugins

USER jenkins
