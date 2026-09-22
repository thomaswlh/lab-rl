# Vendored no-TE patches

PyPI `megatron-bridge==0.5.1` and a few Megatron-Core files import Transformer Engine
unconditionally. This lab stack does **not** install TE (or Apex / flash-attn).
These files were copied from a working environment (2026-09-22) after making TE
optional.

| File | Why |
|---|---|
| `megatron/bridge/models/gpt_provider.py` | `default_layer_spec` falls back to local layers if TE is missing |
| `megatron/bridge/peft/lora.py` | `try/except` around `import transformer_engine` |
| `megatron/bridge/peft/lora_layers.py` | same |
| `megatron/bridge/peft/utils.py` | TE symbols via `safe_import_from` |
| `megatron/core/transformer/dot_product_attention.py` | local attention path without TE |
| `megatron/core/dist_checkpointing/strategies/nvrx.py` | NVRx optional |
| `nvidia_resiliency_ext/__init__.py` | pip 0.4.1 ships no `__init__.py`; bridge import needs `__version__` |

Apply after `pip install` (see `apply.sh`). Re-apply if you reinstall
`megatron-core`, `megatron-bridge`, or `nvidia-resiliency-ext`.
