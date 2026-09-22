#!/usr/bin/env bash
# Start Homer, RL-Insight, TensorBoard, and Run logs. Exit non-zero if any child dies.
set -euo pipefail

HOMER_DIR="${HOMER_DIR:-/www}"
RL_INSIGHT_DATA="${RL_INSIGHT_DATA:-/data/rl-insight}"
TENSORBOARD_LOGDIR="${TENSORBOARD_LOGDIR:-/logs}"
RUNLOGS_ROOTS="${RUNLOGS_ROOTS:-/logs}"

mkdir -p "${RL_INSIGHT_DATA}" /logs/home /var/log/lab-obs

if [[ ! -f "${HOMER_DIR}/assets/config.yml" ]]; then
    echo "obs: missing Homer config at ${HOMER_DIR}/assets/config.yml" >&2
    exit 1
fi

echo "obs: starting RL-Insight (Grafana 3000, hub 18080)"
rl-insight server start --detach --log-dir "${RL_INSIGHT_DATA}"

echo "obs: starting TensorBoard on :6006 logdir=${TENSORBOARD_LOGDIR}"
tensorboard \
    --logdir "${TENSORBOARD_LOGDIR}" \
    --bind_all \
    --port 6006 \
    --reload_interval 30 \
    --path_prefix / \
    > /var/log/lab-obs/tensorboard.log 2>&1 &
echo $! > /var/log/lab-obs/tensorboard.pid

echo "obs: starting Run logs on :8081 roots=${RUNLOGS_ROOTS}"
python3 /opt/obs/runlogs.py \
    --port 8081 \
    --roots "${RUNLOGS_ROOTS}" \
    > /var/log/lab-obs/runlogs.log 2>&1 &
echo $! > /var/log/lab-obs/runlogs.pid

echo "obs: starting Homer on :8080"
python3 -m http.server 8080 --bind 0.0.0.0 --directory "${HOMER_DIR}" \
    > /var/log/lab-obs/homer.log 2>&1 &
echo $! > /var/log/lab-obs/homer.pid

cleanup() {
    echo "obs: stopping"
    rl-insight server stop >/dev/null 2>&1 || true
    for pidfile in /var/log/lab-obs/*.pid; do
        [[ -f "${pidfile}" ]] || continue
        kill "$(cat "${pidfile}")" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT INT TERM

# Fail the container if a long-running child exits.
while true; do
    for name in tensorboard runlogs homer; do
        pidfile="/var/log/lab-obs/${name}.pid"
        if [[ ! -f "${pidfile}" ]] || ! kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
            echo "obs: ${name} exited" >&2
            exit 1
        fi
    done
    if ! curl -sf http://127.0.0.1:18080/ >/dev/null 2>&1; then
        # Hub can take a bit on first boot; only fail after it has been up once.
        if [[ -n "${HUB_SEEN:-}" ]]; then
            echo "obs: rl-insight hub went away" >&2
            exit 1
        fi
    else
        HUB_SEEN=1
    fi
    sleep 5
done
