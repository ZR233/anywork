# 26 - 按需会话加载与有序聊天交付

本文是原子完成历史、真实来源生命周期、Studio Timeline 展示 item 投影与按需分页的唯一权威契约，依据 [#272](https://github.com/ZR233/anywork/issues/272) 的最新定案，排除已否决的“Flutter 唯一分组 owner”方案，保留 #243 的原子发布、统一 RAM/SQLite 读取及可靠保存基础。Studio（Rust）是唯一 Timeline 分组与交接 owner：同一投影生成 `text`／`workGroup`／`status` 顶层展示 item，Main 直接按展示 item 分页，一条 item 对应 Flutter 一条 `Message.custom`；Flutter 只做薄接纳、展开/滚动/布局补载和局部 UI 状态。本文描述批准的目标，不以文档更新冒充实现或性能验收。存储布局、派生表与迁移归 [17](./17-studio-storage.md)，可靠保存归 [15](./15-session-storage.md)，传输归 [07](./07-streaming.md)，客户端生命周期归 [25](./25-frontend-state.md)，视觉归 [19](./19-studio-ui.md)。

## 26.1 完成事实与唯一所有者

历史只包含可靠结束后的不可变最小事实：已接纳输入、完整文本/思考 part、一次工具调用自身终态、确定文件变更、技能激活、交互/计划/压缩或终止回执。不按 token、换行、停顿、EOF 或整组是否安静猜测完成；工具 A 完成不等并行 B 或整个 Turn。后台启动回执和后台任务最终结果是不同事实。

Core Thread 先向既有可靠队列准入 effect，再发布执行观察。Studio 单一产品投影按可靠 effect 顺序及批内稳定顺序冻结 draft，调用 Session 整批发布并分配完成 seq；同一投影依据冻结事实确定展示 item、成员归属与 item 顺序；同一冻结记录由 pending、短读和 writer 共享。完成发布立即可查询、可推送，不等待 SQLite；PendingHandoff 只是将准备结果附到已经准入的义务，不是首次入队或 durable 确认。

| 所有者 | 唯一职责 | 不承担 |
| --- | --- | --- |
| Core Thread | 执行事实、可靠准入 | 产品卡片、Timeline 分组、UI 分页 |
| Studio Timeline 投影 | 原子可靠终态、真实来源身份/顺序/生命周期、`text`／`workGroup`／`status` 顶层展示 item 及其成员归属/顺序/摘要/交接、current 有序未交接片段、展示前缀退役 | 客户端布局、滚动、展开状态、第二权威历史 |
| Core Session | 完成序号、完整 pending、幂等、scope 索引和一致读取 | 业务 payload/工具 renderer、Timeline 分组 |
| HistoryStore 与原 writer | 初始化/迁移、独立短读、完整批事务和确认、派生 item 表 apply/verify/rebuild | GUI 接纳或绘制 |
| ConversationFeed/传输 | 切点、Set/Append、有界传输与取消、同切面 item 与 currentAfter 交付 | 已加载消息镜像 |
| SDK/FRB | 机械映射、串行接纳、游标、ACK 与资源资格 | 分组、成员归属、展示排序、业务终态推测 |
| Flutter 薄呈现 owner | 一条 item 一条 `Message.custom`、已加载 item 集合、展开/滚动/布局补载与局部 UI 状态 | 计算成员归属、封组、展示前缀与排序、第二权威历史 |
| ChatController/View | 已加载 item/消息、展开/布局/滚动与实际视口读取需求 | 来源终态归约、分组、存储一致性 |

### Studio 唯一展示投影

Studio Timeline 投影是展示分组的唯一实现：live effect、重启恢复与派生表重建复用同一 fold，item 身份、顺序和成员归属不依赖客户端页面、控件回调或墙上时钟。

- **item 类别**：`text` 表示用户或父智能体输入、正式接纳的助手正文 part；`workGroup` 表示一个来源上连续的前台工作段（思考、工具、读取、文件变更、技能等）；`status` 表示明确独立的状态或回执（问答结果、计划决定、压缩回执、停止/失败、后台最终结果）。
- **分组边界**：真实后继分隔（正文开始、独立状态、轮次或来源结束）关闭工作段准入；成员终态齐备才提交工作段。同 Turn 的“工作 A→正文 A→工作 B→正文 B”是四个独立 item，不合并、不嵌套。
- **读图属于工作行为**：读图调用以及图片、文字和错误结果都留在原工作组成员内；不因 MIME、附件或解码失败拆组，也不产生图片专用工作组。用户输入附件与助手正式响应携带的媒体分别归各自消息 item。
- **正文规则**：真实空 text part 保留来源身份与结构边界，零字符不画空卡；仅附件、不含正文的消息保留，不因文本为空丢弃。停止/失败等待真实收束，保留已接纳内容，整轮原因由独立回执或 `status` item 表达；待决交互保持 waiting，不能为封组伪造完成。
- **后台结果独立**：后台启动回执与后台任务最终结果是不同事实；最终结果形成独立 `status` item，不按旧调用开始位置回填旧组。
- **逆序终态**：成员与 item 的展示顺序按来源身份和来源位置确定，不按完成先后重排；同一来源内已出现 item 的顺序稳定，后台/独立结果各自独立。
- **摘要有界**：`workGroup` 只保存身份、排序和派生摘要（成员数、运行/失败/取消计数、类目计数、首成员开始与末成员终态时间）与成员引用，不复制成员正文或 payload。

Inference 调用诊断不作为用户过程成员、不产生诊断专用工作组或分隔；完整执行/调用历史和旧原件继续保留。未知工具、Deferred 和敏感问答沿原格式、引用及遮蔽契约处理。新聊天不复制诊断步骤，存量只在必要迁移中标明普通展示资格，不删除原件。

**持久化边界**：原会话历史、正文、工具输出和真实来源元信息是事实源；`timeline_items`、`timeline_item_members` 与小恢复状态是可删除重建的产品读模型。Studio 的原 read owner 统一读取派生 RAM 尾部和 SQLite 前缀，Core Session 仍只认识原子事实。FRB/SDK 只传递投影，不维护第二份成员关系。可靠完成项立即沿原链保存，不等工作组交接；展示增量、来源元信息和原 current 在同一 writer 事务保存。只有原子完成项与最新 current 不足以重放全部真实开始边界，重建依据和维护边界见 §26.11，事务与迁移见 [17](./17-studio-storage.md)。

### 模型成员的可靠封口与交接

厂商提供独立且权威的成员结束事实时，模型层校验真实身份、内容、重复冲突及输出预算，再通过原调用内的有界可靠通道交 Core 形成 effect；不能用可合并 progress watch 代替。没有可靠成员结束的协议以最终 attempt 输出为依据，不根据通道切换猜测。模型上下文、调用用量和 Turn 终态不因此提前推进。

Runtime 沿同一 prepared handoff 和可靠预算封口；最终回执再次含同一成员时按冻结身份/字节幂等，冲突明确失败。停止或失败不撤销已经接纳的成员；生产者先收束并交接已接纳事实，再撤销观察，恢复不重跑旧请求。中断内容如实标识，原因以独立回执表达。

已完成成员从 current 退出由同源完成交接决定；先进入可查询完成集合与派生 item 行，再公开退役后的 current（currentAfter 只保留未交接片段）。现实模型输出与极端碎片化的容量边界见 [24](./24-testing.md)，不以提高帧上限掩盖现实规模内的成员交接问题。

模型适配器在 canonical accumulator 完成身份、part、内容和预算校验后，才向 [Core 成员端口](./16-core-contracts.md#163-模型调用契约) 提交模型拥有的成员回执；不能在原始事件的 `map`、trace 回调或可合并 progress 观察中先发布。独立成员回执与最终回执复用同一规范成员及身份；相同结束事件不重复接纳，后来的冲突不能覆盖已接纳字节。已交接成员不得通过透明重放旧请求来重新制造。厂商明确标记的 incomplete/中断不能冒充正常完成；没有独立权威结束的协议仍只使用最终 attempt 边界。

### 按作用域的 current 交接前缀

原产品 owner 在可靠 effect 的同一发布边界冻结本次展示 item 前沿、交接前后的小 `CurrentProjection` 及派生增量。即使没有新完成 atom 的真实 text-start，也可以提交前一工作组；因此不能用原子完成 seq 或 Session head 代替 item 发布进度。交接信息只保存有界信封/引用，不复制正文或全部成员集合，计入原 prepared/publication 保留责任，不提高帧数或字节上限。

Feed 只消费该类型化交接信息，不解析 payload 判断完成或分组。一个 Append 被条数或字节预算截断时，按已交付展示前缀退役 current 中对应 item，保留未交付 item；已交付 item 与 currentAfter 必须来自同一投影切面，禁止先发 item 后补 current 或跨切面拼接。不得用全局 H 相等作为 Main current 退出的必要条件，也不得在第一小批直接附上清空所有未交接 item 的 post-current。current 信封预算包含本批实际可能交付的 item/成员有界前缀，不在发出后再丢弃 current 凑预算。

部分交接期间沿用的 current item 引用仍遵循现役 revision 资格：它们不是冻结历史快照，来源已经换代时展开成员或范围读取明确返回 stale。不得为让旧引用成功而另存全量 current 集合、伪造空页或从完成 payload 重建成员关系；正文的稳定引用仍沿原 active→completed→durable 路径读取。writer 只保存原 effect 最终的 `PreparedCurrent`（含 items 与派生 item 行），不因不同读者的传输分批写入中间 current。

## 26.2 身份、顺序与动态 payload

每会话区分三条不可互相替代的顺序：原子完成 `seq`（发布会话完成序号）界定 H 与已提交连续完成前缀 D，pending 完整覆盖 `(D,H]`；来源身份与 `source_order` 保留真实来源内部位置和并行成员的实际位置；Timeline `item_order`（历史 `position`）由 Studio 投影在 item 提交时唯一分配，决定 Main 展示 item 的键集分页顺序。item_order 不是开始顺序、不是原子列表下标，也不由客户端或页面计算。seq 在发布时分配，必须为 SQLite 有符号 64 位范围内的正数；过滤后 seq 可有间隔，不要求 Flutter 验证连续。

成员 item_id 从可靠来源身份派生；展示 item id 由同一投影从来源事实派生（如 `text:<atom id>`、`work:<atom id>`），相同身份重试沿用首次冻结字节，不用最新工具 decoder 重建旧内容比较。载荷冲突、序号冲突与溢出明确失败，整批不部分发布。工具名、参数/结果、状态、时间、角色、格式标识和公开语义引用属于自由 UTF-8 JSON payload；索引列只表达查询成员资格和真实父域，不镜像 renderer 联合类型。

query_class 由写入/迁移确定，未知 payload 保留原类别，不因 renderer 不认识而隐藏。Main 查询类为 `timeline`，按派生 `timeline_items.position` 键集读取展示 item；成员窗口与真实业务 Children 使用 `conversation` 查询类，成员窗口经 `timeline_item_members` 关联有界读取。item 资格在 LIMIT 前由派生索引选择，不扫描完整原子集合再分组；不按客户端展开或分组状态筛选。parent_id 只表达真实业务父域，不是工作组身份，Children 只服务真实嵌套业务。来源身份、领域类别、来源内部顺序、完成发布 seq、Timeline item_order、真实生命周期与内容引用以轻量元信息交付，不要求解码大 payload。

来源顺序、可靠事实位置、Timeline item_order 和 feed delivery sequence 不同：来源顺序保持同一前台与并行成员的实际位置，可靠 effect/批内稳定顺序记录事实接纳位置，item_order 决定 Main 历史顺序，delivery 只服务句柄 ACK。后台交接结清前台义务但不表示任务成功；最终结果是独立 `status`，不回填旧组。T 开始→B 完成→T 完成时，T 仍 live、B 立即进入历史，最终 B→T；完整来源事实重建须保持此结果，旧缺失输入采用 §26.11 的明确限制。前台顺序与可提交前缀只由 Rust 计算。

item 进入历史的时刻由提交条件决定，不等于原子完成顺序；冷读只对已加载事实与已保存 current 切面投影。同一完整事实在 live、首屏、旧页和重启后必须有相同 item 身份、成员归属与 item_order，因为四者复用同一 Studio 投影；Flutter 不重放跨来源 UI 插入时刻，也不在客户端重新分组。部分范围保持部分/未知：未加载的 item 不显示为已确认邻居，`GroupMembers` 页只承担该 item 的成员事实，不能据此推断顶层 item 之外的结构，也不据此跨缺口合组或伪造旧时刻。

## 26.3 完整 pending 与保存交接

pending 不是 UI 缓存，不随意 LRU 淘汰。主索引与 class/parent 有序辅助索引引用同一冻结记录，读取不能先扫描全部 pending 再过滤。预算沿原可靠准入/retention 计算，保存失败保留事实并背压，不能无限增长或丢最旧项。

writer 只提交已准备的连续 effect 前缀；事务成功后按本批实际完成项的连续前缀推进 D，不能读此时 Session.head 或取跨空洞最大值。没有 completion 的 effect 不凭空推进 D；保存 ACK 不产生第二次 Append。已提交项仍被已接纳短读引用而短暂存活是正常所有权，不强制销毁引用。

显示不等保存、writer 不等 Flutter。关闭等待原保存屏障；进程提交前崩溃可能丢失 RAM 尾段，不能承诺不等落盘和崩溃零丢失同时成立。批处理、回执、accounting 及故障恢复见 [15](./15-session-storage.md)。

## 26.4 按需分页与 continuation

一个读取需求包含 `max_items` 与 `max_bytes`：条数必须大于零，由当前展示需求决定；字节至少容纳一个合法轻量 envelope，否则返回 InvalidDemand。服务端校验资源上限，但不恢复固定 32 条或固定正文预览长度的 UI 合同。预算覆盖实际编码开销、身份、header/current 和引用；不能用返回条数或估算驻留量冒充传输字节上限。

Main 分页以 Studio 投影生成的展示 item 为单位：`max_items` 限制整个 `ChatBatch.entries` 的条数，展示 item、独立 `Atom`（成员窗口/Children）与可靠 `Source` 事件均计一条，Set、Append、Prepend 和普通窗口查询均须在发送前核验；`max_items=1` 仍是合法需求，不能提高最小条数或排除 Source 事件计量来规避分批。current 继续使用原有界信封与同一字节预算，不另开信用或预算。

Main 的 item 键集由 `timeline_items.position` 递增序确定。首个 Set 固定 item 位置上界与该切面的 current；Append 只交付切点后新提交的 item 与 currentAfter；Prepend 交付更早的 item 页并替换 continuation。`before` 是绑定原库身份、`ChatScope::Main`、item 排他位置与读取作用域的不透明字符串，Flutter 原样回传，不解析来源、seq 或 position。

`GroupMembers { reference }` 是独立读取作用域：类型化引用含 `database_id`、`projection_version`、`item_id`，原 owner 校验后按成员关联索引的 `member_order` 有界读取。该 scope 自有 Set/Prepend/Append、continuation 和活动窗口更新，不复用 Main cursor。成员顺序与归属由投影决定，Flutter 不重排或发现成员；折叠不读取成员与媒体，引用不能跨库或投影版本使用。

成员/Children 的原子页不将每个来源的读取证据再追加为独立 entry：`ChatAtom.source_state` 可携带该原子来源在读取切点的真实 `ChatSourceState`，身份必须与 `atom.source` 一致；其成本纳入原 entry 编码预算，不是工作组或范围证明。冻结完成 metadata 的 `source_state` 必须为 None 且不编码该字段，reader 才按同切面事实填入，不能把较晚来源结束永久写回旧完成项。仅 current 涉及的源直接由已计量的 `current.sources` 交付。真实 start/end 仍沿原可靠 handoff 以 `ChatEntry::Source` 发布并按条数、字节分批，不因存在读取注解而合并或吞掉可靠事实。

Main latest 捕获固定 item 位置上界与完成水位 H0；before 还要求 item position 小于游标排他边界。一次读取如下：

1. Studio 投影在串行边界捕获 H、D、展示 item 上界、current 切面及匹配 scope 的有界派生行引用；所有候选不超过已发布前缀。
2. 按 `timeline_items.position`（或 `GroupMembers` 的 `member_order`）索引倒序取预算内候选；展示 item 只读轻量 metadata 与内容引用，不解码成员正文。内存已满足需求或任一预算耗尽，直接返回，数据库 page/existence 查询为零。
3. 仅匹配候选不足且条数/字节仍有余量时，锁外建立捕获之后的新 SQLite 短读快照，只补持久化前缀的同 scope 数据；短读只碰派生表与必要的原完成项 payload 长度，不重新运行投影。
4. SQL 先按索引选择头部和 payload 长度，再一次或有界批次读预算内 payload，不逐项完整解码工具；两个天然不重叠区间拼接为 position/原子 seq 升序结果。

不能跨 await 持 Session 锁、复用捕获前旧快照、查询触发 flush/执行恢复/完整性检查，或跳过较新的大 item 去库里凑旧小 item；超预算 payload 以 Deferred 表达。捕获后 writer 清 pending 时短读仍持 Arc；捕获前清理则后开的 DB 快照已能看到提交。

before 是绑定原库身份、scope、排他位置和读取作用域的不透明字符串，Flutter 原样回传、不解析来源或 seq。不返回 totalCount，不 COUNT，不为 UI 计算全历史空占位。非空 before 仅表示可继续请求，不保证下一页非空。只有内存和库均已确认耗尽才返回 null；内存恰好够页时不为精确 hasOlder 额外查库。允许一次空末页返回 null，非空页 cursor 必须前进，空页不得原地 continuation；短页和字节截页不自动表示 EOF，item 页只含折叠摘要也不表示成员已经加载完毕。

## 26.5 按 scope 的批次与真实生命周期

Rust 产品契约统一归 pl-protocol，FRB/HTTP 同语义；Core 仅持产品无关完成记录。

| 类型 | 字段/语义 |
| --- | --- |
| 原子 envelope | 稳定成员 item 与完成载荷身份、实际来源/turn/attempt/part/call、完成 seq/来源顺序、领域类别、终态、内容引用及动态 payload |
| 展示 item `TimelineItem` | 稳定 item id、`text`／`workGroup`／`status` 类别、真实来源/turn、delivery 与文本频道、时间、Text/Status 原子确知的可空 terminal outcome、类型化成员引用、有界摘要、内容引用、可选 Inline/Deferred payload、可空历史 `position` 与准入关闭状态；组不合成整体成功、不含全量成员 ID |
| PayloadData | `Inline(bytes)` 或 `Deferred(reference,byte_length)` |
| ChatBatch | `placement`、有界展示 item/成员原子/真实生命周期 `entries`、scope 自有 `before`、可选同切面 `current` |
| ChatPlacement | Set、Prepend、Append |
| CurrentProjection | source effect、真实来源/attempt 状态、有界 active turn/活动、Plan/交互头部、内容/集合引用，以及有序未交接 `items` 和预算内必要活动 `atoms`；不以成员数组镜像完成长组 |

完成 seq、来源位置与 item_order 按各自语义交付，H/D、source incarnation 和 opaque cursor 解析仍归 Rust。`Message.custom` 是 Flutter 自己的类型，不复制 Flyer 联合、oldMessage/index 或任意 UI diff。无后端工作组 PageContext、closedThrough/terminalThrough、readyAt 或组范围协议；`admission_closed` 只表达准入是否被真实后继边界关闭，不是历史提交或终态资格。真实生命周期只补领域确实发生的开始/终态，不增加一套可查询事件存储来替代原 effect/current owner。

Main entries 只有 `ChatEntry::Item(TimelineItem)`；成员/Children 才是 `Atom`／`Source`，scope 不混接。原子 payload 在开始时可缺省，完成后仍归原 item；completion_seq 与可空 source_order 分开，未知不伪造。SourceState 仅说明真实来源 Active/Ended/Unknown，不从未加载推断 Ended。current 的 item 可以已经全部成员终态但等待后继边界，或边界已定但前一成员未终态；成员细节经 typed 引用按需读取，不在快照镜像完整长组。诊断不进入用户工作步骤，原完成 seq 不因展示改变。

活动 `wait`／`sleep` 原子的 `wait` 可选字段直接交付原工具投影已产生的 `ThreadWaitPresentation`，
绑定同一 atom/call 和同 effect 切面，不依赖尚不存在的完成 payload。运行中等待、超时参数、计时器时长及
确知目标均来自原参数与任务事实；缺失保持缺失，不从工具名或通用 `running`／`waiting` 状态猜测。
该字段只表达工具领域事实，不定义工作组、来源结束或新的接纳资格，计入原 current／批次的编码预算，
不提高预算或预读隐藏参数、正文、输出。终态继续使用原完成 payload 中的 typed wait；不在完成 metadata
重复保存活动投影，旧冻结 metadata 缺省此字段仍解码为无活动事实，无需改库或回填。
FRB、HTTP 与 SDK 机械传递同一字段，Flutter 复用现有 Waiting 组件，不建立另一套等待状态或任务查询。
取消 Waiting 仍由真实 Stop 与原任务 owner 执行，不能因显示变化取消之前 Turn 的计时器或伪造终态。

Core ChatDraft/Header 的不透明轻量 metadata 随原冻结完成记录发布、查询和保存，产品 reader 无需解码 payload 即可映射 Atom；Core 不解析其领域内容。实际来源开始/结束经原 Thread effect/current handoff 一次交付并同事务保存，历史页按真实来源身份有界取得同切点状态。它们不是工作段起止或前缀，不能按正文/工具 UI 分类制造来源闭合。来源可跨 attempt，idle 压缩有独立真实操作身份；后台最终结果独立来源，保原 call 关联。

| 来源 | placement | before | current |
| --- | --- | --- | --- |
| Main 首屏，entries 可空 | Set | 设置 Main item continuation | 必须有具体快照，可明确空 active |
| GroupMembers 首屏 | Set | 设置该 item 的成员 continuation | None |
| Children 首屏 | Set | 设置该 scope 的 continuation | None |
| 旧页，末页可空 | Prepend | 替换 continuation，None 为已知 EOF | None |
| 新 item/真实来源事实 | Append | 必须 None，不修改原游标 | Main 可带 currentAfter；GroupMembers/Children 必须 None |
| 纯 current 更新，entries 为空 | Append | 必须 None，不修改原游标 | 必须有，仅 Main |

`current=None` 始终保持不变，具体空快照才清空。完全无变化的空 Append 不发送。每个 handle 首个成功 Chat 必须 Set，之后只有 Append；重同步终结旧 handle 并以新 handle 取得 Set，不在原流偷偷 reset。合法组合由 Rust 构造与测试保证，Flutter 不再跑一套业务切点校验。

## 26.6 被动打开、首屏切点与有序推送

open 在 Rust 内完成观察登记、切点捕获和有界基线准备，events 仅安装唯一消费者交付既定序列，不能等 events 才登记。Studio 投影在串行边界发布完成 H0、同源 effect 切点、真实 current/source 与新增展示 item；首个 Main Set 固定 item 位置上界与 current 切面，后继 Append 交付切点后提交的 item、原子/来源事实与 currentAfter。没有新增 completion 的可靠 start 也不能因 H 未变化而漏掉或被 current 合并吞掉。复用原可靠 handoff、预算及保存路径，不建展示事件总线。打开不追逐最新 head 无限重试。

冷读在同一短快照中取得轻量完成水位、current 与初始页，不读/校验/解码完整 checkpoint/current_context，不激活模型、工具、SSH 或执行 owner。current 表示最后已提交的逻辑状态，是否真有执行 source 由 registry 判定，重启前 running 不冒充当前运行。

无执行 source 的目录状态投影可恢复性，不复用旧进程的资源关闭状态：root 与 child 的非显式 Closed/Closing 均沿既有目录规则投影为 Idle；显式关闭封口、旧 retirement、归档准入及热 owner 的真实关闭阻塞仍有效。输入所需原模型路由与扩展修订号是独立于运行资源的 State 事实，其轻量保存与交付分别见 [17](./17-studio-storage.md) 与 [18](./18-studio-state.md)，不得为补齐它们激活执行或伪造 runtime。

复用 ThreadObservations 的稳定 observation slot 登记并捕获单调 epoch/位置；冷读后复核，覆盖 absent→live→absent 的 ABA。来源判断看 resident/pending，不只看业务 running；idle 也可有未落库尾段。源退役先安全交接 pending/writer。可连续接续由 Rust 完成握手，否则以现有 Failure 明确要求 ConversationResyncRequired，旧分页资格同时失效，不能返回空页或吞错。

slot 已安装而首次 publication 尚未就绪时，open 同时借用该 owner 原有的 retained progress 结果：先登记接收资格，再检查已保留错误及完成状态，并等待同一结果或来源代次变化。不能另建 readiness 镜像、只等 broadcast 或借执行激活/flush 补救。原失败按原共享错误与 typed 分类传出，不将其格式化成新字符串而丢失 code、reason 或可重试性；无错误但 owner 已结束且仍无 source 时明确要求重同步。工具停止还必须能打断该窗口中的 open 和首批接收，不能被 opens 读写锁互相阻塞。

对 Main，原子先成为可查询完成集合与投影成员事实；Studio 投影在同一边界确定 item 与成员，按 item_order 开放可查询。Flutter 薄呈现 owner 只机械接纳 item 与 current、更新已加载 item 集合、把新 item 交给 controller，再 ACK 连续接纳前缀；不计算成员归属、不封组、不拼展示前缀。ACK 不等后继正文、query、用户展开、布局、视口填满或 SQLite；不能用无限队列掩盖背压。成员窗口与真实 Children 仍遵守各自 scope 的可查询及退役前缀。同批 item 与 currentAfter 必须同切面，current 不能越过未交付 item 或吞可靠来源事实，超预算无法保持边界时明确重同步。

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

`CurrentProjection.activeTurn` 保留真实 Turn 身份与阶段，不能作为工作组容器。`CurrentProjection.items` 是有界、有序的未交接片段（`text`／`workGroup`／`status`）。工作组只含摘要与 `TimelineMembersRef`，不在 item/current 中重复传输随组增长的全部成员 ID。该引用绑定原库、投影版本和稳定 item 身份；展开后在独立 `GroupMembers` 窗口读取实际成员。`atoms` 仅保留原 current 预算内确有需要的活动事实，不充当组成员索引。多个未终态 part 不限队首显示；正文在前一思考尚未终态时仍可读，空预览不是来源终态。

工作组展开按 `GroupMembers { reference }` 有界读取成员：Rust 依据成员关联索引选择组内稳定顺序，只返回属于该 item 的成员。current 与 history 使用同一引用和读取契约；活动成员的窗口变化由原有界观察机制交付，同一成员 ID 的真实进度/终态更新只替换该窗口的成员，不改变 Main item。历史成员顺序及归属冻结。Flutter 不发现成员、不找组头、不推断封口。折叠时不读成员与媒体，展开也不改变业务准入；先同步撤销窗口、正文与媒体资格，再 cancel/join。真实业务 Children 继续保留，不以整个 Turn 冒充组。工具参数、结果及附件按真实 call 和内容角色归在一个入口，诊断只借已挂载内容。

Main 的旧页 cursor 固定打开时的 item 切面，不用于任意原子窗口。Flutter 不接收 completion seq 作为分组恢复锚点，不拼装 cursor，不通过旧 `readBefore`／`readAt` 原子扫描接口补组。工作组详情只按 typed `GroupMembers` 引用读取；真实业务 Children 和正文范围保持各自原资格，旧页及成员窗口均不覆盖 Main current。

`CurrentContentPreview.role` 只是展示分类，不是文本频道或出站许可。预览以可空的 `textChannel` 保留原 canonical 文本条目的 `ThreadTextChannel`；非文本或无法证明频道时为未知，缺失也只表示未知，不能由 `Response`、正文、ID 或所属活动补成 `Final`。该事实沿原 current owner、存储与 FRB／HTTP／Client 映射交付，不新增旁路查询或状态镜像；同样计入原有编码和传输预算，不改变正文引用、generation 或完成边界。[机器人出站契约](./27-bots.md)的 Final 资格必须由明确频道及原目标 Turn 共同证明，未知与 Commentary 都不能授权创建或更新回复卡片。

## 26.8 Flutter 薄接纳与组件消息集合

使用已有 InMemoryChatController，不另写 ChatController；已提交 Message 仅由它持有，Chat 负责 Widget 惰性构建/释放。`applyBatch`/owner 只机械接纳 Studio 已确定的展示 item：一条 item 对应一条 `Message.custom`，不分类、不合组、不改 item 顺序、不计算成员归属。Set 一次设置已加载 item 投影与 current；Append 只插入新提交的展示 item 并替换 current；普通 Prepend 按 item 键集插入更早页，不固定 index=0。token/运行进度不修改历史，保存 ACK 不重复插入，初始/旧页不做新增动画，不重置整表或手动重复发组件 operation。

`text`、`workGroup`、`status` 各对应一条顶层 Message；工作组展开后才读取成员，折叠只显示摘要。key 使用稳定 item id，live→history 沿用展示身份；本次观察可按 ID 保留局部展开意图，但跨父树不假定 Widget State 自动保留，重开也不承诺同一内存对象或展开偏好。作者/时间只取可靠值，未知/Deferred 不丢轻量归属或补造时间，单项降级不吞读取错误。历史 Message 只由原 controller 持有，不另存全量 rawAtoms/items/groups、永久成员索引或无界 ID map。

实时、首屏、旧页和重开共用同一 Studio 投影的 item 身份/顺序/成员，不共用第二套客户端规则。R start→T start→T complete→R complete 等交错由投影 fold 一次确定；普通 Prepend 不要求 Flutter 推断显示邻接，也不跨未知缺口合组。满屏后不为找组头继续读取。controller 同步 getter 不经异步 FRB；SDK 纯 Dart、机械映射，不依赖 Flyer 或 app 生成代码；SDK 不分类/分组、不保存历史尾部。

查询 IO 在串行应用段外；分页返回和事件都进入现有串行接纳链。捕获原 lease/controller，组件 await 后、before/current 发布和 ACK 前均复核原资格；不能重新读取当前选择绑定旧结果。主历史只在自身 Set/Prepend 更新 item continuation；`GroupMembers` 窗口的 Prepend 不改主历史游标，也不与主历史共用 cursor。同方向请求沿原 owner 的 single-flight，Append 不改变旧页边界。错误保留原 cursor，EOF/失败/取消都结束分页 Future，不等待物理绘制或数据库保存。

### 按展示 item 的布局补载

首批按视口估计需求并立即展示。View 在本批实际布局后检查聊天滚动视口，未满且 item continuation 可继续即通过原 loadOlder 读取一页；每页完成再安排检查。需求按展示 item 计，不按成员数或原子数计；页内 item 可能都只是折叠摘要、高度很小，也必须继续补载；不设固定启动总页数或固定总页数上限。单次仍受 demand/credit 限制，同方向 single-flight。短页/字节截页不等于 EOF；满屏或明确 EOF 才正常停止，EOF 后允许不足一屏。

无进展作为协议错误暂停，不改成 EOF、不循环重试。读取错误由原 owner 发布并暂停，显式重试成功后可继续。窗口、输入区、实时区、展开/折叠和外层 ScrollMetricsNotification 驱动新布局需求；只测实际聊天视口，零尺寸/不可见/无效 owner 暂停，忽略内层滚动，不持续逐帧轮询。reversed 列表的最新端为 pixels=0，不能把旧端 extentAfter=0 或包含空白的 extentInside 当满屏依据；复用已有有效 scroll range 判断，不新增全列表测高或像素补偿。

折叠工作组的成员数量不影响 Main 页数：一个折叠组无论多少成员都只占一条展示 item，展开时才按 `GroupMembers` 页读取。填屏可能需要经过很多前后相邻的文本、状态和折叠组 item；一组/一段占满全部历史时仍可读到 EOF 后留空白。每页交接给正常布局，不同步长循环/并发预取多页；不为填屏下载隐藏成员正文/媒体、COUNT 或强制 flush。满屏后不为总数、精确成员数或组头额外读取，缺统计只报已加载 N 项或省略。首批可见、满屏/EOF 总耗时和页数分别报告，不承诺长历史整体补满常数成本。

已浏览 Message 在本会话打开期间保留，长期浏览会增长，不宣称默认数据内存恒定；切换/关闭释放旧 controller 和 Message 的所有引用，不能仅 dispose 后继续缓存。列表前插仍有组件移动成本，不承诺无限长已加载列表 O(1)。阅读旧位置时继续接纳新增，回最新走组件公开能力，不重开订阅、不做像素补偿。

### 26.8.1 展示 item 自足与成员按需读取

Main 页的每个 item 自带类别、顺序、有界摘要和引用，不依赖相邻页或成员详情才成立。展开按 `GroupMembers { reference }` 读有界成员页，不改变已提交 item 的顺序、身份或归属，不保存页 DTO 栈或全历史成员索引来“证明”相邻。组总数与结果统计直接来自投影摘要，不能被当前成员窗口的已加载数量覆盖；窗口加载进度另行表达。

真实结构分隔、可靠开始事实和同一投影的在手事实决定 item；Flutter 不根据显示邻接推断，也不因成员页缺失把 item 标为不完整。未知/损坏/Deferred 成员在展开时局部降级，不破坏 item 摘要、邻居或读取错误语义。

### 26.8.2 current 片段与成员展开的资源边界

`CurrentProjection.items` 与 `atoms` 是客户端可见的唯一未交接展示来源：items 保持有界有序片段（可含已终态但尚未满足提交条件的成员/片段），atoms 只承载这些片段的当前成员事实。接受与可绘制是不同完成点；item/成员信封受原 current 预算约束，不能为了显示条数丢弃未终态 part，也不能把未交付事实先画成历史。已提交 item 的内容仍归原完成项，不在客户端复制第二份正文或成员集合。

折叠工作组的成员正文与媒体不随批传输；展开时按 `GroupMembers` 独立 cursor 有界读取，读取窗口存活于该 item 的展开意图，折叠/退役先撤销窗口资格再 cancel/join，不推进主历史 cursor。已加载成员页、正文窗口与图片资源随展开对象和视口需求存活，退出时释放；不得保存每成员/每段的永久骨架、完整 Atom、JSON 或展开意图表，也不得用隐藏 Element 或闭包继续保存已释放 props。

被释放的成员窗口需要恢复时，按原 item 的 `GroupMembers` cursor 或原 read lease 的普通窗口重新有界取得，不重建顶层 item、不重跑投影、不复制完整来源。已完成但尚未提交的片段仍在原 Session 完成集合与 Studio 投影中；恢复只按当前需求物化，阻塞解除后的 item 提交由 Rust 投影继续，客户端 ACK 不等待恢复 IO、成员展开或布局。相同来源先后约束与独立结果完成位置同时满足，不为等前台恢复延迟独立后台结果。

未物化区间的存在不能触发无布局的同步扫描或固定总页数截断；满屏即停，显式滚动/展开继续原有界读取，并分别报告实际页数、重复读取及总成本，不承诺任意来源顺序与完成顺序交叉下的常数恢复成本。current 切面变化时，客户端丢弃不再属于新切面的旧 item/成员引用；不得从完成 payload 重建成员关系或用旧 current 覆盖新快照。

## 26.9 工具当前契约与单条降级

当前执行 schema 与专用 renderer 各只维护一套。展示契约标识在请求冻结时确定，随真实调用/结果保留；同名同形字段不证明旧语义兼容。当前 renderer 只解析它声明支持的契约；无标识/未知标识或当前完整正文非法仅该项不兼容，保留身份、顺序、合法公开原文和可靠通用事实，不虚构时间、状态或工具参数。

合法但截断的预览、Deferred、custom/freeform 非 JSON 正文与真正 Malformed 分别处理，首屏不自动批量拉详情。generic MCP 的通用形状不依赖在线目录；敏感/redacted 继续受公开资源规则约束。数据库错误、内容缺失、身份冲突及执行恢复错误保持独立诊断，不将所有异常吞入“不兼容”。

工具形状改变不改通用 envelope 的 SQL 索引结构或追加历史 decoder/别名，旧工具业务字节只在正式容器迁移边界处理；续聊使用冻结模型上下文，不从当前 UI payload 重建或重跑历史工具。

## 26.10 验收与只读诊断

普通当前格式打开的 full_context_rows、quick_check、execution_activation、tool_or_ssh_initialization、query_triggered_flush 均为零。相同需求下增加总历史、隐藏活动或上下文，不增加线性全量读取/检查/解码。记录 SQL/pending 候选与返回量、payload/content/编码字节、逐项解码数、controller/实际构建行数及排队时间；诊断只临时借用 controller/owner，不反建第二历史集合。

当前展示诊断直接按 controller 的 Message 顺序（即 Studio item 顺序）读取已挂载 item 的 metadata，分别报告顶层 item 数、类别与 position、成员引用、兼容性、有界正文/引用及显示代次；不查询未展开成员或反建隐藏集合。item id/position 与完成 seq/来源位置是不同事实，H/D 与源 epoch 仍留 Rust，不为旧脚本伪造跨 owner 稳定 item key；顺序与局部插入/更新使用真实对象身份和操作证据。

展开内容通过原 Main 展示 lease 登记只读借用，记录实际成员窗口（`GroupMembers`）或真实 Children 读取位置、显示代次、资格及已挂载窗口；真正业务 Children 另保真实 parent，不从 Main item 重建 Children。查询诊断不触发 IO 或建立完整成员镜像。关闭/换代/lease 退役同步撤销借用，旧回调不能登记到新 lease。批接纳、item 页、成员页和 controller 操作分别计数：页内 item 只是折叠摘要、高度不变或没有新增组件操作，不能推断无数据进展。Set/Prepend/Append 的操作计数在原组件操作成功且资格复核后递增，不从当前消息长度或内容推测操作。

运行中详情同样只借用真实挂载的 current 资源：只读观察可读取用户已展开、原 scope 已接纳的有界集合页及正文窗口，并报告原集合引用、局部代次、展开/加载/错误状态和 continuation。读取诊断不能发起 page/watch、展开组件、复制完整 current 集合或保留跨代页面；折叠、引用 revision 变化、来源 attempt 变化和 Main lease 退役同步撤销资格。工具等待只按现役 `tools` 页中原 call 身份与 producer 提供的 typed wait 判断，不从工具名、完成记录或输出片段猜测；没有提供的 item 身份及终态结果保持未知。

各层验收证明其实际拥有的事实。独立工具结果在 Turn 结束前已可靠发布使用原 Runtime/HTTP 读取资格证明，不能以将来的页或实时输出片段冒充更早完整结果，也不要求 Flutter 提前制造历史 item；展示 item 由 Studio 投影按提交条件生成。需完整库存时，验收器沿普通 Main item 与真实业务 scope 有界分页到 EOF 并即时取证，不以最后一组/当前成员窗口代替全历史，不要求惰性行、图片或展开态全常驻。

性能首批主指标为真实 selection 到同 generation 首个有效内容完成布局，迁移完成、同硬件/构建模式下冷打开和普通切换参考 p95≤500ms；另报视口满屏/EOF 总耗时、总页数、读取 item/成员/字节、正文加载量与 build/raster。长历史可按展示 item 逐页经过；折叠组本身不增加 Main 页数，不将首批目标外推固定补满时限。进程冷启动、read scope 冷打开、OS 页缓存、数据规模/样本量/p50/p95及迁移耗时分别报告；Rust/Dart 单调时钟用 trace 关联，不跨时钟相减或用 FrameTiming 批回调时刻代替帧时间。

AppGraph 在规范的可见选择目标成立、发出该目标读取 demand 之前记下同一 Dart `Stopwatch` 的起点；这不是后来的 Set/owner-ready 时间。正文见证仅包裹已解码且实际呈现的非空内容，在该正文子树完成 layout 后捕获同钟时间，再于本帧末核对原 lease、代次及实际可见资格。帧末回调只做资格确认，不用回调到达时间替换已捕获的 layout 时间，也不持续申请帧。skeleton、Deferred 按钮、错误提示、空容器、未呈现内容及已经退役的布局不能完成样本；无有效见证保持未知。应用只留当前展示代次的小样本，外部验收采样器负责汇总，不建立应用内跨会话性能历史。

通用内容范围查看器浏览一个有界字节窗口，下一段只在显式操作时请求。复制操作明确标为“复制当前段”，仅复制当前实际显示的窗口文本；不将它标作全文复制，也不为旧全文断言自动追读所有段。完整公开原文仍可通过同一稳定引用逐段读取。验收脚本分别证明窗口读取、显式续读及当前段复制，未提供的全文复制能力明确列为不适用，不能用窗口成功冒充全文成功或伪造旧详情接口。

需覆盖内存足页零 SQL、提交/清 pending 交错、固定切点/持续新增、并发上翻、源 ABA、同批 item 与 currentAfter 退役、超长内容、未知工具、慢消费者、独立 query、A→B→A、空正文结构边界、附件-only 消息、读图不拆组、逆序终态、后台结果独立、投影版本重建与派生表恢复、成员页独立 cursor、关闭/保存故障和非空迁移。原生、模拟供应商、真实供应商及各平台证据分开，不以日志采集、组件成功或文档目标冒充验收通过。

## 26.11 重建输入与维护暂停

正常增量和重建只调用同一个 Studio 投影算法。输入必须来自原规范来源接纳的真实事实，不从日志、UI 文案、raw token、旧派生组缓存或最新检查点猜出过去的开始/结束。

| 规范输入 | 可证明依据与缺失语义 |
| --- | --- |
| Atom、turn/attempt/part/call 身份、语义类别与频道 | 原可靠模型成员端口、工具/输入/交互 owner 及冻结原子 metadata；工具输出按来源归属，不按 MIME 或 JSON 外观分类 |
| 来源位置与可靠接纳位置 | 原来源 ordinal、`ChatFactPosition` 的 effect/suborder；原子完成 seq、effect/write seq、展示 item_order 与 feed deliverySequence 分属不同顺序域 |
| 真实开始、空正文及可靠终态 | 保存必要的开始/终态元信息；正文 `contentPresent=false` 仅在文字和附件确实都为空时成立，未知不省略、空白字符不裁剪 |
| 后台交接、最终结果和来源结束 | 原调用交接/Inbox/Turn/attempt 的 typed 事实；交接不冒最终成功，页面关闭不制造终态 |
| 时间与内容 | 原始可证明起止以及稳定内容/附件引用；未知时间不填零，不按成员顺序选择“最后完成”，不计 UI 媒体加载耗时 |

这些轻量来源元信息沿原可靠 effect 保存；只记录真实结构/生命周期，不记录 token，也不增加第二个 writer、事件总线或重建队列。最新 `history_items`、`last_write_seq` 与 current/checkpoint 都不是完整事件日志。旧数据在正式准备边界一次规范化：优先可证明来源顺序及消息/终态边界，确无顺序时保留完成顺序，无法证明归属时保留中性独立信息，未知不伪造；随后仍进入同一个投影算法。

派生缺失、版本变化或明确损坏才触发维护重建。先在原产品 owner 的可靠处理边界暂停派生推进，提交已准备连续 writer 前缀取得 durable effect 切点 C；C 之后的输入仍由原队列、原预算与背压承担。按 C 的一致源快照逐批重建，正文/图片不载入内存，内存不攒全会话事件、payload 或全量成员 ID；派生行、版本及多个未交接片段的小恢复状态在同一事务完整替换，失败/取消回滚，原事实与旧完整版本保全。

成功后唯一 owner 接管新状态，再接纳原队列 C 之后的输入。旧查询句柄、cursor 和成员引用按原代际退役，新句柄从 Set 开始，不混用投影版本。维护暂停和失败属于当前加载/连接状态，不插入业务历史，不取消模型/工具；不以失败回退客户端分组。正常命中只查小版本/恢复状态及 item 索引，不重复扫描原历史；重建耗时单独报告。
