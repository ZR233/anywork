# 07 - 会话线程实时流

本文描述 Native 会话的 Current、History 与产品主题传输边界。Current/History 的存储与恢复权威见 [15](./15-session-storage.md)，时间线呈现见 [26](./26-timeline-content.md)，客户端资源所有权见 [25](./25-frontend-state.md)，产品状态查询见 [18](./18-studio-state.md)。ACP 继续遵循 [28](./28-acp.md)，不套用 Native Current 或 History 保证。

## 7.1 三类独立观察

| 观察 | 内容 | 生命周期 |
| --- | --- | --- |
| Current | 当前 run 的 State、projection、collection 与正文 | 由 `CurrentReader` 打开和关闭 |
| History | 不可变事件、Work/Single/member 页面、event/body 与 change | 由 `HistoryReader` 打开和关闭 |
| 产品主题 | 目录、设置、账号、统计、更新器、MCP/LSP 等低频领域 | 由各领域 owner 的 typed topic 提供 |

三者不建立共同游标、共同确认或共同提交。Current 可先出现尚未形成 canonical History 的正文；History 也可在冷页面中独立读取。Flutter 只按稳定业务身份组合显示，不把两个存储的可见性描述成原子。

Native 会话只使用上述 Current/History 端口，不再叠加第二套完成流、展示 reader 或 UI 确认协议。旧 v24 wire 只在冻结迁移 schema 中读取。

## 7.2 Current 观察

`CurrentReader` 是原 State assembler 的唯一薄观察端口。它提供：

- snapshot：一次有界 Current 基线；
- watch：同一 owner 的 Reset、notification 与 projection；
- collection page：由 `CurrentCollectionRef` 选择 bounded page；
- body read/watch：由 `CurrentContentRef` 与范围读取当前正文；
- close：封闭本 reader 的 metadata/body watch 和 page 读取，并等待真实 join。

owner、`runtimeEpoch`、`run_id`、`CurrentRevision` 与正文 generation 都来自同一资源。watch 首次总是给 Reset；连续通知沿用原 State assembler 顺序。若出现 Lagged、resync、owner 失效或无法证明连续，返回新的小型 Reset，不 replay History，也不另建 reducer。

`CurrentStateField` 是带 `kind` 的封闭联合：

- `Body { field, reference: CurrentContentRef, byteLength }`
- `Collection { field, reference: CurrentCollectionRef, count }`

State 只保留字段名与引用。字段序列化超过 2 KiB 才 deferred；小于等于阈值的值保持内联。runtime 的 `activeSkills`、`activeMcpServers`、`activeLspServers` 与 activity 的 `tools.active` 使用 Collection，`count` 是完整集合真实总量，不是当前页行数。`todo`、`progress`、`mcpHealth`、`workflow`、`plan` 以及 activity 的 `thinkingSummary` 等使用 Body。

集合页条目使用 `CurrentPayloadData::Inline` 或 `CurrentPayloadData::Deferred { reference, byteLength }`；条目大时只返回 body 引用。调用方沿 reference 的 owner、generation 与范围读取，不把整个集合拼成第二份常驻 State。Body 也按 64 KiB 窗口读取，并核对 generation、长度与 EOF。

热 owner 的资源由原 ThreadLiveFeed 的 State resource index 持有，多个 Current 引用共享同一不可变内容；冷 current 从 JSON 建立同 shape 的引用。外部只看到 opaque generation 和 owner，不能推导 live/cold 命名公式，也不能把 live 与 cold 的 revision 相互比较或复用。

`thread_snapshot` 等一次性 Current 查询同样打开 `CurrentReader` 并复用该 assembler，只返回有界 State；它不重新 project 全数组、不等待 History usage，也不安装第二个执行 owner。

关闭 CurrentReader 会先同步撤销本 reader 新准入，再取消并 join 它拥有的 metadata/body watch 和 page 读取。调用方先取消与父 reader 后关闭等交错都真实收束；关闭 Current 不关闭 HistoryReader 或 HistoryStore。

## 7.3 History 观察

`HistoryReader` 提供固定 cut 的纯查询：

- 主时间线与业务行页面；
- 按 group 的 member 页面；
- event 页、event 详情与 body 目录；
- body 范围读取；
- Turn、Source、Cost 与 Accounting 查询；
- 从已有 cut 等待后续 change。

History change 只唤醒调用方重新查询有界范围，不携带完成、消费或保存 ACK，也不要求客户端推进 server cursor。新页面使用调用方捕获的 `HistoryCut`；阅读更早页面时保留同一 cut。换 Thread、reader、数据库或 cut 后旧 cursor 失效。

History 读取不促发 Current 保存，不激活模型或工具，也不从 Current source 状态重算历史组。一个 HistoryReader 关闭只释放自身资格，不关闭共享 HistoryStore 或其他 reader。

## 7.4 HTTP 边界

Current 与 History 分别 open，均返回 `readerId`，后续请求用 `X-Anywork-Conversation` 指定原读取资格。

Current 端点：

| 路径 | 用途 |
| --- | --- |
| `POST /current/open` | 检查 `currentProtocolVersion`，建立 CurrentReader 并返回 owner id |
| `POST /current/snapshot` | 有界 Current 基线 |
| `POST /current/watch` | SSE `CurrentFrame`，事件名为 `current` |
| `POST /current/page` | Current collection page |
| `POST /current/body/read` | 有界 Current body window |
| `POST /current/body/watch` | SSE `ContentWindow`，事件名为 `body` |
| `POST /current/close` | 撤销本 reader 的 watch/page 并 join |

History 端点：

| 路径 | 用途 |
| --- | --- |
| `POST /history/open` | 检查 `historyProtocolVersion` 并建立 HistoryReader |
| `POST /history/capture` | 捕获 opaque cut |
| `POST /history/timeline` | Work/Single 主页面 |
| `POST /history/group` | member 页面 |
| `POST /history/turns` | Turn 页面 |
| `POST /history/events` | 按 query 的 event 页面 |
| `POST /history/event` | 精确 event 详情 |
| `POST /history/bodies` | event 的 body 目录 |
| `POST /history/body` | 有界 body 范围 |
| `POST /history/costs` | 费用页 |
| `POST /history/accounting` | 累计用量 head |
| `POST /history/changed` | SSE `changed` / `closed` 通知 |
| `POST /history/close` | 撤销本 HistoryReader |

端点均以 `/api/v1/threads/{thread_id}` 为前缀。SSE 只承担 Current/watch 与 History/change；普通 page/body 查询不占另一个流的信用。连接使用有界发送窗口，断连与 close 都先封闭准入，再 join 原 reader/watch。

协议版本或 schema 不匹配立即返回类型化 Protocol mismatch，不探测旧字段或降级为旧 reader。

## 7.5 FRB 与 SDK

FRB 机械映射同一组 Current/History 类型并转发显式句柄，不生成第二套 State reducer、历史列表或 frame 水位。SDK 会话 owner 通过 Current 提交 State 的唯一 Dart 写入口；History 页面交给 Flutter 时间线 owner。

Current 与 History 的 reader、collection page、body read、watch 和 close 都是独立资源。SDK 不跨 AppGraph 共享原生句柄，不以 `StreamSink.add` 成功证明业务消费，也不在 Dart 建无界中转队列。组件只关闭自己的观察租约；关闭失败保留原 owner 和重试责任。

Flutter 时间线应用规则见 [26.8](./26-timeline-content.md#268-flutter-唯一窗口与串行-apply)。

## 7.6 产品主题流

项目、会话/智能体目录、设置、账号、ACP、MCP/LSP、模型统计、更新器、启动进度与持久化状态使用各自 typed topic。主题只承载领域 owner 已发布的事实，不承载轮次 token 或 History 正文。

主题订阅先登记再捕获基线；最后观察者释放后回收通道。通道关闭不是业务资源删除，重订阅使用新基线。无关领域变更不能触发会话 Current/History 重建。

侧栏目录使用 §7.11 的固定 query/window pull；其他简单可变领域可使用一个最新待交付值和一个在途读取。统计领域保留其自身有界 typed feed 与消费确认，不能把该机制扩张成 Native Current/History ACK。

## 7.7 用量、活动与状态栏

当前 usage、live usage、活动阶段、工具计数、todo/progress 与控件资格来自 Current State。State 的轻量 metadata 不等待正文或集合读取；正文读取失败不撤销仍有效的 usage 与执行指标。

作者性终态用量由 Current 的累计摘要与 History 的 Accounting/usage 事件分别承载。当前指标不能证明 History 已提交，History cut 也不能反推当前 owner 是否存活。展示层不通过全量历史回填缺口，不从日志或字符数估算未知用量。

<a id="78-统计-frb-推送与关闭"></a>

## 7.8 统计 FRB 推送

统计桌面界面使用独立 typed feed 推送头部摘要与传输状态，不从 bootstrap 或全量 History 读取统计数据。首帧是当前基线，后续交付已发布统计材料或版本化增量；慢消费者的待发送槽只保留最新可替代版本。

统计 feed 可以在自身协议中保留有界在途帧、delivery sequence 与连续消费确认。该确认属于 StatisticsRepository 与统计 producer，不是 Native Current/History 的保存或历史 ACK。取消、Failure/Closed、reader join 与材料读取仍由统计 owner 管理。

<a id="79-账号领域观察与背压"></a>

## 7.9 账号与 ACP 领域观察

账号配置、模型目录、用量与 ACP 各自保留事实来源和 revision，通过 typed port 交给对应领域 Repository。Provider/FRB 不合并第二份 canonical，页面重建不主动探测外部服务，迟到结果不得写入换代后的 owner。

ACP 使用其官方会话更新与能力协商，不转换为 Native Current/History、Work/Single、History schema 或保存确认。Native 与 ACP 共用页面路由和资源 UI 边界，但不因此共享业务游标。

<a id="710-会话推送交付确认与关闭"></a>

## 7.10 会话资源生命周期

打开 Current 或 History 都不会启动模型。CurrentReader 可读取 RAM owner 或已保存 current；HistoryReader 仅读取 schema 25 数据库。页面隐藏只释放自己的 reader/watch，不停止运行中的 Thread、Current writer 或 History pending。

关闭顺序是先同步封闭准入，再取消等待，最后 join 该 owner 已登记资源。Current 父 reader 的关闭覆盖自己的 watch；超时或调用方取消都不能遗弃已准入 future。HistoryReader 关闭不关闭共享 store，应用全局关闭另行等待所有 reader 与 writer。

## 7.11 可变目录 pull

目录 query 由不透明句柄绑定固定 query/window 或 thread ID。首次与后续 frame 都来自同一权威切面，携带完整有序 ID、边界和 `ResourceStamp`。SDK 接纳当前帧后才请求下一个，同句柄拒绝并发请求。

关闭同步撤销准入并唤醒等待，再 join 已准入读取。换查询或窗口创建新观察；旧结果不能补入新窗口，也不以目录事件重建第二份过滤结果。目录事实与窗口预算归 [18.7.1](./18-studio-state.md#1871-可变目录的查询观察)。
