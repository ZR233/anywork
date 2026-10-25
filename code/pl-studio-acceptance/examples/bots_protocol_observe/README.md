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

旧名 `bot-markdown-transfer`、`bot-upload-outcomes`、`bot-file-send-outcomes` 已从可选集合、
模型脚本选择及执行分发中隔离；传入任一旧名立即以 `stage-2 pending / obsolete policy`
非零拒绝，不回退默认场景，不启动产品环境，也不能形成当前 RunSummary 的 Passed。
显式待迁移清单仅引用历史入口以保留编译检查，不调用它们；旧自动长 Final 转 `.md` +
短通知及其常规通知身份路径不是当前证据。对应 Markdown、上传故障、文件消息故障 gap
在隔离期间无条件保持未验证，即使出现历史同名 Passed 也不移除。迁移至 C 的真实
saved-artifact 出站及每 item 卡片后，须凭新场景证据重新评审这些 gap。

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

### 第二阶段：等待 C 的真实生产者

- 每真实 Commentary/Final TextItem 一卡、同 item 修订更新；Unicode 4000 scalar 和完整
  JSON/请求30000B双界限，宿主独立截断提示、本地全文不截，不自动分片或长 Final 转文件。
- saved PublicArtifact 的消费/claim/lease/fencing、精确 item/revision/saved 证明、独立文件下载。
- 仅飞书出站要求非空且不超过 30,000,000B；平台拒绝空文件时本地 0B 产物仍有效，
  渠道须明确拒绝/未交付。本阶段不写该平台拒绝断言。
- Pause 保留补发义务；Close/撤权禁止新卡片关闭、上传、文件消息及 aux IM；旧在途/Unknown
  按原操作保留，不换 UUID/正文、不重复模型输入；restart 不把旧 tail 当新授权。
- 旧有限 Final 与旧卡片/文本/文件账本保留及退出，自动首 cut/auto-init；不得 seed 绑定、
  手动 Enable 同步或旧自动回复成功来替代该证据。
- unsupported-only 作为首条入站时不得建 Thread/model；辅助限制提示仍受当前来源授权，
  不能用已绑定场景里的零模型调用外推“未创建 Thread”。

既有 P 的 publish_artifact、可信回执、typed 产物、精确引用和公开 read 端口已存在，不列为
缺失接口。root 已确认沿用 P 契约：0B/未知扩展是本地合法正例，目录是本地拒绝；
文件名、原件 MIME 和 bytes 原样保留，不转码、不加后缀。平台空文件拒绝属第二阶段。

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
