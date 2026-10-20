# PR #112 证据：生图工具真实配置实测

## 1. 同步生图（首版证据）

- 采集方式：`xvfb-run -a -s "-screen 0 1440x900x24" cargo xtask run-gui --driver`
  启动真实配置 GUI（未设置 `ANYWORK_HOME`、未使用 `--demo`），再由
  `cargo dart run test_driver/image_generation_journey.dart <VM_URL> <PROJECT> <PROMPT> <OUT>`
  切换 `mode.task` 与 `openai/gpt-6.1-sol`、提交提示词、等待 `generate_image` 终态、
  展开工具组与图片条目后截图，最后经 Driver 请求优雅关停。
- 采集时间：2026-10-19T15:24:41Z（UTC）。
- 对话 provider：`openai`，`base_url` 主机 `ai.muxai.net`；在线 `/v1/models` 返回 19 个
  模型，其中 5 个 `gpt-image-*`。
- 工具调用：`generate_image` 成功，附件 modality `image`、2,292,105 bytes。
- 截图 `timeline.png`：Studio 时间线中 `generate_image completed` 工具组与 `1 image`
  展开后的生成图；`evidence.json` 为该轮工具调用身份与附件元数据。
- 同一轮 GUI 正常关停（`shutdown_completed`，退出码 0），未残留进程。

## 2. 异步生图 + 图片展示卡片（本轮证据）

- 同一采集方式；提示词要求"先生成（后台任务）、用 `wait` 等待、再用 `show_image` 展示"。
- 采集时间：2026-10-20T00:02:23Z（UTC）。
- 链路事实：`generate_image` 以后台任务受理（运行回执 → 收件箱终态），模型调用
  `wait {"taskIds":["task:call_65a78c68…"]}`，随后调用 `show_image`
  `{"caption":"日落海滩上的柴犬"}`；`show_image` 成功并投影出图片附件 2,342,369 bytes。
- `image-card.png`：时间线中的独立图片展示卡片（头部标题、`Completed` 状态胶囊、大图）。
- `image-card-caption.png`：同一卡片向下滚动后的图片与说明文案「日落海滩上的柴犬」。
- `image-card-dialog.png`：点击卡片图片打开的可缩放全屏视图与关闭按钮。
- `image-card-evidence.json`：两次工具调用的身份、附件元数据与 caption（不含提示词正文、
  资源字节或凭据）。
- 同一轮 GUI 正常关停，未残留进程。
