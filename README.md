# GitHub Actions Runner for Oracle Kubernetes Engine

[![Build and Publish](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/build-and-publish.yml)
[![Validate](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/validate.yml/badge.svg)](https://github.com/devopshouse/oke-github-actions-runner/actions/workflows/validate.yml)

A custom image based on the official `ghcr.io/actions/actions-runner` image, intended for self-hosted runners on OKE with Actions Runner Controller (ARC). Builds target Linux AMD64 and ARM64.

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

This is an image override, not a complete ARC installation. Keep your existing GitHub configuration, authentication, volumes, and Docker-in-Docker setup. The runner binary is supplied by the upstream image; this repository does not add a token registration entrypoint.

For Buildah, the node must allow user namespaces and the pod must allow the namespace operations it uses. The image includes `uidmap`, subordinate UID/GID ranges for `runner`, and a VFS default. Rootless execution is not guaranteed under restrictive seccomp, AppArmor, or `allowPrivilegeEscalation: false` policies. A privileged pod can retain the default `runner` user; root execution is also tested. Configure privileges according to your cluster policy, and validate on your actual OKE nodes.

The validation script checks Buildah builds as both `runner` and root in privileged containers. It does not establish that every unprivileged Kubernetes configuration will work.

Example steps on an already configured runner:

```yaml
jobs:
  build:
    runs-on: oci-oke-runner
    steps:
      - uses: actions/checkout@v7
      - name: Build with Buildah
        run: buildah bud -t example:local .
      - name: Render Kubernetes resources
        run: kustomize build k8s/overlays/production > rendered.yaml
      - name: Deploy
        run: kubectl apply -f rendered.yaml
```

Registry authentication and Kubernetes credentials must be supplied separately. Docker Buildx with the `docker-container` driver remains available for existing pipelines when a Docker daemon is configured.

## Registries

GHCR is the default destination, authenticated with the workflow's `GITHUB_TOKEN` and `packages: write`. The repository and its GHCR package must both be public for anonymous pulls; verify package visibility after the first publication.

OCIR is optional. Set repository variable `OCIR_ENABLED` to `true` and repository secret `PIPELINE_SECRETS` to:

```json
{
  "OCIR_URL": "<region>.ocir.io",
  "OCIR_NAMESPACE": "<tenancy-namespace>",
  "OCIR_USERNAME": "<tenancy-namespace>/<username>",
  "OCIR_PASSWORD": "<auth-token>"
}
```

The local `setup-registry` action reads only these fields, masks credentials, and rejects missing values. OCIR publishes to `<OCIR_URL>/<OCIR_NAMESPACE>/oke-github-actions-runner` with the same tags as GHCR. No OCIR secrets are required when the variable is unset.

## Automation

- **Validate:** PR builds and smoke tests on native AMD64 and ARM64 runners, without publishing images or reading OCIR secrets.
- **Check GitHub Actions Runner Version:** daily at 04:00 UTC, or manually. Reads the latest upstream release and opens an update PR when needed. Existing PRs for that version are not duplicated.
- **Create Tag and Release:** image/build changes merged into `main` create a missing `v<runner-version>` release. Existing releases are preserved. Release titles start with the version, and the notes include image usage details plus the full release notes fetched from the matching `actions/runner` release.
- **Build and Publish Docker Image:** follows a successful release workflow and checks out its exact source SHA. Builds and tests each architecture, then assembles multi-platform manifests. Manual execution is restricted to `main`.
- **Dependabot:** weekly updates for SHA-pinned GitHub Actions. The runner version is managed separately in `.tool-versions`; other tool versions are Dockerfile build arguments maintained manually.

Allow GitHub Actions to create pull requests in repository settings. Default token permissions remain read-only, with additional permissions granted per job. PRs opened by automation may require approval before CI runs, depending on GitHub policy. CODEOWNERS assigns ownership to `@devopshouse/devops`.

## Local development

```bash
version=$(awk '$1 == "actions-runner" {print $2}' .tool-versions)
docker build --build-arg RUNNER_VERSION="$version" -t oke-runner:test .
bash scripts/test-image.sh oke-runner:test
actionlint
```

The smoke script requires a local Docker daemon and permission to start privileged containers. It checks tool versions, Buildah builds with a `RUN` instruction as both users, and Docker Buildx initialization through the host Docker socket. Run only against a trusted image. CI repeats the checks natively on both architectures.

Edit `.tool-versions` to change the runner version. Keep its format `actions-runner X.Y.Z`. Edit the Dockerfile to change tools; merging image changes rebuilds the image even when the runner version is unchanged.

## Troubleshooting

- **Buildah namespace errors:** check the node's user namespace support and pod security profile. VFS does not bypass kernel permission checks.
- **Docker cannot connect:** verify the daemon or Docker-in-Docker sidecar and socket permissions.
- **Image pull denied:** check GHCR package visibility and registry credentials.
- **No update PR:** check Actions PR permissions, upstream API errors, and existing PRs for that version.
- **Missing image tag:** inspect both architecture jobs and the manifest job; a GitHub release can exist before image publication finishes.

## References

- [Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller)
- [GitHub Actions runner](https://github.com/actions/runner)
- [Buildah](https://github.com/containers/buildah)
- [uv Docker integration](https://docs.astral.sh/uv/guides/integration/docker/)
- [Oracle Kubernetes Engine](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)

## Licensing and maintenance

Maintained by `@devopshouse/devops`. Open an issue for questions or bugs. Included third-party tools retain their respective licenses; this repository does not grant a new project license.
