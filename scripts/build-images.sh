#!/usr/bin/env bash
# One-person image build. Not part of daily lab.sh.
# Requires a working rootless (or any) Docker that can pull CUDA / PyPI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ -z "${DOCKER_HOST:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/docker.sock" ]]; then
    export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
fi

echo "building lab-train:latest (this is large and slow)"
docker build -f Dockerfile.train -t lab-train:latest "${ROOT}"

echo "building lab-obs:latest"
docker build -f Dockerfile.obs -t lab-obs:latest "${ROOT}"

docker image ls lab-train:latest lab-obs:latest
echo "next: bash scripts/export-images.sh /path/to/shared/lab-rl-images.tar.gz"
