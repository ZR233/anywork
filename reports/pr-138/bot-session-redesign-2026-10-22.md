# PR #138 机器人界面与会话协作验收

平台为 Windows x64、Flutter 3.47.7。已合入 main 的 `d3bc7418`。
真实飞书与模型验证使用独立 StudioHome，未替换用户的日常数据。

## 实现范围

- 总览、机器人详情、聊天逐级导航，详情隐藏上级列表；返回保留筛选和滚动位置。
- 详情集中展示连接、打开飞书聊天、模型、思考强度与最近聊天；授权、凭据和平台工具按需展开。
- 复用现有模型组件和会话时间线。机器人模型配置统一控制后续输入，普通聊天入口跳转机器人设置。
- 每个机器人自动建立受管工作区，每个飞书聊天保留独立 Thread。
  上传、scratch、产物、命令输出和按需创建的 `.venv` 使用现有 Thread 文件布局。
- 平台配置改为带标签的枚举，当前仅开放飞书；保留机器人、凭据、绑定和历史身份，迁移可接续。
- 安装 `list_sessions`、`get_session`、`search_session_messages`、
  `read_session_messages`、`send_session_message` 五项 Studio 产品工具。
  搜索读取正文；发送复用普通输入受理链与稳定身份，附件通过来源会话的可靠引用导入。
- 飞书文件与图片在授权检查后下载并经过既有附件准入、归档和提交链。
  OpenAI Responses 文件编码及缓存模型能力投影同步完善。

## 真实操作与结果

| 验收 | 实际结果 |
| --- | --- |
| 客户端授权 | 从原生界面拉起本机飞书，创建新应用并授权成功；本地状态 completed，自动创建工作区，没有选择业务项目 |
| 页面导航 | Driver 操作总览、详情、聊天、返回；筛选“飞书”返回后仍在，聊天隐藏上级列表 |
| 模型配置 | 实际切换 GPT-6 Sol 与 GPT-6.1 Sol、medium 与 high；核对 canonical 配置及重启后结果 |
| 归属入口 | 普通聊天显示“由机器人统一设置”，点击进入对应机器人详情 |
| 布局 | 查看 1898×1024、800×850、长名称及 Windows 150% 文字大小截图；修正放大文字后的字段截断，系统文字大小已恢复 100% |
| 跨项目查询 | 飞书调用列表、状态、中文正文搜索及历史读取，找到其他项目的 Fixture Ready Reply；搜索“青山白云”返回真实正文命中 |
| 文字代发 | 通过 send_session_message 提交到目标会话，受理成功；重启后再次代发，目标实际回复“会话协作验证通过”，回复已保存 |
| 文件与图片 | 本机飞书发送 92 字节中文文本和 600×360 PNG；机器人转交目标会话，目标保存两份可靠附件 |
| 内容一致性 | 原件、来源会话和目标会话的 SHA-256 相同；重启后再次核对四份可靠引用，收发账本未重复投递 |
| 模型读取附件 | HTTP 模式读取原有两个附件，返回完整中文文件内容与正确图片描述 |
| Python 环境 | 真实飞书指令执行 uv venv，在机器人 Thread 专用 `.venv` 启动 Python；sys.prefix 与该路径一致，输出 PR138-UV-PASS，未修改全局 Python |
| 正常退出 | 第 9 次真实 GUI 经 Driver 请求退出，cleanExit、pending=0、440 ms；验收所属进程回收 |

文本附件内容：

```text
PR138-FILE-20261022
中文附件转交验证：青山白云，文件原文保持一致。
```

文本 SHA-256：`fdde6b4a5f187e6dd4ee45a50780855207b704f1dae7aa763c5c0669508a5072`。
图片 SHA-256：`8b9f02041b6bf96c796f499e1d9449812d22568da748658419d43e387b4d780b`。

## 验收中修正的问题

- 首次入站附件在终态身份尚未落盘时可能重复建立草稿；现在驻留输入及 terminal identity
  共同表示已受理，等待持久化，不重复提交。
- 桌面提交先校验旧路由 revision，再应用机器人配置，避免自身更新造成错误的过期判断。
- StudioHome 位于 Git 仓库内时，普通项目的向上 Git 根发现会扩大机器人执行目录；
  机器人根会话、子会话和冷恢复现在使用受管目录本身，并发布当前工作区运行时事实。
- 模型保存期间禁用选择器，保存结束后按 canonical 配置重建瞬态选中文字；失败不会留下未保存值。
- 150% 文字大小下思考强度字段被截断；布局阈值和字段宽度现随文字大小调整。
- 上一版 Linux CI 的存储恢复用例缺少 `pl-remote-helper`；作业增加仓库规定的 worker 安装步骤，保留完整测试。
- `107e3f94` 的 CI 中 Rust、Linux Studio、标题和发布配置通过，Flutter 因缓存安装元数据
  误报 FRB 已安装、实际找不到程序而失败。预编译工具安装增加官方
  [`--force` 选项](https://github.com/cargo-bins/cargo-binstall/blob/v1.26.0/crates/bin/src/args.rs#L345-L347)，
  PR、RC 和发布工作流使用同一契约，不改变工具版本或恢复源码回退。

## 自动检查与人工入口

| 命令 | Windows 本地结果 |
| --- | --- |
| `cargo fmt --all --check` | 通过 |
| `cargo clippy --workspace --all-targets -- -D warnings` | 通过 |
| `cargo test -p pl-model` | 200 passed |
| `cargo test -p pl-core --features sqlite` | 188 passed |
| `cargo test -p pl-studio-runtime` | 177 passed |
| `cargo xtask verify-client` | Client 207、adapter 227 passed |
| `cargo xtask verify-gui` | 首轮通过；收尾复跑受 Windows 文件占用阻断，见下文 |
| `cargo xtask manual-gui --scenario gui` | 原生空机器人界面与 fixture 消息回复经 Driver 操作、看图；clean/drained，issues=[]，请求 accepted=2、rejected=0 |
| `git diff --check` | 通过 |
| `actionlint 1.7.12` | PR、RC、发布工作流静态检查通过 |

manual-gui 原始机器报告的人工判定字段保持 pending，本报告记录本轮人工观察结论。
真实飞书结果独立于该模拟供应商报告。Linux GUI 与仅支持 Linux 的飞书协议观察入口未在本机运行；
CI 终态以 PR 对应 head 的检查记录为准，不将排队或运行中状态计为通过。

收尾复跑生成检查时，Dart 格式化部分生成文件返回 Windows error 1224
（文件被用户映射区域占用），因此 canonical 稳定性检查失败。重复执行仍能遇到此问题，
失败日志保留；没有手工修补生成文件，也没有把这些失败算作通过。最后通过统一生成入口
及仓库格式入口恢复输出，再分别检查 Dart 格式（368 文件零改动）和 analyze（无问题）；
最终提交的干净环境生成验证由 PR CI 记录。

在 `107e3f94` 上另补跑 `manual-gui --scenario gui`：Driver 查看空机器人页、返回主界面、
建立项目并发送 fixture 消息，实际显示 `fixture ready`；所属进程退出后核对独立退出报告。
本次证据位于同目录的 `manual-head/`，原有 `manual-final/` 保留。

## 已确认的外部限制

- 当前 OpenAI-compatible 服务的 Responses WebSocket 文件输入返回 HTTP 400
  `unsupported_parameter`，服务提示不支持所需文件预处理。错误保持可见；通过账号界面
  明确切换 HTTP 后成功，不以 wire 模拟测试代替真实服务兼容，也未增加静默自动降级。
- 深层仓库内验收目录生成的 Windows Python 虚拟环境可以创建，但启动其解释器失败
  （`Unknown error (0xfffffffe)` / `os error 267`）。正常长度独立 StudioHome 中
  同一 uv 与 Python 实际运行成功。原长路径现场保留，没有更改系统长路径策略或全局 Python。
  验收使用 uv 0.13.5；本次并未将 uv 分发器加入产品。
- 调试过程中曾有 Driver 超时和非正常退出，原始日志保留；这些尝试不计为 clean。
  最终正常退出和 manual-gui 的 clean 结果分别有独立证据。

## 证据

截图、原始日志、快照、文件样本和哈希证明保存在忽略目录
`target/manual-gui/pr138-bot-redesign-20261022/`，不提交图片或原始日志。
其中 `attachment-byte-proof.json`、`restart-after.json`、`final-home-proof.json`
记录附件一致性；`manual-final/` 保留模拟验收请求、截图与退出报告。
精选截图通过 GitHub PR 附件提供；二维码、凭据、个人聊天列表和带宿主路径的截图不公开。

- [总览与返回筛选](https://github.com/user-attachments/assets/164392b3-2151-44f3-a896-1a77ac4ce52d)
- [机器人详情](https://github.com/user-attachments/assets/818c34a1-eb0c-4190-b717-4d34bc421d06)
- [窄窗口与长名称](https://github.com/user-attachments/assets/ec15f664-7f47-4dd3-9dfb-366f7c51211f)
- [150% 文字大小的模型设置](https://github.com/user-attachments/assets/3a823b3e-7208-410e-acaf-316e4a5e7235)
- [跨项目中文搜索和附件历史](https://github.com/user-attachments/assets/b64b13d0-d39b-4c0b-956e-0d71f829e452)
- [重启后的真实文字代发和目标回复](https://github.com/user-attachments/assets/9db3cfd4-e90f-40c9-b863-0feac80dace7)
