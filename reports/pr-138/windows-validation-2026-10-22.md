# PR #138 Windows 合并验证

本次将 `main` 的 `436f42210e34aaecf633006612cb39def2f3784d` 合入 PR head，
保留原生飞书机器人功能，并适配项目级会话存储、更新器接口和生成的 bridge。

## 修复范围

- 历史库读写继续共用 PR 的初始化锁与共享句柄，同时使用 main 的 Project + Thread 路径和身份校验。
- checkpoint 恢复、子会话准备和迁移测试同步使用上述存储入口。
- 机器人 SQLite 库改用已有的原生文件路径连接接口，保留 WAL、FULL 同步、外键和连接池约束。
- 合并存储与 crate 职责文档，并通过统一生成入口重新生成 FRB/Dart 文件。

## 本地自动检查

平台：Windows x64。以下命令均通过：

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all --check` | 通过 |
| `cargo clippy --workspace --all-targets -- -D warnings` | 通过 |
| `cargo test -p pl-model` | 198 passed |
| `cargo test -p pl-core --features sqlite` | 188 passed |
| `cargo test -p pl-studio-runtime --locked` | 173 passed |
| `cargo xtask verify-client` | Client 205、Flutter adapter 224 passed |
| `cargo xtask verify-gui` | 生成一致性、格式与 analyze 通过 |

第一次 GUI 生成检查与原生编译被并行启动，Windows 文件映射锁导致 5 个生成文件格式化写入失败；
停止这两个命令后串行重新生成并复检通过。该次失败不计作通过。

## Windows 隔离 GUI 观察

执行 `cargo xtask manual-gui --output target/manual-gui/pr138-windows-smoke-20261022`，
通过 Driver 打开本地项目并发送 `Reply with exactly: fixture ready`。
实际界面显示 `fixture ready`，本轮状态为 `completed`，快照中的 4 个历史项均已保存。
本地模型 fixture 接受 2 个请求、拒绝 0 个；关闭报告为 `clean` / `drained`，无 issues，
验收命令退出码为 0，所属 GUI、Flutter 与 fixture 进程已回收。
截图、快照、请求与日志保存在上述目录；harness 的人工结论字段保持 `pending`。
这些观察只覆盖本地模拟模型，不证明真实飞书消息闭环。

## 真实飞书边界

通过 `cargo xtask run-gui --driver --native-launch` 启动真实 bridge，使用 Flutter Driver
打开机器人页、填写名称、核对项目与模型配置、确认远程工具风险并发起注册。
真实飞书注册服务返回成功，状态从 `preparing` 进入 `waiting`，界面显示“等待扫码”与二维码，
后续轮询保持等待状态。随后通过界面取消，canonical snapshot 变为 `cancelled`，机器人列表为空。
通过应用退出协调器关闭后，原生退出码为 0，无剩余或强制回收的子进程。

本机飞书已运行且已登录。开发者后台仍要求独立扫码登录。
Computer Use 因无法可靠识别当前浏览器 URL 而停止本轮操作，随后停止网页与飞书客户端自动操作。
未完成手机授权、机器人创建、客户端入站消息、模型回复或主动发消息的完整真实闭环；
自动检查不能替代这些实际结果。

GUI 验证使用独立 `ANYWORK_HOME` 和验收工作区，沿用已有配置的凭据关联，
不复制正在使用的历史库。日志、快照及临时 Driver 脚本仅保存在忽略的
`target/manual-gui/pr138-feishu-live-20261022/`，不提交授权二维码、票据或私有配置。

Linux 专用的 `--bots-fixture` 未在 Windows 上执行，跨平台与真实平台兼容结论仍待验证。
