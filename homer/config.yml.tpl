---
title: "__LAB_NAME__"
subtitle: "__LAB_USER__ / __LAB_WHO__ · ports __PORT_HOMER__–__PORT_LOGS__"
documentTitle: "__LAB_NAME__ · lab-rl"
logo: "logo.png"
header: true
footer: false
columns: "3"
connectivityCheck: true

message:
  style: "is-info"
  title: "这是 __LAB_USER__/__LAB_WHO__/__LAB_NAME__ 的栈"
  icon: "fa fa-circle-info"
  content: "先对名字再点卡片。Ray Dashboard 只在 GRPO 期间在线；其余看板随 obs 常驻。"

links:
  - name: "usage"
    icon: "fas fa-book"
    url: "https://github.com/thomaswlh/lab-rl/blob/main/docs/usage.md"

services:
  - name: "Always on"
    icon: "fas fa-eye"
    items:
      - name: "RL-Insight Grafana"
        icon: "fas fa-chart-line"
        subtitle: "训练曲线 / traces · 常驻"
        tag: "live"
        tagstyle: "is-success"
        url: "http://__LAB_HOST__:__PORT_GRAFANA__"
        target: "_blank"
      - name: "TensorBoard"
        icon: "fas fa-wave-square"
        subtitle: "历史 run · 常驻"
        tag: "live"
        tagstyle: "is-success"
        url: "http://__LAB_HOST__:__PORT_TB__"
        target: "_blank"
      - name: "Run logs"
        icon: "fas fa-file-lines"
        subtitle: "只读 train.log · 常驻"
        tag: "live"
        tagstyle: "is-success"
        url: "http://__LAB_HOST__:__PORT_LOGS__"
        target: "_blank"

  - name: "During GRPO only"
    icon: "fas fa-bolt"
    items:
      - name: "Ray Dashboard"
        icon: "fas fa-circle-nodes"
        subtitle: "仅 GRPO 期间在线；SFT / 训完会离线"
        tag: "grpo"
        tagstyle: "is-warning"
        url: "http://__LAB_HOST__:__PORT_RAY__"
        target: "_blank"
        type: "Ping"
