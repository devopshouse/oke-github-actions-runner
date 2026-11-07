# Custom GitHub Actions runner with CI/CD tools
# Based on the official GitHub Actions runner image

ARG RUNNER_VERSION=2.337.0
ARG UV_VERSION=0.13.7
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

# Install packages as root
USER root

ARG TARGETARCH
ARG KUBECTL_VERSION=v1.35.0
ARG HELM_VERSION=v3.17.3
ARG KUSTOMIZE_VERSION=5.6.0
ARG YQ_VERSION=v4.45.1
COPY --from=uv /uv /uvx /usr/local/bin/

# Configure environment
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI, Buildx, and Compose
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Install development and container build tools
RUN apt-get update && apt-get install -y \
    buildah \
    uidmap \
    slirp4netns \
    fuse-overlayfs \
    make \
    git \
    jq \
    unzip \
    gcc \
    g++ \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install yq for the target architecture
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH} && \
    chmod a+x /usr/local/bin/yq

# Install OCI CLI in an isolated environment with uv
RUN uv venv --python /usr/bin/python3 /opt/oci-cli && \
    uv pip install --no-cache --python /opt/oci-cli/bin/python oci-cli && \
    ln -s /opt/oci-cli/bin/oci /usr/local/bin/oci

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm -f kubectl

# Install Helm
RUN cd /tmp && \
    curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz.sha256sum" | sha256sum -c - && \
    tar -xzf "helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    install -m 0755 "linux-${TARGETARCH}/helm" /usr/local/bin/helm

# Install standalone Kustomize
RUN cd /tmp && \
    curl -fsSLo kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf kustomize.tar.gz && install -m 0755 kustomize /usr/local/bin/kustomize

# Configure Buildah for both runner and root; the host must allow user namespaces.
ENV STORAGE_DRIVER=vfs BUILDAH_ISOLATION=chroot
RUN mkdir -p /etc/containers /home/runner/.config/containers && \
    printf '[storage]\ndriver = "vfs"\nrunroot = "/run/containers/storage"\ngraphroot = "/var/lib/containers/storage"\n' > /etc/containers/storage.conf && \
    printf '[registries.search]\nregistries = ["docker.io", "ghcr.io"]\n' > /etc/containers/registries.conf && \
    (grep -q '^runner:' /etc/subuid || echo 'runner:100000:65536' >> /etc/subuid) && \
    (grep -q '^runner:' /etc/subgid || echo 'runner:100000:65536' >> /etc/subgid) && \
    chown -R runner:runner /home/runner/.config

# Remove temporary files
RUN rm -rf /tmp/* /var/tmp/*

# Create runner workspace
RUN mkdir -p /home/runner/work && \
    mkdir -p /home/runner/.docker && \
    echo '{"auths":{}}' > /home/runner/.docker/config.json && \
    chown -R runner:runner /home/runner/work && \
    chown -R runner:runner /home/runner/.docker

# Return to the runner user
USER runner

# Configure PATH
ENV PATH="/home/runner/.local/bin:${PATH}"

# Image metadata
LABEL maintainer="DevOps Team"
LABEL description="GitHub Actions runner with Docker, Buildah, kubectl, Helm, Kustomize, and OCI CLI"
LABEL org.opencontainers.image.source="https://github.com/devopshouse/oke-github-actions-runner"

# Check runner listener health
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -x "Runner.Listener" > /dev/null || exit 1

WORKDIR /home/runner
