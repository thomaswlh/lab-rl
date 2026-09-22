# 训练栈

本仓库锁定的训练栈为 **verl 0.9 + Megatron（actor/ref）+ vLLM（rollout）+ Ray**。

`Dockerfile.train` 必须按本文顺序安装。不要改顺序，也不要使用 `pip install "verl[vllm]"`。

驱动侧 CUDA 12.9 的机器应安装 **cu128** 的 PyTorch，不要安装 cu130。

## 锁定版本

锁定日期：2026-09-22。

| 包 | 版本 |
|---|---|
| Python | 3.12 |
| torch | 2.10.0+**cu128** |
| torchvision / torchaudio | 0.25.0+cu128 / 2.10.0+cu128 |
| vllm | 0.19.1 |
| megatron-core | 0.18.2 |
| megatron-bridge | 0.5.1（无 Transformer Engine 补丁） |
| verl | 0.9.0 |
| ray | 2.58.0 |
| transformers | **5.8.1**（verl 要求 `<5.11`，bridge 要求 `<5.9`） |
| peft | 0.20.0 |
| datasets | 5.0.1 |
| hydra-core / omegaconf | 1.3.2 / 2.3.1 |
| accelerate | 1.14.0 |
| tensordict | 0.10.0 |
| nvidia-modelopt | 0.46.0 |
| nvidia-resiliency-ext | 0.4.1（补 `__version__`） |
| TransferQueue | 0.1.10（GRPO / Ray 需要） |
| flashinfer-python | 0.6.6（配合 vLLM 0.19.1；不要升到 0.6.8） |

镜像不安装独立的 `flash_attn` 或 Transformer Engine。脚本默认 `attention_backend=unfused`。

## 安装顺序

### 1. 安装与驱动匹配的 PyTorch

必须从 **PyTorch 官方 cu128 源**安装。默认 PyPI 会装到不带 `+cu128` 的 `torch==2.10.0`：

```bash
pip install torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0 \
  --index-url https://download.pytorch.org/whl/cu128
```

不要安装 `cu130` 或 `torch==2.11.0+cu130`。镜像构建只做 CPU import；构建阶段 `torch.cuda.is_available()` 可以为 False。

### 2. 安装 vLLM（锁住 torch）

```bash
pip install "vllm==0.19.1" "torch==2.10.0"
```

完成后仍须是 `2.10.0+cu128` 与 `vllm 0.19.1`。vLLM 可能把 `transformers` 升到 5.17，后续步骤会降回 **5.8.1**。

### 3. 安装 Megatron / verl（不要带 extras）

`megatron-bridge==0.5.1` 的 PyPI 依赖会拉取 `flashinfer==0.6.8`、Transformer Engine、mlflow、comet 等，与本栈冲突。使用 `--no-deps`：

```bash
pip install --no-deps megatron-core==0.18.2
pip install --no-deps megatron-bridge==0.5.1
pip install --no-deps verl==0.9.0
```

再用仓库根目录的 `constraints.txt` 安装其余依赖，避免后续 pip 替换 torch / vLLM / flashinfer：

```bash
pip install -c constraints.txt \
  "transformers==5.8.1" \
  "ray[default]==2.58.0" \
  "peft==0.20.0" \
  "datasets==5.0.1" \
  "hydra-core==1.3.2" \
  "omegaconf==2.3.1" \
  "accelerate==1.14.0" \
  "tensordict==0.10.0" \
  "nvidia-modelopt[torch]==0.46.0" \
  "nvidia-resiliency-ext==0.4.1" \
  "TransferQueue==0.1.10" \
  "diffusers==0.40.0" \
  "qwen-vl-utils" \
  pyarrow pandas \
  codetiming pylatexenc pybind11 torchdata wandb tensorboard \
  --upgrade-strategy only-if-needed
```

`verl` 要求 `transformers!=5.6.0,<5.11,>=5.5.3`，`megatron-bridge` 要求 `transformers>=5.8.1,<5.9`。交叉点为 **5.8.1**。

未安装 `TransferQueue` 时，`verl.trainer.main_ppo` 会在 Ray worker 中报 `No module named 'transfer_queue'`。

### 4. 无 Transformer Engine 补丁

```bash
bash patches/apply.sh
```

重装 `megatron-core`、`megatron-bridge` 或 `nvidia-resiliency-ext` 后需再执行一次。

## 不安装的包

| 包 | 原因 |
|---|---|
| `flash-attn` | 默认 `unfused`；需要时再设 `FLASH=1` |
| `transformer-engine` / Apex | 由补丁与 `masked_softmax_fusion=False` 替代 |
| `flashinfer==0.6.8` | 与 vLLM 0.19.1 自带的 0.6.6 冲突 |
| `verl[vllm]` extras | 可能把 torch 升到 cu130，或把 vLLM 升到 0.20 |

## 兼容性约束

1. **torch 的 CUDA 版本必须不超过宿主机驱动。** 驱动 12.9 使用 cu128，禁用 cu130。
2. **不要用默认 PyPI 再安装一遍 `torch==2.10.0`**，会覆盖 `+cu128` wheel。
3. **`megatron-core` 与 `megatron-bridge` 必须配对。** bridge 0.5.1 需要带 `megatron.core.distributed.fsdp` 的 mcore（已验证 0.18.2）。`0.12.3` 会 import 失败。
4. **vLLM 与 torch 必须配对。** 工作组合是 `torch 2.10.0+cu128` + `vllm 0.19.1`。
5. **`transformers` 锁定 5.8.1。** vLLM 默认拉取的 5.17 过新，verl 与 bridge 都会拒绝。
6. **GRPO 必须安装 `TransferQueue`。**
7. **GRPO 不要设置** `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`，vLLM 会 assert。
8. 共享 GPU 上，`vllm gpu_memory_utilization` 按整卡容量计算，不是按剩余显存。

## 构建自检

镜像构建只运行 CPU import（`check_env.py --cpu-only`）。GPU 与 `nvidia-smi` 检查放在宿主机 `./lab.sh doctor`。
