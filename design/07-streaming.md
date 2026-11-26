# 07 - 会话线程实时流

本文描述 Native 会话的单一元事件广播、`ConversationFeed` 观察端口与产品主题传输边界。存储与实时区零读库边界见 [15](./15-session-storage.md)，时间线封组与状态机契约见 [26](./26-timeline-content.md)，客户端资源所有权见 [25](./25-frontend-state.md)，产品状态查询见 [18](./18-studio-state.md)。ACP 继续遵循 [28](./28-acp.md)，不套用 Native 协议。

## 7.1 两类独立观察

| 观察 | 内容 | 生命周期 |
| --- | --- | --- |
| 会话阅读流（`ConversationFeed`） | 主时间线增量补丁（`TimelinePatch`）、实时状态栏快照（`LiveStatusSnapshot`）、低频会话元数据（`SessionMetaSnapshot`）及按需大字段/工作组/历史页查询 | 由单一 `ConversationFeed` 打开和关闭 |
| 产品主题（Product Topics） | 目录、设置、账号、统计、更新器、MCP/LSP 等低频领域 | 由各领域 owner 的 typed topic 提供 |

Native 会话只使用上述单一 `ConversationFeed` 观察端口，不再拆分为互不协调的 `CurrentReader` 与 `HistoryReader` 双端口，也不在客户端同时开启多条观察流拼装时间线。

## 7.2 单一元事件总线与零真空拼接

Core 线程主循环通过单一通道发射无状态 `CoreEvent`，由 `pl-studio-runtime` 的单点翻译器归类后进入 `MetaEventBus`：

1. **规范历史事实（`Durable`）**：翻译器按 `history_events.timeline_role`（`0=hidden` / `1=work` / `2=boundary`）与 16 KiB 混合正文规则组装不可变历史事件，**纯内存**同步追加到 `HistoryStore` 的未入库内存日志（`UnflushedLog`）并立即分配单调 `seq`（严禁在热路径查询 SQLite），随后向 `MetaEventBus` 广播；后台持久化工作者异步批量 `INSERT` 写入 `history.sqlite` 并在事务提交后安全回收已落盘内存。
2. **瞬态实时信号（`Ephemeral`）**：流式文本开始/增量/结束、思考摘要增量、工具进度增量、压缩开始与模型断连重连恢复态不写历史库，由元事件所有者更新实时状态机，再发布 typed `LiveStatusSnapshot`；不额外把原始瞬态事件转发给主时间线。

由此保证：**已产生但尚未落盘 SQLite 的内存历史**与**已落盘历史**在同一个进程内对时间线数据处理层立即可见，彻底消除批处理窗口真空。

## 7.3 ConversationFeed 观察与按需查询

`ConversationFeed` 是 Native 会话面向 FRB、HTTP 与纯 Dart 客户端的唯一观察端口。每个可见会话仅建立一条连接：

- **订阅即同切面首帧**：打开 `ConversationFeed` 时先同步登记 `MetaEventBus` 接收者，再从 `(history.sqlite ∪ UnflushedLog)` 与当前内存态捕获同一切面的初始基线，随后持续输出有序增量流 `ConversationEvent`：
  - `Timeline(TimelinePatch)`：`Reset`、`PrependOlder`、`Append`、`Update`、`Remove`，与 Flyer Chat 的 `ChatOperation` 1:1 对齐；
  - `LiveStatus(LiveStatusSnapshot)`：实时状态栏互斥状态机快照（经过 16ms 节拍合并高频流式文本增量）；
  - `SessionMeta(SessionMetaSnapshot)`：低频元数据（用量、吞吐、待决交互摘要、Plan 头、工作流摘要、存储状态）；
  - `InputPresented { input_id, item_id }`：已入列主时间线的输入及其条目 ID，用于结算临时发送回显。
- **按需有界点查（复用同一句柄）**：
  - `load_older(cursor, page_size)`：向上翻页读取更早历史（拼接 SQLite 与未入库内存），返回 `PrependOlder`；
  - `reset_to_latest(page_size)`：从历史浏览模式追平最新窗口；
  - `load_work_group_members(after_seq, before_seq)`：在服务端完成同 `call_id` / `entity_id` 折叠及跨区间 `tool_called` 参数补拉；
  - `read_body_window(body_ref, offset, max_bytes)`：按 64 KiB 窗口读取 `> 16 KiB` 大正文或二进制附件；
  - `read_session_detail(kind, offset, max_bytes)`：从 Feed 已应用的内存快照读取 Plan、待决交互、Todo、Workflow 或 Active Skills/MCP/LSP 的 JSON 字节窗口。窗口最多 64 KiB，按字节偏移读取。非 ASCII 字符可能跨窗，拼接时必须核对 `owner_epoch`、`revision`、偏移和总长度，再解码 UTF-8。超过末尾返回空窗口。

若后端广播消费者发生滞后，`ConversationFeed` 发出 `ResyncRequired`。桌面时间线关闭旧句柄，打开新句柄并从首个 `TimelinePatch::Reset` 重建对应窗口。

## 7.4 HTTP 与 FRB 边界

HTTP Server 与 FRB 共用 `ConversationFeed` 和强类型 DTO。类型化工具条目同时可携带原有工具负载，供工具注册表选择对应的呈现格式。

| 能力 | FRB 单句柄方法 | HTTP 端点（相对于 `/api/v1/threads/{thread_id}/feed`） |
| --- | --- | --- |
| 打开并订阅事件流 | `open_conversation_feed` 及 `next_event` | `POST /open` + `GET /{feed_id}/events`（SSE `ConversationEvent`） |
| 读取会话元数据 | `session_meta_snapshot` | `GET /{feed_id}/meta` |
| 向上翻页 | `load_older` | `POST /{feed_id}/older` |
| 回到最新窗口 | `reset_to_latest` | `POST /{feed_id}/reset` |
| 展开历史工作组 | `load_work_group_members` | `POST /{feed_id}/work-group` |
| 读取大正文窗口 | `read_body_window` | `POST /{feed_id}/body` |
| 读取延迟详情字段 | `read_session_detail` | `POST /detail` |
| 请求关闭与汇合 | `request_close` / `close` | `POST /{feed_id}/close` |

CLI（`anywk`）、Bots 与内部运行导出仍可直接消费底层 `HistoryStore` 原子查询（`events_page`、`turns_page`、`read_body`）与内存 `MetaEventBus` 通知，并同步受益于零延迟内存序列。

## 7.5 产品主题流、用量与关闭生命周期

产品主题流（项目、目录、设置、账号、ACP、MCP/LSP、模型统计、更新器、启动与关机进度）沿用各自 typed topic 与既有 pull/feed 机制。无关领域变更不得触发会话 `ConversationFeed` 重建。

当前累计用量、live 用量、吞吐率与控件资格随 `SessionMeta` 发布。Plan 只推送状态和修订信息，打开详情时经 `read_session_detail` 读取正文。待决交互和侧栏所需的当前集合也随元数据提供，详情调用可独立读取选定字段。详情读取失败只影响对应面板。

打开、切换和关闭 `ConversationFeed` 只管理观察，不激活或停止执行。打开时先登记观察，再取得基线。没有运行所有者时，从只读保存状态取得暂停信息并读取历史；已有执行时只消费原观察所有者发布的当前状态。观察所有者先接住事件并准备历史来源与首份元数据，再发布可用观察源；准备期间的读取等待同一生命周期的完成、失败或取消，不另从执行句柄拼装一份修订含义不同的元数据。执行恢复边界见 [15](./15-session-storage.md#冷加载暂停与继续)。

热打开与冷转热共用订阅、来源交接和接续规则。冷转热保留同一 Feed 的读取身份与游标校验，把按需查询来源交接给运行所有者持有的历史 Store，再发布对应补丁。每次查询在准入时固定来源；已开始的查询按原切面完成或随关闭取消，旧分页游标仍限制在原历史上界。实时接续只消费生产者最近广播的有界内存记录，重叠事件按序号去重；范围不足或广播滞后时发出 `ResyncRequired`，由客户端重开观察获取新基线，生产者不读 SQLite 补洞。

关闭 `ConversationFeed` 先同步调用 `request_close()` 封闭查询与来源交接准入、撤销订阅与在途异步查询，再 `close()` 汇合等待所有在途任务退出并释放读取来源。失败保留原资源与重试责任，后台运行的业务 Thread 和共享 Store 的持久化写入器沿自身生命周期继续处理。

## 7.6 统计、账号、ACP 与目录观察边界

统计桌面界面继续使用独立 typed feed 推送头部摘要与传输状态；账号配置、模型目录与 ACP 各自保持其领域所有权与独立观察边界（详见 [25](./25-frontend-state.md) 与 [28](./28-acp.md)）。可变目录查询沿用固定 query/window pull 与独立成员观察契约，详情见 [18.7.1](./18-studio-state.md#1871-可变目录的查询观察)。

统计 feed 在自身协议中管理有界在途帧、连续消费确认和关闭。Dart 接收端退出后，推送任务取消生产并请求关闭统计 feed。关闭回执等待已登记的任务和读取资源完成清理，并报告真实的清理失败。桌面统计页基线读取的生命周期见 [25.13](./25-frontend-state.md#2513-独立统计领域与呈现模块)。
