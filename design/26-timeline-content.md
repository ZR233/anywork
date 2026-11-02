# 26 - 按需会话加载与有序聊天交付

本文是原子完成历史、真实来源生命周期、普通分页与 Flutter 呈现所有权的唯一权威契约，依据 [#272](https://github.com/ZR233/anywork/issues/272) 的最新定案，保留 #243 的原子发布、统一 RAM/SQLite 读取及可靠保存基础，替代一原子一顶层消息、整 Turn Children 假工作组和后端展示前缀/排序方案。本文描述批准的目标，不以文档更新冒充实现或性能验收。存储布局与迁移归 [17](./17-studio-storage.md)，可靠保存归 [15](./15-session-storage.md)，传输归 [07](./07-streaming.md)，客户端生命周期归 [25](./25-frontend-state.md)，视觉归 [19](./19-studio-ui.md)。

## 26.1 完成事实与唯一所有者

历史只包含可靠结束后的不可变最小事实：已接纳输入、完整文本/思考 part、一次工具调用自身终态、确定文件变更、技能激活、交互/计划/压缩或终止回执。不按 token、换行、停顿、EOF 或整组是否安静猜测完成；工具 A 完成不等并行 B 或整个 Turn。后台启动回执和后台任务最终结果是不同事实。

Core Thread 先向既有可靠队列准入 effect，再发布执行观察。Studio 单一产品投影按可靠 effect 顺序及批内稳定顺序冻结 draft，调用 Session 整批发布并分配完成 seq；同一冻结记录由 pending、短读和 writer 共享。完成发布立即可查询、可推送，不等待 SQLite；PendingHandoff 只是将准备结果附到已经准入的义务，不是首次入队或 durable 确认。

| 所有者 | 唯一职责 | 不承担 |
| --- | --- | --- |
| Core Thread | 执行事实、可靠准入 | 产品卡片、UI 分页 |
| Studio 产品投影 | 原子可靠终态、真实来源身份/顺序/生命周期、current 小投影 | 工作组、组关闭、展示可提交前缀或排序 |
| Core Session | 完成序号、完整 pending、幂等、scope 索引和一致读取 | 业务 payload/工具 renderer |
| HistoryStore 与原 writer | 初始化/迁移、独立短读、完整批事务和确认 | GUI 接纳或绘制 |
| ConversationFeed/传输 | 切点、Set/Append、有界传输与取消 | 已加载消息镜像 |
| SDK/FRB | 机械映射、串行接纳、游标、ACK 与资源资格 | 分类、分组、业务终态推测 |
| Flutter 唯一呈现 owner | 分类、相邻分组、当前未提交片段、前台可提交前缀与 controller 交接 | 保存、业务成功判断、第二权威历史 |
| ChatController/View | 已加载消息、展开/布局/滚动与实际视口读取需求 | 来源终态归约、存储一致性 |

### 呈现生命周期不下沉存储

思考、工具与正文先在实时区域生成。工作段的真实后继分隔确定后关闭成员准入，且全部前台成员有可靠终态或真实后台交接回执，才由 Flutter 按前台来源顺序整体提交；正文可靠结束后整段提交。暂时全部完成、空预览、静默、保存 ACK、折叠或页读取完成均不封组。一个工作组对应一条 `Message.custom`，不是数据库完成项或 Rust 对象；同 Turn 的工作 A→正文 A→工作 B→正文 B 必须分成独立呈现项。

同响应允许多个未终态 part，text-start 不能伪造 reasoning.end，前一成员未结束时后续正文仍须在同一实时区域可读。没有独立 part-end 的来源只以权威 attempt 终态结算。真实空 text part 保留来源身份与结构分隔，零字符不画空卡，前后工作不因此合并。停止/失败等待真实收束，保留已接纳内容，整轮原因只由独立回执表达；待决交互保持 waiting，不能为封组伪造完成。

Inference 调用诊断不作为用户过程成员、不产生诊断专用工作组或分隔；完整执行/调用历史和旧原件继续保留。未知工具、Deferred 和敏感问答沿原格式、引用及遮蔽契约处理。新聊天不复制诊断步骤，存量只在必要迁移中标明普通展示资格，不删除原件。

数据库、Core、Runtime reader、FRB/SDK 均不保存或查询组 ID、成员关系、标题、折叠、组关闭、进入 Timeline 的时刻、展示可提交前缀或展示排序。不得将这些改名为 ready 区间、来源范围证明或首次资格位置后保留。分组变化或改成平铺不要求 schema 或后端展示 API 变化；工具结果可靠完成仍立即发布保存，整组交接不产生数据库写入。

### 模型成员的可靠封口与交接

厂商提供独立且权威的成员结束事实时，模型层校验真实身份、内容、重复冲突及输出预算，再通过原调用内的有界可靠通道交 Core 形成 effect；不能用可合并 progress watch 代替。没有可靠成员结束的协议以最终 attempt 输出为依据，不根据通道切换猜测。模型上下文、调用用量和 Turn 终态不因此提前推进。

Runtime 沿同一 prepared handoff 和可靠预算封口；最终回执再次含同一成员时按冻结身份/字节幂等，冲突明确失败。停止或失败不撤销已经接纳的成员；生产者先收束并交接已接纳事实，再撤销观察，恢复不重跑旧请求。中断内容如实标识，原因以独立回执表达。

已完成成员从 current 退出由同源完成交接决定；先进入可查询集合，再公开退役后的 current。现实模型输出与极端碎片化的容量边界见 [24](./24-testing.md)，不以提高帧上限掩盖现实规模内的成员交接问题。

模型适配器在 canonical accumulator 完成身份、part、内容和预算校验后，才向 [Core 成员端口](./16-core-contracts.md#163-模型调用契约) 提交模型拥有的成员回执；不能在原始事件的 `map`、trace 回调或可合并 progress 观察中先发布。独立成员回执与最终回执复用同一规范成员及身份；相同结束事件不重复接纳，后来的冲突不能覆盖已接纳字节。已交接成员不得通过透明重放旧请求来重新制造。厂商明确标记的 incomplete/中断不能冒充正常完成；没有独立权威结束的协议仍只使用最终 attempt 边界。

### 按作用域的 current 交接前缀

完成记录分配 seq 后，产品 owner 冻结可靠 current 交接信息：本次 Main 完成前沿、交接前后的小 `CurrentProjection`，以及交接前已公开 preview 身份对应的完成 seq。此信息归原 prepared/publication owner，只保存有界信封与身份，不保存另一份完成正文或全部成员集合；它与原 publication 队列一起计量，不能提高帧数或字节上限。

Feed 只消费该类型化交接信息，不解析 payload 判断完成。一个 Append 被条数或字节预算截断时，只退役其已交付前缀对应的 preview，保留未交付 preview；本 scope 前沿已覆盖时，在同批采用交接后的 current，并可越过已证明仅属其他 scope 的全局后缀。不得用全局 H 相等作为 Main current 退出的必要条件，也不得在第一小批直接附上清空所有未交付成员的 post-current。current 信封预算包含本批实际可能交付的有界前缀，不在发出后再丢弃 current 凑预算。

部分交接期间沿用的小 current 集合引用仍遵循现役 revision 资格：它们不是冻结历史快照，来源已经换代时范围读取明确返回 stale。不得为让旧引用成功而另存全量 current 集合、伪造空页或从完成 payload 重建集合；正文的稳定 item 内容引用仍沿原 active→completed→durable 路径读取。writer 只保存原 effect 最终的 `PreparedCurrent`，不因不同读者的传输分批写入中间 current。

## 26.2 身份、顺序与动态 payload

每会话定义 H 为已发布最新完成序号，D 为已实际提交的连续完成前缀，pending 完整覆盖 `(D,H]`。seq 在发布时分配，不是开始顺序、effect write_seq 或 UI 下标，必须为 SQLite 有符号 64 位范围内的正数。过滤后 seq 可有间隔，不要求 Flutter 验证连续。

稳定 item_id 从可靠来源身份派生；相同身份重试沿用首次冻结字节，不用最新工具 decoder 重建旧内容比较。载荷冲突、序号冲突与溢出明确失败，整批不部分发布。工具名、参数/结果、状态、时间、角色、格式标识和公开语义引用属于自由 UTF-8 JSON payload；索引列只表达查询成员资格和真实父域，不镜像 renderer 联合类型。

query_class 由写入/迁移确定，未知 payload 保留原类别，不因 renderer 不认识而隐藏。Main 纳入正文、思考、工具、文件/技能等普通过程与独立回执，不能固定只选 conversation 而漏掉 activity；资格在 LIMIT 前由普通原子索引选择，不按 Flutter 封组资格筛选。parent_id 只表达真实业务父域，不是工作组身份，Children 只服务真实嵌套业务。来源身份、领域类别、来源内部顺序、完成发布 seq、真实生命周期与内容引用以轻量元信息交付，不要求解码大 payload。

来源顺序、可靠事实位置和 feed delivery sequence 不同：前者保持前台与并行成员的实际位置，可靠 effect/批内稳定顺序说明何时接纳真实事实，delivery 只服务本句柄 ACK。后台 acknowledgement 结清原前台义务但不表示成功，最终 Inbox 结果是独立 item，不按旧调用开始位置回填。T 开始→B 完成→T 完成时 T 仍 live、B 立即历史，最终 B→T，普通完成 seq 足以重建此例。前台内部由 Flutter 维护来源顺序和可提交前缀。

连续观察的组插入时刻不等于原子完成顺序。冷读只对已加载事实和真实来源状态投影；相同完整事实须有相同分隔、成员归属和约定顺序，但不要求任意小页独立重放所有跨来源 UI 插入时刻。部分范围保持部分/未知，不据此封组、跨缺口合组或伪造旧时刻。

## 26.3 完整 pending 与保存交接

pending 不是 UI 缓存，不随意 LRU 淘汰。主索引与 class/parent 有序辅助索引引用同一冻结记录，读取不能先扫描全部 pending 再过滤。预算沿原可靠准入/retention 计算，保存失败保留事实并背压，不能无限增长或丢最旧项。

writer 只提交已准备的连续 effect 前缀；事务成功后按本批实际完成项的连续前缀推进 D，不能读此时 Session.head 或取跨空洞最大值。没有 completion 的 effect 不凭空推进 D；保存 ACK 不产生第二次 Append。已提交项仍被已接纳短读引用而短暂存活是正常所有权，不强制销毁引用。

显示不等保存、writer 不等 Flutter。关闭等待原保存屏障；进程提交前崩溃可能丢失 RAM 尾段，不能承诺不等落盘和崩溃零丢失同时成立。批处理、回执、accounting 及故障恢复见 [15](./15-session-storage.md)。

## 26.4 按需分页与 continuation

一个读取需求包含 `max_items` 与 `max_bytes`：条数必须大于零，由当前展示需求决定；字节至少容纳一个合法轻量 envelope，否则返回 InvalidDemand。服务端校验资源上限，但不恢复固定 32 条或固定正文预览长度的 UI 合同。预算覆盖实际编码开销、身份、header/current 和引用；不能用返回条数或估算驻留量冒充传输字节上限。

`max_items` 限制整个 `ChatBatch.entries` 的条数，独立 `Atom`、可靠 `Source` 事件均计一条，Set、Append、Prepend 和普通窗口查询均须在发送前核验。`max_items=1` 仍是合法需求，不能提高最小条数或排除 Source 事件计量来规避分批。current 继续使用原有界信封与同一字节预算，不另开信用或预算。

普通页不将每个来源的读取证据再追加为独立 entry：`ChatAtom.source_state` 可携带该原子来源在读取切点的真实 `ChatSourceState`，身份必须与 `atom.source` 一致；其成本纳入原 item 编码预算，不是工作组或范围证明。冻结完成 metadata 的 `source_state` 必须为 None 且不编码该字段，reader 才按同切面事实填入，不能把较晚来源结束永久写回旧完成项。仅 current 涉及的源直接由已计量的 `current.sources` 交付。真实 start/end 仍沿原可靠 handoff 以 `ChatEntry::Source` 发布并按条数、字节分批，不因存在读取注解而合并或吞掉可靠事实。

latest 捕获固定 H0；before 还要求 seq 小于游标排他边界。一次读取如下：

1. Session 短临界区捕获 D、H、源资格及匹配 scope 的有界 pending 引用；所有候选不超过 H0，数据库上界为 `min(captured_D,H0)`。
2. 按 scope 索引倒序取预算内候选。内存已满足需求或任一预算耗尽，直接返回，数据库 page/existence 查询为零。
3. 仅匹配候选不足且条数/字节仍有余量时，锁外建立捕获之后的新 SQLite 短读快照，只补持久化前缀的同 scope 数据。
4. SQL 先按索引选择头部和 payload 长度，再一次或有界批次读预算内 payload，不逐项完整解码工具。两个天然不重叠区间拼接为 seq 升序消息。

不能跨 await 持 Session 锁、复用捕获前旧快照、查询触发 flush/执行恢复/完整性检查，或跳过较新的大项去库里凑旧小项；超预算 payload 以 Deferred 表达。捕获后 writer 清 pending 时短读仍持 Arc；捕获前清理则后开的 DB 快照已能看到提交。

before 是绑定原库身份、ChatScope、排他边界和读取作用域的不透明字符串，Flutter 原样回传、不解析来源或 seq。不返回 totalCount，不 COUNT，不为 UI 计算全历史空占位。

非空 before 仅表示可继续请求，不保证下一页非空。只有内存和库均已确认耗尽才返回 null；内存恰好够页时不为精确 hasOlder 额外查库。允许一次空末页返回 null，非空页 cursor 必须前进，空页不得原地 continuation；短页和字节截页不自动表示 EOF。

## 26.5 唯一原子批次与真实生命周期

Rust 产品契约统一归 pl-protocol，FRB/HTTP 同语义；Core 仅持产品无关完成记录。

| 类型 | 字段/语义 |
| --- | --- |
| 原子 envelope | 稳定 item/member 与完成载荷身份、实际来源/turn/attempt/part/call、完成 seq/来源顺序、领域类别、终态、内容引用及动态 payload |
| PayloadData | `Inline(bytes)` 或 `Deferred(reference,byte_length)` |
| ChatBatch | `placement`、有界原子/真实生命周期 `entries`、普通 `before`、可选同切面 `current` |
| ChatPlacement | Set、Prepend、Append |
| CurrentProjection | source effect、真实来源/attempt 状态、有界 active turn/活动、Plan/交互头部和内容/集合引用的具体快照；不是未提交工作组范围 |

完成 seq 与来源位置按各自语义交付，H/D、source incarnation 和 opaque cursor 解析仍归 Rust。Message.custom 是 Flutter 自己的类型，不复制 Flyer 联合、oldMessage/index 或任意 UI diff。无后端工作组 PageContext、closedThrough/terminalThrough、readyAt 或组范围协议。真实生命周期只补领域确实发生的开始/终态，不增加一套可查询事件存储来替代原 effect/current owner。

当前协议统一为 `ChatEntry::Atom(ChatAtom)` / `ChatEntry::Source(ChatSourceState)`。Atom 的 payload 可在真实开始时缺省，完成时引用原 item；completion_seq 由完成 header 取得，与可空的 source_order 分开，缺来源位置不伪造。SourceState 只表示实际来源 Active/Ended/Unknown 与确有的开始/终态位置。CurrentProjection 只含有界真实 source 状态及未终态 atoms，不含已完成尾组或展示范围。部分页的 source 状态来自同切面的实际生命周期，不能用“未加载”补成 Ended。普通 Main 项统一进入 conversation 查询类，Children 使用同类及真实业务 parent；诊断单独保留，不改完成 seq。

Core ChatDraft/Header 的不透明轻量 metadata 随原冻结完成记录发布、查询和保存，产品 reader 无需解码 payload 即可映射 Atom；Core 不解析其领域内容。实际来源开始/结束经原 Thread effect/current handoff 一次交付并同事务保存，历史页按真实来源身份有界取得同切点状态。它们不是工作段起止或前缀，不能按正文/工具 UI 分类制造来源闭合。来源可跨 attempt，idle 压缩有独立真实操作身份；后台最终结果独立来源，保原 call 关联。

| 来源 | placement | before | current |
| --- | --- | --- | --- |
| Main 首屏，entries 可空 | Set | 设置普通原子 continuation | 必须有具体快照，可明确空 active |
| Children 首屏 | Set | 设置该 scope 的 continuation | None |
| 旧页，末页可空 | Prepend | 替换 continuation，None 为已知 EOF | None |
| 新原子/真实来源事实 | Append | 必须 None，不修改原游标 | Main 可有；Children 必须 None |
| 纯 current 更新，entries 为空 | Append | 必须 None，不修改原游标 | 必须有，仅 Main |

`current=None` 始终保持不变，具体空快照才清空。完全无变化的空 Append 不发送。每个 handle 首个成功 Chat 必须 Set，之后只有 Append；重同步终结旧 handle 并以新 handle 取得 Set，不在原流偷偷 reset。合法组合由 Rust 构造与测试保证，Flutter 不再跑一套业务切点校验。

## 26.6 被动打开、首屏切点与有序推送

open 在 Rust 内完成观察登记、切点捕获和有界基线准备，events 仅安装唯一消费者交付既定序列，不能等 events 才登记。主 owner 串行边界发布完成 H0、同源 effect 切点与真实 current/source；旧原子页固定 H0，后继 Append 交付切点后原子及真实来源事实。没有新增 completion 的可靠 start 也不能因 H 未变化而漏掉或被 current 合并吞掉。复用原可靠 handoff、预算及保存路径，不建展示事件总线。打开不追逐最新 head 无限重试。

冷读在同一短快照中取得轻量完成水位、current 与初始页，不读/校验/解码完整 checkpoint/current_context，不激活模型、工具、SSH 或执行 owner。current 表示最后已提交的逻辑状态，是否真有执行 source 由 registry 判定，重启前 running 不冒充当前运行。

无执行 source 的目录状态投影可恢复性，不复用旧进程的资源关闭状态：root 与 child 的非显式 Closed/Closing 均沿既有目录规则投影为 Idle；显式关闭封口、旧 retirement、归档准入及热 owner 的真实关闭阻塞仍有效。输入所需原模型路由与扩展修订号是独立于运行资源的 State 事实，其轻量保存与交付分别见 [17](./17-studio-storage.md) 与 [18](./18-studio-state.md)，不得为补齐它们激活执行或伪造 runtime。

复用 ThreadObservations 的稳定 observation slot 登记并捕获单调 epoch/位置；冷读后复核，覆盖 absent→live→absent 的 ABA。来源判断看 resident/pending，不只看业务 running；idle 也可有未落库尾段。源退役先安全交接 pending/writer。可连续接续由 Rust 完成握手，否则以现有 Failure 明确要求 ConversationResyncRequired，旧分页资格同时失效，不能返回空页或吞错。

slot 已安装而首次 publication 尚未就绪时，open 同时借用该 owner 原有的 retained progress 结果：先登记接收资格，再检查已保留错误及完成状态，并等待同一结果或来源代次变化。不能另建 readiness 镜像、只等 broadcast 或借执行激活/flush 补救。原失败按原共享错误与 typed 分类传出，不将其格式化成新字符串而丢失 code、reason 或可重试性；无错误但 owner 已结束且仍无 source 时明确要求重同步。工具停止还必须能打断该窗口中的 open 和首批接收，不能被 opens 读写锁互相阻塞。

对 Main，原子先成为可查询集合的一部分。Flutter 唯一呈现 owner 接纳轻量元信息及合法引用、更新当前片段、向 controller 提交可提交前台前缀或独立结果，再发布同批实时呈现并 ACK 连续接纳前缀。已完成成员可仅留在 live，ACK 不等封组、后继正文、query、用户展开、布局、视口填满或 SQLite；不能用无限队列掩盖背压。普通成员直接由 Main 接纳，真实 Children 仍遵守各自 scope 的可查询及退役前缀。current 可合并预览但不能越过未交付原子或吞可靠来源事实，超预算无法保持边界时明确重同步。

保留现役 Frame 的 thread/subscription/delivery sequence 和 State/Failure/Closed，只把 ContentBaseline/ContentUpdate/ActivityContent 合为 Chat。State 继续同步输入、workspace、元数据等其他领域，但不拼正文、推断 terminal 或覆盖 Main Chat.current；Children 不倒灌 Main current。

已有 resident/pending source 时，首个 State snapshot 必须携带所选 owner 切点已冻结的交互事实，不能固定为空再依赖打开前已发生的一次通知。State 的覆盖水位与这份基线一致；被基线覆盖的交互不重复通知，之后的交互新增、回答或取消继续沿原可靠 State 事件交付。交互元数据仍由原 owner 从同一 canonical 状态投影，基线与 current 集合只是该投影的交付出口，不由订阅者、Connector 或 reducer 从 current 引用、序列化集合正文或历史回执重建。所保留的类型化元数据计入原 owner 的内存及 Frame 预算，不另建订阅、补偿队列或提高上限。

原可靠 pending handoff 必须冻结同一 effect 的类型化 State 变化，不以准备当刻有无订阅者决定是否保留。订阅者可在准备与可靠交接之间登记；该窗口不能丢失 Turn/交互事实，也不能仅因当刻无订阅者而制造正常流的连续性失败。冻结变化仍计入原 handoff 预算，交接成功才发布，不增加队列或上限；外层传输信封仍按实际订阅需求构造。确实缺少未被基线覆盖的可靠 State 事实时，继续明确重同步，不从 current 的逻辑状态或活动预览、progress 或完成正文推断这些事件。

State 首帧必须保留同一读取切点的完整待决交互，不能用空集合代替已被首帧水位覆盖的交互事件。无热源时，冷读取在取得 current 与初始页的同一短事务内读取已保存的交互集合；不读取完整 checkpoint、不激活执行。计划确认、普通问答与权限审批沿原身份交付，解码或内容读取失败明确传播，不能静默丢掉待决项。后续决议继续由既有 State 事件发布，不从完成回执重建可操作的交互。

## 26.7 内容与 current 集合按需读取

公开读取复用原 read lease 与内容 owner：listContents 取得 manifest，readContent 按 range 返回窗口，watchContent 取得有界当前窗口，pageCurrent 读取 revision 绑定的当前集合页。它们不是聊天列表操作，不强行塞为 ChatBatch。

工具取得 feed/reader 后、交付首批前，就由原 read owner 接管资源及名额；首批失败或取消须请求关闭并汇合原资源。关闭失败仍由原表项和 permit 承担重试责任，不另建清理队列或因 future 被丢弃而宣称 join 完成。

会话搜索区分输入 cursor 借来的已交付资格与本次新开的未交付资格。读取、取消或结果编码失败时收束后者，并保持尚未提交退休的输入资格可重试；跨 session EOF 不在随后读取仍可能失败时提前关闭输入 scope。完整成功结果构造完成后才提交旧资格退休和新 continuation 的转交；过渡仍受原 16 个 scope 上限约束，容量不足明确拒绝，不额外开第 17 个或驱逐其他读者。退休不可逆，提交清理失败时保留原待 join 资源与 permit，不伪造旧 cursor 仍可读，也不以清理错误掩盖先发生的操作错误。

ContentRef 区分 ItemPayload(itemId) 与 Body(owner,key)，绑定原库/读取资格。ItemPayload 按 item_id 定位原 payload BLOB 范围；Body 按 offset 索引定位目标块及必要边界块，不能先读/拼全文再切片。ContentWindow 统一携带实际 offset、bytes、generation、availableThrough、sealed。

具有 item 身份的正文从 active 即使用 Item(item_id)，完成前没有完成 seq；seal 移交已有共享块/manifest，不改名复制全文。append-only generation 不随 token 改变，替换才变代；非 item 当前文档用 Current(domain,id,revision)，过期明确 StaleContent。当前集合以领域 position 稳定排序并绑定 revision，过期重取所需页，不混接不同代次。

current 只推有界预览和引用；展开时订阅所需正文范围，Rust 组装窗口，Flutter 不归约原始文本 delta。折叠/未订阅正文不推全文。manifest 由 producer 明确提交，不解析未知 payload 查引用；完成内容随 item 保留，current 随 owner 退役且保障已接纳短读结束，不另建全局 GC。存储布局、内容发布屏障和缺失投影处理见 [17](./17-studio-storage.md)。

`CurrentProjection.activeTurn` 保留真实 Turn 身份与阶段，不能作为工作组容器。当前内容包含有界的实际来源/part/call 元信息和窗口；完成 part 退出 Rust active 后，Flutter 仍可持其稳定 Item 引用留在未封口段，不依赖过期的 current revision。多个未终态 part 不限队首显示；空预览不是来源终态，不能清空 Flutter 已接纳尾段。

工作组展开沿已观察的普通原子位置/cursor 有界补载，读取条件可能交错其他来源；Rust 只执行原子条件，Flutter 用同一规则选成员，不要求后端找组头、凑组或给完整证明。组的加载范围不等于业务成员准入。真实业务嵌套仍可用 Children；未展开详情不建额外 reader，引用/选择退役先同步撤资格再 cancel/join。工具摘要、参数、输出通过生产者明确的 call 关联和内容角色归到一个语义入口，不解析内部 ID 或任意 JSON 猜归属。诊断只借实际挂载内容，不触发 IO。

原打开切面的旧页 `before` 只覆盖原 H0，不能用于读取其后的完成原子，也不能由 Flutter 将 completion seq 自行编码成不透明 cursor。原 read lease 提供通用 `read_before(completion_seq, before?, demand) -> ChatBatch`：首调用以已观察的实际 completion seq 为排他上界，复用原发布 owner 捕获当前可查询前缀及 source effect 切面，拒绝零值或超出该已发布前缀的位置；只返回普通原子页，不按来源、工作组或展示资格筛选。该窗口固定自己的完成上界及 source effect cut，后续使用返回的 opaque cursor；cursor 绑定原 lease、数据库、scope、epoch 和原始 anchor，不能混入原 H0 的 `load_older` 游标链。每页仍受原 demand 约束，显式 EOF、无进展和错误语义不变，不找组头、不扫描完整来源、不 flush。

这类查询返回普通 `Prepend`、`current=None`，仅提供窗口自身的 `before`，不推进或替换会话主历史游标。SDK 的 `readBefore` 是原 query scope 内的有界只读操作，不自动应用到主历史 consumer；Flutter 原展示 lease 通过已有 `_mutate` 串行入口将结果交给同一个 `applyBatch`，保留主历史 cursor/current，并在 await 前后核验原代次资格。原子事实和分组仍各只有一个写入口，不能为展开再建 feed、全历史镜像或另一套 reducer。展开窗口位置及加载状态随实际借用和展示对象存活，退役时同步撤销。

`CurrentContentPreview.role` 只是展示分类，不是文本频道或出站许可。预览以可空的 `textChannel` 保留原 canonical 文本条目的 `ThreadTextChannel`；非文本或无法证明频道时为未知，缺失也只表示未知，不能由 `Response`、正文、ID 或所属活动补成 `Final`。该事实沿原 current owner、存储与 FRB／HTTP／Client 映射交付，不新增旁路查询或状态镜像；同样计入原有编码和传输预算，不改变正文引用、generation 或完成边界。[机器人出站契约](./27-bots.md)的 Final 资格必须由明确频道及原目标 Turn 共同证明，未知与 Commentary 都不能授权创建或更新回复卡片。

`read_at(completion_seq, before?, demand)` 使用同一个原 read lease，提供包含已观察锚点自身的普通完成窗口。首调用拒绝零值和超过原 owner 已发布前缀的位置，以该完成 seq 为包含式上界，并捕获同一次 source effect 切面；匹配原 scope 的锚点和更早原子按原 Core 普通页交付。返回普通 Prepend、current=None 和该窗口自己的 opaque continuation；条数、字节、资格、取消及关闭责任均与 read_before 相同，cursor 另绑定包含式查询种类，不能与排他窗口或 H0 链混用。它用于重新取得已观察完成位置的原 Atom，包括合法 Inline/Deferred payload，不从 member ID 构造内容引用、不使用 seq+1、自编码 cursor 或扫描组头；Rust 仍不知道调用方是否展示工作组。

## 26.8 Flutter 唯一组件消息集合

使用已有 InMemoryChatController，不另写 ChatController；已提交 Message 仅由它持有，Chat 负责 Widget 惰性构建/释放。在原 applyBatch/owner 唯一实现分类、相邻分组和交接。Set 一次设置已加载投影；Append 只插入可提交前台前缀及独立结果；普通 Prepend 根据来源位置局部投影受影响段并插入/更新，不能固定 index=0。token/运行进度不修改历史，保存 ACK 不重复插入，初始/旧页不做新增动画，不重置整表或手动重复发组件 operation。

正文、工作组、独立回执分别形成顶层 item，一组是一条 Message.custom。展示 key 仅要求当前 Flutter owner 内稳定：live→history 和前插补旧成员继续同对象/key及展开意图，冷读部分组可用已加载身份建立对象，重开可重建。作者/时间只用可靠值，未知/Deferred 不丢轻量归属但不补造时间；单项未知/损坏不破坏邻居或读取错误语义。已加载历史不另存全量 rawAtoms/groups/messages 或无界 ID map，当前仅持需求内片段、普通读取位置和必要汇总。

实时、首屏、旧页和重开共用一份纯呈现规则。只处理新页及实际影响的已加载段，确认显示邻接才合组，不跨未知缺口推断相邻。R start→T start→T complete→R complete 时最新原子页可能先 R、旧页再 T，但前台仍显示 R→T；普通 Prepend 不保证只影响显示页首接缝。满屏后不为找组头继续读取。controller 同步 getter 不经异步 FRB；SDK 纯 Dart、机械映射，不依赖 Flyer 或 app 生成代码。

查询 IO 在串行应用段外；分页返回和事件都进入现有串行接纳链。捕获原 lease/controller，组件 await 后、before/current 发布和 ACK 前均复核原资格；不能重新读取当前选择绑定旧结果。主历史只在自身 Set/Prepend 更新 before；普通展开窗口的 Prepend 不改主历史游标。同方向请求沿原 owner 的 single-flight，Append 不改变旧页边界。错误保留原 cursor，EOF/失败/取消都结束分页 Future，不等待物理绘制或数据库保存。

首批按视口估计需求并立即展示。View 在本批实际布局后检查聊天滚动视口，未满且有 continuation 即通过原 loadOlder 读取一页；每页完成再安排检查，即使全页并入同一折叠组/实时段、没有新增 ChatOperation 或高度不变。删除固定启动总页数及独立永久错误锁；单次仍受 demand/credit 限制，同方向 single-flight。短页/字节截页不等于 EOF；满屏或明确 EOF 才正常停止，EOF 后允许不足一屏。

无进展作为协议错误暂停，不改成 EOF、不循环重试。读取错误由原 owner 发布并暂停，显式重试成功后可继续。窗口、输入区、实时区、展开/折叠和外层 ScrollMetricsNotification 驱动新布局需求；只测实际聊天视口，零尺寸/不可见/无效 owner 暂停，忽略内层滚动，不持续逐帧轮询。reversed 列表的最新端为 pixels=0，不能把旧端 extentAfter=0 或包含空白的 extentInside 当满屏依据；复用已有有效 scroll range 判断，不新增全列表测高或像素补偿。

折叠组有 M 条原子、每页 K 条时，填屏允许经过约 ceil(M/K) 页乃至整个组/Turn；一组占满全部历史时可读到 EOF 仍留空白。每页交接给正常布局，不同步长循环/并发预取多页；不为填屏下载隐藏全文/媒体、COUNT 或强制 flush。满屏后不为总数、摘要或组头额外读取，缺统计只报已加载 N 项或省略。首批可见、满屏/EOF 总耗时和页数分别报告，不承诺长组整体补满常数成本。

已浏览 Message 在本会话打开期间保留，长期浏览会增长，不宣称默认数据内存恒定；切换/关闭释放旧 controller 和 Message 的所有引用，不能仅 dispose 后继续缓存。列表前插仍有组件移动成本，不承诺无限长已加载列表 O(1)。阅读旧位置时继续接纳新增，回最新走组件公开能力，不重开订阅、不做像素补偿。

### 26.8.1 普通页中的未知结构

source_order 是可比较的真实来源位置，不是稠密编号。普通非 EOF 页中两个同来源工作成员之间是否存在未读正文，可能无法从当前事实判断；这不是协议错误，也不是来源已经结束就能消除的未知。唯一 applyBatch 必须接纳该页的合法原子，将尚不能确认相邻的内容保留为局部片段，不猜合组、不静默过滤，也不因缺少组归属证明拒绝合法 continuation。工作组详情使用的普通窗口同样进入这一入口：其他片段可以局部插入原 controller，主 H0 cursor/current 不变，详情只借当前确实属于它的成员。

真实结构分隔、已连续观察的开始事实或普通读取覆盖到 EOF 可以消除相应未知；仅重投影实际受影响片段，保留仍存续对象的 key 和展开意图。不保存每页原始 DTO、cursor 栈或全历史成员索引以“证明”相邻。统计只表述实际已加载内容；未知前缀不伪装完整组或精确总数。

### 26.8.2 整个未提交范围的资源边界

轻量可靠接纳与当前可绘制 props 是不同完成点。未终态事实沿原有界 current 预算保留，不能为了满足显示条数丢弃 part；所有尚未交给 controller 的**已完成**成员则共用一份展示工作集预算，按 demand 的总条数和实际编码字节限制，不能给每个段各分配 K。members、lastCompletion、anchor、已解码 presentation、Inline payload 及闭包持有的副本都计入，已由 controller 持有的完成历史不再复制。字节计量复用 SDK 的规范机械编码器，包含 Atom entry 信封的 UTF-8 编码，不以字符串长度、原 payload 字节或另写一份 UI 协议 schema 代替；Demo 使用同一编码规则。

最早成员晚终态而后续任意多段完成时，实时区只物化需求内的完成片段及真实未终态活动；更早内容以明确的“尚有活动未载入”加载提示表示，不能伪装已完成组或精确数量。被驱逐内容仅保留按仍受阻真实来源/可合并普通完成区间计量的恢复位置、边界和读取资格，不保存每成员/每段的永久骨架、完整 Atom、JSON 或展开意图表。保留的对象在 live→history 和补成员时不换 key；范围退役同步撤销其局部正文/展开资源，后续未物化片段按冷读规则重建，不能用隐藏 Element 或闭包继续保存已驱逐 props。

恢复描述不按每个段或每次读取增长：每个仍受阻真实来源至多一个合并的完成位置区间，解除阻挡后的需求并入同 lease 的普通未物化区间，不按已结束 Turn 建永久表。区间可覆盖其间已经展示的普通原子，由唯一接纳入口处理重合，不保存去重 ID 库。需要合并不同读取窗口时，先退役旧窗口资格，再以实际已观察位置创建新的固定切面；不能拼 opaque cursor 或在一条 continuation 链中混合切面，产生的重复读取如实计量。

被驱逐完成项仍在原 Session/RAM/SQLite 完成集合中。需要当前窗口、显式阅读，或前台阻挡解除后产生新的视口需求时，由原展示 lease 的 single-flight/串行接纳调用普通 read_at/read_before，一次只物化一个 demand 页；包含式窗口允许恢复锚点自身，不制造 Deferred 引用。窗口保持自己的切面/continuation，按实际完成区间覆盖结束，不覆盖主 H0 cursor/current，不新增 feed 或分页 manager，不为恢复强制保存或全量预读。

阻挡成员结束仍先接纳并 ACK，不等待恢复 IO、组封口或布局。已确定可提交的片段交给原 controller；尚未载入的区间继续保持未知，普通后续页可局部插入中间，再依据真实分隔/覆盖消除片段缺口。相同来源先后约束与独立结果完成位置同时满足，不为等前台恢复延迟独立后台结果。未物化区间的存在不能触发无布局的同步扫描或固定总页数截断；满屏即停，显式滚动/展开继续原有界读取，并分别报告实际页数、重复读取及总成本，不承诺任意来源顺序与完成顺序交叉下的常数恢复成本。

## 26.9 工具当前契约与单条降级

当前执行 schema 与专用 renderer 各只维护一套。展示契约标识在请求冻结时确定，随真实调用/结果保留；同名同形字段不证明旧语义兼容。当前 renderer 只解析它声明支持的契约；无标识/未知标识或当前完整正文非法仅该项不兼容，保留身份、顺序、合法公开原文和可靠通用事实，不虚构时间、状态或工具参数。

合法但截断的预览、Deferred、custom/freeform 非 JSON 正文与真正 Malformed 分别处理，首屏不自动批量拉详情。generic MCP 的通用形状不依赖在线目录；敏感/redacted 继续受公开资源规则约束。数据库错误、内容缺失、身份冲突及执行恢复错误保持独立诊断，不将所有异常吞入“不兼容”。

工具形状改变不改通用 envelope 的 SQL 索引结构或追加历史 decoder/别名，旧工具业务字节只在正式容器迁移边界处理；续聊使用冻结模型上下文，不从当前 UI payload 重建或重跑历史工具。

## 26.10 验收与只读诊断

普通当前格式打开的 full_context_rows、quick_check、execution_activation、tool_or_ssh_initialization、query_triggered_flush 均为零。相同需求下增加总历史、隐藏活动或上下文，不增加线性全量读取/检查/解码。记录 SQL/pending 候选与返回量、payload/content/编码字节、逐项解码数、controller/实际构建行数及排队时间；诊断只临时借用 controller/owner，不反建第二历史集合。

Driver 直接按 controller 的 Message 顺序和唯一呈现 owner 已挂载的片段读取 metadata，分别报告顶层项数、已加载原子身份、兼容性、有界正文/引用及显示代次；不查询未展开内容或反建隐藏集合。完成 seq/来源位置是实际原子事实，H/D 与源 epoch 仍留 Rust，不为旧脚本伪造组成员或跨 owner 稳定组 key；顺序与局部插入/更新使用真实对象身份和操作证据。

展开内容通过原 Main 展示 lease 登记只读借用，记录实际普通原子读取位置、显示代次、资格及已挂载窗口；真正业务 Children 另保真实 parent。查询 Driver 不触发 IO 或建立完整组镜像。关闭/换代/lease 退役同步撤销借用，旧回调不能登记到新 lease。批接纳、读页和 controller 操作分别计数：一页可以没有新增顶层项，不能用卡片数/高度不变推断无数据进展。

运行中详情同样只借用真实挂载的 current 资源：Driver 可读取用户已展开、原 scope 已接纳的有界集合页及正文窗口，并报告原集合引用、局部代次、展开/加载/错误状态和 continuation。读取诊断不能发起 page/watch、展开组件、复制完整 current 集合或保留跨代页面；折叠、引用 revision 变化、来源 attempt 变化和 Main lease 退役同步撤销资格。工具等待只按现役 `tools` 页中原 call 身份与 producer 提供的 typed wait 判断，不从工具名、完成记录或输出片段猜测；没有提供的 item 身份及终态结果保持未知。

各层验收证明其实际拥有的事实。独立工具结果在 Turn 结束前已可靠发布使用原 Runtime/HTTP 读取资格证明，不能以将来的页或实时输出片段冒充更早完整结果，也不要求 Flutter 提前制造历史卡片。需完整库存时，验收器沿普通 Main 与真实业务 scope 有界分页到 EOF 并即时取证，不以最后一组/当前成员窗口代替全历史，不要求惰性行、图片或展开态全常驻。

性能首批主指标为真实 selection 到同 generation 首个有效内容完成布局，迁移完成、同硬件/构建模式下冷打开和普通切换参考 p95≤500ms；另报视口满屏/EOF 总耗时、总页数、读取原子/字节、正文加载量与 build/raster。长折叠组可线性经过很多普通页，不将首批目标外推固定补满时限。进程冷启动、read scope 冷打开、OS 页缓存、数据规模/样本量/p50/p95及迁移耗时分别报告；Rust/Dart 单调时钟用 trace 关联，不跨时钟相减或用 FrameTiming 批回调时刻代替帧时间。

AppGraph 在规范的可见选择目标成立、发出该目标读取 demand 之前记下同一 Dart `Stopwatch` 的起点；这不是后来的 Set/owner-ready 时间。正文见证仅包裹已解码且实际呈现的非空内容，在该正文子树完成 layout 后捕获同钟时间，再于本帧末核对原 lease、代次及实际可见资格。帧末回调只做资格确认，不用回调到达时间替换已捕获的 layout 时间，也不持续申请帧。skeleton、Deferred 按钮、错误提示、空容器、未呈现内容及已经退役的布局不能完成样本；无有效见证保持未知。应用只留当前展示代次的小样本，外部验收采样器负责汇总，不建立应用内跨会话性能历史。

通用内容范围查看器浏览一个有界字节窗口，下一段只在显式操作时请求。复制操作明确标为“复制当前段”，仅复制当前实际显示的窗口文本；不将它标作全文复制，也不为旧全文断言自动追读所有段。完整公开原文仍可通过同一稳定引用逐段读取。验收脚本分别证明窗口读取、显式续读及当前段复制，未提供的全文复制能力明确列为不适用，不能用窗口成功冒充全文成功或伪造旧详情接口。

需覆盖内存足页零 SQL、提交/清 pending 交错、固定切点/持续新增、并发上翻、源 ABA、同批 current 退役、超长内容、未知工具、慢消费者、独立 query、A→B→A、关闭/保存故障和非空迁移。原生、模拟供应商、真实供应商及各平台证据分开，不以日志采集、组件成功或文档目标冒充验收通过。
