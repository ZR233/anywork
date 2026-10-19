# 等待界面原生验收截图

源码提交：`64177427bbc7c29055e14352aa29d4ea75e1bb6a`。本分支仅保存已由主代理实际查看的合成场景截图，不进入功能分支源码 diff。

## 实际范围

- Linux 原生 GTK / Xvfb，本地模拟供应商与真实 Bridge、工具和隔离持久化。
- 当前基线正常旅程：75 项检查全部为真，30 次 fixture 请求无拒绝，GUI 无未处理错误。
- 定时器先就绪、命令先就绪、子代理消息唤醒非空任务等待、已就绪、正常超时、跨 Turn 取消均通过。
- 同一合成 home 冷重开后，Tab 24 次到达真实等待卡标题，Enter 展开、Space 收起；公共 PlatformDispatcher 与实际标题上下文 MediaQuery 都为减少动画 true、文字缩放 1.3。
- 窄窗口 640×700，长展开面板通过正常垂直滚动查看；折叠数量与摘要、展开来源及任一就绪规则可读。
- 等待组件字节不变的减少动画 profile 旅程另有 75 项检查全绿；等待脉冲存在期间无持续动画回调，标题高度由正常 15 增为 19。
- 所属 GUI、Driver、helper、私有 D-Bus/Portal 与 Xvfb 进程均已按 PID/启动身份确认退出。

截图仅有合成任务与命令，不含凭据、用户会话、配置、VM 地址或原始快照。未验证 Windows 原生 GUI 或真实付费供应商。

## 图片

- [live-wait-expanded.png](screenshots/live-wait-expanded.png)
- [tool-first-history.png](screenshots/tool-first-history.png)
- [timeout-history.png](screenshots/timeout-history.png)
- [keyboard-enter-large-text.png](screenshots/keyboard-enter-large-text.png)
- [narrow-large-text-collapsed.png](screenshots/narrow-large-text-collapsed.png)
- [narrow-large-text-sources.png](screenshots/narrow-large-text-sources.png)
