#!/usr/bin/env bash
# Build and push the custom IaC runner image to the Nexus Docker registry.
# Run from a workstation that can reach registry.andusystems.com and has
# docker login credentials for the andusystems-docker repo.
#
#   apps/github-runner/build-and-push.sh           # builds :latest
#   IMAGE_TAG=2025-06-14 apps/github-runner/build-and-push.sh  # pin a tag
set -euo pipefail

REGISTRY="${REGISTRY:-registry.andusystems.com}"
IMAGE="${IMAGE:-andusystems-docker/github-runner-iac}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker build \
  --tag "${REGISTRY}/${IMAGE}:${IMAGE_TAG}" \
  --label "org.opencontainers.image.source=https://github.com/andusystems-dev-0/andusystems-management-iac" \
  --label "org.opencontainers.image.revision=$(git -C "${SCRIPT_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "${SCRIPT_DIR}"

docker push "${REGISTRY}/${IMAGE}:${IMAGE_TAG}"

# Keep :latest in sync when a specific tag was built, so the IaC scale sets
# (which reference :latest) pick up the new image on next runner pod start.
if [[ "${IMAGE_TAG}" != "latest" ]]; then
  docker tag "${REGISTRY}/${IMAGE}:${IMAGE_TAG}" "${REGISTRY}/${IMAGE}:latest"
  docker push "${REGISTRY}/${IMAGE}:latest"
fi
