# 用法

映像檔由一個人建置並匯出，其他人 `docker load`。每個實例佔用一段連續的連接埠。Homer 標題用 `--name`，副標題帶 Unix 使用者、身分和連接埠範圍。

## 主機準備

每個 Unix 帳號設一次：

1. 安裝 rootless Docker：`dockerd-rootless`、使用者層級的 `docker.service`，以及 `loginctl enable-linger $USER`。
2. 用 `nvidia-ctk` 設定 rootless GPU：`no-cgroups`，`default-runtime: nvidia`。
3. `/etc/subuid` 與 `/etc/subgid` 裡，這個使用者只留一段對應範圍。
4. 不要把使用者加入 `docker` 群組，也不要用 `/var/run/docker.sock`。

設完跑 `./lab.sh doctor`，它要能連上 `$XDG_RUNTIME_DIR/docker.sock`（或環境變數 `DOCKER_HOST` 指到的 rootless socket）。

## 取得程式碼

```bash
git clone https://github.com/thomaswlh/lab-rl.git
cd lab-rl
```

## 映像檔

rootless 的映像檔在各自的 `~/.local/share/docker`，機器上沒有一份大家共用的，所以建置一次再 `docker load`。

維護者（要有外網，磁碟也要夠）：

```bash
bash scripts/build-images.sh
bash scripts/export-images.sh /path/to/shared/lab-rl-images.tar.gz
```

其他帳號等 rootless daemon 起來之後：

```bash
docker load -i /path/to/shared/lab-rl-images.tar.gz
```

同一個 Unix 帳號共用一份 rootless 映像檔庫，load 一次就好。不同帳號或不同機器要各 load 一次。

映像檔還沒 load 時，`lab.sh` 不會自動 `compose build`。`doctor` 和 `up` 會提示先 load。

建置順序和版本鎖見 [stack.md](stack.md)。順序不能亂：cu128 torch → vLLM 0.19.1 → `--no-deps` megatron/verl → `constraints.txt` → `patches/`。重裝 Megatron 相關套件後要再執行 `patches/apply.sh`，說明見 [../patches/README.md](../patches/README.md)。

## 身分

個人帳號就是你自己。群組帳號（使用者名稱以 `_team` 結尾）用 `$HOME` 底下第一層目錄當人，例如 `$HOME/alice` 就是 alice。

| 情境 | `WHO` | `PERSON_HOME` | Compose 專案名稱 |
|---|---|---|---|
| 個人帳號 `alice` | `alice` | `$HOME` | `alice-box` |
| 群組帳號（使用者名稱以 `_team` 結尾），工作目錄在 `$HOME/alice/...` | `alice` | `$HOME/alice` | `<unix>-alice-box` |

群組帳號從 `$PWD` 判斷 `WHO`（`$HOME` 下第一層目錄）。不在那層目錄裡啟動時，要自己加 `--who`：

```bash
./lab.sh up --name box --who alice
```

`up` 把 `PERSON_HOME` 照原路徑掛進訓練容器，不用再掛專案目錄。進容器之後：

```bash
cd "$PERSON_HOME/workspace/your-project"
```

實例狀態寫在 `$PERSON_HOME/.lab/<name>/`（連接埠、Homer 設定、RL-Insight 資料）。

Hugging Face 快取的預設：如果有 `$HOME/.cache/huggingface` 就用它（群組帳號可以共用），否則用 `$PERSON_HOME/.cache/huggingface`。可以用環境變數 `HF_HOME` 覆寫。

## 日常操作

```bash
./lab.sh doctor
./lab.sh up --name box
./lab.sh url --name box
```

瀏覽器打開列出的 Homer 網址。先看標題和副標題，別進錯實例。

容器裡看得到全部 GPU。開訓時用 `CUDA_VISIBLE_DEVICES` 選卡：

```bash
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv
CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name box -- bash scripts/run_sft.sh
```

沒設 `CUDA_VISIBLE_DEVICES` 時，`train` 不會跑。

進入容器：

```bash
./lab.sh exec --name box
# 容器內
source /opt/lab/env.sh
cd "$PERSON_HOME/workspace/your-project"
python /opt/lab/check_env.py
```

停掉訓練，或停掉整組服務：

```bash
./lab.sh stop-train --name box
./lab.sh down --name box          # 監控服務一起停；狀態和連接埠留著
```

`train` 加 `-d` 可以在背景跑，再用 `stop-train` 停掉。

## 什麼時候看得到

`lab.sh up` 之後 obs 一直開著，跟有沒有在訓練無關。

| 服務 | 開多久 | Homer |
|---|---|---|
| Homer | 跟 obs 一起 | 入口本身 |
| RL-Insight Grafana / Prometheus / Tempo | 一直開著 | Grafana |
| TensorBoard | 一直開著，沒在訓練也能看舊的 | TensorBoard |
| Run logs | 一直開著，只讀 `$PERSON_HOME/logs` 和 `workspace/*/logs` | Run logs |
| Ray Dashboard | 只有 GRPO 在跑的時候 | 寫著「只有 GRPO 在跑時才開」 |
| 訓練程式 | `train` 才啟動；SFT 不啟動 Ray | — |

訓練容器是 `restart: no`，機器重新開機後不會自己佔住 GPU。obs 是 `unless-stopped`。

容器裡的連接埠是固定的：Homer `8080`、Grafana `3000`、TensorBoard `6006`、Ray `8265`、Run logs `8081`。主機從 **18000** 起，每次往上 10，連拿 5 個沒人用的。`flock /tmp/lab-rl-ports.lock` 是為了避免兩個人同時拿同一個。要固定連接埠時：

```bash
LAB_PORT_BASE=18200 ./lab.sh up --name box
```

不要把主機連接埠寫成 `8080` 或 `3000`，那些常常已經有人在用。

## 監控怎麼接

容器會設這些環境變數：

| 變數 | 預設 | 意思 |
|---|---|---|
| `RL_INSIGHT_SERVER_URL` | `http://obs:18080` | 訓練程式走 compose DNS，跟主機上的連接埠對應無關 |
| `TRAINER_LOGGER` | `console,tensorboard,rl_insight` | verl logger 列表 |
| `RAY_DASHBOARD_HOST` / `PORT` | `0.0.0.0` / `8265` | GRPO 時 Ray 要綁這個位址，Homer 才開得了 |
| `TENSORBOARD_LOGDIR` | `$PERSON_HOME/logs` | TensorBoard 掃描的目錄 |
| `HF_HOME` | 見上面 | Hugging Face 快取 |

verl 裡要把 `trainer.logger` 寫成含 `rl_insight`。在訓練專案裡改：`trainer.logger='[console,tensorboard,rl_insight]'`。

Grafana 預設是匿名 Viewer（實驗室網路、不用登入）。Ray Dashboard 在 GRPO 期間也同樣開著。

另外的記錄目錄：

```bash
LAB_LOG_DIRS=/path/a/logs:/path/b/logs ./lab.sh up --name box
```

不起 Web Shell：機器是大家共用的，頁面沒有登入。不再另外起一份 vLLM。GRPO 裡的 vLLM 是 process 裡面的 engine，多起一份會佔住 GPU。不接 Loki / ELK。

## 人在校外

Homer 聽的是實驗室網路。人在外面時：

```bash
./lab.sh url --name box
```

照輸出的 `ssh -L` 轉到自己電腦，然後用瀏覽器打開 `http://127.0.0.1:<Homer口>`。

通道建立後，Homer 卡片仍可能寫主機 IP。打不開就把 host 改成 `127.0.0.1`，連接埠不動。也可以在 `up` 時加 `--host 127.0.0.1`（只適合自己走通道）。

## doctor

- 只連 `DOCKER_HOST` 或 `$XDG_RUNTIME_DIR/docker.sock`，不會改去連 `/var/run/docker.sock`
- 檢查 `lab-train:latest` 和 `lab-obs:latest` 有沒有 load
- 檢查主機上的 `nvidia-smi`
- 檢查 linger 有沒有開

映像檔建置只做 CPU import（`check_env.py --cpu-only`）。GPU 自己測是在 `doctor` 或進容器之後。
