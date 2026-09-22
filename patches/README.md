# 无 Transformer Engine 补丁

PyPI 上的 `megatron-bridge==0.5.1` 以及部分 Megatron-Core 文件会无条件导入 Transformer Engine。本仓库的训练镜像不安装 TE、Apex 或 flash-attn。这些文件使 TE 变为可选依赖。

| 文件 | 作用 |
|---|---|
| `megatron/bridge/models/gpt_provider.py` | `default_layer_spec` 在缺少 TE 时回退到本地 layer |
| `megatron/bridge/peft/lora.py` | `import transformer_engine` 包在 `try/except` 中 |
| `megatron/bridge/peft/lora_layers.py` | 同上 |
| `megatron/bridge/peft/utils.py` | 通过 `safe_import_from` 引用 TE 符号 |
| `megatron/core/transformer/dot_product_attention.py` | 不依赖 TE 的本地 attention 路径 |
| `megatron/core/dist_checkpointing/strategies/nvrx.py` | NVRx 变为可选 |
| `nvidia_resiliency_ext/__init__.py` | pip 0.4.1 未附带 `__init__.py`；bridge import 需要 `__version__` |

在 `pip install` 之后执行 `apply.sh`。重装 `megatron-core`、`megatron-bridge` 或 `nvidia-resiliency-ext` 后需再打一次补丁。
