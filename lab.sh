#!/usr/bin/env bash
# Host-side orchestrator for lab-rl. Do not run this inside the container.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${LAB_ROOT}/compose.yml"
PORT_LOCK="${LAB_PORT_LOCK:-/tmp/lab-rl-ports.lock}"
PORT_BASE="${LAB_PORT_BASE:-18000}"
PORT_CEILING="${LAB_PORT_CEILING:-18990}"

CMD="${1:-}"
shift || true

NAME="box"
WHO_FLAG=""
LAB_HOST="${LAB_HOST:-}"
DETACH=0
TRAIN_ARGS=()

usage() {
    cat <<'EOF'
lab.sh — lab-rl host helper (rootless Docker only)

  ./lab.sh doctor
  ./lab.sh up [--name box] [--who lxhu] [--host 10.x.x.x]
  ./lab.sh exec [--name box]
  ./lab.sh train [--name box] -- <command...>
  ./lab.sh stop-train [--name box]
  ./lab.sh url [--name box]
  ./lab.sh list
  ./lab.sh down [--name box]

Identity
  personal account : WHO=$USER, PERSON_HOME=$HOME
  *_team account   : /home/jpzhao_team/lxhu/... → WHO=lxhu, PERSON_HOME=$HOME/lxhu
                     or pass --who

Training
  CUDA_VISIBLE_DEVICES must be set. The container sees every GPU; you pick at train time.

  CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name box -- bash scripts/run_sft.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            NAME="${2:?--name needs a value}"
            shift 2
            ;;
        --who)
            WHO_FLAG="${2:?--who needs a value}"
            shift 2
            ;;
        --host)
            LAB_HOST="${2:?--host needs a value}"
            shift 2
            ;;
        -d|--detach)
            DETACH=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            TRAIN_ARGS+=("$@")
            break
            ;;
        *)
            TRAIN_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ! "${NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "lab.sh: invalid --name '${NAME}' (use letters, digits, . _ -)" >&2
    exit 1
fi

die() {
    echo "lab.sh: $*" >&2
    exit 1
}

unix_user() {
    echo "${USER:-$(id -un)}"
}

detect_identity() {
    UNIX_USER="$(unix_user)"
    if [[ -n "${WHO_FLAG}" ]]; then
        WHO="${WHO_FLAG}"
    elif [[ "${UNIX_USER}" == *_team ]]; then
        local rest first
        if [[ "${PWD}" == "${HOME}/"* ]]; then
            rest="${PWD#"${HOME}/"}"
            first="${rest%%/*}"
            if [[ -n "${first}" && "${first}" != "${rest}" ]]; then
                WHO="${first}"
            fi
        fi
        if [[ -z "${WHO:-}" ]]; then
            die "shared account ${UNIX_USER}: pass --who <id> (example: --who lxhu)"
        fi
    else
        WHO="${UNIX_USER}"
    fi

    if [[ "${UNIX_USER}" == *_team ]]; then
        PERSON_HOME="${HOME}/${WHO}"
        COMPOSE_PROJECT_NAME="${UNIX_USER}-${WHO}-${NAME}"
    else
        PERSON_HOME="${HOME}"
        COMPOSE_PROJECT_NAME="${UNIX_USER}-${NAME}"
    fi

    [[ -d "${PERSON_HOME}" ]] || die "PERSON_HOME does not exist: ${PERSON_HOME}"
    LAB_USER="${UNIX_USER}"
    LAB_WHO="${WHO}"
    LAB_NAME="${NAME}"
    STATE_DIR="${PERSON_HOME}/.lab/${NAME}"
    ENV_FILE="${STATE_DIR}/lab.env"
}

setup_docker() {
    if [[ -n "${DOCKER_HOST:-}" ]]; then
        :
    elif [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/docker.sock" ]]; then
        export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
    else
        echo "lab.sh: rootless docker socket not found (looked at \$DOCKER_HOST and \$XDG_RUNTIME_DIR/docker.sock). Do not use /var/run/docker.sock. Wait for user docker.service + linger." >&2
        return 1
    fi

    case "${DOCKER_HOST}" in
        unix:///var/run/docker.sock|unix:///run/docker.sock|/var/run/docker.sock)
            echo "lab.sh: refusing rootful docker socket: ${DOCKER_HOST}" >&2
            return 1
            ;;
    esac

    if ! docker info >/dev/null 2>&1; then
        echo "lab.sh: docker info failed via ${DOCKER_HOST}. Is the user dockerd running?" >&2
        return 1
    fi
    return 0
}

require_docker() {
    setup_docker || exit 1
}

default_hf_home() {
    if [[ -d "${HOME}/.cache/huggingface" ]]; then
        echo "${HOME}/.cache/huggingface"
    else
        echo "${PERSON_HOME}/.cache/huggingface"
    fi
}

default_host() {
    if [[ -n "${LAB_HOST}" ]]; then
        echo "${LAB_HOST}"
        return
    fi
    if command -v hostname >/dev/null 2>&1; then
        local ip
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
        if [[ -n "${ip}" ]]; then
            echo "${ip}"
            return
        fi
        hostname -f 2>/dev/null && return
    fi
    echo "127.0.0.1"
}

port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq ":${port}$" && return 0
    fi
    if command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    fi
    # Last resort: try binding.
    python3 - "${port}" <<'PY' 2>/dev/null
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("", int(sys.argv[1])))
except OSError:
    sys.exit(0)
sys.exit(1)
PY
}

allocate_ports() {
    mkdir -p "$(dirname "${PORT_LOCK}")"
    exec 9>"${PORT_LOCK}"
    flock 9

    if [[ -f "${ENV_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${ENV_FILE}"
        if [[ -n "${HOST_HOMER:-}" && -n "${HOST_LOGS:-}" ]]; then
            return 0
        fi
    fi

    local start off ok p
    for start in $(seq "${PORT_BASE}" 10 "${PORT_CEILING}"); do
        ok=1
        for off in 0 1 2 3 4; do
            p=$((start + off))
            if port_in_use "${p}"; then
                ok=0
                break
            fi
        done
        if [[ "${ok}" == 1 ]]; then
            HOST_HOMER="${start}"
            HOST_GRAFANA=$((start + 1))
            HOST_TB=$((start + 2))
            HOST_RAY=$((start + 3))
            HOST_LOGS=$((start + 4))
            return 0
        fi
    done
    die "no free 5-port block from ${PORT_BASE} to ${PORT_CEILING} (step 10)"
}

write_env_file() {
    local hf_home host
    hf_home="${HF_HOME:-$(default_hf_home)}"
    host="$(default_host)"
    mkdir -p "${PERSON_HOME}/logs" "${STATE_DIR}/homer" "${STATE_DIR}/rl-insight" "${hf_home}"

    cat > "${ENV_FILE}" <<EOF
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
LAB_NAME=${NAME}
LAB_WHO=${WHO}
LAB_USER=${UNIX_USER}
PERSON_HOME=${PERSON_HOME}
HF_HOME=${hf_home}
HF_DATASETS_CACHE=${hf_home}/datasets
LAB_STATE=${STATE_DIR}
LAB_HOST=${host}
HOST_HOMER=${HOST_HOMER}
HOST_GRAFANA=${HOST_GRAFANA}
HOST_TB=${HOST_TB}
HOST_RAY=${HOST_RAY}
HOST_LOGS=${HOST_LOGS}
LAB_TRAIN_IMAGE=${LAB_TRAIN_IMAGE:-lab-train:latest}
LAB_OBS_IMAGE=${LAB_OBS_IMAGE:-lab-obs:latest}
TRAINER_LOGGER=${TRAINER_LOGGER:-console,tensorboard,rl_insight}
TRAIN_SHM_SIZE=${TRAIN_SHM_SIZE:-16gb}
EOF

    {
        echo "HOMER=${HOST_HOMER}"
        echo "GRAFANA=${HOST_GRAFANA}"
        echo "TENSORBOARD=${HOST_TB}"
        echo "RAY=${HOST_RAY}"
        echo "LOGS=${HOST_LOGS}"
    } > "${STATE_DIR}/.lab-ports"

    render_homer "${host}"
    write_override
}

render_homer() {
    local host="$1"
    local tpl="${LAB_ROOT}/homer/config.yml.tpl"
    [[ -f "${tpl}" ]] || die "missing ${tpl}"
    sed \
        -e "s|__LAB_NAME__|${NAME}|g" \
        -e "s|__LAB_WHO__|${WHO}|g" \
        -e "s|__LAB_USER__|${UNIX_USER}|g" \
        -e "s|__LAB_HOST__|${host}|g" \
        -e "s|__PORT_HOMER__|${HOST_HOMER}|g" \
        -e "s|__PORT_GRAFANA__|${HOST_GRAFANA}|g" \
        -e "s|__PORT_TB__|${HOST_TB}|g" \
        -e "s|__PORT_RAY__|${HOST_RAY}|g" \
        -e "s|__PORT_LOGS__|${HOST_LOGS}|g" \
        "${tpl}" > "${STATE_DIR}/homer/config.yml"
}

write_override() {
    local override="${STATE_DIR}/compose.override.yml"
    local logs=()
    local d i=0

    if [[ -d "${PERSON_HOME}/workspace" ]]; then
        shopt -s nullglob
        for d in "${PERSON_HOME}/workspace"/*/logs; do
            [[ -d "${d}" ]] && logs+=("${d}")
        done
        shopt -u nullglob
    fi
    if [[ -n "${LAB_LOG_DIRS:-}" ]]; then
        IFS=':' read -r -a extra <<< "${LAB_LOG_DIRS}"
        logs+=("${extra[@]}")
    fi

    if [[ ${#logs[@]} -eq 0 ]]; then
        printf '%s\n' '{}' > "${override}"
        return 0
    fi
    {
        echo "services:"
        echo "  obs:"
        echo "    volumes:"
        for d in "${logs[@]}"; do
            [[ -d "${d}" ]] || continue
            echo "      - ${d}:/logs/proj${i}:ro"
            i=$((i + 1))
        done
    } > "${override}"
    if [[ "${i}" == 0 ]]; then
        printf '%s\n' '{}' > "${override}"
    fi
}

load_instance() {
    detect_identity
    [[ -f "${ENV_FILE}" ]] || die "instance '${NAME}' not found at ${ENV_FILE}. Run: ./lab.sh up --name ${NAME}"
    # shellcheck disable=SC1090
    set -a
    source "${ENV_FILE}"
    set +a
    require_docker
}

lab_compose() {
    local files=("${COMPOSE_FILE}")
    if [[ -f "${STATE_DIR}/compose.override.yml" ]]; then
        files+=("${STATE_DIR}/compose.override.yml")
    fi
    local file_args=()
    local f
    for f in "${files[@]}"; do
        file_args+=(-f "${f}")
    done
    docker compose \
        --project-directory "${LAB_ROOT}" \
        --env-file "${ENV_FILE}" \
        "${file_args[@]}" \
        -p "${COMPOSE_PROJECT_NAME}" \
        "$@"
}

need_images() {
    local img missing=0
    for img in "${LAB_TRAIN_IMAGE:-lab-train:latest}" "${LAB_OBS_IMAGE:-lab-obs:latest}"; do
        if ! docker image inspect "${img}" >/dev/null 2>&1; then
            echo "missing image: ${img}" >&2
            missing=1
        fi
    done
    if [[ "${missing}" == 1 ]]; then
        die "images are not in this rootless store. Load the shared tarball, do not compose build here:
  docker load -i /path/to/lab-rl-images.tar.gz"
    fi
}

cmd_doctor() {
    detect_identity
    echo "user        ${UNIX_USER}"
    echo "who         ${WHO}"
    echo "person_home ${PERSON_HOME}"
    echo "instance    ${NAME}  (compose ${COMPOSE_PROJECT_NAME})"
    echo

    if [[ -n "${DOCKER_HOST:-}" ]]; then
        echo "DOCKER_HOST ${DOCKER_HOST} (from env)"
    elif [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/docker.sock" ]]; then
        echo "socket     ${XDG_RUNTIME_DIR}/docker.sock"
    else
        echo "socket     MISSING  (no \$DOCKER_HOST, no \$XDG_RUNTIME_DIR/docker.sock)"
        echo "           rootless dockerd is not up. Do not add this user to the docker group."
        echo
    fi

    if setup_docker; then
        echo "docker     ok via ${DOCKER_HOST}"
        docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}' 2>/dev/null || docker version | head -8
        echo
        if docker image inspect lab-train:latest >/dev/null 2>&1; then
            echo "image      lab-train:latest  present"
        else
            echo "image      lab-train:latest  MISSING  → docker load -i lab-rl-images.tar.gz"
        fi
        if docker image inspect lab-obs:latest >/dev/null 2>&1; then
            echo "image      lab-obs:latest    present"
        else
            echo "image      lab-obs:latest    MISSING  → docker load -i lab-rl-images.tar.gz"
        fi
    fi

    echo
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "host gpu"
        nvidia-smi --query-gpu=index,name,memory.used,memory.free --format=csv,noheader || true
    else
        echo "host gpu   nvidia-smi not found"
    fi

    if command -v loginctl >/dev/null 2>&1; then
        echo
        echo "linger     $(loginctl show-user "${UNIX_USER}" -p Linger --value 2>/dev/null || echo unknown)"
    fi
    echo
    echo "doctor does not start containers. After images are loaded: ./lab.sh up --name ${NAME}"
}

cmd_up() {
    detect_identity
    require_docker
    need_images
    allocate_ports
    write_env_file
    lab_compose up -d --remove-orphans
    echo
    cmd_url
}

cmd_exec() {
    load_instance
    lab_compose exec -w "${PERSON_HOME}" train bash -l
}

cmd_train() {
    load_instance
    if [[ ${#TRAIN_ARGS[@]} -eq 0 ]]; then
        die "train needs a command. Example: CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name ${NAME} -- bash scripts/run_sft.sh"
    fi
    if [[ -z "${CUDA_VISIBLE_DEVICES:-}" ]]; then
        die "CUDA_VISIBLE_DEVICES is unset. The container can see every GPU; pick one at train time (example: CUDA_VISIBLE_DEVICES=2)."
    fi
    if ! lab_compose ps --status running --services 2>/dev/null | grep -qx train; then
        die "train container is not running. ./lab.sh up --name ${NAME}"
    fi

    local inner='source /opt/lab/env.sh
mkdir -p "${PERSON_HOME}/logs"
echo $$ > /tmp/lab-train.pid
echo "[lab] pid=$(cat /tmp/lab-train.pid) CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
exec "$@"'

    if [[ "${DETACH}" == 1 ]]; then
        lab_compose exec -d \
            -e "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}" \
            -w "${PERSON_HOME}" \
            train bash -lc "${inner}" -- "${TRAIN_ARGS[@]}"
        echo "training detached in ${COMPOSE_PROJECT_NAME}. Stop with: ./lab.sh stop-train --name ${NAME}"
    else
        lab_compose exec \
            -e "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}" \
            -w "${PERSON_HOME}" \
            train bash -lc "${inner}" -- "${TRAIN_ARGS[@]}"
    fi
}

cmd_stop_train() {
    load_instance
    lab_compose exec -T train bash -lc '
if [[ -f /tmp/lab-train.pid ]]; then
  pid=$(cat /tmp/lab-train.pid)
  echo "stopping pid ${pid}"
  kill "${pid}" 2>/dev/null || true
  sleep 1
  kill -9 "${pid}" 2>/dev/null || true
  rm -f /tmp/lab-train.pid
else
  echo "no /tmp/lab-train.pid; trying common trainer processes"
fi
pkill -f "verl.trainer" 2>/dev/null || true
pkill -f "ray::" 2>/dev/null || true
true
'
}

cmd_url() {
    if [[ -z "${ENV_FILE:-}" || ! -f "${ENV_FILE}" ]]; then
        detect_identity
    fi
    [[ -f "${ENV_FILE}" ]] || die "instance '${NAME}' not found. Run up first."
    # shellcheck disable=SC1090
    set -a
    source "${ENV_FILE}"
    set +a
    local host="${LAB_HOST:-$(default_host)}"
    local ssh_user="${UNIX_USER:-$(unix_user)}"
    echo "[${LAB_USER:-${ssh_user}}/${LAB_WHO:-${WHO}}/${LAB_NAME:-${NAME}}] Homer: http://${host}:${HOST_HOMER}"
    echo "  Grafana      http://${host}:${HOST_GRAFANA}"
    echo "  TensorBoard  http://${host}:${HOST_TB}"
    echo "  Run logs     http://${host}:${HOST_LOGS}"
    echo "  Ray          http://${host}:${HOST_RAY}   (GRPO only)"
    echo
    echo "off-campus tunnel:"
    echo "  ssh -N \\
    -L ${HOST_HOMER}:127.0.0.1:${HOST_HOMER} \\
    -L ${HOST_GRAFANA}:127.0.0.1:${HOST_GRAFANA} \\
    -L ${HOST_TB}:127.0.0.1:${HOST_TB} \\
    -L ${HOST_LOGS}:127.0.0.1:${HOST_LOGS} \\
    -L ${HOST_RAY}:127.0.0.1:${HOST_RAY} \\
    ${ssh_user}@${host}"
}

cmd_list() {
    detect_identity
    echo "instances under ${PERSON_HOME}/.lab"
    if [[ ! -d "${PERSON_HOME}/.lab" ]]; then
        echo "  (none)"
        return 0
    fi
    local dir envf
    for dir in "${PERSON_HOME}/.lab"/*; do
        [[ -d "${dir}" ]] || continue
        envf="${dir}/lab.env"
        if [[ -f "${envf}" ]]; then
            # shellcheck disable=SC1090
            HOST_HOMER="?" COMPOSE_PROJECT_NAME="?" LAB_NAME="$(basename "${dir}")"
            # shellcheck disable=SC1090
            source "${envf}"
            echo "  ${LAB_NAME}  compose=${COMPOSE_PROJECT_NAME}  homer=${HOST_HOMER}  state=${dir}"
        else
            echo "  $(basename "${dir}")  (no lab.env)"
        fi
    done
    if [[ -n "${DOCKER_HOST:-}" ]] || [[ -S "${XDG_RUNTIME_DIR:-/dev/null}/docker.sock" ]]; then
        setup_docker || true
        echo
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -40 || true
    fi
}

cmd_down() {
    load_instance
    lab_compose down --remove-orphans
    echo "stopped ${COMPOSE_PROJECT_NAME}. State kept at ${STATE_DIR} (ports reused on next up)."
}

case "${CMD}" in
    doctor) cmd_doctor ;;
    up) cmd_up ;;
    exec) cmd_exec ;;
    train) cmd_train ;;
    stop-train) cmd_stop_train ;;
    url) cmd_url ;;
    list) cmd_list ;;
    down) cmd_down ;;
    ""|-h|--help) usage ;;
    *)
        usage >&2
        die "unknown command: ${CMD}"
        ;;
esac
