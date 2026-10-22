# PR #138 Windows 合并验证

本次将 `main` 的 `436f42210e34aaecf633006612cb39def2f3784d` 合入 PR head，
保留原生飞书机器人功能，并适配项目级会话存储、更新器接口和生成的 bridge。

## 修复范围

- 历史库读写继续共用 PR 的初始化锁与共享句柄，同时使用 main 的 Project + Thread 路径和身份校验。
- checkpoint 恢复、子会话准备和迁移测试同步使用上述存储入口。
- 机器人 SQLite 库改用已有的原生文件路径连接接口，保留 WAL、FULL 同步、外键和连接池约束。
- 合并存储与 crate 职责文档，并通过统一生成入口重新生成 FRB/Dart 文件。
- 注册尝试独立显示在页面顶部，切换设置页后仍可继续，等待期间可直接取消。
- 采用 Flutter 官方 `url_launcher 6.3.3` 检测和打开飞书协议；未检测到可用客户端时
  引导手机扫码，始终保留二维码与浏览器入口。外部链接统一迁入该插件，发布说明入口同步调整。
- 按飞书官方 AppLink 协议增加客户端内创建应用、打开机器人聊天入口；授权 URL 与 App ID
  按单一 query 值编码，并限制真实客户端的授权来源，不回显含票据的打开失败异常。

## 本地自动检查

平台：Windows x64。以下命令均通过：

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all --check` | 通过 |
| `cargo clippy --workspace --all-targets -- -D warnings` | 通过 |
| `cargo test -p pl-model` | 198 passed |
| `cargo test -p pl-core --features sqlite` | 188 passed |
| `cargo test -p pl-studio-runtime --locked` | 173 passed |
| `cargo xtask verify-client` | Client 205、Flutter adapter 226 passed |
| `cargo xtask verify-gui` | 生成一致性、格式与 analyze 通过 |

第一次 GUI 生成检查与原生编译被并行启动，Windows 文件映射锁导致 5 个生成文件格式化写入失败；
停止这两个命令后串行重新生成并复检通过。该次失败不计作通过。
流程改进后重新执行了上表全部检查。生成阶段还遇到一次 `rustfmt` 文件映射占用，串行
重跑成功；统一链接入口的初次检查发现发布说明调用方漏迁移，修复后完整复检通过。

## Windows 隔离 GUI 观察

执行 `cargo xtask manual-gui --output target/manual-gui/pr138-windows-smoke-20261022`，
通过 Driver 打开本地项目并发送 `Reply with exactly: fixture ready`。
实际界面显示 `fixture ready`，本轮状态为 `completed`，快照中的 4 个历史项均已保存。
本地模型 fixture 接受 2 个请求、拒绝 0 个；关闭报告为 `clean` / `drained`，无 issues，
验收命令退出码为 0，所属 GUI、Flutter 与 fixture 进程已回收。
截图、快照、请求与日志保存在上述目录；harness 的人工结论字段保持 `pending`。
这些观察只覆盖本地模拟模型，不证明真实飞书消息闭环。

流程改进后再次运行 `cargo xtask manual-gui --output target/manual-gui/pr138-onboarding-smoke-20261022`，
同样通过 Driver 完成实际输入与回复观察。fixture 接受 2 个请求、拒绝 0 个，4 个历史项，
退出报告为 `clean` / `drained`，issues 为空，命令退出码 0，所属进程已回收。

## 真实飞书边界

通过 `cargo xtask run-gui --driver --native-launch` 启动真实 bridge，使用 Flutter Driver
打开机器人页、填写名称、核对项目与模型配置、确认远程工具风险并发起注册。
真实飞书注册服务返回成功，状态从 `preparing` 进入 `waiting`，界面显示“等待扫码”与二维码，
后续轮询保持等待状态。随后通过界面取消，canonical snapshot 变为 `cancelled`，机器人列表为空。
通过应用退出协调器关闭后，原生退出码为 0，无剩余或强制回收的子进程。

后续使用新版 `cargo xtask run-gui --driver --native-launch` 重新发起真实注册：

- 系统成功检测到本机已安装的飞书，界面显示“打开飞书继续”，同时保留可扫描二维码。
- 通过 Driver 切换到账号页再返回，确认 registration attempt ID 不变、授权面板仍可见。
- 点击新入口后，真实飞书打开独立的开放平台窗口，直接复用客户端登录状态进入
  “创建飞书智能体应用”页面，无需开发者后台独立扫码登录。
- 填写 `anywork PR138 验证` 并进入最终应用权限确认页；当前已交给用户点击“创建”。
  这一步尚未完成，因此机器人凭据回传、连接、真实入站、模型回复和主动发消息仍未验证。

未卸载用户飞书，未把当前结果视为无客户端环境或手机扫码授权完成的实际验证。
上述扫码分支已实现，授权参数保真与来源边界由 adapter 测试覆盖。

GUI 验证使用独立 `ANYWORK_HOME` 和验收工作区，沿用已有配置的凭据关联，
不复制正在使用的历史库。日志、快照及临时 Driver 脚本仅保存在忽略的
`target/manual-gui/pr138-feishu-live-20261022/`，不提交授权二维码、票据或私有配置。

Linux 专用的 `--bots-fixture` 未在 Windows 上执行，跨平台与真实平台兼容结论仍待验证。
