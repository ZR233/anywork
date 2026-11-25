# 26 - Native 时间线、Current 与追加历史

本文是 Native 时间线呈现的唯一权威源。Current 的恢复与历史存储见 [15](./15-session-storage.md)，Schema 26 的物理结构见 [17](./17-studio-storage.md)，客户端资源归 [25](./25-frontend-state.md)，视觉规范见 [19](./19-studio-ui.md)。ACP 内容仍由其外部协议定义，不转换成这里的 Native 原子事件或 `WorkRange`。

## 26.1 三类事实与唯一所有者

| 数据 | 所有者 | 交付 |
| --- | --- | --- |
| 当前执行、当前正文、交互、Plan、usage 与活动摘要 | Core owner 与 Current assembler | `CurrentReader` 的有界 snapshot、watch、collection、body |
| 已接纳的不可变原子历史事件与正文 | schema 26 HistoryStore | `HistoryReader` 的 cut、`timeline_page`、`work_range_page`、event、body、change |
| 已加载不可变历史窗口、历史工作组折叠、展开、滚动 | Flutter 时间线会话 owner | 唯一不可变 controller、历史工作组 ViewModel、generation 与 serialized apply |
| 实时开放工作区、进行中原子项、流式正文与状态提示 | Flutter 实时状态栏（`LiveStatusBar` / `TimelineSessionOwner`） | 仅在 `LiveStatusBar` 呈现当前未封口 `WorkRange`、Current overlay 与流式正文 |

Current 和 History 没有共同事务、共同切点或 ACK。Current 可先显示仍在执行的内容；在执行尚未结算前，未封口 `WorkRange`、进行中工具/思考及流式助手正文仅在底部实时状态栏呈现，主时间线严格只接纳已封口 `WorkRange` 与不可变 `divider` 卡片，不对已入列条目做原地覆盖。后续事件落库封口后，新块再追加到主时间线并同步退出实时状态栏。不能把两个存储的可见性描述成原子，也不能从 Current 字段推断某个历史事件一定已提交。

新的 Native 写入只产生 Current 与 schema 26 原子 History 事件。schema 25 与 v24 类型只存在于显式迁移边界，正常读写路径只使用 schema 26。

## 26.2 无状态原子事件、`divider` 与索引派生 `WorkRange`

历史写入完全无状态，事件之间**互不等待、不维护工作组状态机、不回改历史行、也不改写后台工具终态身份**。每次用户输入、工具调用、等待审批、转后台、取消请求、终态完成与助手回复都作为各自独立的不可变原子事件顺序追加至 `history_events`（前导纯索引标量列，尾部为动态字段 `payload_schema` + `payload_json`；数据库不对 `kind` 设枚举 `CHECK`，新增工具或新事件字段零数据库迁移）：

- `divider`（主时间线分隔事件）：用户输入（`input_accepted`）、助手可见完成正文（`text_completed`，含曾有可见边界但最终为空时的 `finalEmptyAfterContent` 标记）、计划公开决议（`plan_resolved`）及带独立展示资格的终态工具事件。每条 `divider` 本身就是主时间线上的独立卡片。
- `work`（工作过程原子事件）：工具生命周期原子事件（`tool_called`、`tool_waiting_approval`、`tool_backgrounded`、`tool_cancel_requested`、`tool_completed`，同一次调用全程共享同一个 `call_id` 与 `tool_name`）、推理（`reasoning_started`／`reasoning_completed`）、上下文压缩（`compaction_started`／`compaction_completed`）、子智能体（`agent_spawned`／`agent_completed`）与等待/原始/技能/文件事件。
- `hidden`（非时间线业务与审计事件）：`run_*`、`turn_*`、`source_*`、`usage_*`、`parent_report_recorded`、`review_delivery_recorded`、`retained_resource_recorded` 及不可见空产物，供业务查询、导出、计费和机器人回复消费。

主时间线的工作区间 `WorkRange` 不在写入期持久化为 `Work` 锚点或 `group_*` 事件，而是在查询期由 `idx_events_dividers` 与覆盖索引 `idx_events_work(seq DESC, occurred_at)` O(log N) 直接切分：

- 任意相邻两条 `divider` 之间（以及最新 `divider` 到 `through` 之间）只要存在至少一条 `work` 事件，即自然构成一个稳定的 `WorkRange`（标识 `work:<first_seq>`，边界 `(after_seq, before_seq)`、`first_seq`、`last_seq`、`started_at`、`ended_at`、`run_id`、`event_count`）；
- 一旦新的 `divider`（如助手可见说明或终稿）落盘，`before_seq` 自动固定，旧工作区间天然封口；即使后台工具跨正文运行或被用户停止，写入器也不做跨事件等待或 `BoundaryObserved` 截断快照。

## 26.3 混合正文契约（16 KiB 内联与 64 KiB BLOB 分块）

写入任何原子事件的正文（`body`、`reasoning.summary`、`tool.arguments`、`tool.result`、`tool.output-artifacts`、`wait.presentation` 及内部回执等）统一采用固定 16 KiB 阈值分流：

- **有效 UTF-8 文本/JSON 且单正文 `<= 16 KiB` 且单事件累计内联总字节 `<= 16 KiB`**（非二进制附件）：直接以内联字段 `"inlineText"` 存入该事件 `payload_json.bodies[]`，不写入 `history_bodies`／`history_body_chunks`，列表或工作组页拉回即可首帧直出，无需二次 `read_body`；
- **`> 16 KiB`、超出单事件 16 KiB 内联预算或非 UTF-8 二进制与附件**：写入 `history_bodies` 与 64 KiB `WITHOUT ROWID` 分块表 `history_body_chunks`，并在 `payload_json.bodies[]` 记录 `HistoryEventBodyRef`，由读取侧按 64 KiB 固定窗口 O(log N) 随机读取。

事件不再使用 `CanonicalPayload`／`CanonicalMetadata` 二次正文包装；旧 schema 25 已有 `history_bodies` 与 `history_body_chunks` 在升级到 schema 26 时原地零拷贝复用。正文缺失、越界、摘要不符或引用身份冲突都明确失败，不把损坏显示为“空”。

## 26.4 HistoryReader：固定 cut、`WorkRange` 与跨区间反查

History 只提供 query/page/cut/change，不保存全历史缓存或 ACK 状态。读取开始先捕获 accepted head 和 RAM pending 根，再打开新的只读事务；数据库已提交事件与尚未 flush 的 pending 在固定 cut 内合并。flush 成功后才 reclaim 对应 pending；在途查询持有旧根，回收不破坏其读取。

- `timeline_page(cut, cursor, demand)`：沿 `idx_events_dividers` 与覆盖索引 `idx_events_work` 返回 `Divider(HistoryEventRecord)` 与 `WorkRange(HistoryWorkRange)` 有界页，**构建折叠 `WorkRange` 不回读事件 `payload_json` 或正文**；
- `work_range_page(after_seq, before_seq, cut, cursor, demand)`：在固定 `cut` 上按 `seq ASC` 有界分页原样返回区间内的 `work` 原子事件 `HistoryEventRecord`，后端不做跨事件融合；
- `events_page`（含按 `call_id` 走 `idx_events_call` 精确查询 `Call`）、`read_event`、`list_bodies`、`read_body`、`turns_page`、`costs_page` 与 `accounting`：服务跨区间调用参数补拉、全文检索、运行导出、机器人回复与计费；
- `HistoryReader` 读取 `history_events` 时原样透传 `(kind, payload_schema, payload_json)`，**不使用 `deny_unknown_fields` 或按未知 `kind` 拒绝整页**，保证前向兼容。

主列表默认页预算提升至 `128 KiB`（协议允许 1–512 行与 1 字节–1 MiB，适应至多 16 KiB 内联正文）；完整响应、游标和编码字节均计入预算，候选放不下时留给下一页，单项超限明确报需求错误。查询游标固定数据库身份、历史 `cut`、查询范围与顺序；更换 Thread、reader、数据库或 `cut` 时旧游标失效。

## 26.5 CurrentReader：同一 State assembler 的唯一输出

Current 由原 State assembler 生成，`CurrentReader` 是 snapshot/watch、collection、body 与 close 的薄端口。owner、`runtimeEpoch`、`run_id` 和 revision 来自同一 owner；UI 只订阅这一 State 来源，不再接旧 ConversationStateFeed 做二次 apply。

`CurrentView` 包含当前 owner/revision、schema 18 `ThreadSnapshot` 和 `CurrentProjection`。Projection 只携带 logical status、execution presence、当前 activity/turn、真实 sources、当前 atoms、Plan/交互引用、有界 previews 和 collection refs。`CurrentAtom` 不携带历史完成身份。

大字段通过 tagged `CurrentStateField` 明确 deferred：runtime 的 `todo`、`progress`、`mcpHealth`、`workflow`、`plan` 等为 Body；`activeSkills`、`activeMcpServers`、`activeLspServers` 与 activity 的 `tools.active` 为 Collection；`thinkingSummary`、`tools.latestStarted` 等单值为 Body。字段超过 2 KiB 才 deferred，Collection 的 `count` 是完整总量，页条目可为 Inline 或 `CurrentPayloadData::Deferred`，大项不复制进 State。小头空占位不是完整值；调用方按 reference 的 owner、generation、offset 与 length 读取。generation 是 opaque namespace，冷/热公式不公开；两种来源使用同一 State shape，不维护两套 DTO。

state 元数据、usage、live usage、耗时和 controls 不等正文或 collection。Current 正文观察只随该 owner/generation 增长或替换；token 变化可以只发 body 更新，不推动历史事件或全 State 重建。当前正文终态也不必然已有 canonical 历史。

Flutter 不自造持久化历史分组。主时间线严格保持不可变，只展示历史 `divider` 与已封口/已结算 `WorkRange`，从不接收 `CurrentAtom` 叠加或原地行替换。所有实时/可变执行 UI——包括未封口 `WorkRange`（可按需在实时栏内局部展开查看进行中工具与思考）、正在流式输出的 `CurrentAtom`（由 `ConversationResponseView` 渲染）以及活动/审批/保存阻塞提示——统一由底部 `LiveStatusBar` 承载；只有对应 Current 正文在 `LiveStatusBar` 中已有真实挂载与内容布局证据时，才由正文渲染器承接响应／压缩提示，折叠、遮蔽或卸载时撤销该资格。一旦后续 `divider` 写入封口或执行结束，该尾部 `WorkRange` 与终态事件再作为不可变块一次性追加进主时间线，并退出 `LiveStatusBar`。即使主时间线处于历史浏览模式（固定原 `cut`），`LiveStatusBar` 仍持续独立更新当前执行的开放工作区、流式正文与活动状态，提示存在新输出而不改写旧历史窗口。Current Atoms 保留一个有界集合页，只报告已加载数；进行中工具明细统一在实时状态栏内可展开的开放工作组中查看，不在实时状态栏外单设平行的活动工具分页列表。

Current watch 发生 lag、resync 或 owner 更换时返回小型 Reset，并重新捕获完整小 State；不 replay 历史。collection cursor 固定 owner 和 revision，版本变化返回 stale；body reference 固定 owner 与 generation，replace 后旧引用失效。旧 owner 的迟到 body、collection 和 watch 结果不能写入新 owner。

关闭 CurrentReader 时先同步撤销本 reader 的 metadata/body watch 与 page 读取准入，再唤醒并 join 所有已准入操作及子 watch。调用方取消与父 reader 关闭并发时也必须共同收束，不等待或关闭 HistoryStore。

## 26.6 业务引用由 State 交付

Plan 与交互的当前读引用由同一 State 发布者交付。`CurrentPlanHead` 包含 revision、phase 和可选 document body ref；`CurrentCollectionRef` 绑定 owner、collection 与 revision。引用只有在原业务资源已经可读时才发布，token、正文读取、保存进度和 UI apply 不推动其 revision。

`plan = None` 表示当前没有计划；计划存在但没有文档时 document 为 `None`。interactions collection 未建立时引用为 `None`；已经建立的空集合可拥有有效引用，不能把读取失败吞成空集合。

Plan、交互详情和文件内容通过引用自己的 owner/generation 读取；资源换代只退役对应详情窗口。交互集合按待审批、待回答、已结束及稳定身份排序。原 Session State owner 独立读取首条，最多物化一个当前决定，不累计完整列表；结构化载荷上限为 1 MiB，deferred 原文按 64 KiB 分段读取。引用变化、Reset 与关闭撤销旧请求；解析或读取失败单独交付交互错误，不阻塞其他 Current State 或冒充空集合。当前引用未读完或失败时不授予交互基线，不能因空展示确认原交互已处理；只有匹配引用的成功结果可证明缺席。命令仍对原交互身份与 revision 做 CAS，详情窗口不改变当前决定。

## 26.7 工作组 ViewModel 折叠、单条回退与正文阅读

Current 正文按 `CurrentContentRef` 的有界窗口读取；History 的 `<= 16 KiB` 小正文直接从事件 `payload_json.bodies[].inlineText` 读取，`> 16 KiB` 大正文与二进制附件按 `HistoryEventBodyRef` 的 64 KiB 有界窗口读取。两者都保留 offset、返回 bytes、可用长度和真实资格，不能用一个所有者的窗口扩展另一个所有者。

折叠工作组在主列表只渲染 `WorkRange` 头部，不读取区间事件或正文；展开后，工作组 ViewModel（`DisplayMemberController`）连续拉取该固定 `cut` 下 `work_range_page(after_seq, before_seq)` 的全部原子事件批次，并在视图模型内按 `first_seq` 升序完成折叠：

1. **同 `call_id` 合并为一条最新态展示行**：按该 `call_id` 首次出现的 `first_seq` 固定列表位置；从 `tool_called` 提取调用元数据、`presentationContract` 与 `tool.arguments` 正文；从区间内 `seq` 最大的事件提取最新状态/终态（`running`、`waitingApproval`、`backgroundStarted`、`cancelRequested`、`succeeded`、`failed`、`cancelled`、`interrupted`）、完成时间与 `tool.result` / `tool.output-artifacts` 正文，合并为单条展示并保留按阶段排序的原子事件列表。
2. **跨区间 `call_id` 补拉**：若某 `call_id` 在本区间内只出现后续状态或完成事件（例如后台 `exec` 跨过助手正文后才结束），ViewModel 对缺失 `tool_called` 的 `call_id` 去重发起有界 `Call` 历史查询，补齐调用参数与契约而不阻塞其他条目渲染。
3. **非工具实体与实时状态栏内 `Current` 叠加**：同区间内无 `call_id` 但有相同 `entity_id` 的事件（如 `reasoning_started` → `reasoning_completed`、`compaction_started` → `compaction_completed`、`agent_spawned` → `agent_completed`）同样折叠为一条最新态行；当且仅当工作组处于 `LiveStatusBar` 的未封口开放区（`beforeSeq == null` 且 `runId == currentOwnerId`）时，工作组 ViewModel 按 `call_id`/`entity_id` 叠加仍在运行中的 `CurrentAtom`，并追加尚未入库的活跃实体行；主时间线内的 `WorkRange` 永不叠加 `CurrentAtom`。
4. **单条独立解码与不兼容回退**：
   - 未注册的新工具 `presentationContract` 或未知工具名统一回退内置 `generic@1` 通用策略，正常展示工具名、状态、参数与输出，新增工具无需数据库迁移或前置发版；
   - 遇到未知 `kind`、不支持的 `payload_schema` 或单行损坏的 `payload_json` 时，通过 `ChatItemCompatibility.unknown` / `ChatItemCompatibility.malformed` 在**该单条记录**原地呈现中性回退提示，绝不抛错中断整页或影响相邻卡片；
   - 仅含 `tool_called` / `tool_backgrounded` 等非终态事件的工具直接按最新原子状态与调用参数渲染，不再回查终态事件或误报读取失败。

附件和媒体继续使用会话 `resources/` 的可靠引用、长度、摘要和媒体类型。工具捕获已截断的事实在 bytes 中保持截断来源，UI 不能把显示摘要当完整输出。历史读取不重新执行工具、访问原工作区文件或重新生成附件。

用户及上级智能体输入的复制图标位于气泡外下方，与气泡末端对齐。智能体输出中，只有 `finish_turn` 成功交付后写入历史的原始最终正文显示复制图标，图标位于正文下方起始侧。复制图标通过无障碍语义提供本地化名称。生产者将 `completion:` 实体身份命名空间专用于这类交付，界面结合最终正文通道与已完成的原始历史记录识别。长正文的「下一段」独立于复制操作。

## 26.8 Flutter 唯一窗口与串行 apply

Flutter 的现有 timeline controller 是应用内唯一已加载**不可变历史窗口**。它只保存有界主列表条目（`Divider` 与已封口/已结算 `WorkRange`）、历史工作组 ViewModel 和展开状态；不是 Rust HistoryStore 的镜像，也不为每个 scope 建立第二 reducer，且对已入列的不可变条目仅在严格需要时做安全补充，绝不因 `HistoryCut` 推进或 `beforeSeq` 补齐触发原地改写或折叠状态重置。实时 `Current` overlay、未封口尾部 `WorkRange` 与流式正文全部由 `TimelineDisplayLease.liveOpenWork` / `live` 交付给 `LiveStatusBar` 持有。

画面键使用稳定 `event_id`（`divider`）与 `work:<first_seq>`（`WorkRange`）；工作组内部行使用稳定 `call:<call_id>` / `entity:<entity_id>` / `event:<event_id>`。older query 是纯页查询，只能通过明确 apply 入口一次 Prepend，不能隐藏 apply、推进 Current owner 或复写其他 scopes。

实时模式只接纳最新一页的不可变历史项及其 cut：若最新页首项为执行仍在进行的开放 `WorkRange` 且当前尚未进入流式正文回复，将其分流给 `LiveStatusBar.liveOpenWork` 持有而不入列主时间线；仅将已固定的历史项按稳定键只增不改（并在超出窗口上限时从头部裁剪）同步至该有界页面，且在组件成功后提交该页的 older 游标。一旦流式正文开始、执行结束或后续 `divider` 写入封口，原开放 `WorkRange` 立即结算为历史块追加至主时间线并退出 `LiveStatusBar`。进入历史浏览后，整个已加载历史窗口固定原 cut；后台变化只提示存在新输出，older 仍使用该 cut 的 opaque 游标，不裁掉正在浏览的行。历史浏览模式只读 History，同时 `LiveStatusBar` 仍继续更新当前执行的实时工作区与流式正文。回到实时位置通过原 reader 读取新的最新页并建立新的展示资格；保留同键的展开意图，旧正文与查询资格退休。提交消息不等待这次查询或绘制。

`WorkRange` 的边界 `(after_seq, before_seq)` 必须来自该行接纳的同一 `cut`；展开工作组时，原 History owner 按 `seq ASC` 连续拉取该固定 `cut` 下的全部 `work_range_page` 批次，传输预算限制单批，不限制组内总事件数。工作组 ViewModel 增量折叠并发布每个稳定行的最新态，换 `cut` 或失败保留原静态展示并撤销旧读取资格。

原生主时间线和实时正文各自保有阅读位置。用户向旧内容滚动时暂停该视口，手动滚回最新边缘时恢复。内容或视口尺寸变化只调整仍在跟随的视口。短视口自动补页沿用窗口的切面和预算，补页期间仍可接纳新的最新页，过期的补页结果丢弃。文本有选区时，实时正文保留阅读位置，直到选区结束并由用户返回末端，或用户显式恢复跟随。

原生会话用一个“回到最新”入口恢复所有暂停的可见视口，有新历史输出时在同一入口提示。主时间线从历史浏览恢复时只由 `TimelineSessionOwner` 读取并接纳最新窗口，Flutter 负责视口位置。用户再次向旧内容滚动、隐藏或切换会话可撤销这次定位；查询失败沿已有错误状态呈现。Composer 提交独立完成，新回显进入视图便可定位到它，同时通过同一个恢复操作请求最新窗口。

ACP 将当前会话的消息和过程组交给 Flyer Chat 反向列表。组件管理滚动位置、用户消息出现后的定位以及“回到最新”。最新内容从阅读区下缘向上生长，长消息继续排版时，浏览位置可能随行高变化。权限和执行状态分别在权限卡与状态栏呈现。列表使用当前 ACP 内容投影提供的稳定行标识。工作区布局见 [19](./19-studio-ui.md)。

所有历史 apply 串行执行：前一个 controller 操作完成后才启动下一次 UI 应用。generation 覆盖换 Thread、换 reader、页面销毁和显示接管；旧 query 成功、失败或 finally 不能写入新 generation。普通绘制、动画或滚动不进业务 apply 队列，也不构成 ACK。

controller 调用异常时，无法证明列表未被部分修改，因此终止当前 generation，并以新 HistoryReader 的 Set 重建；不盲重放 Prepend。重建成功前保留旧画面，成功后一次替换；失败显示真实错误，不删除草稿、Current 状态或无关会话。

关闭显示 owner 先撤销新需求，再取消自己拥有的 History/Current reader 与 body watches 并等待 join。一个 scope 失效不关闭共享 HistoryStore、其他页面或业务会话；迟到 Future 只能结算原 generation。

Current 正文的打开失败或读取过期通过正文流交付，不作为原生句柄关闭失败长期保留。关闭等待实际取消与句柄回收，不等待显示消费者读取流终态；消费者从未监听或已暂停也必须能够收束。只有真实取消／关闭失败保留在原 owner 的清理报告中。

## 26.9 实时状态与展示组件

状态栏（`LiveStatusBar`）通过 `LiveStatusMachine` 从唯一 Current State、`liveOpenWork`、`DomainSyncStatus` 与持久化状态派生互斥主阶段（`LiveResponsePhase` / `LiveWorkPhase` / `LiveCompactingPhase` / `LiveActivityPhase` / `LiveReconnectingPhase`）和去重并发关注条（`LiveStatusAttention`），统一交由纯视图 `LiveStatusSurfaceView` 与共用 `WorkGroupMemberList` / `LiveStatusHeaderSpec` 呈现当前未封口实时工作区（直接吸纳正在运行、等待审批与停止中顶行状态）、流式助手正文（`ConversationResponseView`，开始即收束前序工作组）、实时压缩与正交关注提示；`projectConversationActivity` 同步透传 `wait` 呈现事实，计时超过 60 分钟自动按小时、超过 24 小时按天进位格式化。`execution_present` 不等于正在执行，完整运行资格仍来自真实 sources、atoms、activity 和原 owner 状态（以 `executionActive` 统一界定）。无 active turn 的有效后台活动仍可显示。

实时正文的同一个读取窗口每次更新只解码一次，正文就绪判断与渲染共用该文本。已经可见的窗口在追加文本或更新回调时保留首次可见布局证据。更换正文窗口或卸载时撤销原证据，新窗口在正文实际可见后重新报告。

主时间线中已封口的 `WorkRange` 与实时栏中的未封口工作区均支持默认一行展示真实图标、单行摘要与经过时间；展开后才由工作组 ViewModel 拉取并折叠区间事件。隐藏或折叠撤销该视图自己的正文/媒体读取，不停止业务执行。工作组沿用 `WorkRange` 的 Unix 毫秒起止时间，实时栏开放工作区以当前 Unix 毫秒为上界，主时间线已封口历史工作组取区间末事件时间。先取毫秒差，再按整秒展示；时间缺失或倒序时显示“工作记录”。实时计时只是 UI 派生值，不写 Current 或 History。

实时工作组展开后，标题固定在有界成员区上方，普通执行时沿用当前组的思考摘要。成员区读取期间继续显示可用成员，省略横向加载指示。历史工作组展开后随主时间线连续布局和滚动，并提供加载反馈。具体呈现见 [桌面界面规范](./19-studio-ui.md)。

开放工作组只在区间历史引用变化时重新读取 History。成员控制器将最新 Current 叠加到最近接纳的完整历史结果，在历史事件到达前按相同的调用或实体身份显示实时成员。成员的内容引用、状态或正文变化由对应行单独消费。成员身份或顺序变化时更新列表结构，读取失败及重试按组显示。重连通过同一主阶段选择入口暂时取代实时工作组；恢复后按最新快照重新选择主阶段。

组内成员折叠或不可展开时只显示一行活动入口：语义图标、主文案和可用的展开标记同行对齐。思考以单行行内 Markdown 显示概要，超长省略，读取状态与错误不增加第二行；无概要时使用真实状态或已知耗时。只有存在正文时才可展开思考。思考概要和正文均无独立复制按钮；展开后的正文仍可选择文字，长正文保留范围导航。工具及正式消息的复制行为不变。

保存失败、停止、审批、存储错误和冷恢复限制必须保持可见，不能被普通活动摘要合并隐藏。发送回显由原 Composer 持有；Current 中同一 `input_id` 的规范输入被时间线消费者应用后，临时回显结算为正式呈现，不产生历史事件或按正文去重。

每个内置工具由 `timeline/tools/items/<domain>/` 下的独立 Dart 文件实现 `TimelineToolItemAdapter`（通用兜底 `generic@1` 同样独立实现），完整声明 `TimelineToolMatcher` 匹配规则、`TimelineToolIcon` 静态/动态图标策略（支持组件与 `TimelineToolItemController` 通过 `TimelineToolItemScope` 动态更新图标）、单行折叠摘要与展开视图。集中注册入口 `timeline/tools/tool_item_registry.dart` 建立唯一索引并校验精确契约不重复；`wait` 与 `sleep` 统一纳入同一 `TimelineToolItemView` 与适配器管线，不再单独分叉；未知工具契约回退内置 `generic@1`，展示工具名、状态、参数与输出而不报错。

## 26.10 当前快照格式与旧数据边界

Current JSON schema 为 1，Current 协议为 1，ThreadSnapshot schema 为 18；History schema 与协议分别为 26 和 2。正常 reader 只接受当前版本。schema 25 与 schema 24 类型仅存在于显式迁移边界，正常代码与测试不依赖它们作为现役 wire。

schema 24 → 25 与 schema 25 → 26 的备份、单事务升级和回滚规则由 [17.21](./17-studio-storage.md#1721-独立当前状态与追加历史的升级边界) 与 [17.22](./17-studio-storage.md#1722-schema-25-到-26-原子事件迁移边界) 定义。其中 schema 25 → 26 升级原地零拷贝保留既有 `history_bodies` 与 `history_body_chunks`，并将旧 `KnownActive` 无 payload 行转换为合法的原子工具事件，消除既有受损会话的读取失败。

计划、交互、正在执行的工具和旧 partial stream 只按 Current 的 paused 事实呈现。历史不补齐 current，冷打开也不激活模型、工具、进程或外部投递。
