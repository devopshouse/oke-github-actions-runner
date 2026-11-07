# GitHub Actions Runner for Oracle Kubernetes Engine

[![Build and Publish](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/build-and-publish.yml)
[![Validate](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/validate.yml/badge.svg)](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/validate.yml)
[![Check Runner Version](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/check-actions-runner.yml/badge.svg)](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/check-actions-runner.yml)

A custom image based on the official `ghcr.io/actions/actions-runner` image, intended for self-hosted runners on OKE with Actions Runner Controller (ARC). Builds target Linux AMD64 and ARM64.

For the complete setup, see the [configuration and operations guide](docs/guide.md). It covers ARC configuration, container build requirements, OCI and Kubernetes access, registry publication, automation, and troubleshooting.

## Why this project exists

This project provides a ready-to-use GitHub Actions runner image for CI/CD pipelines on **Oracle Cloud Infrastructure (OCI)**, specifically **Oracle Kubernetes Engine (OKE)**. It combines the official GitHub runner with the tools needed to build container images, deploy Kubernetes workloads, and interact with OCI services.

With OCI CLI, kubectl, Helm, Kustomize, and container build tools already installed, pipelines can use a consistent environment instead of installing these dependencies during every job. The image supports both AMD64 and ARM64 nodes and is intended to run in OKE through Actions Runner Controller (ARC).

OCI authentication, Kubernetes access, and runner registration remain part of your deployment configuration; the image supplies the tools without embedding cloud credentials.

## Included tools

| Purpose | Tools |
| --- | --- |
| Containers | Docker CLI, Buildx, Compose plugin, Buildah |
| Kubernetes | kubectl, Helm, standalone Kustomize |
| Oracle Cloud | OCI CLI in `/opt/oci-cli`, installed with uv |
| Development | uv, Python 3, Git, jq, yq, make, GCC, G++ |

The default user is `runner`. Docker CLI requires a reachable Docker daemon, such as ARC's Docker-in-Docker sidecar. Installing the CLI alone does not provide a daemon. Buildah is configured with VFS storage and chroot isolation; it still requires appropriate host and pod permissions.

## Pull the image

```bash
docker pull ghcr.io/devopshouse/oke-github-actions-runner:latest
docker pull ghcr.io/devopshouse/oke-github-actions-runner:2.337.0
```

Both tags select the platform matching the host. Publication also creates `sha-<commit>` tags. Version and `latest` tags can be rebuilt when image tooling changes; use an image digest when an immutable reference is required.

## Use with ARC on OKE

Set the image in your existing ARC runner scale set Helm values:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/devopshouse/oke-github-actions-runner:2.337.0
        command: ["/home/runner/run.sh"]
```

Keep your ARC GitHub authentication, volumes, and Docker-in-Docker configuration. This snippet overrides the image in an existing scale set. ARC manages runner registration; this image supplies the runner binary and tools.

Example job on an already configured runner:

```yaml
jobs:
  deploy:
    runs-on: oci-oke-runner
    steps:
      - uses: actions/checkout@v7
      - name: Render Kubernetes resources
        run: kustomize build k8s/overlays/production > rendered.yaml
      - name: Deploy
        run: kubectl apply -f rendered.yaml
```

Replace `oci-oke-runner` with your runner scale set name. Supply Kubernetes credentials, OCI authentication, and registry credentials as required by your jobs. See the guide for [ARC setup requirements](docs/guide.md#deployment-requirements), [Buildah and Docker builds](docs/guide.md#container-builds), and [OCI and Kubernetes access](docs/guide.md#oci-and-kubernetes-access).

## Registries and automation

GHCR is the default publication destination. Optional OCIR publication uses `OCIR_ENABLED=true` and the `PIPELINE_SECRETS` repository secret. See [registry configuration](docs/guide.md#registries) for the required fields.

Pull requests run workflow linting, native AMD64 and ARM64 builds, and smoke tests. A daily version check opens runner update PRs. Image and build changes on `main` trigger release creation and image publication; shared multi-platform tags are assembled after both architecture tests pass. See [automation](docs/guide.md#automation) for triggers, permissions, and publication behavior.

## Local development

```bash
version=$(awk '$1 == "actions-runner" {print $2}' .tool-versions)
docker build --build-arg RUNNER_VERSION="$version" -t oke-runner:test .
bash scripts/test-image.sh oke-runner:test
actionlint
```

The smoke tests require a Docker daemon and permission to start privileged containers. They check the installed tools, Buildah builds as `runner` and root, and Docker Buildx initialization. See [local development](docs/guide.md#local-development) for version management and test details.

## Documentation

- [Configuration and operations guide](docs/guide.md)
- [Troubleshooting](docs/guide.md#troubleshooting)
- [Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller)
- [GitHub Actions runner](https://github.com/actions/runner)

## Licensing and maintenance

Maintained by `@devopshouse/devops`. Open an issue for questions or bugs. Included third-party tools retain their respective licenses; this repository does not grant a new project license.
