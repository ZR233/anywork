# PR #112 证据：生图工具真实配置实测

- 采集方式：`xvfb-run -a -s "-screen 0 1440x900x24" cargo xtask run-gui --driver`
  启动真实配置 GUI（未设置 `ANYWORK_HOME`、未使用 `--demo`），再由
  `cargo dart run test_driver/image_generation_journey.dart <VM_URL> <PROJECT> <PROMPT> <OUT>`
  切换 `mode.task` 与 `openai/gpt-6.1-sol`、提交提示词、等待 `generate_image` 终态、
  展开工具组与图片条目后截图，最后经 Driver 请求优雅关停。
- 采集时间：2026-10-19T15:24:41Z（UTC）。
- 对话 provider：`openai`，`base_url` 主机 `ai.muxai.net`；在线 `/v1/models` 返回 19 个
  模型，其中 5 个 `gpt-image-*`。
- 工具调用：`generate_image` 成功，附件 modality `image`、2,292,105 bytes。
- 截图内容：Studio 时间线中 `generate_image completed` 工具组与 `1 image` 展开后的生成图、
  Tool activity 计数与模型选择器；界面不含凭据或配置页。
- `evidence.json` 为 Driver 脚本写出的工具调用身份与附件元数据（不含提示词正文、资源字节或凭据）。
- 同一轮 GUI 正常关停（`shutdown_completed`，退出码 0），未残留进程。
