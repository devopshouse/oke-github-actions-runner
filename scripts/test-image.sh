#!/usr/bin/env bash
set -euo pipefail
image=${1:?Usage: test-image.sh IMAGE}
docker run --rm --entrypoint bash "$image" -ec '
  test "$(id -un)" = runner
  docker --version
  docker buildx version
  docker compose version
  buildah --version
  kubectl version --client
  helm version --short
  kustomize version
  uv --version
  oci --version
  git --version
  jq --version
  yq --version
  python3 --version
  make --version
'
for user in runner root; do
  docker run --rm --privileged --user "$user" --entrypoint bash "$image" -ec '
    cd /tmp
    printf "FROM docker.io/library/alpine:3.21\nRUN echo buildah-ok > /result\n" > Containerfile
    buildah bud -t smoke:local .
    buildah inspect smoke:local >/dev/null
  '
done
# Existing pipelines need an available Docker daemon for the docker-container driver.
docker run --rm --user root -v /var/run/docker.sock:/var/run/docker.sock --entrypoint bash "$image" -ec '
  name="runner-smoke-$$"
  trap '\''docker buildx rm "$name"'\'' EXIT
  docker buildx create --name "$name" --driver docker-container --use
  docker buildx inspect --bootstrap
'
