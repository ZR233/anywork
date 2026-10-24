# Bot / user-file explicit observer

这是 Linux 上的显式产品观察入口，不进入普通 Rust 测试门禁。它启动隔离的真实
`pl-studio-server`、私有 D-Bus / keyring、独立飞书 HTTP/WebSocket peer 和严格脚本模型。
不接触真实租户、账号或用户数据；`humanVerdict` 始终为 `pending`。

## 文件旅程（均须独立选择）

| `--case` | 产品 oracle |
| --- | --- |
| `chat-isolation` | 同 bot 的两个 p2p 和一个授权 group 使用三个实际 DB Thread 身份；同 chat/群成员共享复用；重复、未授权、无真 mention 不进入实际模型上下文 |
| `chat-media-ingress` | image/file/noext/unknown/audio/有效 video/坏容器/post；逐 message/key 绑定可靠附件身份、中文/空格名和两个同名等长不同原件；native image 显示名取可靠 DTO，不发明供应商字段；实际 native block/尺寸派生及 text 冷恢复的显示名、真实 bytes/hash、不同路径 |
| `bot-file-source` | 模型真实 `write_file` → `submit_bot_file`，`toolsEnabled=false` 的当前入站和公开交互 continuation 成功；普通/运行中本地输入、目标 JSON、空文件和撤权失败；拒绝前后 upload/send 事实不增加 |
| `bot-markdown-transfer` | 完整 post.md 原文，先接受完整超长/JSON 转义 `.md` 再发短说明；通知须匹配有限的完整肯定交付/下载模板，并绑定实际文件名，仅忽略无语义空白/陈述分隔标点；独立 GET/tail、公开 stages 与 ledger；同 operation 回读/冲突、Partial 冷恢复 |
| `bot-upload-outcomes` | 模型文件调用的 upload Reject / AcceptThenDrop / Hang + 公开取消；拒绝/未知账本与冷重启无 POST 重放 |
| `bot-file-send-outcomes` | 确认上传后 file-message Reject / AcceptThenDrop / Hang + 公开取消；资源 key、UUID 和各阶段账本与冷重启无 POST 重放 |
| `user-file-compaction` | 普通 HTTP 文件输入的旧 Turn → 当前纯文本；真实公开 `StudioRuntime::compact_thread` 完成/ContextCompaction；删除副本后 replacement 及冷恢复重建；第二次真实挂起 compact 被公开 shutdown 取消并 join |
| `user-file-compaction-timeout` | 真实公共 Studio compact 已在 provider 挂起后才 arm 外层 deadline；runner 真正丢弃 case future，再通过 Session owner shutdown/join，之后才清理 peer/server；不能靠 Drop 或 abort 冒充成功 |
| `user-file-admission-limits` | 普通 multipart 实际接受 32 项、包含两个 50MiB 原件的精确 128MiB 批次，逐原件公开 GET 核显示名/bytes/hash并删除 draft；拒绝 33 项、50MiB+1、128MiB+1；请求以 64KiB chunk 流式产生 |

既有 `reply-send-outcomes-restart` 同步按当前 `.md` 文件 + 短说明契约观察 Partial，
不再声称文本被任意切成三个片段。生产账本使用 typed camelCase 阶段事实，
`platform_message_ids` 的存储编码仍按实际数据库契约读取，不猜成 JSON array。
`bot-markdown-transfer` 按本次入站的精确回复操作身份等待同一账本记录中的完整文件
Accepted、短说明 Rejected，以及本次入站执行收束；再以真实平台 message/UUID 和公开
回执交叉核对。聚合 Partial 可为发送中间态，不能单独当作完成屏障。等待有界，仅在
实际未完成阶段轮询；解码、IO 或明确错误终态直接失败，不吞错或用固定延迟掩盖竞态。

模型 fixture 只提供固定文本、真实工具调用和挂起刺激，不替产品决定授权、去重或发送状态。
撤权后的文件工具拒绝步骤以空 Final 结束，避免把已受理入站仍允许的正式回复混入该工具的
零新增 upload/send POST 断言；实际工具拒绝原因仍由真实返回值独立核验。
资源 peer 的原件摘要也不证明客户端收到；成功文件旅程必须独立 GET 消息和资源原件。
媒体样本使用已安装的 `ffmpeg` 生成真实 PNG/WAV/有 video track 的 MP4，派生尺寸用
`ffprobe` 独立读取；没有这些成熟工具时失败，不拼伪容器头冒充有效视频。

media ingress 同一旅程还用 peer 的既有 Raw post 入口发送精确 `content_v2: []`、
`content_v2: null`、坏结构、字段缺失及 mixed-unknown 节点。空数组不得回退，null/坏结构
不得执行模型或下载 legacy 资源，须产生独立明确限制通知；只有字段缺失才读取 legacy。
mixed unknown 必须保留已支持的图片和独立限制提示，资源只下载并归档一次。原始 Raw
content、ACK、入站内容指纹、实际模型请求、可靠附件和 peer 下载身份共同形成证据，
不把 `Option::None` 省略字段当作显式 null，也不引入第二套平台解析器。
五个唯一 Raw 输入各只发送一次；首个 ACK 到达后即要求该 ID 只有一个 ACK，且
`code == 200`、`biz_rt == "0"`。缺失字段、错误结果或重复 ACK 均失败，post 分支结束
及整个 ingress 冷恢复完成后的 peer 事实还会复核五个 ID 的唯一成功，捕获晚到重复。
32 项普通 multipart 正例中包含一个真实 0B file；公开 DTO 长度、GET 空原件 SHA-256
与 draft 删除均须核对。它与窄文件工具的空出站拒绝是不同边界，不额外增加独立 case。

## 运行

先由主代理确认生产版本稳定，并按工程规范安装匹配的外部 helper。运行输出必须指定到
当前 Thread 宿主 `studio.session-files` 的 `artifacts/`，每次用新子目录：

```bash
cargo run -p pl-studio-acceptance --example bots_protocol_observe --locked -- \
  --case chat-media-ingress --output <current-thread-artifacts>/<new-run> \
  --server-binary <confirmed-current-pl-studio-server> --retain-environment
```

`--server-binary` 可省略，届时观察器显式构建当前 server；首次双重编译和共享构建锁时间
不属于 case 的运行预算，外层命令 timeout 应独立留够。显式二进制的真实路径/hash、
观察器源码 manifest、实际模型请求、peer 阶段事实和关闭后事实分别留在输出中。
`feishu-closed.json` 的 listener/socket/media 终态与 `summary.json` 的进程树证据共同核对回收；
被监督器强制回收不算自然回收通过。失败保留已完成阶段和原始错误，内部失败传到非零退出。
私有 D-Bus 包装脚本记录实际 server 子进程 PID，并等待该进程与 keyring 完成；正常停止
仅向实际 server 发 SIGINT，再等待包装脚本退出，不能先结束整个包装进程组而把仍在
shutdown 的 server 当作已回收。启动失败或超预算才使用进程组兜底，强制终止仍判失败。

`user-file-compaction` 的 compact 命令当前没有 HTTP endpoint，因此先停止/reap server，
再通过同一隔离 home 的真实公开 StudioRuntime/factory 执行；不调用私有 core/model helper，
也不创建假的压缩结果或权限。
所有执行副本的 expected uploads 根从实际公开 Thread 身份，按正式
`SessionFiles::new` 的 `SHA-256(raw Thread id)` 映射独立导出为
`.anywork/sessions/<thread-key>/uploads/`，绝不从 descriptor path 反推。模型路径必须以
该根的完整路径组件为相对前缀；随后 canonical 文件必须同时位于实际 workspace 和当前
Thread uploads 之下，且原 bytes/digest 与可靠附件一致。另 Thread、普通 `other/uploads`、
workspace 顶层 `uploads`、遍历或链接逃逸不符合当前契约。
机器人执行根读取公开 `BotSnapshot.workspace_path`，并与受管 `v2/bots/<botId>/workspace`
及实际模型请求的宿主工作区事实交叉核对；Thread 的历史归属工作区不代替机器人执行根。
该 runtime 和 compact JoinHandle 始终登记在 Session 的单一 `CompactionOwner`，而非 case
future 的局部变量；普通结果、错误和外层 deadline 都先调用公开 shutdown 并 join，再进行
server/model/peer cleanup。fallback abort 也必须 await，并使该观察失败，不能报告自然取消。
`case-runtime-cleanup.json` 记录这条终态证据；timeout case 是可显式复现相同 runner 路径的
故障观察，不降低其他 case 的 300s 失败门槛。

### 固定短通知的有限语义模板

短通知是产品生成的确定性消息，不是任意模型自然语言。接受下列完整肯定模式，`<name>`
必须逐字等于实际已交付 `.md` 文件名，可只用一对 inline-code 反引号包裹或不包裹：

- `正文超过飞书富文本大小限制，完整 Markdown 原文已作为 UTF-8 文件 <name> 交付，可下载查看。`
- `完整 Markdown 原文已作为 UTF-8 文件 <name> 交付，可下载查看。`
- `完整 Markdown 原文已交付为文件 <name>，可下载查看。`
- `The complete Markdown original has been delivered as UTF-8 file <name>; download it to view.`

只在文件名之外忽略空白、逗号、句号和分号的中英文变体；不忽略问号、引号、code fence、
未知子句或否定语句，也不归一化文件名里的空白/标点。整句不匹配就拒绝，不用关键词 bag、
否定词穷举或自研 Markdown AST。scratch 负向 probe 只证明 observer oracle 的缺陷敏感度，
不代替任何真实 Studio/飞书/GUI case。

## 明确保留的边界

- HTTP prompt 在运行中是中断并开启新 Turn，不能冒充同 Turn steering；该风险留在 gaps。
- 不伪造 continuation/source/child 权限，不手写产品数据库或生产 fault injection。
- 同一个模型 tool call identity 无法由公开 HTTP 指定重放；文件 tool 的异 intent 重放不能由普通新 call 代证。
- 子代理排除、项目跨 chat 权限、outbound 30,000,000-byte 文件极限，仍须各自真实边界证据；admission 边界只有对应 case 实际通过才缩小 gap。
- `BotSendStatus` 不是平台动作事实。真实工具/API 结果必须分别核 `uploadStage`、`messageStage`、`stopReason`；on-wire Hang 的取消不能代证 uploadAccepted/messageNotStarted 的精确取消窗口。
- 12s/14s 的 sampled restart quiet window 证明该有限区间无重放，不声称精确认领/扫表竞争窗口。
- 真实飞书客户端 Markdown 排版、真实租户、Linux GUI、远端 SSH 和 E helper 安全性质须由主代理另验收；本地自动化不能外推。
