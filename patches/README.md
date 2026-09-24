# 沒有 Transformer Engine 時要打的修補

PyPI 上的 `megatron-bridge==0.5.1` 和幾處 Megatron-Core 檔案會無條件 import Transformer Engine。映像檔不裝 TE、Apex、flash-attn。沒打這個修補的話，import 會去找沒安裝的 Transformer Engine。打上之後，沒裝 TE 也能 import。

| 檔案 | 用途 |
|---|---|
| `megatron/bridge/models/gpt_provider.py` | `default_layer_spec` 在沒有 TE 時改走自己的 layer |
| `megatron/bridge/peft/lora.py` | `import transformer_engine` 放在 `try/except` 裡 |
| `megatron/bridge/peft/lora_layers.py` | 同上 |
| `megatron/bridge/peft/utils.py` | 透過 `safe_import_from` 引用 TE 的符號 |
| `megatron/core/transformer/dot_product_attention.py` | 不依賴 TE 的 attention 路徑 |
| `megatron/core/dist_checkpointing/strategies/nvrx.py` | 沒裝 NVRx 時略過 |
| `nvidia_resiliency_ext/__init__.py` | pip 0.4.1 沒有附 `__init__.py`；bridge import 需要 `__version__` |

在 `pip install` 之後執行 `apply.sh`。重裝 `megatron-core`、`megatron-bridge` 或 `nvidia-resiliency-ext` 後要再打一次。
