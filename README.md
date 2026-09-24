# lab-rl

共用 GPU 機器上的訓練環境。訓練和監控各一個容器。Docker 跑在你自己的帳號下（rootless），不用機器上的 root。瀏覽器從 Homer 進去。

這個存放庫只有啟動腳本和映像檔配方。訓練程式放在自己的目錄，進容器再 `cd`。

套件是 verl 0.9、Megatron、vLLM、Ray。版本見 [docs/stack.md](docs/stack.md)。

## 快速開始

```bash
git clone https://github.com/thomaswlh/lab-rl.git
cd lab-rl
./lab.sh doctor
./lab.sh up --name box
./lab.sh exec --name box
```

`up` 會列出 Homer 網址。帳號怎麼分、映像檔怎麼發、人在校外怎麼連，見 [docs/usage.md](docs/usage.md)。

先把這台機器的 rootless Docker 和 NVIDIA Container Toolkit 設好，見 [docs/usage.md](docs/usage.md#主機準備)。映像檔由一個人建置、匯出，其他人 `docker load`。平常不要在這台機器上 `compose build`。

## 指令

| 指令 | 用途 |
|---|---|
| `./lab.sh doctor` | 檢查 rootless socket、映像檔與主機 GPU |
| `./lab.sh up --name box` | 分配連接埠，啟動 obs（一直開著）與 train（待命） |
| `./lab.sh exec --name box` | 進入訓練容器 |
| `CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name box -- bash scripts/run_sft.sh` | 開始訓練（一定要指定 GPU） |
| `./lab.sh stop-train --name box` | 停掉訓練程式 |
| `./lab.sh url --name box` | 列出 Homer / 儀表板網址，以及 `ssh -L` 通道 |
| `./lab.sh list` | 列出目前這個身分下的實例 |
| `./lab.sh down --name box` | 停掉容器，連接埠和狀態留著 |

## 文件

| 文件 | 內容 |
|---|---|
| [docs/usage.md](docs/usage.md) | 主機準備、映像檔分發、日常操作、監控怎麼接 |
| [docs/stack.md](docs/stack.md) | 版本與安裝順序 |
| [patches/README.md](patches/README.md) | 沒有 Transformer Engine 時要打的修補 |
