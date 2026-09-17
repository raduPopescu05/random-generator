FROM jenkins/jenkins:lts-jdk21

USER root

# Install the tools used by this repository's Jenkins pipeline.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        awscli \
        ca-certificates \
        curl \
        docker.io \
        git \
        gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install the Jenkins plugins required for this pipeline and its UI.
RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    pipeline-model-definition \
    git \
    github-branch-source \
    junit \
    pipeline-stage-view

USER jenkins
