# lab-rl

实验室共享机上的通用 RL 训练环境：rootless Docker + Homer 观测入口。

冻住的栈是 **verl 0.9 + Megatron + vLLM + Ray**（见 [docs/stack.md](docs/stack.md)）。项目目录按原路径挂进容器，进壳自己 `cd`。不绑死某一个仓库。

```bash
git clone https://github.com/thomaswlh/lab-rl.git
cd lab-rl
./lab.sh doctor
./lab.sh up --name box
./lab.sh exec --name box
```

`up` 会打印 Homer 地址。浏览器只记那一个入口。完整用法、组账号、`docker load`、校外 SSH 隧道见 [docs/usage.md](docs/usage.md)。

## 日常命令

| 命令 | 作用 |
|---|---|
| `./lab.sh doctor` | 查 rootless socket、镜像、宿主机 GPU |
| `./lab.sh up --name box` | 领端口，拉起 obs（常驻）+ train（待命） |
| `./lab.sh exec --name box` | 进训练容器 |
| `CUDA_VISIBLE_DEVICES=2 ./lab.sh train --name box -- bash scripts/run_sft.sh` | 开训（必须选卡） |
| `./lab.sh stop-train --name box` | 停训 |
| `./lab.sh url --name box` | 打 Homer / 看板 URL 和 `ssh -L` |
| `./lab.sh list` | 看自己的实例 |
| `./lab.sh down --name box` | 停容器，保留端口和状态 |

## 现在还做不了的

镜像大约 40GB，**等学长配好 rootless Docker**（user `docker.service`、`enable-linger`、`nvidia-ctk` + `no-cgroups`）之后再 `scripts/build-images.sh`。`lab.sh` 不负责日常 build。

v1 不做：Web Shell、vLLM Playground、Loki、把用户加进 `docker` 组。
