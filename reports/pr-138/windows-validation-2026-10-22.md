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
- 将真实遇到的飞书 `21001` 从通用服务不可用改为不可自动重试的权限错误，保留平台码，
  返回 `checkTenantAccessPolicy` 指引。界面显示访问控制原因、错误码和开发者后台入口。
- 升级至当前 OAuth 租户令牌接口，保留非 2xx 业务错误码，按官方含义区分消息权限错误。
- 修复 canonical 项目定义已保存而 SQLite 镜像缺失时，机器人首条消息创建会话的外键失败。

## 本地自动检查

平台：Windows x64。以下命令均通过：

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all --check` | 通过 |
| `cargo clippy --workspace --all-targets -- -D warnings` | 通过 |
| `cargo test -p pl-model` | 198 passed |
| `cargo test -p pl-core --features sqlite` | 188 passed |
| `cargo test -p pl-studio-runtime` | 174 passed |
| `cargo xtask verify-client` | Client 205、Flutter adapter 226 passed |
| `cargo xtask verify-gui` | 生成一致性、格式与 analyze 通过 |

第一次 GUI 生成检查与原生编译被并行启动，Windows 文件映射锁导致 5 个生成文件格式化写入失败；
停止这两个命令后串行重新生成并复检通过。该次失败不计作通过。
流程改进后重新执行了上表全部检查。生成阶段还遇到一次 `rustfmt` 文件映射占用，串行
重跑成功；统一链接入口的初次检查发现发布说明调用方漏迁移，修复后完整复检通过。
访问策略提示修复后的首次生成检查还遇到 Dart 格式化文件映射占用，检查正确拒绝不一致
输出；再次通过统一入口生成，随后生成一致性、格式和 analyze 均通过。
OAuth 升级与真实收信缺陷修复后，上表全部检查再次通过；Studio 新增 1 项保存/恢复回归，
其余测试数量保持一致。日志为 `target/manual-gui/pr138-feishu-live-20261022/final-gate-{1..7}.log`。
当前生成输出与已提交版本一致，没有手改生成文件。

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

访问策略提示修复后执行 `cargo xtask manual-gui --output target/manual-gui/pr138-policy-smoke-20261022`，
通过 Driver 再次观察到 `fixture ready` 回复；fixture 接受 2 个请求、拒绝 0 个。
退出报告为 `clean` / `drained`，issues 为空，命令退出码 0，所属进程已回收。

OAuth 与目录镜像修复后执行
`cargo xtask manual-gui --output target/manual-gui/pr138-oauth-smoke-20261022`：
Driver 完成打开项目、创建会话、发送与观察 `fixture ready` 回复；模型 fixture 接受 2 个
请求、拒绝 0 个。退出报告为 `clean` / `drained`，issues 为空，验收退出码 0；所属 GUI、
Flutter 和 fixture 已回收。harness 人工结论字段仍为 `pending`，本段记录本次实际观察。

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
- 填写 `anywork PR138 验证` 并进入最终应用权限确认页，由用户手动点击“创建”。
  飞书页面随后显示“创建成功”；canonical registration 为 `completed`，机器人已保存，
  credential 为 `stored`，注册账号已绑定为 1 个可信用户。
- 首次连接失败，显式重试后仍失败。通过当前进程的只读 Dart VM 对象检查取得安全字段：
  `platformCode=21001`、旧分类 `unavailable`、`retryable=false`。
  [官方 CLI 分类](https://github.com/larksuite/cli/blob/main/internal/errclass/codemeta.go)
  将该码标为 `policy/access_denied`；据此修正分类与用户指引。
  当前证据无法进一步确定拒绝由哪项账号或组织策略触发。
- 点击“在飞书中打开聊天”，本机飞书确实打开了新机器人的对应会话。
- 注册、凭据保存、首用户关联和聊天唤起已验证；平台访问控制仍阻止连接，
  真实消息进入 runtime、模型回复与主动发送尚未走通，不能记为成功。

上述原生进程通过应用退出协调器关闭，退出码 0，剩余和强制回收子进程均为空。
隔离验证 home 与已创建机器人的配置及凭据关联保留，待平台允许后继续使用同一机器人重试。

错误提示修复后，用同一隔离 home 再次原生启动复验：

- 同一机器人成功恢复，凭据仍为 `stored`，可信用户数仍为 1。
- 只读 Dart VM 检查确认连接诊断为 `permission` / `21001` / `retryable=false`。
- Driver 截图确认界面显示中文访问控制拒绝原因、平台码、管理员处理说明和后台入口，
  聊天唤起入口仍可见；截图位于 `target/manual-gui/pr138-feishu-live-20261022/policy-denied.png`。
- 通过应用退出协调器正常关闭，`policy-exit-report.json` 为退出码 0，无剩余或回收子进程。

未卸载用户飞书，未把当前结果视为无客户端环境或手机扫码授权完成的实际验证。
上述扫码分支已实现，授权参数保真与来源边界由 adapter 测试覆盖。

### 已登录开发者后台的进一步核查

用户在 Edge 登录后，于同日继续检查当前应用：

- 后台显示应用已启用、当前修改均已发布，所属身份为“豆包账号”。
- 安全设置中没有 IP 白名单条目。
- `im:chat:readonly`、`im:message.group_at_msg:readonly`、
  `im:message.p2p_msg:readonly`、`im:message:readonly`、
  `im:message:send_as_bot` 五项应用身份权限均显示已开通。
- 事件订阅采用长连接，已订阅 `im.message.receive_v1`。
- 服务端日志确认失败发生于 `POST /open-apis/auth/v3/tenant_access_token/internal`，
  HTTP 200、业务错误码 `21001`；平台原文为
  “Access denied due to platform policy. If you have questions, contact customer support for help.”
  因此该失败尚未进入消息 API 调用；不能将它归因于未发布或未开通上述权限。
- 再次启动原生程序，安全诊断仍为 `permission` / `21001` / `retryable=false`。
- 官方 API 调试台的“获取 Token”操作未填入凭证，也未提供可确认的成功结果；
  不将该界面操作记录为独立的接口验证通过。

[官方旧接口文档](https://open.feishu.cn/document/server-docs/authentication-management/access-token/tenant_access_token_internal)
已在 2026-10-14 将当前 token 接口列为历史版本，并指向
[新版 OAuth 接口](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/authentication-management/access-token/tenant_access_token)。
这说明后续需要评估协议升级，但当前没有证据说明接口版本就是平台策略拒绝的原因。
未以切换端点、身份或放宽安全设置尝试绕过拒绝。具体命中的策略仍需飞书支持确认，
已在本地准备不含 App Secret、token 或消息正文的支持请求草稿，尚未对外发送。

GUI 验证使用独立 `ANYWORK_HOME` 和验收工作区，沿用已有配置的凭据关联，
不复制正在使用的历史库。日志、快照及临时 Driver 脚本仅保存在忽略的
`target/manual-gui/pr138-feishu-live-20261022/`，不提交授权二维码、票据或私有配置。

### Hermes / OpenClaw 对照与当前接口复核

按用户要求复核了以下上游实现，而不是仅根据错误文案归因：

- [Hermes 飞书适配](https://github.com/NousResearch/hermes-agent/blob/4e58c721c8cf9b51c46636ea84ea6a5cb540880a/plugins/platforms/feishu/adapter.py)
  使用官方 `lark-oapi`；注册同样采用 `PersonalAgent` 与 `client_secret`，注册返回的
  `client_id/client_secret` 作为 App ID/App Secret。身份探测失败仍可尝试长连接，
  因此长连接在线不证明回复发送可用。
- [OpenClaw 客户端](https://github.com/openclaw/openclaw/blob/0d0df35a139ac9e71a830691bcd115764740e585/extensions/feishu/src/client.ts)
  使用官方 Node SDK 的自建应用模式；[官方 token manager](https://github.com/larksuite/node-sdk/blob/b188be60134d409b61259546bcf69c731d2b0b7c/client/token-manager.ts)
  的 App Secret 分支仍请求旧版 `tenant_access_token/internal`，请求字段与升级前的
  anywork 相同。没有证据表明扫码创建的应用需要另一种专属消息鉴权方式。

按当前飞书文档完成协议升级：

- 租户令牌改为 `POST accounts.feishu.cn/oauth/v3/token`，表单提交
  `grant_type=client_credentials`、`client_id`、`client_secret`；读取 `access_token`、
  `expires_in` 和 `token_type`。保留共享刷新与内存缓存，不新增依赖或旧端点回退。
- OAuth HTTP 400/500 业务错误保留平台码，并区分认证、权限、参数和临时服务错误。
- [消息发送](https://open.feishu.cn/document/server-docs/im-v1/message/create)及
  [历史消息](https://open.feishu.cn/document/server-docs/im-v1/message/list)仍使用当前
  `im/v1/messages`。修复非 2xx 响应丢失业务码的问题；不再把所有历史读取权限错误
  一概改写为缺少群历史 scope，保留群成员、可用范围及平台拒绝的实际类别。
- 本地 Feishu peer 与观察入口同步使用新 token 协议及真实 HTTP 错误状态。

真实对照使用同一已注册机器人和 Windows 凭据库中配置选定的同一版本，未显示或落盘
App Secret，未发送给非飞书服务；官方 SDK 只向飞书官方接口发送认证请求。按 Hermes 的客户端与
`bot/v3/info` 调用方式运行官方 Python SDK `lark-oapi 1.7.5`：

- SDK 实际请求旧 token 路径，JSON 字段为 `app_id`、`app_secret`，内存比较确认凭据一致。
- HTTP 200，业务码 `21001`，`tokenPresent=false`；SDK 抛出 `ObtainAccessTokenException`。
- 因而同一失败已在 anywork Rust 实现之外独立复现，尚未进入机器人信息与消息 API。
- 再按当前文档，以同一凭据独立请求 `/oauth/v3/token`，得到 HTTP 400、业务码 `21001`、
  `tokenPresent=false`；因此旧接口被弃用不是解除本次策略拒绝的充分解释。
- 升级后的原生 anywork 首次复验也显示 `permission / 21001 / retryable=false`。
  该次进程已通过应用退出协调器关闭，退出码 0，无剩余子进程。

### 网络同类报告

截至本次查询，以下记录尚无飞书维护者给出的已确认恢复步骤：

- [飞书官方 OpenClaw 插件 #639](https://github.com/larksuite/openclaw-lark/issues/639)：
  多个应用可接收入站，但独立 token 请求和出站均被 `21001` 拒绝；评论中的账号标记
  同样是“正式应用@豆包账号”。
- [飞书 CLI #2815](https://github.com/larksuite/cli/issues/2815)：多名用户报告自 10 月
  13 日前后失效，应用和用户身份均受影响；[10 月 21 日跟进](https://github.com/larksuite/cli/issues/2815#issuecomment-6307651617)
  仍报告未恢复。评论提出的企业账号迁移只是用户经验，不能当作官方规则或本项目已验证修复。
- [OpenClaw #173726](https://github.com/openclaw/openclaw/issues/173726)：同样可收不能回，
  自动分诊因独立 token 请求也被拒而按外部策略问题关闭；这不是飞书官方对策略原因的确认。

上述阶段证据支持“旧应用的令牌签发被平台策略拒绝”，不能确定具体账号资格或租户规则，
也不能据此声称所有飞书个人账号均不支持。随后用户主动切换飞书账号，继续验证如下。

Linux 专用的 `--bots-fixture` 未在 Windows 上执行，跨平台与真实平台兼容结论仍待验证。

### 用户切换飞书账号后的真实验证

- 使用当前客户端账号，通过 anywork 的“创建并连接飞书应用”与“打开飞书继续”入口
  创建 `anywork 飞书账号验证`。用户亲自确认最终凭据授权后，registration 为 `completed`，
  credential 为 `stored`，trusted user 为 1，connection 为 `connected`。
- 同一原生进程、同一新版 OAuth 实现下，旧豆包账号应用仍为 `permission / 21001`，
  新账号应用已完成 token、机器人身份与 WebSocket 连接。这个对照支持本次账号/应用
  准入差异的判断，不将其外推为飞书对所有账号的正式规则。
- 通过 anywork 唤起新机器人的真实飞书会话，向该机器人发送固定测试文字。
  runtime 接收到消息，建立了对应的单聊和 Thread 映射。
- anywork 设置页成功读取该聊天的真实历史；从设置页主动发送验证文字，界面显示
  “全部送达”，飞书客户端实际出现该机器人发出的同一文字。
- 首次自动回复暴露本地产品目录镜像缺失：隔离 home 的 `workspaces.toml` 已有项目，
  但 SQLite 的 `projects` 尚无父行，Thread 镜像写入失败，错误为 SQLite 787
  `FOREIGN KEY constraint failed`。保存状态如实进入 `blocked`，未伪报回复成功。
- 修复目录 writer：仅在父镜像缺失时，从已加载的 canonical Project 定义补齐父行，
  然后在同一事务写入 Thread。保留外键约束及已有父行的目录顺序，不清理任何历史或配置。
- 新增现有 Studio 保存/恢复故障层的回归场景，模拟 canonical 发布成功而镜像未提交后重启。
  相同测试在修复前因 787 失败；修复后通过，并确认新会话、历史库及关联在再次重启后保留，
  未触发全局恢复。证据为 `mirror-red.log` 与 `mirror-green.log`。
- 首次有保存失败的原生进程经退出协调器关闭，退出码正确为 1；无残留或强制回收子进程。
  不将该次退出计为正常排空。机器人配置、系统凭据关联、收发账本与会话目录原样保留。
- 修复后用同一 home 启动：新机器人自动恢复为 `connected`，凭据和可信用户关联不变。
  原先失败的入站记录自动接续，真实模型完成后，飞书客户端收到“飞书收发验证通过”；
  没有重发原消息，也没有修改账本强制标记成功。
- 再从飞书发送一条新的测试输入，收到“重启后收发正常”。两条入站最终均为 `completed`，
  两次自动回复与一次设置页主动发送均为 `succeeded`，没有重复发送记录。
- Driver 在 anywork 设置页重新读取平台历史，实际显示上述 5 条往返消息，截图为
  `target/manual-gui/pr138-feishu-live-20261022/real-feishu-roundtrip.png`。
  最终保存状态 `ready`、pending 0、无错误；产品库、会话历史库与机器人库完整性检查
  均为 `ok`，没有外键违规。产品镜像保留 1 个项目与 1 个机器人会话。
- 经应用退出协调器关闭，`recovered-exit-report.json` 的 exit code 为 0，
  `descendantsAtRootExit` 与 `reclaimedDescendants` 均为空。

本次真实平台结论覆盖 Windows、本机飞书客户端注册、凭据恢复、私聊收信、真实模型自动回复、
主动发送、平台历史读取及失败后的重启接续。未执行真实群聊、陌生人配对、手机扫码授权，
也未卸载客户端模拟未安装场景；这些范围不能由本次私聊结果外推。
