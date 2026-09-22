# 用法

lab-rl 面向共享 GPU 机器与 rootless Docker。镜像由一名维护者构建并导出，其余账号 `docker load`。每个实例占用一段连续端口，Homer 标题使用 `--name`，副标题带 Unix 用户、身份与端口段。

## 宿主机准备

每个需要使用 lab-rl 的 Unix 账号配置一次：

1. 安装 rootless Docker：`dockerd-rootless`、用户级 `docker.service`，以及 `loginctl enable-linger $USER`。
2. 用 `nvidia-ctk` 配置 rootless GPU：`no-cgroups`，`default-runtime: nvidia`。
3. `/etc/subuid` 与 `/etc/subgid` 中该用户只保留一段映射。
4. 不要把用户加入 `docker` 组，也不要使用 `/var/run/docker.sock`。

配置完成后，`./lab.sh doctor` 应能连上 `$XDG_RUNTIME_DIR/docker.sock`（或环境变量 `DOCKER_HOST` 指向的 rootless socket）。

## 获取代码

```bash
git clone https://github.com/thomaswlh/lab-rl.git
cd lab-rl
```

本仓库只包含编排与镜像配方。训练代码仍放在各自平时使用的路径，进入容器后 `cd` 过去。

## 镜像

rootless Docker 的镜像库位于各账号自己的 `~/.local/share/docker`，不能在全机共享层。因此只构建一次，再分发 tarball。

维护者（需要外网与足够磁盘）：

```bash
bash scripts/build-images.sh
bash scripts/export-images.sh /path/to/shared/lab-rl-images.tar.gz
```

其余账号在 rootless daemon 已启动后：

```bash
docker load -i /path/to/shared/lab-rl-images.tar.gz
```

同一 Unix 账号共用一份 rootless 镜像库，load 一次即可。不同账号或不同机器各 load 一次。

`lab.sh` 在镜像缺失时不会自动 `compose build`。`doctor` 与 `up` 会提示先 load。

构建顺序与版本锁见 [stack.md](stack.md)。必须按以下顺序：cu128 torch → vLLM 0.19.1 → `--no-deps` megatron/verl → `constraints.txt` → `patches/`。重装 Megatron 相关包后需再执行 `patches/apply.sh`，说明见 [../patches/README.md](../patches/README.md)。

## 身份

| 场景 | `WHO` | `PERSON_HOME` | Compose 项目名 |
|---|---|---|---|
| 个人账号 `alice` | `alice` | `$HOME` | `alice-box` |
| 组账号（用户名以 `_team` 结尾），工作目录在 `$HOME/alice/...` | `alice` | `$HOME/alice` | `<unix>-alice-box` |

组账号从 `$PWD` 推断 `WHO`（`$HOME` 下第一级目录）。不在个人目录内启动时需显式指定：

```bash
./lab.sh up --name box --who alice
```

`up` 把 `PERSON_HOME` 按原路径挂进训练容器，无需再指定项目文件夹。进入容器后：

```bash
cd "$PERSON_HOME/workspace/your-project"
```

实例状态写在 `$PERSON_HOME/.lab/<name>/`（端口、Homer 配置、RL-Insight 数据）。

Hugging Face 缓存默认规则：若存在 `$HOME/.cache/huggingface` 则使用它（便于组账号共享缓存），否则使用 `$PERSON_HOME/.cache/huggingface`。可用环境变量 `HF_HOME` 覆盖。

## 日常操作

```bash
./lab.sh doctor
./lab.sh up --name box
./lab.sh url --name box
```

浏览器打开打印出的 Homer 地址。先核对标题与副标题，避免进入他人实例。

训练容器启动时全部 GPU 可见，不预占某一张卡。开训必须指定 `CUDA_VISIBLE_DEVICES`：

```bash
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv
CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name box -- bash scripts/run_sft.sh
```

未设置 `CUDA_VISIBLE_DEVICES` 时，`train` 会拒绝执行。

进入容器：

```bash
./lab.sh exec --name box
# 容器内
source /opt/lab/env.sh
cd "$PERSON_HOME/workspace/your-project"
python /opt/lab/check_env.py
```

停止训练或整栈：

```bash
./lab.sh stop-train --name box
./lab.sh down --name box          # 观测服务一并停止；状态与端口保留
```

`train` 加 `-d` 可后台运行，再用 `stop-train` 停止。

## 服务寿命

`lab.sh up` 之后 **obs 常驻**，不依赖是否正在训练。

| 服务 | 寿命 | Homer |
|---|---|---|
| Homer | 随 obs | 入口本身 |
| RL-Insight Grafana / Prometheus / Tempo | 常驻 | Grafana |
| TensorBoard | 常驻，无训练时也可看历史 | TensorBoard |
| Run logs | 常驻，只读 `$PERSON_HOME/logs` 与 `workspace/*/logs` | Run logs |
| Ray Dashboard | 仅 GRPO 期间 | 标明「仅 GRPO 期间在线」 |
| 训练进程 | `train` 才启动；SFT 不启动 Ray | — |

训练容器 `restart: no`，避免机器重启后自动占卡。obs 为 `unless-stopped`。

容器内端口固定：Homer `8080`、Grafana `3000`、TensorBoard `6006`、Ray `8265`、Run logs `8081`。宿主机从 **18000** 起按 10 递增，领取连续 5 个空闲端口，并用 `flock /tmp/lab-rl-ports.lock` 避免并发冲突。需要固定端口时：

```bash
LAB_PORT_BASE=18200 ./lab.sh up --name box
```

不要把宿主机端口写死为 `8080` / `3000` 等常见占用端口。

## 观测接入

本仓库不修改外部训练脚本。容器会注入下列环境变量，训练项目按需读取：

| 变量 | 默认 | 含义 |
|---|---|---|
| `RL_INSIGHT_SERVER_URL` | `http://obs:18080` | 训练进程走 compose DNS，与宿主机映射无关 |
| `TRAINER_LOGGER` | `console,tensorboard,rl_insight` | verl logger 列表 |
| `RAY_DASHBOARD_HOST` / `PORT` | `0.0.0.0` / `8265` | GRPO 中 Ray 需绑定该地址，Homer 才能打开 |
| `TENSORBOARD_LOGDIR` | `$PERSON_HOME/logs` | TensorBoard 扫描目录 |
| `HF_HOME` | 见上文 | Hugging Face 缓存 |

verl 侧若要启用 RL-Insight，在训练项目中设置 `trainer.logger='[console,tensorboard,rl_insight]'`。这不属于 lab-rl 的改动范围。

Grafana 默认匿名 Viewer（内网、无认证）。Ray Dashboard 在 GRPO 期间同样开放。

额外日志目录：

```bash
LAB_LOG_DIRS=/path/a/logs:/path/b/logs ./lab.sh up --name box
```

## 校外访问

Homer 监听实验室内网。在外网时：

```bash
./lab.sh url --name box
```

按输出的 `ssh -L` 做本地转发，然后在浏览器打开 `http://127.0.0.1:<Homer口>`。

隧道建立后，Homer 卡片仍可能写宿主机 IP。若打不开，将 URL 中的 host 改为 `127.0.0.1`，端口不变。也可以在 `up` 时指定 `--host 127.0.0.1`（仅适合本人走隧道）。

## doctor

- 只连接 `DOCKER_HOST` 或 `$XDG_RUNTIME_DIR/docker.sock`，不会回落到 `/var/run/docker.sock`
- 检查 `lab-train:latest` 与 `lab-obs:latest` 是否已 load
- 检查宿主机 `nvidia-smi`
- 检查 linger 是否开启

镜像构建只做 CPU import（`check_env.py --cpu-only`）。GPU 自检在 `doctor` 或进入容器之后进行。

## 明确不做（v1）

- Web Shell（共享机器、无认证）
- 独立 vLLM Playground / Control（GRPO 内的 vLLM 是进程内 engine，再起一份会抢卡）
- Loki / ELK
- 将用户加入 `docker` 组
- 日常由 `lab.sh` 构建镜像（体积约 40GB，按人数复制会占满磁盘）
