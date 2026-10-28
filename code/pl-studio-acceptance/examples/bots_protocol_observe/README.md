# Bot / user-file explicit observer

这是 Linux 的显式产品观察入口，不进入普通 Rust 测试门禁。既有 runner 负责隔离的真实
`pl-studio-server`、受控进程 owner、私有 D-Bus/keyring、飞书 HTTP/WebSocket peer 和脚本模型。
不接触真实租户、账号或用户数据；`humanVerdict` 始终为 `pending`。

## 组合迁移第一阶段

权威契约为 `design/29-conversation-publication.md`、`design/27-bots.md` 和
`design/24-testing.md`。飞书是完整会话前端：有效受众起点后的公开 Commentary、Final 和
显式 PublicArtifact 由宿主同步，包括 GUI 继续的公开输出；不镜像 GUI prompt、输入附件、
旧历史、Thinking 或 raw tool output。正常公开输出不依赖主动工具开关。

文件交付使用 `write_file` → `publish_artifact` → 受信生产者提交 → typed PublicArtifact →
按当前 Thread 和 `resource.id` 的公开附件读取。工具回执、canonical 提交、history saved
和外部平台接受是不同事实；不能以归档成功冒充发送成功。普通本机输入不是必然不得外发，
`toolsEnabled=false` 也不阻止会话发布或 typed 产物投影。

第一阶段只对齐合并基线、严格平台身份和本地产物契约，不宣称新的飞书 delivery 已实现。
`public-artifact-source` 替代旧的机器人文件工具场景，使用同一 session-exclusive selector 和
FixtureServer/Step；模型只提供工具调用刺激，产物授权、持久化和读取均由真实产品判断。
该例显式建立本机绑定用于隔离检验，不是第二阶段 auto-init 的证据。

| `--case` | 范围 / 当前迁移状态 |
| --- | --- |
| `public-artifact-source` | toolsEnabled=false 的绑定 Thread 接受本机输入并实际 write_file/publish_artifact；0B、未知扩展、无扩展、中文空格文件名均为本地合法正例，核成功调用关联、saved typed 产物及公开读取 bytes/hash/长度/MIME 原样保留；目录发布失败且不产生新产物/平台 POST，正例在其前后仍可读；跨 Thread/resource 读取拒绝。平台 delivery/撤权外写屏障留第二阶段 |
| `chat-isolation` | bot+chat 的真实 Thread/上下文隔离；新受众起点及 auto-init 由第二阶段补充 |
| `chat-media-ingress` | 原件、native block、执行路径及冷恢复；严格 content_v2/presence 和零模型/legacy fallback 断言保留；unsupported-only 在首个绑定前不建 Thread/model 的独立边界仍须补证 |
| `reply-markdown-streaming-cards`、其他 `replies` cases | 保留 main 的官方 CardKit JSON2.0、streaming/update_multi、稳定 elementID/UUID、正 int32 递增 sequence、真实平台身份、Unknown 与恢复证据；不冒充新的每 item delivery 已通过 |
| `user-file-compaction`、`user-file-compaction-timeout` | 真实公开 compact、恢复原件、Session owner shutdown/join；不证明飞书新投递 |
| `user-file-admission-limits` | 普通 multipart 50MiB/32项/128MiB、真实 0B admission、公开原件读取与删除，和平台空出站拒绝是不同边界 |
| `conversation-frontend` | 完整前端纵向旅程：真实机器人配置+信任+首条合法入站 → 自动创建 Thread 并在执行前保存首个授权起点 → 同 Thread 多个真实 Commentary/Final item 各自成卡、同 item 修订更新原卡、至少一帧早于 Turn 终态 → 公开 HTTP 本机输入模拟 GUI 通路继续公开输出 → 一次真实 continuation；用户原文、输入附件、thinking、tool 材料、其他 Thread 与 unsupported-only 首条入站均不外发 |
| `conversation-frontend-budget` | 超过 4000 Unicode 标量与真实 30000B JSON/请求预算（中文/emoji/转义/围栏）：宿主独立截断提示、本地 history 全文不变、Final 不被前项截断抑制、无自动 transcript/分片/换形态重发；peer 独立计算预算 |
| `conversation-frontend-artifact` | saved PublicArtifact 真正出站：非空长 Markdown → publish → typed item → history saved → upload/message → 按消息 GET 资源下载（upload key 与 download key 不同）bytes/hash 一致；0B 本地合法但渠道 `EmptyFile` 阻断、>30,000,000B 本地合法且 `PlatformSizeLimit` 不上传；toolsEnabled=false 不阻止自动前端与产物，额外主动发送仍有独立权限 |
| `conversation-frontend-lifecycle` | Pause 同代补发；Close/停用/撤权旧代无任何新写入（含迟到的卡片 settings close、upload、message）；一次已发起但响应丢失的卡片操作保留原 operation/UUID 与 Unknown，同一 home 重启不重放、不重跑模型；恢复后重新 Enable 才产生新代 |

旧名 `bot-markdown-transfer`、`bot-upload-outcomes`、`bot-file-send-outcomes` 已从可选集合、
模型脚本选择及执行分发中隔离；传入任一旧名立即以 `stage-2 pending / obsolete policy`
非零拒绝，不回退默认场景，不启动产品环境，也不能形成当前 RunSummary 的 Passed。
显式待迁移清单仅引用历史入口以保留编译检查，不调用它们；旧自动长 Final 转 `.md` +
短通知及其常规通知身份路径不是当前证据。对应 Markdown、上传故障、文件消息故障 gap
在隔离期间无条件保持未验证，即使出现历史同名 Passed 也不移除。迁移至 C 的真实
saved-artifact 出站及每 item 卡片后，须凭新场景证据重新评审这些 gap。

`markdown-streaming-cards` 及其他 `replies` 用例编码的是**冻结的存量有限回复政策**
（每轮一张卡、Commentary 不外发）。完整前端的政策相反（每个公开 item 一卡，Commentary
也公开）。两者不能共用同一个“通过”标识，但“没有 Active 完整前端授权”**不等于**存量有限
资格：新建 Thread 也可能是 Closed/PendingStart，甚至 `NeverActivated` 的已关闭授权。因此
该用例在自身断言之后要求 `assert_legacy_limited_source` 给出真实公共证据：**受测的那条
Final canonical item**（携带本用例 marker，且必须是 Final 频道）被产品标为
`NotAuthorized(LegacyOnly)`，把
legacy 来源与当前原 Final/输入绑定。当前没有迁移后旧账本刺激时该证据不存在，用例以
“legacy 来源不可证、保留 GAP_LEGACY_LIMITED_FINAL”失败，而不是沉默地断言相反政策，也不把
它当前置永久拒绝冒充迁移完成。

### 严格身份与独立读取

只有 peer outcome 为 Stored/StoredResponseDropped 且 `message_id` 是 `Some(非空)` 才可继续
消息 GET 或 ledger 身份比对；丢失响应仍可能已存储，不能据此把产品 Unknown 改成成功。
Rejected/Waiting/Cancelled 没有平台 ID，禁止默认空串、候选 ID 回退或用 None==None 证明送达。
文件独立回读使用消息 GET 返回的实际 download key，而不是 upload key；文件场景开启
peer 的 message-scoped key 模式，要求两个 key 不同，再通过目标消息资源 GET 核原 bytes/hash。
每次 ServerRestart 保留类型化回执，核单次 SIGINT、graceful 和 exitCode0 后再进入冷恢复断言。

资源摘要不证明模型或客户端收到原件。媒体原件与请求派生分别核对；uploads 路径从实际
Thread 身份与正式 SessionFiles 映射独立导出，canonical 路径须同时在实际执行根和该
Thread uploads 内，不能由 descriptor 反推归属。媒体样本使用 ffmpeg/ffprobe，不造伪容器。

本地产物场景在首次模型输入前公开停用机器人以隔离渠道投递；这不停止该 Thread 的本机
执行，也不改变 toolsEnabled=false。目录负例前后比较 peer 的全部 POST 事实，同时重读
每份已保存原件；不把此隔离条件的零 POST 当成有效受众撤权或 C 出站 delivery 的证据。

### peer CardKit 全卡协议（fixture 侧）

peer 实现官方 `PUT /open-apis/cardkit/v1/cards/:card_id` 全卡更新，请求体为
`{card:{type:"card_json",data:"<序列化 JSON2.0>"},uuid,sequence}`。全卡、元素内容与
settings 共用同一 card 实体、uuid 认领、sequence 计数器、message 身份和 stream 状态，
因此全卡写入不是第二份事实源。文档化的平台答复一律不改变已存卡：跨应用写 300311、
过期 200750、嵌套文档或真实请求字节任一项超过 30000 为 200860、同卡非递增 sequence
300317、uuid 复用到另一载荷 200770、非 JSON2.0 文档 232001；同一 uuid 与同一载荷的
重放是幂等成功，不计入写次数。

观察端可读 `CardOperation::WholeCard` 事实、`CardObservation.card_bytes`（嵌套文档字节，
与 `request_bytes` 分开暴露，用于区分“实体超限”与“转义后请求超限”）以及
`CardEntityReport.whole_card_updates`（已接受的全卡写次数）。场景据此自行计算 4000 标量
与 30000B 双预算，不导入生产截断 helper，也不用脚本化 code 冒充真实字节判定。
当前生产仍只用元素内容更新，因此 `conversation-frontend-budget` 的全卡断言属于上文
“预期红灯”的一部分，不是 fixture 缺陷。

故意违反官方契约的负例（复用 sequence、非法 JSON2.0 文档）只在 `--feishu-observe` 的
invariant peer 上驱动，并由该 peer 显式断定为 violation；正常旅程 peer 的报告必须零
violation，不能用 owned 标记掩盖产品违规。

### 第二阶段：完整会话前端场景（本包已实现，等待生产交付）

四个 `conversation-frontend*` case 已按批准契约实现并注册；它们描述目标能力，不是当前
生产状态的描述。当前生产仍是“入站消息 → 单张 Final 卡片”，完整投递由其他工作包实现，
因此这些 case 现在**预期红灯**：首个未满足的断言就是缺陷信号。不得为了让它们变绿而放宽
断言、删除负例或把未实现当成通过。

- 首个授权起点：`audience` 为 `Known`+`Active` 只是投影，不能证明顺序。场景另行以**只读**
  方式，在**同一只读快照**（一条 `history_meta LEFT JOIN history_fact_receipts`）内读取隔离
  验收库的不可变 fact receipts：同一 history 身份与水位下，`audience-start`
  的 `sequence` 必须严格小于首个 `turn-start` 的 `sequence`，`excludedTurnId` 不得排除该
  Turn，`turnStart.inputId` 必须是首个真实入站输入；receipt 的 kind/revision/digest 与
  `last_write_seq` 逐项核对，digest 由观察端本地重算。读不到或坏 proof 一律失败并保留
  AUTO_INIT gap。不 seed 绑定、不手动 Enable、不手工建会话，也不以 provider gate 到达代替顺序。
- 逐项卡片：每个真实 Commentary/Final `TextItem` 一卡，同 item 的新 revision 更新原卡
  （实体数不增），至少一帧在 Turn 仍 Running 时已被平台接受；关联由 canonical item 文本、
  canonical ordinal 顺序与 `readThreadAudienceItems` 的 per-item 事实共同判定，peer 从不
  接收或猜测 itemId。per-item 事实必须同时满足：canonical 当前 revision/saved/eligibility、
  `ledger.projected` 与 `ledger.accepted` 均为该 revision 与完整性、该项平台结果为
  `Accepted`；旧 revision 的 accepted 或 `Unknown` 一律不能通过。文件仍分别核 upload 与
  message。
- 显示预算：由观察端独立计算 4000 Unicode 标量与 peer 记录的真实请求字节，不导入生产
  截断 helper。样例分两种：**密集换行**正文（任意切口前都有可用换行）必须按换行截断；
  **单行**正文只核 UTF-8 边界与双预算。不固定生产算法的私有搜索半径，也不要求产品补
  Markdown 围栏——截断提示必须是独立宿主元素、不得拼进正文。当前样例本身已真实越过两界：
  密集换行 22,516 标量 / 41,724 UTF-8 字节，单行 20,209 / 42,889；断言用 `full.len()`
  的原始字节，不用平台请求字节冒充。
- 产物出站：只有 typed、history-saved 的 PublicArtifact 才允许 upload/message；peer 以
  message-scoped 模式给出与 upload key 不同的 download key，并按消息资源 GET 核 bytes/hash。
  120,181 字节的 `write_file` 工具调用会让该 Turn 先做文本摘要压缩，因此脚本必须为压缩请求
  单独给出摘要步；普通 tool call 不能当压缩摘要，压缩请求与压缩后的正常请求各自有强判据。
  压缩后还必须比对两次请求中同一 `write_file` 的完整工具输出逐字节相同，并在**生产自建**的
  后续上下文里看到摘要记录（不向 fixture 请求注入摘要）。主动发送对照使用现役
  `send_bot_message {botId, chatId, text}`：场景经公开 `saveBot` 显式创建固定合法
  `bot_frontend_artifact`（`expected_config_revision=0`，不 seed 绑定/Active），断言工具名与实参、
  `Failed(Execution)` 且消息含 `bot is not authorized for this project`，并用专有 marker 证明
  该意图没有产生任何 send/upload/durable operation。EmptyFile / PlatformSizeLimit / Delivered
  各自按精确期望等待，`upload` 已接受但 `message` 未完成仍继续等，终态不相容立即失败。
- 生命周期：Pause 期间零平台写入、Resume 同代补发；Close/停用/撤权后旧代不得有任何新写入
  （包括迟到的卡片 settings close）；已发起但响应丢失的卡片操作保持 Unknown，重启不重放、
  不重跑模型。每次真实业务意图使用独立稳定 operationId（阶段/序号区分），只有同一意图的
  重试才复用。绑定替换仅在**已存在已激活 head** 时改用显式 `Enable` 新代（root 已在
  design 29 首次初始化段补明该既有约定）；替换后必须证明新代 `Saved` 后**真的外发一条
  新公开输出**，且旧代后续输入保持本地，才可移除 `GAP_BINDING_REPLACEMENT`。
- unsupported-only 作为另一聊天的首条入站（群聊，必须真实提及机器人；`@all` 不算）：须记录为
  **一条干净 `completed` 入站工作行**，零 Thread 绑定、零模型执行、零卡片/上传/文件，并恰好
  发出**一条**有界 `post` 辅助提示；其身份由只读 bot ledger 的稳定 operation
  （`botunsupported:<bot>:<chat>:<message>`）、segment uuid 与已接受的平台 message id 共同证明，
  提示正文只说明不支持的类型、不回显原消息正文。`needs_attention` 是失败/不可恢复态，不能当作
  通过；全旅程的 11 条 `interactive` 公开卡与该 1 条辅助 `post` 分别精确对账，任何第三种发送都失败。

#### 需要 root 提供的外部刺激

- **存量有限回复账本**：`markdown-streaming-cards` 的作用域门要求“非 Active/Paused 的存量
  有限回复范围”。只有迁移后的旧卡片/文本/文件账本才能提供该来源，公开 API 不能新建；在
  该刺激到位前，该用例对新建完整前端 Thread 会明确失败（不共享通过标识）。
- **子 Thread / 绑定替换**：`conversation-frontend` 用同项目的独立 Thread 证明“其他会话
  不外发”，但没有 delegation fixture 时无法产生真实子 Thread；绑定替换闭环另需 root 指定
  的目标种类证明路径。两者都保留为 gap，不用伪造库行补齐。
- **首 cut / Archived**：若需覆盖创建期 first-cut 与 Archived 线程，需要公开入口支持。

既有 P 的 publish_artifact、可信回执、typed 产物、精确引用和公开 read 端口已存在，不列为
缺失接口。root 已确认沿用 P 契约：0B/未知扩展是本地合法正例，目录是本地拒绝；
文件名、原件 MIME 和 bytes 原样保留，不转码、不加后缀。平台空文件拒绝与
>30,000,000B 不上传由 `conversation-frontend-artifact` 断言。

## 运行与边界

```bash
CARGO_INCREMENTAL=0 cargo check --locked -p pl-studio-acceptance --example bots_protocol_observe
cargo fmt -p pl-studio-acceptance -- --check
cargo run --locked -p pl-studio-acceptance --example bots_protocol_observe -- \
  --case public-artifact-source --output <current-thread-artifacts>/<new-run> \
  --server-binary <confirmed-current-pl-studio-server> --retain-environment
```

每个独占 case 单独运行；新文件由 env.rs 递归 ROOTS 自动纳入身份。必须使用已确认且匹配
当前生产基线的 server/helper，不能复用旧 server 绿灯证明新行为。进程/socket/fixture 的
真实关闭、join、退出回执与回收是成功条件；失败保留已到达证据并传播为非零退出。
不为概率成功加任意等待、不吞 IO/解码错误、不改生产DB/测试接口、不另建平行 harness。
真实租户、客户端渲染、GUI/live/SSH/Windows、精确 lease/sweep 竞争及未覆盖边界仍须独立验收。
