# 15 - 会话状态、历史与调用记录

本文是 Native 会话当前状态、追加历史、调用诊断与冷恢复的唯一权威契约；Studio 文件布局与迁移边界见 [17](./17-studio-storage.md)，时间线展示见 [26](./26-timeline-content.md)，客户端与资源生命周期见 [25](./25-frontend-state.md)。ACP 内容继续遵循 [28](./28-acp.md) 的对端协议，不使用本文的 Native 当前态或追加历史契约。文档声明表示设计合同，不代表实现、迁移或跨平台验收已经通过。

<a id="native-current-与历史解耦的目标合同"></a>

## 15.1 Native 实时区与持久化的严格边界

Native 会话严格区分**实时纯内存区**与**持久化及冷启动区**：

| 区域与用途 | 权威载体 | 访问约束 |
| --- | --- | --- |
| 执行、上下文、状态机与实时广播 | `pl-core` 内存 `Thread` 状态 + `MetaEventBus` | **严禁读取 `current.json` 或 `history.sqlite`** |
| 已接纳但尚未刷盘的历史前缀 | `HistoryStore` 内存未入库日志（`UnflushedLog`） | 运行期纯内存递增分配 `seq` 与 CoW 追加；仅冷启动读一次 `MAX(seq)` 初始化 |
| 完整执行检查点与冷页面暂停信息 | 每会话独立的 `current.json` | 实时区每 2s 节流异步覆盖写沉（以及关闭最终落盘）；新一代执行准备统一加载，未运行时的页面可只读投影 |
| 已落盘的不可变原子历史 | Schema 27 追加历史库 `history.sqlite` | 后台工作者异步单向批量 `INSERT` 落盘；仅冷打开历史、翻页、展开已落盘工作组、读大块正文与 CLI/导出查询读取 |

实时处理链路（主循环状态推进、用户输入受理、工具执行与进度、元事件翻译、实时状态栏状态机、主时间线实时追加封组）不以任何方式打开 SQLite 读事务或读取 `current.json`。运行期内工具结果查验（如 `get_tool_task`）直接读取本进程内存任务表；驻留子智能体的协作等待直接消费内存 `MetaEventBus`。持久化对实时区仅承担异步落盘与背压通知职责，不构成同步栅栏或跨存储共同事务。

模型透明重试子尝试按原 `attempt_id + generation` 稳定身份纳入 `ModelSettlementPort`，经 `HistoryStore` 唯一有序效应确认保存；工具进度预览在任务退出当前状态时同步释放。

#### 可恢复对象与身份

`current.json` 是完整的 `ThreadCurrent`（schema 1），包含会话身份、保存者运行代次（`runtime_epoch`，UUIDv4）、保存时间、完整逻辑状态以及至多一个暂停态模型调用。正文、context、opaque 载荷、待交付结果、已接纳工具观察和模型已合并流按当前格式内联；持久附件沿用原资源身份、长度、摘要与媒体类型并逐项校验。连接、凭据、锁、取消令牌与活执行句柄从不持久化。

模型透明重试的子尝试通过原 Current 生产者保留稳定身份、已知用量及失败结果，并经原可靠交付/写入路径确认保存；确认仅覆盖该次事实，不能由后续无关写入顺带确认。失败保留原 writer 责任和模型失败，不开启下一次发送。此处保存确认遵循现有写入完成保证，不额外承诺断电持久性；具体预算、计量与重放语义见 [06 §6.5](./06-model.md#65-协议与传输层transport)，可靠模型交付见 [16](./16-core-contracts.md)。旧格式缺少子尝试明细时在明确版本迁移边界保留原总量与未知完整性，不编造拆分或按当前价格重算。正常 reader 只消费当前结构。

工具进度预览是驻留任务的可选观察。运行中、暂停或结果尚待交付的任务可保留预览；任务退出当前状态时，同次发布释放其预览，不等待下一次模型请求。捕获与展示从任务读取可用预览，缺少预览不阻断会话。加载已有 Current 时，在内存中丢弃没有所属任务的预览，不改写原文件、不从 History 补造任务，也不把进度推断为完成结果；后续正常保存只保留仍有任务归属的预览。有效预览的内容边界和必要恢复资源仍按原契约校验。

#### 捕获、保存与关闭

`CurrentWriter` 订阅核心内存脏版本号，每 2 秒节流捕获并异步覆盖写 `current.json`；每 Thread 至多一个在途写入任务。关闭时先等待主循环终止并发出最终 `ThreadCurrent` 交接，再等待写入完成并报告真实错误。保存失败保留脏标记与类型化错误供重试，不以历史库提交成功替代当前态保存成功。

#### 冷加载、暂停与继续

查看与执行恢复分别管理生命周期。未运行时的页面只读保存状态，呈现暂停信息及历史，不准备、迁移或改写存档，也不启动模型、工具或外部投递。页面观察的接续与关闭见 [07](./07-streaming.md#75-产品主题流用量与关闭生命周期)。

用户明确启动执行时，现有装配协调流程统一加载并校验完整 `ThreadCurrent` 及所需资源。根、子线程的工作区、模型和工具等准备步骤共用已加载结果，再将完整检查点交给执行所有者；检查函数不在参数缺失时自行读盘。检查点包含上下文、轮次、队列、工具与待答交互、模型路由以及执行使用的计划和工作流，不用历史或产品投影拼装逻辑上下文。必要的旧数据迁移仍由原冷恢复边界完成。

驻留所有者维护当前执行事实，后续命令复用它；页面切走不结束执行，切回订阅同一代次。只有新一代执行准备才再次加载检查点，不以磁盘保存状态覆盖驻留状态。独立冷查询、关闭和归档保留各自的存储职责。恢复后仍按现有规则对未配对工具调用以“结果未知”完成本地对账，不重放旧未完成工具调用，再进入正常执行流程。

<a id="独立追加历史"></a>

## 15.2 独立追加历史（Schema 27）

每个 Native Thread 只有一个 Schema 27 `HistoryStore`。`history_store_meta` 保存数据库、Thread 与 schema 身份；`history_events`、`history_bodies`、`history_body_chunks` 是唯一业务表，均由数据库触发器禁止更新和删除。`history_events` 由用于稀疏索引的标量列与开放动态字段（`payload_schema` + `payload_json`）构成，数据库不对 `kind` 设枚举 `CHECK`；**`timeline_role`（`0=hidden` / `1=work` / `2=boundary`）是主时间线直接展示与分组隔断的唯一权威标识**。

- **纯内存热接纳与单调序号**：`MetaEventBus` 将翻译后的 `HistoryEvent` 直接写入内存 `UnflushedLog`（有界容量 4096 事件 / 64 MiB，CoW `Arc` 共享快照），在内存锁内按冷启动初始化好的序列头连续分配 `seq` 而不查 SQLite，随即发布广播。
- **异步写沉与安全回收**：`HistoryPersistWorker` 按 20ms / 64 事件 / 1 MiB 批处理窗口从 `UnflushedLog` 拉取批次，在单一 `BEGIN IMMEDIATE` 事务中幂等 `INSERT OR IGNORE` 落盘，仅在 SQLite `COMMIT` 成功后才从 `UnflushedLog` 回收已提交序号；若此时存在翻页或初始化读操作持有旧内存快照，CoW 语义保证在途读取绝不丢失刚落盘的记录。写入失败保留未入库数据与类型化存储错误供显式重试，并发出背压信号在下一执行安全点阻塞新的付费模型/副作用操作。
- **16 KiB 混合正文**：单正文 `<= 16 KiB` 且单事件累计内联 `<= 16 KiB` 的有效 UTF-8 文本直接以内联 `inlineText` 写入事件载荷；超限正文或二进制附件写入 `history_bodies` 与 64 KiB `WITHOUT ROWID` 分块表 `history_body_chunks`，查询侧按 64 KiB 固定窗口随机读取。
- **冷热统一拼接查询**：非实时历史读取（会话初始化、向上翻页、展开历史工作组、大正文读取、CLI/Bots/导出查询）在同一切面先捕获 `UnflushedLog` 内存快照并随后开启 SQLite 只读事务，按 `seq` 去重合并两者，确保未入库事件与已入库事件无缝衔接。

## 15.3 传输与客户端边界

`pl-studio-runtime` 的时间线数据处理层统一消费 `MetaEventBus` 与 `(history.sqlite ∪ UnflushedLog)`，直接向上层 FRB 与 HTTP 交付贴近 Flyer Chat 的强类型 `TimelinePatch`、`LiveStatusSnapshot`、`SessionMetaSnapshot` 与折叠后的 `WorkGroupMember`。客户端不再维护双套 `CurrentReader`/`HistoryReader` 端口、第二套历史缓存或 UI 线程 JSON 二次解码逻辑（详见 [07](./07-streaming.md) 与 [26](./26-timeline-content.md)）。

## 15.4 调用诊断与关闭边界

模型与工具调用诊断继续使用版本化 JSONL 与可重建的 `calls.sqlite` 索引，不参与当前态恢复或历史正文。应用关闭分别等待各 Thread 的 `CurrentWriter`、`HistoryPersistWorker`、`ConversationFeed` 观察者与调用诊断所有者真实退出；显式永久删除先行封闭持久化准入并打断在途刷盘，仍需等待在途任务与资源释放后再移除磁盘目录。

未知结构版本、身份冲突、损坏资源或缺失必要迁移路径一律 fail-closed 并保留原文件/数据库。历史正文局部损坏明确返回读取错误，不把缺块解释为空内容；单个未知或损坏事件条目在时间线按条降级提示，不阻塞整页读取。旧 `pl-core` 通用 `ThreadCheckpoint`/`ColdStore` 双轨实现与 `CurrentReader`/`HistoryReader` 双端口已移除，历史迁移逻辑仅存在于 [17](./17-studio-storage.md) 定义的显式迁移边界。
