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
  title: "__LAB_USER__ / __LAB_WHO__ / __LAB_NAME__"
  icon: "fa fa-circle-info"
  content: "先對一下標題，別進錯人的實例。Ray 只有 GRPO 在跑時才開；Grafana、TensorBoard、記錄一直在。"

links:
  - name: "usage"
    icon: "fas fa-book"
    url: "https://github.com/thomaswlh/lab-rl/blob/main/docs/usage.md"

services:
  - name: "一直開著"
    icon: "fas fa-eye"
    items:
      - name: "RL-Insight Grafana"
        icon: "fas fa-chart-line"
        subtitle: "訓練曲線 / traces · 一直開著"
        tag: "live"
        tagstyle: "is-success"
        url: "http://__LAB_HOST__:__PORT_GRAFANA__"
        target: "_blank"
      - name: "TensorBoard"
        icon: "fas fa-wave-square"
        subtitle: "舊的 run · 一直開著"
        tag: "live"
        tagstyle: "is-success"
        url: "http://__LAB_HOST__:__PORT_TB__"
        target: "_blank"
      - name: "Run logs"
        icon: "fas fa-file-lines"
        subtitle: "只讀 train.log · 一直開著"
        tag: "live"
        tagstyle: "is-success"
        url: "http://__LAB_HOST__:__PORT_LOGS__"
        target: "_blank"

  - name: "只有 GRPO"
    icon: "fas fa-bolt"
    items:
      - name: "Ray Dashboard"
        icon: "fas fa-circle-nodes"
        subtitle: "只有 GRPO 在跑時才開；SFT 或訓練結束會離線"
        tag: "grpo"
        tagstyle: "is-warning"
        url: "http://__LAB_HOST__:__PORT_RAY__"
        target: "_blank"
        type: "Ping"
