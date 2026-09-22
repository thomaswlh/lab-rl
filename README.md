# lab-rl

共享 GPU 机器上的通用强化学习训练环境。通过 rootless Docker 隔离训练与观测服务，浏览器只记一个 Homer 入口。

本仓库提供编排脚本与镜像配方，不绑定具体训练项目。用户主目录按宿主机原路径挂入训练容器，进入后自行 `cd` 到项目目录即可。

锁定训练栈为 **verl 0.9 + Megatron + vLLM + Ray**，版本与安装顺序见 [docs/stack.md](docs/stack.md)。

## 快速开始

```bash
git clone https://github.com/thomaswlh/lab-rl.git
cd lab-rl
./lab.sh doctor
./lab.sh up --name box
./lab.sh exec --name box
```

`up` 会打印 Homer 地址。完整用法、账号模型、镜像分发与校外隧道见 [docs/usage.md](docs/usage.md)。

使用前需完成本机 rootless Docker 与 NVIDIA Container Toolkit 配置，见 [docs/usage.md](docs/usage.md#宿主机准备)。日常不要在本机 `compose build`；由一名维护者构建后导出，其余人 `docker load`。

## 命令

| 命令 | 作用 |
|---|---|
| `./lab.sh doctor` | 检查 rootless socket、镜像与宿主机 GPU |
| `./lab.sh up --name box` | 分配端口，启动 obs（常驻）与 train（待命） |
| `./lab.sh exec --name box` | 进入训练容器 |
| `CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name box -- bash scripts/run_sft.sh` | 启动训练（必须指定 GPU） |
| `./lab.sh stop-train --name box` | 停止训练进程 |
| `./lab.sh url --name box` | 打印 Homer / 看板 URL 与 `ssh -L` 隧道 |
| `./lab.sh list` | 列出当前身份下的实例 |
| `./lab.sh down --name box` | 停止容器，保留端口与状态 |

## 文档

| 文档 | 内容 |
|---|---|
| [docs/usage.md](docs/usage.md) | 宿主机准备、镜像分发、日常操作、观测接入 |
| [docs/stack.md](docs/stack.md) | 锁定版本与安装顺序 |
| [patches/README.md](patches/README.md) | 无 Transformer Engine 补丁 |

## 范围（v1）

不做 Web Shell、独立 vLLM Playground、Loki / ELK，也不把用户加入 `docker` 组。`lab.sh` 不负责日常镜像构建。
