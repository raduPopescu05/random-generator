FROM jenkins/jenkins:lts-jdk21

USER root

# Install pipeline dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        awscli \
        ca-certificates \
        curl \
        git \
        gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Docker from Docker's official Debian repository
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && printf '%s\n' \
        "Types: deb" \
        "URIs: https://download.docker.com/linux/debian" \
        "Suites: trixie" \
        "Components: stable" \
        "Architectures: $(dpkg --print-architecture)" \
        "Signed-By: /etc/apt/keyrings/docker.asc" \
        > /etc/apt/sources.list.d/docker.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    pipeline-model-definition \
    git \
    github-branch-source \
    junit \
    pipeline-stage-view

USER jenkins