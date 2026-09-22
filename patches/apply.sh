#!/usr/bin/env bash
# Overlay vendored no-TE files onto the active interpreter's site-packages.
set -euo pipefail

PATCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON:-${1:-python}}"

SITE="$("${PYTHON_BIN}" -c 'import site; print(site.getsitepackages()[0])')"
if [[ ! -d "${SITE}" ]]; then
    echo "apply.sh: site-packages not found via ${PYTHON_BIN}" >&2
    exit 1
fi

copy_into() {
    local rel="$1"
    local dest="${SITE}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    cp -a "${PATCH_ROOT}/${rel}" "${dest}"
    echo "patched ${dest}"
}

copy_into megatron/bridge/models/gpt_provider.py
copy_into megatron/bridge/peft/lora_layers.py
copy_into megatron/bridge/peft/lora.py
copy_into megatron/bridge/peft/utils.py
copy_into megatron/core/dist_checkpointing/strategies/nvrx.py
copy_into megatron/core/transformer/dot_product_attention.py
copy_into nvidia_resiliency_ext/__init__.py

echo "patches applied to ${SITE}"
