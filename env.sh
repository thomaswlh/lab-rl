#!/usr/bin/env bash
# Container-generic environment for lab-rl.
# Usage: source /opt/lab/env.sh   (or source this file from the repo)
#
# Does not hardcode conda paths or a GPU index.
# CUDA_VISIBLE_DEVICES is left to the caller (lab.sh train refuses if unset).

if [[ -n "${_LAB_RL_ENV_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
export _LAB_RL_ENV_LOADED=1

_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -x /opt/lab/bin/python ]]; then
    export PYTHON="${PYTHON:-/opt/lab/bin/python}"
elif [[ -x "${_ENV_DIR}/.venv/bin/python" ]]; then
    export PYTHON="${PYTHON:-${_ENV_DIR}/.venv/bin/python}"
else
    export PYTHON="${PYTHON:-$(command -v python3 || command -v python)}"
fi

export CUDA_DEVICE_ORDER="${CUDA_DEVICE_ORDER:-PCI_BUS_ID}"
export CUDA_DEVICE_MAX_CONNECTIONS="${CUDA_DEVICE_MAX_CONNECTIONS:-1}"
export VLLM_USE_V1="${VLLM_USE_V1:-1}"
export VERL_USE_UV="${VERL_USE_UV:-0}"
export TOKENIZERS_PARALLELISM=true
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-8}"

_default_home="${PERSON_HOME:-${HOME}}"
export HF_HOME="${HF_HOME:-${_default_home}/.cache/huggingface}"
export HF_DATASETS_CACHE="${HF_DATASETS_CACHE:-${HF_HOME}/datasets}"
export TRANSFORMERS_OFFLINE="${TRANSFORMERS_OFFLINE:-1}"
export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}"
export HF_DATASETS_OFFLINE="${HF_DATASETS_OFFLINE:-1}"

export NGPUS="${NGPUS:-1}"
export TP="${TP:-1}"
export PP="${PP:-1}"
export SP="${SP:-1}"
export FULL_RECOMPUTE="${FULL_RECOMPUTE:-0}"
export FLASH="${FLASH:-0}"
export LORA="${LORA:-0}"
export LORA_RANK="${LORA_RANK:-32}"
export LORA_ALPHA="${LORA_ALPHA:-32}"
export VLLM_GPU_UTIL="${VLLM_GPU_UTIL:-0.15}"

if [[ "${FLASH}" == "1" ]]; then
    export ATTN_BACKEND=flash
else
    export ATTN_BACKEND=unfused
fi
if [[ "${SP}" == "1" ]]; then
    export SP_BOOL=True
else
    export SP_BOOL=False
fi

# Observability knobs for projects that choose to read them.
export RL_INSIGHT_SERVER_URL="${RL_INSIGHT_SERVER_URL:-http://obs:18080}"
export TRAINER_LOGGER="${TRAINER_LOGGER:-console,tensorboard,rl_insight}"
export RAY_DASHBOARD_HOST="${RAY_DASHBOARD_HOST:-0.0.0.0}"
export RAY_DASHBOARD_PORT="${RAY_DASHBOARD_PORT:-8265}"
export TENSORBOARD_LOGDIR="${TENSORBOARD_LOGDIR:-${_default_home}/logs}"

if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
    _gpu_msg="CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
else
    _gpu_msg="CUDA_VISIBLE_DEVICES=(unset)"
fi

echo "[env] PYTHON=${PYTHON}"
echo "[env] ${_gpu_msg} NGPUS=${NGPUS} TP=${TP} PP=${PP} SP=${SP} FLASH=${FLASH} LORA=${LORA} RECOMPUTE=${FULL_RECOMPUTE}"
echo "[env] HF_HOME=${HF_HOME} RL_INSIGHT_SERVER_URL=${RL_INSIGHT_SERVER_URL}"
