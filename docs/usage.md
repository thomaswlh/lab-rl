# lab-rl 用法

实验室共享机、rootless Docker。一个人编镜像，其他人 `docker load`。每人一套端口，Homer 上写着实例名。

## 0. 学长先配（只做一次）

本机 `jpzhao_team` 还没有 user docker / `nvidia-ctk`。需要：

1. 每个要用的 Unix 账号：`dockerd-rootless`、user `docker.service`、`loginctl enable-linger $USER`
2. `nvidia-ctk` 配 rootless：`no-cgroups`，`default-runtime: nvidia`
3. `/etc/subuid` / `/etc/subgid`：`jpzhao_team` 若有两段，收成一段
4. **不要**把人加进 `docker` 组，**不要**用 `/var/run/docker.sock`

配好之后 `./lab.sh doctor` 应能连上 `$XDG_RUNTIME_DIR/docker.sock`。

## 1. 拿代码

```bash
git clone https://github.com/thomaswlh/lab-rl.git
cd lab-rl
```

仓库只是编排和配方。训练项目（例如 qwen-ft）仍放在你平时的路径，进容器后 `cd` 过去。

## 2. 拿镜像（不要每人 build）

rootless 的镜像库在每人自己的 `~/.local/share/docker`，不能全机共享一层。

一个人（有网、有 disk）编一次：

```bash
# 仅构建者
bash scripts/build-images.sh
bash scripts/export-images.sh /path/to/shared/lab-rl-images.tar.gz
```

其他人：

```bash
# 先能 docker info（rootless daemon 已起来）
docker load -i /path/to/shared/lab-rl-images.tar.gz
```

组账号共用同一份 rootless 库，load 一次即可。个人账号各 load 一次。

`lab.sh` **不会**在镜像缺失时偷偷 `compose build`。`doctor` / `up` 会告诉你去 load。

## 3. 身份：个人账号 vs 组账号

| | `WHO` | `PERSON_HOME` | compose 项目名 |
|---|---|---|---|
| 个人账号 `alice` | `alice` | `$HOME` | `alice-box` |
| 组账号 `jpzhao_team`，人在 `/home/jpzhao_team/lxhu/...` | `lxhu` | `/home/jpzhao_team/lxhu` | `jpzhao_team-lxhu-box` |

组账号从 `$PWD` 推断 `WHO`（`$HOME` 下第一级目录）。不在自己目录里就显式传：

```bash
./lab.sh up --name box --who lxhu
```

`up` 把 `PERSON_HOME` **按原路径**挂进训练容器。不必指定项目文件夹。进壳后：

```bash
cd /home/jpzhao_team/lxhu/workspace/qwen-ft
```

状态写在 `$PERSON_HOME/.lab/<name>/`（端口、Homer 配置、RL-Insight 数据）。

HF 缓存默认：若存在 `$HOME/.cache/huggingface` 就用它（组账号共享缓存），否则 `$PERSON_HOME/.cache/huggingface`。可被环境变量 `HF_HOME` 覆盖。

## 4. 每天怎么用

```bash
./lab.sh doctor
./lab.sh up --name box
./lab.sh url --name box
```

浏览器打开打印出来的 Homer。标题是 `--name`，副标题带 Unix 用户、`WHO` 和端口段，避免点进别人的栈。

开训必须选卡。容器启动时 **全部 GPU 可见**，不预占某一张：

```bash
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv
CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name box -- bash scripts/run_sft.sh
```

不设 `CUDA_VISIBLE_DEVICES` 时 `train` 直接拒绝。

进壳自己干活：

```bash
./lab.sh exec --name box
# 容器内
source /opt/lab/env.sh
cd ~/workspace/your-project   # 或 PERSON_HOME 下的原路径
python /opt/lab/check_env.py
```

停训 / 停栈：

```bash
./lab.sh stop-train --name box
./lab.sh down --name box          # 看板一起停；状态和端口保留
```

`train` 加 `-d` 可后台跑，再用 `stop-train` 停。

## 5. 哪些常驻，哪些跟训练走

`lab.sh up` 之后 **obs 常驻**，不依赖有没有人在训。

| 服务 | 寿命 | Homer |
|---|---|---|
| Homer | obs 活着就在 | 入口本身 |
| RL-Insight Grafana / Prometheus / Tempo | 常驻 | Grafana 卡片 |
| TensorBoard | 常驻，没训也能看历史 | TensorBoard 卡片 |
| Run logs | 常驻，只读 `$PERSON_HOME/logs` 和 `workspace/*/logs` | Run logs 卡片 |
| Ray Dashboard | **仅 GRPO 期间** | 写明「仅 GRPO 期间在线」 |
| 训练进程 | `train` 才起，SFT 不起 Ray | — |

训练容器 `restart: no`，避免机器重启后默默占卡。obs 是 `unless-stopped`。

容器里端口固定（Homer 8080、Grafana 3000、TB 6006、Ray 8265、logs 8081）。宿主机从 **18000** 起按 10 领连续 5 个空闲口，`flock /tmp/lab-rl-ports.lock`，避免两人同时 `up` 抢同一段。想固定：`LAB_PORT_BASE=18200 ./lab.sh up --name box`。

本机 8080 / 3000 已被占用，所以不要写死这些宿主机端口。

## 6. 项目怎么接到观测

本仓库 **不改** 你的训练脚本。容器里会带上这些环境变量，项目愿意读就读：

| 变量 | 默认 | 含义 |
|---|---|---|
| `RL_INSIGHT_SERVER_URL` | `http://obs:18080` | 训练进程走 compose DNS，和宿主机映射无关 |
| `TRAINER_LOGGER` | `console,tensorboard,rl_insight` | 给 verl 的 logger 列表 |
| `RAY_DASHBOARD_HOST` / `PORT` | `0.0.0.0` / `8265` | GRPO 里 Ray 要绑这个才能从 Homer 点开 |
| `TENSORBOARD_LOGDIR` | `$PERSON_HOME/logs` | TensorBoard 扫描这里 |
| `HF_HOME` | 见上 | Hugging Face 缓存 |

verl 侧以后可以加 `trainer.logger='[console,tensorboard,rl_insight]'`。那是项目仓库的事，不在 lab-rl v1。

Grafana 默认匿名 Viewer（实验室内网、无认证）。Ray Dashboard 在 GRPO 期间同样是开放的。

额外日志目录：`LAB_LOG_DIRS=/path/a/logs:/path/b/logs ./lab.sh up --name box`。

## 7. 校外 SSH 隧道

Homer 在实验室内网。人在外面：

```bash
./lab.sh url --name box
# 按它打印的 ssh -L 做本地转发，然后浏览器开 http://127.0.0.1:<Homer口>
```

隧道里的 Homer 卡片仍写着机器 IP。若打不开，把 URL 里的 host 改成 `127.0.0.1`，端口不变。或者 `up` 时 `--host 127.0.0.1`（只适合你自己走隧道）。

## 8. doctor 在查什么

- 只连 `DOCKER_HOST` 或 `$XDG_RUNTIME_DIR/docker.sock`，**绝不回落** `/var/run/docker.sock`
- `lab-train:latest` / `lab-obs:latest` 是否已 load
- 宿主机 `nvidia-smi`
- linger 是否打开

构建镜像时只做 CPU import（`check_env.py --cpu-only`）。真正的 GPU 自检在 doctor / 进容器之后。

## 9. 明确不做（v1）

- Web Shell（共享机、无认证）
- vLLM Playground / Control（GRPO 里的 vLLM 是进程内 engine，再起一个会抢卡）
- Loki / ELK
- 把用户加进 `docker` 组
- 日常 `lab.sh build`（40GB，磁盘会按人数翻倍）

## 10. 构建者备忘

配方锁在 [stack.md](stack.md)。顺序必须是：cu128 torch → vLLM 0.19.1 → `--no-deps` megatron/verl → `constraints.txt` → `patches/`。

```bash
bash scripts/build-images.sh
bash scripts/export-images.sh /shared/lab-rl-images.tar.gz
```

补丁说明见 [../patches/README.md](../patches/README.md)。重装 Megatron 后要再 `patches/apply.sh`。
