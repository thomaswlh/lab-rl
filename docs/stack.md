# 套件版本

訓練用的套件是 verl 0.9、Megatron（actor/ref）、vLLM（rollout）、Ray。

`Dockerfile.train` 照下面的順序裝。不要 `pip install "verl[vllm]"`。那個 extras 可能把 torch 升到 cu130，或把 vLLM 升到 0.20。

驅動程式是 CUDA 12.9 就裝 **cu128**，不要裝 cu130。

## 版本

鎖定日期：2026-09-22。

| 套件 | 版本 |
|---|---|
| Python | 3.12 |
| torch | 2.10.0+**cu128** |
| torchvision / torchaudio | 0.25.0+cu128 / 2.10.0+cu128 |
| vllm | 0.19.1 |
| megatron-core | 0.18.2 |
| megatron-bridge | 0.5.1（沒有 Transformer Engine 的修補） |
| verl | 0.9.0 |
| ray | 2.58.0 |
| transformers | **5.8.1**（verl 要求 `<5.11`，bridge 要求 `<5.9`） |
| peft | 0.20.0 |
| datasets | 5.0.1 |
| hydra-core / omegaconf | 1.3.2 / 2.3.1 |
| accelerate | 1.14.0 |
| tensordict | 0.10.0 |
| nvidia-modelopt | 0.46.0 |
| nvidia-resiliency-ext | 0.4.1（補上 `__version__`） |
| TransferQueue | 0.1.10（GRPO / Ray 需要） |
| flashinfer-python | 0.6.6（搭配 vLLM 0.19.1；不要升到 0.6.8） |

映像檔不安裝獨立的 `flash_attn` 或 Transformer Engine。腳本預設 `attention_backend=unfused`。

## 安裝順序

### 1. 安裝和驅動程式相符的 PyTorch

一定要從 **PyTorch 官方的 cu128 套件來源**裝。直接用 PyPI 會裝到沒有 `+cu128` 的 `torch==2.10.0`：

```bash
pip install torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0 \
  --index-url https://download.pytorch.org/whl/cu128
```

不要裝 `cu130` 或 `torch==2.11.0+cu130`。映像檔建置只做 CPU import；建置時 `torch.cuda.is_available()` 可以是 False。

### 2. 安裝 vLLM（把 torch 釘住）

vLLM 會把 torch 換掉。這裡把 `torch==2.10.0` 一起寫上，裝完還得是 cu128：

```bash
pip install "vllm==0.19.1" "torch==2.10.0"
```

裝完核對，還得是 `2.10.0+cu128` 和 `vllm 0.19.1`。vLLM 可能把 `transformers` 升到 5.17，後面的步驟會降回 **5.8.1**。

### 3. 安裝 Megatron / verl（不要帶 extras）

`megatron-bridge==0.5.1` 的 PyPI 相依套件會把 `flashinfer==0.6.8`、Transformer Engine、mlflow、comet 一起帶進來，跟這組套件衝突。所以用 `--no-deps`：

```bash
pip install --no-deps megatron-core==0.18.2
pip install --no-deps megatron-bridge==0.5.1
pip install --no-deps verl==0.9.0
```

再用存放庫根目錄的 `constraints.txt` 裝其餘相依套件，避免後面的 pip 把 torch / vLLM / flashinfer 換掉：

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

`verl` 要求 `transformers!=5.6.0,<5.11,>=5.5.3`，`megatron-bridge` 要求 `transformers>=5.8.1,<5.9`。兩邊都能用的是 **5.8.1**。

沒裝 `TransferQueue` 時，`verl.trainer.main_ppo` 會在 Ray worker 裡出現 `No module named 'transfer_queue'`。

### 4. 沒有 Transformer Engine 時要打的修補

沒打的話，import 會去找沒安裝的 Transformer Engine：

```bash
bash patches/apply.sh
```

重裝 `megatron-core`、`megatron-bridge` 或 `nvidia-resiliency-ext` 之後要再執行一次。

megatron-core 用 0.18.2。0.12.3 沒有 `megatron.core.distributed.fsdp`，bridge 0.5.1 會 import 失敗。GRPO 不要設 `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`，vLLM 會 assert。`vllm gpu_memory_utilization` 按整張卡的 GPU 記憶體算，不是按剩下的記憶體。

## 不要裝的套件

| 套件 | 原因 |
|---|---|
| `flash-attn` | 預設 `unfused`；需要時再設 `FLASH=1` |
| `transformer-engine` / Apex | 用修補和 `masked_softmax_fusion=False` 代替 |
| `flashinfer==0.6.8` | 和 vLLM 0.19.1 自帶的 0.6.6 衝突 |
| `verl[vllm]` extras | 可能把 torch 升到 cu130，或把 vLLM 升到 0.20 |

## 建置時檢查什麼

映像檔建置只跑 CPU import（`check_env.py --cpu-only`）。GPU 和 `nvidia-smi` 的檢查放在主機上的 `./lab.sh doctor`。
