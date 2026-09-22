# 训练栈配方（锁版本）

本仓库冻住的栈是：**verl 0.9 + Megatron（actor/ref）+ vLLM（rollout）+ Ray**。
`Dockerfile.train` 按下面的顺序装，不要改顺序，也不要走 `pip install "verl[vllm]"`。

驱动侧 CUDA 12.9 的机器只能装 **cu128** 的 torch，不能装 cu130。

## 锁定版本（2026-09-22 跑通）

| 包 | 版本 |
|---|---|
| Python | 3.12 |
| torch | 2.10.0+**cu128** |
| torchvision / torchaudio | 0.25.0+cu128 / 2.10.0+cu128 |
| vllm | 0.19.1 |
| megatron-core | 0.18.2 |
| megatron-bridge | 0.5.1（打无 TE 补丁） |
| verl | 0.9.0 |
| ray | 2.58.0 |
| transformers | **5.8.1**（verl 要 `<5.11`，bridge 要 `<5.9`） |
| peft | 0.20.0 |
| datasets | 5.0.1 |
| hydra-core / omegaconf | 1.3.2 / 2.3.1 |
| accelerate | 1.14.0 |
| tensordict | 0.10.0 |
| nvidia-modelopt | 0.46.0 |
| nvidia-resiliency-ext | 0.4.1（补 `__version__`） |
| TransferQueue | 0.1.10（GRPO / Ray 需要） |
| flashinfer-python | 0.6.6（跟 vLLM 0.19.1，不要升到 0.6.8） |

没装独立的 `flash_attn` / Transformer Engine。脚本默认 `attention_backend=unfused`，这是预期行为。

## 安装顺序

### 1. 先装匹配驱动的 PyTorch

必须从 **PyTorch 官方 cu128 源**装，不要走默认 PyPI（会拉到不带 `+cu128` 的 `torch==2.10.0`）：

```bash
pip install torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0 \
  --index-url https://download.pytorch.org/whl/cu128
```

不要装 `cu130` / `torch==2.11.0+cu130`。镜像构建只做 CPU import；`torch.cuda.is_available()` 在 build 阶段可以是 False。

### 2. 装 vLLM（锁住 torch）

```bash
pip install "vllm==0.19.1" "torch==2.10.0"
```

必须仍是 `2.10.0+cu128` 和 `vllm 0.19.1`。vLLM 可能把 `transformers` 拉到 5.17，后面要降回 **5.8.1**。

### 3. 装 Megatron / verl（不要带 extras）

`megatron-bridge==0.5.1` 的 PyPI 依赖会要 `flashinfer==0.6.8`、TE、mlflow、comet 等，和本栈冲突。**用 `--no-deps`**：

```bash
pip install --no-deps megatron-core==0.18.2
pip install --no-deps megatron-bridge==0.5.1
pip install --no-deps verl==0.9.0
```

再用仓库根目录的 `constraints.txt` 装其余依赖，避免后续 pip 把 torch / vLLM / flashinfer 换掉：

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

`verl` 需要 `transformers!=5.6.0,<5.11,>=5.5.3`，`megatron-bridge` 需要 `transformers>=5.8.1,<5.9`。交叉点就是 **5.8.1**。

`TransferQueue` 不装的话，`verl.trainer.main_ppo` 会在 Ray worker 里报 `No module named 'transfer_queue'`。

### 4. 无 TE 本地补丁（必做）

```bash
bash patches/apply.sh
```

重装 `megatron-core` / `megatron-bridge` / `nvidia-resiliency-ext` 后要再打一次。

## 不必装的包

| 包 | 为什么跳过 |
|---|---|
| `flash-attn` | 默认 `unfused`；需要时再 `FLASH=1` |
| `transformer-engine` / Apex | 靠补丁 + `masked_softmax_fusion=False` |
| `flashinfer==0.6.8` | 和 vLLM 0.19.1 的 0.6.6 打架 |
| `verl[vllm]` extras | 可能把 torch 升到 cu130 / 把 vLLM 升到 0.20 |

## 版本坑

1. **torch CUDA 必须 ≤ 驱动**。驱动 12.9 → 用 cu128，禁用 cu130。
2. **不要用默认 PyPI 再装一遍 `torch==2.10.0`**，会覆盖掉 `+cu128` wheel。
3. **`megatron-core` 和 `megatron-bridge` 要配对**。bridge 0.5.1 需要带 `megatron.core.distributed.fsdp` 的 mcore（验证过 0.18.2）。`0.12.3` 会 import 失败。
4. **vLLM 和 torch 要配对**。工作组合是 `torch 2.10.0+cu128` + `vllm 0.19.1`。
5. **`transformers` 锁 5.8.1**。vLLM 默认拉上来的 5.17 过新，verl / bridge 都会拒。
6. **GRPO 必须有 `TransferQueue`**。
7. **不要给 GRPO 开** `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`，vLLM 会 assert。
8. 共享卡上 `vllm gpu_memory_utilization` 按整卡容量算，不是按剩余显存。

## 构建自检

镜像构建只跑 CPU import（`check_env.py --cpu-only`）。GPU / `nvidia-smi` 放到宿主机 `./lab.sh doctor`。
