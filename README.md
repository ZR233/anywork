# 历史会话视口加载：Linux 原生证据

代码提交：`bfd6821087d3762ca58db7e21479823b48e85890`，基于 main `37b9b59dc162096498f08cc45bc84a223674f1d7`。

截图来自 Linux 原生 GUI、隔离 v2 数据根、本地模拟供应商和真实 FRB，未使用 demo 或修改图片。只发布合成会话画面及筛选后的验证事实，不发布配置、凭据或完整数据目录。`screenshots.json` 记录逐图来源与 SHA256；主代理逐张打开关键截图核对。

## 运行范围

- `viewport-before-r3`：修改前基线 `6b14752f3c82eec3f46bbd71098127b1191d6ad6` 的定向截取，显示“加载更早消息”和空白区域；用于缺陷画面，未标为完整旧版本验收通过。该旧 fixture 的工具组为 30 项。
- `viewport-cold-delivery`：最终 Timeline、Client 与侧栏实现；同一保留数据根冷开，64 个原始条目自动补齐，六尺寸、900px、80px 拖动、方向键/Home、按键后失焦保存及 14 行未发送草稿。原生退出报告为实际程序状态。fixture 工具组为 40 项。
- `viewport-history-delivery`：最终提交上的 20,000 条事件（1,000/s）、History 暂不可读 Busy、后台完成期间冻结、界面重试、回到实时；重启前后各 40 页的有序身份与游标逐页匹配。`verification.json` 保留每页摘要及身份/游标 SHA256。两轮 Driver PID 与原生退出报告一致，均 code 0、无 signal、取消或遗留子进程。
- `viewport-sessions-delivery`：最终提交上的 5,000/s 压力与 16 会话、多轮 A/B/C、分页在途切换及打开在途的 A→B→A。保留真实 pending query、opening attempt 和退役回收的断言结果。功能断言与帧率阈值分别记录。
- `viewport-history-final-v2`：在 main `7c6b4d42` 上的功能工作树完成的完整输入矩阵：六尺寸各 96 次、三尺寸各 600 次、40 次连续输入及 8 次真实分页重叠输入。后续集成主线与 Client 关闭修复后，冷开、自适应、长历史及会话切换另行复验；完整矩阵的时点单独保留。
- `viewport-tool-scroll-r4`：真实工具、图片、复制/详情、嵌套滚轮/滚动条、14 次 PageUp 及折叠组补齐。
- `viewport-realtime-final`：在 main `7c6b4d42` 的功能工作树执行，History 直接发送建立新代次、供应商错误、取消/继续、冻结与显式回实时均通过。

## 复现入口

从代码提交的仓库根目录运行（本机为 Linux；Python 使用 python3）：

```sh
PUB_HOSTED_URL=https://pub.dev cargo xtask verify-client
PUB_HOSTED_URL=https://pub.dev cargo xtask verify-gui
PUB_HOSTED_URL=https://pub.dev cargo xtask build-gui --no-clean
PUB_HOSTED_URL=https://pub.dev GDK_BACKEND=x11 xvfb-run -a -s '-screen 0 1920x1200x24' cargo xtask manual-gui --scenario timeline-history --retain-environment --output target/manual-gui/history
PUB_HOSTED_URL=https://pub.dev GDK_BACKEND=x11 xvfb-run -a -s '-screen 0 1920x1200x24' cargo xtask manual-gui --scenario timeline-history --timeline-displacement --output target/manual-gui/input-matrix
```

压力场景使用可交互终端运行 `cargo xtask manual-gui --scenario stress`，按提示输入 `done`，协调器会等待真实 probe 完成后执行 16 会话旅程。冷开和窗口入口是代码中的 `timeline_adaptive_journey.dart`，按设计文档传入同一 home 下已有会话的 baseline snapshot，并继承 GUI 的 DISPLAY/XAUTHORITY。

`driver_deadline_probe.dart` 是本次额外的宿主故障探针，不作为真实 GUI 证明。复制到代码检出的 `target/gui-acceptance/driver_deadline_probe.dart` 后，用 `cargo dart --packages=.dart_tool/package_config.json ../../target/gui-acceptance/driver_deadline_probe.dart` 运行；旧 Driver 的默认期限/挂起拖动均失败，修复后验证超时关闭、一次派发且不重放。

## 限制

代码门禁全部通过；额外 Widget 回归不纳入仓库默认门禁。人工 verdict 保持 `pending`。

默认 Xvfb/Impeller 软件光栅环境中，stress 帧率阈值未通过，CLI 因帧率返回 1；没有有效的旧版本帧率对照，未证明硬件加速性能。准确帧数、慢帧、最大帧时和响应采样见 `verification.json`。普通功能断言、错误检查和输入矩阵结果分别列出。

Windows/macOS 原生 GUI 和真实供应商兼容未在本机人工验证。CI 的 Windows 检查结果由 PR 当前 head 单独跟踪，不把 Linux 原生结果外推为跨平台 GUI 通过。
