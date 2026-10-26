# T1.B — Thread 分域字段与来源准入表（未冻结实施合同）

本表保存 root 已核实的当前字段及目标归属，防止后续分域时漏能力或重复投送。
**不是可派发实施合同**：新 feed 类型、全部基线／变化封套、owner epoch、准入字节预算、
冷读与恢复、初始化／关闭竞争、生产者—消费者删除表及测试矩阵未齐全前，不派 Rust 实施。
它补充 [既有准入事实](./thread-contract-preflight.md)，不撤销批准计划；旧 Timeline 证据与
本次同步发现的逻辑缺口分别见 [同步记录](./main-sync-v4.md)，不视为最终逻辑已通过。

## 1. 版本与唯一事实源

贡献比较基线 `b3f22b8f651816851852582a10a970fe25af3ae6`，重放后的已提交设计基线
`78a2762495772d7fe416faaf5f14876cf46597c4`。原表按旧 f6 核对；本次只读增量核实后已将
计量字段同步为 response 时长，其余共享接缝仍须完整冻结。本表核对的协议位于真实
`code/pl-protocol`；没有 `pl-studio-protocol` crate。产品 runtime 协议另外位于
`code/pl-studio-runtime/src/protocol`，不能把路径或类型归属混写。

当前公开集合为 `ThreadSnapshot`／`ThreadRuntimeSnapshot`／`ThreadNotification`／
`ThreadNotificationEnvelope`／`ThreadSubscriptionUpdate`，定义见
`code/pl-protocol/src/thread/mod.rs`。目标是源头按变化原因发布五域，不是把整包搬到 bridge
再筛字段。正文继续由已冻结的 [Timeline 合同](./t1a-timeline-contract.md) 交付。

目录是 Thread 元数据的唯一 canonical cache；分域基线中的身份不能反向覆盖目录中的
title、mode、role、workspace、archive 或当前状态，不在 Dart 新建可写选择事实源。

## 2. 当前顶层字段的完整去向

### 2.1 ThreadSnapshot

| 当前字段／类型 | 目标职责 | 约束 |
| --- | --- | --- |
| `schema_version: u32` | 公共结构版本，不是业务水位 | 分域不能冒用它作 feed revision |
| `revision: u64` | 当前查询快照版本 | 不能拿查询结果修补实时封套的连续性 |
| `thread: Thread` | 目录身份与元数据绑定 | 不在 execution 再造第二份可写目录；冷读仍需验证目标 |
| `active_turn: Option<Turn>` | execution | 保留 canonical tagged state，不退化为平行 status／reason 字符串 |
| `interactions: Vec<InteractionRequest>` | execution | 请求与决定是有序可靠事实；不静默 latest 覆盖或截短决定 |
| `runtime: Option<ThreadRuntimeSnapshot>` | 拆到下述四域 | `None` 与“已知空域”不能静默合并 |
| `activity: Option<ThreadActivity>` | execution | 小摘要及稳定活动身份；详情继续按身份查询，不发正文 |
| `storage: Option<ThreadStorageState>` | execution | `None` 是无可报告事实，不是健康、已 durable 或可继续 |

最近终态 Turn 当前由真实观察 owner 保留，冷恢复／retired child 也有有界播种路径；新基线
必须保留该能力。不能只给 active Turn，再靠 Timeline 文本或客户端曾见过 running 推测 last Turn。

FRB 另加的 `BridgeThreadSnapshot.runtime_availability` 不在上述 protocol 八字段内。
`convert/thread_stream/mod.rs::bridge_thread_snapshot` 只按 `runtime.is_some()` 赋
Active／Inactive，它不是从 assembler incarnation／驻留 registry 读取的 owner 状态。
Dart `studio_thread_stream.dart::_threadWorkspaceFromSnapshot` 不消费该字段，且当前会把
runtime None 替成 `_emptyRuntimeView()`。新域不能把这两个旧适配行为当成“已知健康空域”或
冷热 owner 的权威证明；迁移清单须覆盖这份 bridge-only 类型与 None 的转换，不能只删 protocol DTO。

### 2.2 ThreadRuntimeSnapshot

以下列出当前全部 15 个字段，不以“其余字段原样处理”把 owner 决策下放：

| 当前字段／类型 | 目标 facet | 投送约束 |
| --- | --- | --- |
| `thread_id: String` | 每域资源身份 | 不因拆域形成多个逻辑 Thread |
| `model_route: Option<ThreadModelRouteSnapshot>` | configuration | route 的业务 CAS revision 与可用性来源分开；只真变化发布 |
| `usage: ThreadRuntimeUsage` | context | 完整原子计量／容量／cache／费用，具体字段见下一表 |
| `live_usage: Option<ThreadRuntimeLiveUsage>` | metrics 与 context 各取自身字段 | metrics 不携带 context 读数；保留原 attempt／observation 身份 |
| `turn_completion_tokens: u64` | metrics | 与同源 Turn 身份、response 毫秒成对，不按当前 active Turn 猜身份 |
| `turn_response_millis: u64` | metrics | 总响应耗时含首字等待，不能把 live 部分值与累计样本拼接 |
| `todo: Option<TodoListSnapshot>` | authoring／TodoChanged | todo 变化不重传 Plan 正文或 workflow |
| `active_skills: Vec<String>` | configuration／ActiveResourcesChanged | 空列表与未知域区分，不因 token 更新重复通知 |
| `active_mcp_servers: Vec<String>` | configuration／ActiveResourcesChanged | 同上 |
| `active_lsp_servers: Vec<String>` | configuration／ActiveResourcesChanged | 同上 |
| `progress: Option<String>` | authoring／ProgressChanged | 保留现有事实语义，不混入新 Thread preparation 命令流 |
| `mcp_health: Option<McpHealthSnapshot>` | configuration／McpHealthChanged | generation／server 字段保留，不由 GUI 推算健康 |
| `workflow: Option<WorkflowRuntimeSnapshot>` | authoring／WorkflowChanged | workflow 变化不重传 Plan 正文 |
| `plan: Option<AgentSessionPlanRuntimeSnapshot>` | authoring／PlanChanged | 正文只在文档身份变化或该域新基线时交付 |
| `updated_at: i64` | 各事实的诊断时间 | 不单凭整包时间前进判定其它域改变，不是跨域事务戳 |

## 3. 计量字段与单位

### 3.1 高频样本

当前 `ThreadRuntimeLiveUsage` 的全部字段：

| 字段 | 语义／目标 |
| --- | --- |
| `turn_id: String` | 原运行观察的 Turn 身份，metrics／context 各自保留关联 |
| `attempt_id: String` | 原模型 attempt 身份，不能按现在的选择重定向 |
| `completion_tokens: Option<u64>` | metrics，缺失是未报告，不是零 |
| `response_millis: Option<u64>` | metrics，总响应毫秒含首字等待，缺失不是零，不更名成秒 |
| `latest_context_tokens: Option<u64>` | context，不搭便 metrics 发送 |
| `state: ThreadRuntimeUsageState` | `Live`／`Authoritative`，保留实际原生产值，不伪造终态 |
| `observation_sequence: u64` | 在 `(turn_id, attempt_id)` 内单调，已存在，不能再声称缺序号 |

metrics 是可覆盖的样本，不要求每个中间读数。它自己的 latest 样本水位、可靠域 revision、
core commit sequence 和传输 delivery sequence 必须分别命名；不能把跳过样本当 execution 缺口。

成对累计速度的真实来源为 `pl_core::thread::UsageSummary` 的 `turn_id`、
`turn_completion_tokens`、`turn_response_millis`，不是从 `active_turn` 或上一份 live 观察补身份。
在下一轮模型采样前保留最近有效速度的现有语义不能因拆域丢失。
新主线失败／停止会撤回原 live generation 的计量，恢复 attempt 从空样本开始；不能用旧
generation 的分子搭新耗时。历史 TTFT 使用独立 `ttft_sample_count`，不是全部调用数。

### 3.2 ThreadRuntimeUsage

| 当前字段 | 类型 | 约束 |
| --- | --- | --- |
| `has_incomplete_usage` | bool | 真实计量不完整标志 |
| `model_id` | String | 最新请求绑定事实，不拿显示名替代身份 |
| `context_window` | Option<u64> | 已解析有效容量，未知保持 None |
| `max_context_window` | Option<u64> | 模型声明容量，不从有效窗口倒推 |
| `auto_compact_limit` | Option<u64> | 模型层最终阈值，不由 Dart 重算比例／预留 |
| `latest_context_tokens` | u64 | 保留现有累计协议值；外层 runtime 缺失不伪造成已测零 |
| `prompt_tokens` | u64 | 原 token 单位 |
| `completion_tokens` | u64 | 原 token 单位，不与 live 样本混加 |
| `cached_prompt_tokens` | u64 | 原 cache-read 累计事实 |
| `cache_write_tokens` | u64 | 原累计事实 |
| `reasoning_tokens` | u64 | 原累计事实 |
| `inference_count` | u64 | 原模型计数 |
| `total_tokens` | u64 | 原计量，不让 GUI 重推缺失项 |
| `cache_usage` | CacheUsageSummary | 同一次读数原子交付 |
| `estimated_costs` | Vec<RuntimeCostAmount> | 保留各 currency／amount，不拼成无单位数字 |
| `estimated_cache_savings` | Vec<RuntimeCostAmount> | 保留原币种／金额语义 |
| `has_unpriced_usage` | bool | 未定价不等于免费 |
| `prompt_generation` | Option<u64> | 当前投影恒 None，尚无真实来源；不补默认 generation |
| `prompt_cache_policy` | Option<String> | 当前投影恒 None，不能称为已报告的缓存策略 |
| `prefix_changed_reason` | Option<PromptPrefixChangedReason> | 当前投影恒 None，不从工具文案猜测 typed 原因 |
| `updated_at` | i64 | Unix 秒，不用它使无变化的域递增 |

`CacheUsageSummary` 保留 `input_tokens:u64`、`cache_read_tokens:u64`、`hit_rate:Option<f64>`、
`has_incomplete_usage:bool`；输入累计为零时命中率 None，不补 0。金额与更深的 canonical 类型
继续复用协议定义；最终实施契约需绑定全部复用类型的内容身份，不允许执行者另补字段。

## 4. 配置与 authoring 的已知边界

`ThreadModelRouteSnapshot` 当前全字段为 `account_id:String`、`model_id:String`、
`effort:Option<String>`、`revision:u64`、`available:bool`、`unavailable_reason:Option<String>`。
可用性变化不是 route CAS 发生业务写入，目录也不能回滚在途／历史冻结绑定。

Plan runtime 当前只含 `revision:u64`、`state:AgentSessionPlanPhase`、
`document:Option<AgentSessionPlanDocument>`、`updated_at:i64`；文档含
`version:u64`、`markdown:String`、`content_hash:String`。不能把 Plan 工具／确认使用的
完整 `AgentSessionPlanSnapshot` 与此 GUI runtime 类型混为一谈，也不能静默丢批准／待确认语义。
文档已有 64KiB 上限，是否需要新增 query 取决于实际交付边界，不能仅为抽象对称自建分块接口。

已证新鲜度缺口：当前 Thread 观察没有 config／catalog／Mode 唤醒，只在消费边界现读 annotate。
新设计要求变化主动刷新已驻留 owner 的对应域，不等待 token、换页或手动刷新；不激活冷执行
owner，也不在 Dart 重算模型策略。已有 ConfigRuntime catalog 观察与 ProductEventBus 内部通知
可复用，初始化与 drain 的精确屏障尚在补证，未在本表宣称新接线已成立。

### 4.1 发布点、占位值与冻结绑定（已读生产实现）

- `runtime/thread_observation.rs` 的 `LiveOwner::observe_runtime` 从当前 owner snapshot 调用
  `project_runtime`，与 retained `runtime_published` 全等比较，实际变化后才更新时间并发
  `ThreadLiveEvent::Runtime`。稳定时间用于去重，但只要 live token 改变，就仍重建／发送整包；
  新协议必须在此真实发布责任内分域，不能据“已有去重”宣称无无关字段投送。
- `studio/thread_projection/runtime.rs` 的 `project_runtime` 对 active MCP／LSP 显式使用
  `Vec::new()`，progress／MCP health 显式使用 None。这些是当前未实现的投影占位，不能在新
  领域合同中把它们解释为经 authority 确认的空集合／健康，也不能声称已经测得资源状态。
  active skills 则从已有 typed skill-view 扩展集合读取，两者来源不同。
- 同文件 `fold_effect_accounting_in_place` 从 attempt admission 的 request metadata 成组更新
  model／context window／声明窗口／最终阈值；没有 metadata 时整组未知，不沿用前次绑定。
  这是最近请求的冻结计量绑定，不是 idle 当前 catalog 的重新解析结果。
- `runtime/thread_stream.rs` 的 `annotate_model_route` 仅更改 `available` 与
  `unavailable_reason`，不改 route account／model／effort／CAS revision，也不改 usage 容量／
  阈值。新 context 合同必须明确区分当前可用策略与冻结请求来源，不靠此 annotate 伪装已刷新。

### 4.2 冷读与 server 消费面的已知限制

- 当前 `subscribe_thread` 只对 `parent_thread_id.is_some() && role == "planner"` 的分支走
  retired 源；不能将它笼统写成所有 child 均不激活 owner。此路径会先
  `history_writer.prepare_activation()` 准备既有 schema，再读 snapshot 与有界最近终态；
  它不是完全无写的探针，也不是执行 owner 激活。
- 其它 live 订阅分支调用 `ensure_thread_owner`。常规快照的 `read_thread_state` 驻留时读
  handle snapshot，未驻留时读 checkpoint，并向现有持久化协调器内存播种 usage；无保存
  checkpoint 显式失败。冷域新入口的准入／迁移副作用必须在完整合同中说清，不隐瞒为纯 getter。
- retired 源发一次 snapshot，必要时补一次 canonical `TurnCompleted`，之后等待 transport
  取消；不能因没有新生产者反复正常 EOF，让 Dart 无限重连历史。
- server 实际消费者为 `pl-studio-server/src/routes.rs` 的 Thread 查询／activity detail，及
  `src/sse.rs` 的 `thread_events`。后者透传 typed Snapshot／Notification，Lagged 有独立 SSE
  名称；迁移要同步 HTTP／OpenAPI，不能只让 FRB 编译通过而留下旧聚合公开协议。

以上仅为现状与消费者事实。新配置唤醒需在登记、读取与 drain 之间证明连续性，不能把现有
ProductEventBus“先更新快照、后 emit”误当成已证明 Thread 接线无竞态。

### 4.3 载荷与来源的进一步准入事实

下表是现有写入边界，不是新 feed 的预算。读取端能解析一个结构，不等于已经重新验证
其写入限制；不能将这些数值直接当成完整封套大小、FRB wire bytes 或进程内存上界。

| 资源 | 已核实限制／来源 | 实际入口 |
| --- | --- | --- |
| Todo | 非空且最多32项、最多一个 inProgress、trim 后 step 非空且最多256字符；整个文档 JSON 最多8KiB | `pl-tool/src/todo.rs` 的 `todo_document`；`saved_snapshot` 只校验 format/version 并解码，不重复业务校验 |
| Plan | 正文最多64KiB；整体 session state 序列化最多128KiB | `plan_tool/state/machine.rs::validate_plan`、`state/mod.rs::validate_session_state_size`；runtime 文档仍是整份 markdown，无独立正文 query |
| Workflow 定义 | normalized 定义最多64KiB、1..32个state、最多96条transition；instructions 4KiB、guard 2KiB | `mode/compiler.rs`；不能把注册图预算冒充 runtime 投影预算 |
| Workflow state | 序列化最多256KiB、history tail最多64、archived runs最多16、operation receipts最多32 | `mode/state.rs`；不是“每次都投送完整256KiB”的结论 |
| Interaction | core `request_interaction` 只校验非空身份与身份冲突，未施加统一载荷字节上限 | `pl-core/src/thread/interactions.rs`；typed questions 与 approval 完整输入还需独立投送预算，不能静默截断 |
| Storage 诊断 | `last_error` 从 core persistence error 原样克隆，不参与 typed 分类 | `thread_projection/snapshot.rs::storage_state`；未在此投影施加文本上限 |

root 另亲读确认：

- `thread_projection/runtime.rs` 对 prompt_generation、prompt_cache_policy、prefix_changed_reason
  均显式赋 None。和 MCP／LSP／progress／health 占位一样，DTO 支持不等于来源已实现；最终
  合同必须明确补真实来源或删除无来源接口，不能宣称这些字段已成功独立投送。
- Todo 的 call_id 当前从 `state.deliveries` 倒序按 payload 查找，找不到即空串；扩展文档自身
  不保存该身份。该来源不能被未经证明地当成跨冷恢复的稳定身份，需要在完整合同中解决。
- `project_snapshot` 对 interaction 使用 `if let Ok(Some(...))`，runtime 使用 `.ok()`；当前
  投影错误可能被折成缺项／None。live interaction 投影也有同样分支。新可靠域必须区分真实
  absence 与无法投影，不能沿用这些分支后将其宣称为健康空基线或无损 typed 错误传递。
- live Turn 投影传入的 revision 是 `effect.sequence`，snapshot active Turn 使用
  `commit_sequence`。`ThreadLiveFeed::publish_last_turn` 的跨 Turn 单调 guard 据此成立；不能
  把它误写为只在单个 Turn 内递增的 aggregate revision，再照搬跨身份比较。

上述事实只补充准入，不预先选定 pending interaction cap、超限 query／拒绝方案、Todo 身份
迁移或来源补全方案；这些仍需 root 在派发合同中逐项冻结。不同资源的已有文本／集合限制
不能替代按领域、频率与载荷分割的传输设计。

### 4.4 聚合类型的非订阅消费者（迁移不得漏项）

当前聚合公开面不止 `subscribe_thread`。以下已经按真实调用链核对，最终删除表不能只搜索
订阅方法，也不能因同名就误删 core 自己的 `ThreadSnapshot`：

| 当前入口／类型 | 真实消费者与语义 |
| --- | --- |
| protocol `ThreadSnapshot`／`ThreadRuntimeSnapshot` | `pl-protocol/src/thread/mod.rs` 的产品投影；不同于 `pl_core::thread::ThreadSnapshot`，后者仍是执行 owner 的内部 canonical source，不是本次待删除公开聚合 DTO |
| FRB `handlers/history/mod.rs::read_thread` | 返回 `BridgeThreadSnapshot`，实际调用 `StudioRuntime::thread_snapshot`；不是同名 `StudioRuntime::read_thread` 的目录元数据查询 |
| `ThreadModelRouteCommandReply` | protocol `studio/settings_update.rs` 中包含整包 runtime、receipt、settings、mode_default_saved、warning；bridge `types/command.rs` 和 Dart adapter 同样机械转换，不能因删除 runtime 类型而丢掉其它命令结果 |
| SDK `ThreadCommands::_requestThreadModelRoute` | 每次尝试前从各自 owner 读取 route revision 与 settings revision；响应 runtime 不进入 store。新分域接缝必须保持这个观察／命令事实边界，而非用 query 或命令回复修复订阅水位 |
| SDK `ThreadCommands::_refreshRouteOwners` | 冲突后先刷新 canonical settings，再等待 `ThreadSession::resyncRuntime` 取得新 owner 基线；观察失败／demand 退役保留原已知冲突，不把失败变成无条件重发 |
| SDK `ThreadSession::resyncRuntime` | 只替换运行状态观察 binding，等待旧 binding 真实取消，再等新首基线；不关闭 Timeline 或替换唯一已加载正文。分域后需冻结对应域的精确屏障，不顺带把所有内容／其它域一起重开 |

`SetThreadModelRouteRequest` 的现有完整 CAS 面为 operation_id、expected_model_route_revision、
expected_settings_revision、account_id、model_id、effort；模型／思考强度共同校验，不能把
本次迁移变成两个互相覆盖的写入。命令 receipt 的 targets 与新域 stamp 之间的映射、公开
query 的替代签名及 server／Dart 消费者删除表，仍由最终 T1.B／T2 合同明确，本表不自行
发明替代返回值或保留旧兼容转发。

### 4.5 当前模型策略与请求冻结事实的实际来源

模型层已存在可复用的纯内存解析能力，不能因为 Thread 现有投影未接线，就在 runtime 或
Dart 重新计算策略：

- `pl-model/src/config/route.rs::AgentModelConfig::resolve_route` 返回
  `ResolvedModelRoute`，其中含完整 `ModelContextResolution`；
  `pl-model/src/model/info.rs::ModelInfo::resolve_context` 是最终策略的唯一算法入口。
  catalog 的 `ModelDescriptor.context` 已携带 unavailable、context_window、input_token_limit、
  auto_compact_limit、adjustment。当前 catalog 的读取／解析本身不发模型请求。
- 准备请求时冻结的是 `pl-model/src/runtime/thread_model/receipt.rs::ModelCallBinding`：
  account_id、model_id、protocol、wire_api、isolation、purpose、context_window、
  max_context_window、auto_compact_limit。它属于 `pl.model.prepared-request` v2；三个窗口
  缺失保持未知，不能用当前目录回填。turn_id／attempt_id／input_revision 由 core 的同一次
  `AttemptUpdate` 绑定，不在 binding 内。
- 当前 `ModelCallBinding`／`ModelRequestReceipt` **没有** settings revision、catalog revision
  或用户原始阈值覆盖字段；只保存模型层已经解析的最终值。不能在迁移 DTO 时凭现在配置
  补出“请求当时”的 revision／覆盖来源，也不能把配置命令的 expected revision 当成它们。
- `runtime/model_refresh.rs::start_model_refresh` 已消费 settings watch 和 catalog broadcast，
  对 `observed_threads()` 排队 deferred model update；该更新在下一 Turn 边界应用，不激活
  冷 owner，也不等于 Thread 的当前策略投影已主动发布。该既有执行绑定路径不能被新的
  GUI 新鲜度接线重复提交一次。
- `ConfigRuntime::read_with_catalog` 在同一读锁下返回配置与目录的相容快照，**不登记任何
  receiver**。`publish_settings_state` 的 watch 更新先于 ProductEventBus emit，也不能单独
  证明 subscribe/read/drain 无竞态；新投影仍需明确先登记观察、捕获基线和按来源水位去重
  的屏障。不能把“同一次读锁”误写成“观察登记与当前值读取已经是同一步”。

最终合同必须分别说明当前选定路由的最新模型策略与最近请求的冻结计量绑定，保留两者的
目标身份、unknown 与可用性差异；当前目录变化不改历史／在途绑定，GUI 不根据同名字段
猜测它们属于同一次请求。源结构是否需要扩充属于待冻结的接口／迁移决策，不从本次调查
推断需要升级持久化格式。

### 4.6 现有登记、驻留与可靠保存屏障（已核实，不等于新域屏障）

- `runtime/thread_stream.rs::subscribe_thread` 在整个登记过程持有 lifecycle lock，并先持有
  residency pin。live 路径先取得 `ThreadLiveFeed` 的 broadcast、storage watch 与 last-turn
  watch，再读取执行 handle 的 snapshot；当前 applied/revision 从该 snapshot 的
  commit_sequence 起步，当前 epoch 初值为1。这些是旧聚合订阅事实，**不是**新 owner epoch
  的已选方案，也不证明配置／catalog／Mode 三来源已经处于同一原子基线。
- `runtime/thread_observation.rs::ThreadLiveFeed` 的 storage 和最近终态分别为 retained watch，
  事件为 broadcast；最近终态只向更新的 canonical Turn/revision 推进。新域不能把这两份
  已保留事实改成只有订阅期间才能见到的瞬时事件，或通过历史正文猜最近终态。
- 同文件 `ThreadObservations::synchronize` 在调用时冻结目标 commit，等待初始化／applied，
  然后等待**原 observation incarnation 的 HistoryChannel handoff ticket** durable；最后只
  flush 已冻结的产品 writer ticket。它没有把新 incarnation 的 checkpoint 序号当作旧 channel
  的绝对 durable 水位，也不会无限等待之后的新写入。feed ACK／查询基线不能替代这个屏障。
- `product_event_bus/mod.rs::subscribe_topic` 通过同一 topics mutex 登记 topic receiver；
  `emit` 先分配全局 sequence、投送 internal channel，再取 topics mutex 分发。单独读取
  `current_sequence()` 不能证明某来源状态与 topic 事件已经在同一事务发布；后续仍需 root
  明确按来源版本捕获／drain／去重，不把全局产品 sequence 当任意域的可靠 revision。
- `runtime/mode_definitions.rs::finish_mode_command` 在真实配置命令结果形成后发布 Mode
  catalog；`product_event_bus/snapshots.rs::emit_thread_mode_catalog` 只接收非零且高于已发布
  水位的 revision，再发 `ThreadModeCatalogChanged`。目录事件可作为刷新通知来源，不能
  把通知中的全局 sequence 当 Mode registry revision，也不能令原运行中的 workflow
  改绑到同名新定义。`mode/manager.rs::ThreadModeRegistrySnapshot` 独立持有不可变
  revision／modes／catalog；它不与 ConfigRuntime 的配置＋模型目录共享同一把锁。
- `runtime/model_refresh.rs::start_model_refresh` 的当前 select 只消费 settings watch 和
  model catalog broadcast，没有消费 Mode catalog 事件。`model_binding` 会核验当前／保存的
  Mode 可用性，但那是执行绑定时读取，不是 Mode 变化已主动唤醒 Thread GUI 域的证明。

### 4.7 Assembler incarnation 与观察 owner 的释放边界

本节来自独立只读补证并经 root 核对关键关闭路径；不是新 feed epoch 的已选设计。

- `thread_assembler.rs` 的 Entry 已有进程内 `incarnation: Arc<()>`；reserve 在 registry
  mutex 下拒绝同 ID 已存在的 creating／entry。它用于 cleanup 的同一实例比较，不是可跨
  FRB 投递或冷恢复持久化的 owner ID，不能把“没有公开 epoch”误写成“没有内部 incarnation”。
- 同文件 `close_thread` 先将 entry 设为非 ready，然后依次等待 before-close、core Closed、
  observation drain、published resource cleanup；最后只在 token 仍相同时移除 entry。
  任何关闭／drain／cleanup 失败均在 remove 前返回，保留 owner 供重试。正常成功路径中，
  同 ID 的新 entry 只能在旧 entry 清理并移除后 reserve，不能再把新旧 entry 重叠写成已证事实。
- `close_all` 在 mutex 下先设 closing 封准入并广播准备取消；独立森林关闭与 preparation
  排空并行，失败累计且 owner 保留。Runtime 只在 close_all 无失败后继续 observation finish／
  task join，再做持久化 flush。单个 observation drain 中的同步保存屏障与最终 task join
  是两个义务，不能把现有 Drop abort 宣称为新可靠 feed 已真实 join。
- Runtime lifecycle lock 覆盖显式持锁的订阅／退出等操作，但后台 title 和部分新 Thread
  activation 可直接 ensure owner；并非每条 activation 路径都持有该总锁。assembler 的
  registry／closing 约束才是上述同 ID entry 保证的直接依据。旧 subscription 的 receiver
  不因 registry 移除自动改绑新 sender，远端 epoch／Closed／重建语义仍需完整合同明确。
- `runtime/thread_observation.rs::ObservationServices` 当前只有 recovery、store、events、
  performance、threads、writer；**没有 ConfigRuntime、settings receiver 或 ModeManager**。
  ProjectionWorker／LiveOwner 不能直接读取这些未注入来源。若 root 选择在此保有分域
  投影，配置／目录相容读取、通知与 Mode canonical baseline 能力必须显式定义注入边界，
  不把 ProductEventBus 的通知能力冒充已有配置／Mode 事实源。

### 4.8 交互 payload、读取能力与回应边界

- protocol `InteractionRequest` 包含 interaction_id、scope、revision、content、可选
  continuation、created_at／updated_at；scope 另含 thread_id、turn_id、可选 item_id／
  tool_id／agent_path 与 purpose。ToolApproval 的完整工具 arguments 原本是 opaque JSON，
  FRB 映射为 arguments_json；UserInput 的题目／选项／is_other／is_secret 都是真实请求，
  不是可丢弃摘要。FRB 当前未映射 continuation／purpose，但 Rust 决议仍消费这些语义。
- `request_user_input` producer 只限制非空题集、trim 后 ID 非空且唯一、question 非空；
  没有统一题数／选项数／字段字节 cap。core interaction 与工具 approval arguments 也没有
  可直接沿用的统一总载荷 cap。不能只套 Todo／Plan 上限，或截短完整审批输入后继续允许操作。
- Composer 的 approval／user-input docks 直接消费完整 payload，活动摘要／详情、Plan
  confirmation 与 Timeline 已结算交互也有真实消费者。若新执行域改为引用＋query，必须同时
  冻结完整数据到达前的动作准入、identity／revision 校验与这些消费者迁移，而非只缩小帧。
- 已有内部读取：assembler `read_product_interaction` 读当前驻留 entry；store
  `read_interaction`／`list_pending_interactions` 读 checkpoint；resolve 路径优先当前 actor，
  pending 不能用冷 checkpoint 冒充。它们没有可直接交给 Dart 的 FRB owner-scoped typed
  detail query，也没有现成分页／预算／取消 join／Superseded 合同。
- 当前 FRB `respond_interaction` 的完整参数是 operation_id、interaction_id、typed
  resolution，**没有来自 UI 的 expected_revision 参数**。SDK 冻结展示的 Thread／Turn／
  interaction 身份并在 lane 执行前再次核活跃身份；Runtime 重新读取 Pending，再由内部
  typed 状态机完成 revision/CAS。不能把内部 CAS 描述为 UI 已经传递了观察 revision。
- 相同 terminal resolution 只读取原事实／durable receipt；不同 resolution 冲突，不再次
  授权或执行。SDK 仅受理 receipt 并等待有序 identity observation，不用响应替代 canonical
  删除交互。新 feed ACK 不等于决议生效或 durable，也不能自动重放未知回应。
- Storage 已有 HistoryFault 类别、generation 与 accepted／durable 水位等 typed 小事实，
  但 last_error 仍是未限长字符串，没有在该投影统一生成 code／correlation 对象。没有已核
  可替代交互事实源的脱敏日志 query；按身份活动详情与 Timeline 字段读取不能冒交互详情。

### 4.9 配置／Mode 来源的实际 revision 与通知能力

真实 `ConfigRuntime` 位于 `code/pl-studio-runtime/src/config/runtime/mod.rs`，不是模型 crate。
root 已亲读其 `read_with_catalog`、catalog 发布和 Settings 发布路径：

- `ConfigRuntimeSnapshot` 有 `revision`、`updated_at`、有效运行配置，以及私有 canonical
  配置／usage-query revisions；`ModelCatalogRuntimeSnapshot` 独立有 `revision`、`updated_at`
  与 catalogs。两者位于同一 `RuntimeState` 的 `RwLock` 内，`read_with_catalog()` 在同一个
  read guard 下克隆两值。它保证这对读取相容，不等于给 Mode 或 observer 登记建立原子事务。
- `config/runtime/catalog.rs::publish_catalog_locked` 在已有 state write guard 内递增
  `catalog.revision`、更新目录，然后发 `CatalogChange { affected }`。catalog 接收器可先登记，
  但事件自身没有 revision；不能把 `affected` 当来源水位或把通知丢失当没有变更。
- `runtime/lifecycle/snapshot.rs::publish_settings_state` 先调用上述相容读取，再构造产品
  Settings／catalog 投影，随后 `settings_updates.send_replace(settings)`，最后分别发产品事件。
  该 watch 不在 ConfigRuntime 的 state lock 内登记或更新；投影构造也是 fallible，不能仅凭
  这一发布顺序声称所有配置写入与 Thread 新域基线之间已经有不可丢的登记屏障。
- Mode 的真实路径是 `code/pl-studio-runtime/src/mode/manager.rs`。
  `ThreadModeRegistrySnapshot` 保有独立 revision、modes 和 catalog；`ThreadModeManager`
  当前公开读取能力为 `snapshot()`，此版本没有与之配对的 retained revision subscription。
  Product 的 Mode catalog 通知和 registry 读取仍是两个边界。
- `ProductEventBus::subscribe_internal` 仅允许 runtime 自身跨域观察。已有 tool refresh 使用
  该通知来驱动原有执行资源刷新；这不能成为 GUI 订阅全部事件后在末端筛选的理由，也不等于
  新 Thread 投影已经接入配置或 Mode。执行绑定刷新与 GUI 只读策略发布必须区分。

root 已在 [design/18 §18.2.2](../../design/18-studio-state.md#1822-thread-只读策略来源与驻留投影)
选定目标架构：配置 owner 的相容 Settings／catalog 对与 Mode owner 的独立快照，分别提供
同步登记／当前值和 retained revision 唤醒，经组合根显式注入唯一 Thread 投影；不把现有
Product 全局 sequence、轮询或另一套配置缓存当来源屏障。这个来源观察是新增的必要 owner
边界，不宣称当前方法已经存在，也不重复执行 deferred model update。

所用标准能力是锁定的 Tokio 1.53.3 `watch`，root 从 `cargo metadata --locked --offline`
定位官方依赖源码并核对：subscribe 的当前值视为 seen，消费者必须先处理初值；
`borrow_and_update` 标记已见，`send_replace` 即使没有 receiver 仍保留值。watch 只保留最后值，
因此它承载配置失效水位，不承载 Turn／Interaction 可靠事件或命令结果。核对源码为该版本
`src/sync/watch.rs`（SHA-256 `301e9219793f97b513784501c00bc357e3e110f5d73f03742f5169cdb71d7a72`）。
来源能力的完整方法／类型、所有写入发布点及关闭接线仍须纳入 T1.B 完整合同；仅冻结本项
架构选择不足以释放编码，执行者不得自行补齐其余关键设计。

### 4.10 Interaction 嵌套字段册与不能丢失的语义

本节来自新的只读字段探索；root 已复核聚合、scope、purpose、continuation、question／option／
answer 与共用状态源码。下表保留 Rust 名与类型；serde 使用 camelCase，enum 的 tag 另行注明。
现有类型并未规定下列字符串／集合的统一大小上限，不把 serde default 当准入验证。

| 类型 | 全部数据字段／变体 |
| --- | --- |
| `InteractionRequest` | `interaction_id:String`、`scope:InteractionScope`、`revision:u64`、`content:InteractionContent`、`continuation:Option<InteractionContinuationPreset>`、`created_at:i64`、`updated_at:i64` |
| `InteractionScope` | `thread_id:String`、`turn_id:String`、`item_id:Option<String>`、`tool_id:Option<String>`、`agent_path:Option<String>`、`purpose:InteractionPurpose` |
| `InteractionPurpose` | `General`（serde 默认）；`AgentSessionPlanConfirmation(AgentSessionPlanConfirmationPurpose)`；tag为 `kind`／`data` |
| `AgentSessionPlanConfirmationPurpose` | `expected_revision:u64`、`operation_id:String`、`argument_hash:String`、`plan_hash:String` |
| `InteractionContinuationPreset` | `message:InteractionContinuationMessage`、`presentation:MessagePresentation` |
| `InteractionContinuationMessage` | `Resolution`；`Question { question_id:String }`；tag为 `type` |
| `MessagePresentation` | `Visible`／`Hidden` |
| `InteractionContent` | `UserInput(UserInputInteraction)`／`ToolApproval(ToolApprovalInteraction)`；tag为 `kind`／`data` |
| `UserInputInteraction` | `questions:Vec<UserQuestion>`、`state:UserInputState` |
| `UserQuestion` | `id:String`、`header:String`、`question:String`、`is_other:bool`、`is_secret:bool`、`options:Option<Vec<UserQuestionOption>>` |
| `UserQuestionOption` | `label:String`、`description:String` |
| `ToolApprovalInteraction` | `request:ToolApprovalRequest`、`state:ToolApprovalState` |
| `ToolApprovalRequest` | `name:String`、`arguments:serde_json::Value`、`working_directory:Option<String>`、`parent_agent_id:Option<String>` |
| `PendingInteractionState` | `operation_id:String` |
| `CancelledInteractionState` | `operation_id:String`、`cancelled_at:i64`、`reason:String` |
| `ExpiredInteractionState` | `operation_id:String`、`expired_at:i64` |
| UserInput resolved state | `operation_id:String`、`resolved_at:i64`、`answers:HashMap<String, UserInputAnswer>` |
| ToolApproval resolved state | `operation_id:String`、`resolved_at:i64`、`decision`（`Approved`／`Denied`）、`reason:Option<String>` |
| `UserInputAnswer` | `answers:Vec<String>`；外层 map 的 key 为原 question ID |
| `UserInputState`／`ToolApprovalState` | 各自有 `Pending`／`Resolved`／`Cancelled`／`Expired`，分别携带本表对应状态 |
| `InteractionResolution` | `UserInput(UserInputResolution)`／`ToolApproval(ToolApprovalResolutionPayload)` |
| `UserInputResolution` | `answers:HashMap<String, UserInputAnswer>` |
| `ToolApprovalResolutionPayload` | `decision`（`Approved`／`Denied`）、`reason:Option<String>` |

字段定义定位：`pl-protocol/src/interaction/mod.rs`、`interaction/state/{common,user_input,
tool_approval}.rs`、`event.rs`、`agent_session/plan/mod.rs`、`message.rs`。
聚合源码 SHA-256 为 `68430a734792191aff43147da549b36c77f29408049ffa01238e7b227b04b03b`，
共用状态为 `de6410e76d82ed5fbfc8508fcaff2705bc0f323aeec627b045532c345eb89c5a`，
question／answer 的 `event.rs` 为 `a6ccc810f5e428cbb3ce5577f65cfbe103c4c1bdb147dff3c35fe339ac809785`。

必须保留的区别与消费者约束：

- `is_other`／`is_secret` 缺省为 false；`options:None` 与 `Some([])` 是不同值。
  `continuation:None` 不能推导默认 continuation；Question 预设要求指定 ID 恰好存在一次。
  scope purpose 绑定 Plan 的 expected revision／operation／argument hash／plan hash，不能丢掉后
  再从当前 Plan 猜回原请求。当前 FRB 漏 purpose／continuation 不构成删除授权。
- terminal 状态仍有真实 payload：回答、批准／拒绝及可选理由、取消理由、过期时间和 operation
  身份。不能把 terminal 当成可任意丢弃问题或工具请求的证明；历史呈现与回应幂等仍有消费者。
- 既有问答 dock 读取完整 questions、原顺序、题干／header、全部 options 和 isOther／isSecret，
  空 questions 另有现存 rawBody fallback。它没有强制每题非空答案才能提交，当前 UI 的 trim／
  替代 answer key 也不是 Rust 一般协议限制。`request_user_input` 工具自身的非空题集／trim
  后 ID 非空唯一规则继续保留，但不能未经证据扩成全部 Interaction producer 的共同准入。
- approval dock 在操作前展示工具名、工作目录和完整格式化 arguments；parentAgentId 虽未在该
  dock直接显示，仍在领域值及相等比较中。arguments 的内部工具 schema 是 opaque，不能给任意
  JSON 子键发明 Interaction 公共协议字段。除该 opaque JSON 外，问题和生命周期均是已知 typed
  schema，不引入 raw JSON 兼容入口来代替它们。
- 未来如采用引用＋读取，必须同时覆盖上述全部字段、terminal与空题路径、当前请求 revision、
  取消／join以及完整输入到达前的动作准入。按 kind／index／field 可以定位现有 typed 数据，
  但当前尚无该公共 query／cursor／预算，不能把可定位性冒充已冻结方案或现成功能。

## 5. 不变的可靠语义与待定门槛

- 手动压缩仍为真实 `compact_thread(thread_id) -> Result<()>`／Dart `Future<void>`，没有
  native OperationId／receipt；不从 context 数字变化猜本命令成功，不自动重试写入。
- `ContextCompaction` 当前生产路径的 before／after token 实际为 None，DTO 支持不等于已测值。
- 新会话 preparation 是同一次创建命令的 Progress／Succeeded／Failed，不是可重连资源 feed；
  终态前断流 UnknownOutcome 不重发，观察离开不取消创建，成功导航仍核原意图。
- 不同 facet 不承诺跨域事务；ACK 不证明 effects／durable，可靠终态不绕投送额度。

派发前仍须 root 完成：

1. 新具体 Rust／FRB／Dart 类型与全部方法、基线／变化／缺口／传输错误字段。
2. owner epoch 与各域 revision 的生命周期、配置唤醒与冷／热 owner 转换屏障。
3. 各域双重载荷预算与可靠／latest 排队上限、超限动作和真正取消／join。
4. Plan 文档交付、状态变化与冷恢复方式、context 当前 catalog／冻结请求来源的精确选择。
5. HTTP／FRB／Repository／命令 receipt 的迁移、旧聚合公开入口删除及回归矩阵。

在此之前只允许互斥的事实调查与已批准 A2 实施，不把本表交执行者“自行合理实现”。
