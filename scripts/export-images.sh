#!/usr/bin/env bash
# docker save the two lab images for other rootless users to docker load.
set -euo pipefail

OUT="${1:?usage: scripts/export-images.sh /shared/lab-rl-images.tar.gz}"

if [[ -z "${DOCKER_HOST:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/docker.sock" ]]; then
    export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
fi

mkdir -p "$(dirname "${OUT}")"
echo "saving lab-train:latest lab-obs:latest → ${OUT}"
docker save lab-train:latest lab-obs:latest | gzip > "${OUT}"
ls -lh "${OUT}"
echo "others: docker load -i ${OUT}"
