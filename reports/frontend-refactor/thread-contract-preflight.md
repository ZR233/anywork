# 后续 Thread 契约准入事实（f6cb327c）

> 历史调查快照，保留当时字段与证据。当前批准计划为全链路 v4，贡献基线已更新为 b3f22b8f；
> 最新字段增量见 [字段准入表](./t1b-thread-field-map.md)，同步与待修逻辑见
> [v4 同步记录](./main-sync-v4.md)。下文“当前唯一切片”及 decode 字段仅指旧现场，不是
> 新实施节奏或现行吞吐定义；不得据此提前测试或派发不完整合同。

本文件是 root 的已核实事实与实施准入清单，**不是可派发的 T1.B 完整合同**。未冻结新类型／
全部方法／预算／迁移矩阵前，不释放该实施任务。当前唯一实施切片是 T1.A Timeline。

## 1. 当前发布者与领域边界

事实定位以 `f6cb327ceb3416dca181790575711588571d3ec7` 为准：

- `code/pl-studio-runtime/src/studio/runtime/thread_observation.rs` 的唯一 `LiveOwner` 将内容写入
  Session，并通过 `ThreadLiveFeed` 发布执行／runtime／活动；storage 与 retained last Turn 有独立 watch。
- `thread_stream.rs` 现有 subscriber 先登记 broadcast receiver，再捕获 core snapshot；按已覆盖
  commit sequence 丢弃旧 effect。这条无缺帧屏障必须保留，不能改成 snapshot→await→listen。
- 现有 subscriber 自己有 pending 512 帧和 16 ms 观察窗口；新协议不能保留该旧窗口后再叠加
  多层队列，把 bridge 前的 bounded channel 误认为 Dart 消费背压。
- `BridgeThreadRuntimeSnapshot` 目前包含 usage、live usage、route、服务、plan、workflow、todo、
  progress 等整包。新生产者必须在权威发布点分出五域；不能只在 Dart select 或 bridge 末端丢字段。

## 2. 已证实的新鲜度缺口

`runtime/thread_stream.rs:923-958` 的 `annotate_model_route` 在读取时重新解析当前配置；现有
`LiveOwner` 主等待分支（`thread_observation.rs:1205-1233`）没有配置／catalog 唤醒源。
`ConfigRuntime::subscribe_model_catalogs` 及其 `CatalogChange{affected:Vec<AccountId>}` 已存在，
产品内部事件也发布 SettingsConfig／ModelCatalog／ThreadModeCatalog 变化，但 Thread owner
尚未消费这些信号。不能将“重新打开页面后值正确”当作实时路径完整。

新合同验收必须包括：模型撤下／参数变化／Mode 删除，在 Thread 无 token 和无新 Turn 时也能
让已显示字段更新；没有实际值变化不提升领域 revision。只能刷新驻留事实，不激活冷 Thread，
不由页面轮询、重读聚合状态或构造第二份配置目录修补。进行中请求与历史不被当前 catalog 改写。

## 3. metrics／context 的现成字段与身份

- `pl-protocol/src/thread/mod.rs:229-241` 已有
  `ThreadRuntimeLiveUsage{turn_id,attempt_id,completion_tokens?,decode_millis?,latest_context_tokens?,
  state,observation_sequence}`。observation_sequence 在 `(turn_id,attempt_id)` 内单调，不能声称
  “live usage 没有序号”。新 metrics 不应夹带 context 或其它大域。
- `pl-core/src/thread/types.rs:412-475` 的 `UsageSummary` 已持有累计事实，并有配套
  `turn_id + turn_completion_tokens + turn_decode_millis`；这是完整的成对 canonical 速度样本，
  不从当前 active Turn 猜其身份，也不把部分 live 读数与该样本拼接。
- `ThreadRuntimeUsage` 已携带最终绑定的容量／阈值、累计 usage、cache 与费用；这些值保留其
  unknown／zero 与单位语义。当前 catalog 的完整 `ModelContextResolution` 已定义在
  `pl-protocol/src/account_catalog.rs:127-147`，由模型层生成；不在 Dart 重算。
- 分域比较必须忽略由其它域变化顺带改写的 `updated_at`，不能每次输出 token 都仅因整包时间戳
  前进而发布 context／plan。新的 stamp、样本序号、业务 CAS revision、delivery sequence 要逐项区分。

## 4. Plan、workflow 与手动压缩

- Plan 文档上限已有 64 KiB，Plan state 上限 128 KiB；现有 runtime Plan 投影包含 revision、
  state、document(version/markdown/content_hash)、updated_at。当前没有独立 Plan 分块查询。
  root 必须决定正文／metadata 的具体交付形状，不能让执行者自行新增查询或随速度重复正文。
- Workflow 有独立内部 revision 和当前 run 小投影；Mode 目录变化会影响其删除提示，不能漏掉
  这一无新 token 的触发路径。todo／progress 各自变化不应重传 Plan 文档。
- 手动压缩当前是一次 `Future<void>`，**没有 native OperationId／receipt**。领域 operation ticket
  的接线必须明确区分本地操作身份、真实 Future 成功、明确拒绝和 transport UnknownOutcome；
  不伪造 Rust receipt、不自动重试，也不能用 context 数字变化猜本命令已经成功。
- 压缩 receipt 经 effect 转换为 Timeline ContextCompaction；`thread_projection/effect.rs:364-389`
  当前生产路径的 beforeTokens／afterTokens 实际为 None，虽 DTO 支持这些字段。后续证据不能
  宣称当前已经测得这两个数值。失败 receipt 不生成成功压缩 Item，错误仍需单独保留。

## 5. T1.B／T2 派发前仍须 root 完成

- [ ] Thread 五域全部新 DTO／stamp／变化／baseline／错误签名与字节预算。
- [ ] config/catalog/Mode 主动唤醒的唯一 owner 接线及初始化／关闭屏障。
- [ ] 可靠队列的帧数＋字节准入、latest 1 槽、Resync 与两未 ACK 的完整状态机。
- [ ] Plan metadata／文档交付、context 冻结绑定与当前 catalog 来源的完整字段语义。
- [ ] Rust／FRB／server 真实消费者迁移、旧整包入口删除与证明矩阵。
- [ ] 产品集合实体变化／有界基线、统计摘要／历史查询的完整合同。
- [ ] T2 分域 Repository／ports／operation ticket、全部领域动作及旧导出删除表。

SDK 动作与回执已另有只读调查证据：原配置 lane／MutationBoard／附件 ledger／UnknownOutcome
屏障应迁移复用，而模式 JSON／graph／undo 呈现和 pending／error overlay 应迁往 VM。调查结果
不替代 root 冻结的新签名，也不授权执行者自由设计。
