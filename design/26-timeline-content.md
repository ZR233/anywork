# 26 - 原子完成事实与增量展示快照

本文维护 Native 完成内容及 GUI 展示契约，依据 [#316](https://github.com/ZR233/anywork/issues/316) 及其补充修订 #311 的展示时机，保留其不可变完成原件、唯一保存链与 State 业务引用。这里定义目标，不以文档更新冒充实现或性能验收。ACP 的外部协议保证不变。可靠执行保存归 [15](./15-session-storage.md)，存储迁移归 [17](./17-studio-storage.md)，传输归 [07](./07-streaming.md)，客户端资源归 [25](./25-frontend-state.md)，视觉归 [19](./19-studio-ui.md)。

## 26.1 两个完成点与唯一所有者

**原子内容完成立即保存；展示段在真实边界确定且成员收束后整体进入 Timeline。** 内容完成与展示完成有独立序号，不能把完成记录数当成历史卡片数。工作组中的已完成成员保留在实时区，已经交接的历史块不再接新成员或更新摘要。

| 所有者 | 职责 |
| --- | --- |
| 原 Core Thread / 业务 producer | 真实执行准入、成员开始/终态、来源事实、可靠 effect、检查点与上下文 |
| 原 Native live owner | 完成封存、读取分类、增量展示段与成员关系、同切面发布 |
| Core Session | 原件 seq/run 分配、精确幂等、完整 pending、统一原件读取；不解析展示 metadata |
| 原 HistoryChannel / 唯一 writer | 原件、内容、检查点与冻结展示增量同事务保存，原背压及提交确认 |
| Feed / FRB / HTTP / SDK | 有界读取、固定目标补读、机械串行接纳、信用与资格 |
| Flutter 原 controller / display lease | 一冻结块一卡、局部展开与滚动、历史插入和实时退役的同次公开 |

原 `ChatDraft → ChatItem` 和 `conversation_items` 是唯一完成原件。展示快照只持小头、身份、成员引用及计数，不是第二套执行状态。无新 actor、线程、全局注册表、writer、可靠展示队列或保存定时器。真实 Plan、交互和配置仍由原领域 State 管理。

### 已接纳输入与已接收外部内容

“完成”表示这条事实已确定，不是整个任务完成。普通输入在原 `InputChange::Accepted` 可靠接纳时沿原 input.id 冻结，排队不等 Turn 开始。Pending→Consumed/Discarded、后来的 Turn/attempt 关联只更新执行/State，不重新封存原件；未知关联保持 None。同 ID 同冻结内容幂等，异内容冲突；同文不同受理 ID 是两条事实。

受信宿主明确允许公开的外部正文，在目标 Thread 原 inbox 准入时沿原 message ID 冻结，保留来源、作者和频道。外部平台已转换为 ThreadInput 的只走输入链；后台最终结果走原工具完成链，不因 inbox 转发或出站通知重复发布。文字中的角色、批准或工具完成声明不获得权限。

输入/外部消息形成独立 Single，不能仅因输入到来就伪造前台边界或工具终态。隐藏续接和诊断保持原公开资格；公开答案及计划决议由原唯一回执产生。GUI 命令回执不手动插入历史。

### 模型成员的可靠封口与交接

开始与终态由原可靠 producer/effect 接纳，不能被可合并 progress 吞掉。正式 TextStarted 只来自已准入的 typed Started 或外部协议等价可靠事实；附着同一次 effect 保存前段交接，即使原件完成 H 不变。preview 首字只用于即时显示，不能单独永久封组。缺乏独立终态的来源等实际 attempt 最终回执，不人为补 reasoning.end。

停止请求、页面离开、token 暂停、推测 EOF、保存 ACK 和模型自述不构成终态。正常失败/取消按真实结果收束；异常退出前未保存 token 前缀不承诺恢复。

## 26.2 展示身份、来源与真实边界

原件 `item_id` 是稳定业务身份，`seq` 是完成发布顺序，范围为 `1..=i64::MAX`，由原 Session 在 RAM 分配，不是时间戳或开始顺序。原件历史始终按完成 seq，不反向改写。

展示 lane 直接使用 typed `ChatSourceId`；成员身份由来源、真实 atom/call/part ID 与阶段组成。前台责任和后台最终结果分属不同阶段，同 call 的启动交接和最终结果不能命中同一成员槽。块 ID 使用库身份、来源和段首真实身份的无歧义编码；旧库用独立 `legacy-run` 域与原 run_start。不得用墙钟、正文 hash、成员数或查询次数生成身份。

每个来源维护开放 Work 及有序待交接段队列。成员开始时一次确定归属，之后通过成员索引定位；只推进该来源 ready 队首，不全局两两比较、拓扑排序或重排已发布块。

| 事实 | 展示处理 |
| --- | --- |
| 首个思考/工具/文件/技能开始 | 创建 Work；后续同来源成员加入无边界的开放 Work |
| 成员真实完成 | 原件立即发布保存；增量更新计数和引用，成员继续留在实时组 |
| 全员完成但无边界 | 继续留实时；不按 running=0、超时、下一帧或保存 ACK 封组 |
| 正式正文开始 | 关闭前 Work 准入，建立 Text 实时段；前组已收束则立即交接 |
| 正文流式变化 | 原正文 owner 范围更新，不写展示表、不插入历史 token |
| 正文可靠结束 | 内容完整；同来源前段均已交接后整段进入历史 |
| 正文后再次工作 | 创建新 Work，不重新打开旧组 |
| 同来源独立业务回执、真实来源结束、停止/失败终态 | 形成有据边界；仍运行成员保持真实状态，终态齐备才交接 |
| 前台转后台 | 前台成员以真实 Transferred 收束；不代表后台成功 |
| 后台最终结果 | 每个真实终态独立冻结一段，不封前台、不回填历史尾组 |
| 页面关闭/观察取消 | 释放读取，不取消执行、不构造边界 |
| 权限/问答待决 | State/dock 保持可操作；遮蔽实时区不销毁展示状态 |

可交接条件只有：存在真实 boundary、unfinished_count=0、同来源更早段均已交接。工作时长只累积真实工作时间，不累加全员完成后等待后继的空闲；缺失时间保持 None。

逆序例：`R开始 → A开始 → T开始 → T完成 → A完成 → R完成`，原子 seq 仍为 T/A/R。实时区保留 G(R,A) 与 T；R 真实结束后一次追加 G，再追加 T。独立输入及后台来源不受该前台阻塞。

### 空正文与附件

真实空正文开始仍分隔前后工作组。可靠结束且 producer 证明正文与附件均为空后，标记 SkipDisplay；到达同来源队首时直接弹出，不分配 history_pos、不推进 P、不发空卡。冻结增量显式 RemoveEmpty，只删除该未分配位置且确无可见内容的派生块/成员，先成员后块；原件、内容、可靠边界和执行事实全部保留，删除与原 effect 同事务、同重放凭据。live 结构 revision 仍更新，即使 P 不变也交付 live 变化。

仅附件消息有效。图片读取仍属原工具成员；媒体失败不拆组、不制造顶层工具失败、不改变业务终态。Hidden 分类不能通过文本外观猜测边界。

## 26.3 增量状态与保存交接

原 live owner 持有唯一 PresentationState：来源队列、按创建顺序的开放块、成员位置、待保存冻结头及 P/Dp。加入或结束成员只触及该成员及组小头，平均 O(1)/O(log n)；边界只关闭对应来源，ready 前缀每段处理一次。

- H/D：原子完成发布上界及已保存连续前缀，原 Session pending 完整覆盖 `(D,H]`。
- P/Dp：冻结展示发布上界及已确认持久前缀；待保存索引引用原 PreparedEffect 中同一冻结材料，覆盖 `(Dp,P]`，不是另一可靠队列。
- PreparedDisplayDelta 绑定 effect_seq，只保存本次变化的块/成员冻结行及必要 RemoveEmpty；writer 不读取最新内存状态，也不查询原历史计算摘要。

原 writer 在一个事务保存 effect、checkpoint/context、原件、内容、展示增量及水位，任一失败整批回滚。精确重放复用同冻结材料和原提交凭据；不允许 OR REPLACE、无条件旧头覆盖、OR IGNORE 吞冲突或异步修复队列。同一 writer 批次可合并同一小头中间写值，但保留所有成员和原业务增量。

成功确认只对应实际批次，释放相应 pending；保存确认不等 GUI ACK，也不制造新的展示事件。组交接且保存确认后释放成员索引，短查询共享引用自然结束。开放大组的轻量索引允许随成员数增长，计入原预算，不能保活已落盘完整输出或用任意丢弃阈值掩盖占用。

## 26.4 展示快照、冷打开与恢复

存储表和迁移归 [17](./17-studio-storage.md)。块小头保存种类、来源、boundary、计数、真实时间、有界概要和内容/成员引用，不保存全成员 ID 数组、全部 ChatAtom、正文、完整 payload 或 ThreadSnapshot。成员索引保存轻量身份、顺序、开始/终态证据与 completion_id/ContentRef。

历史 Main 只按冻结 history_pos 查询块头，不 JOIN 成员、不 COUNT、不读正文。短锁捕获 P/Dp 与必要 pending 共享引用；内存足页不查库，不足则在捕获后新建 SQLite 短读快照，只补 captured_Dp 前缀。continuation 绑定库、资格、初始 ceiling 与排他位置；坏 ref/换库/旧资格明确 stale/invalid，错误不推进 cursor。

热 current 头和摘要直接读内存；成员轻量头按序页读。历史/冷成员从展示索引读取，不用原完成 seq 范围猜组。明确请求的成员正文、payload 与媒体才按 completion_id/ContentRef 走原 RAM 优先、SQLite 补齐及范围预算。

冷打开直接读取展示头和需要的成员页，不扫描原子历史、不加载完整 checkpoint/context、不激活模型工具。history_pos=NULL 的块显示“上次执行未收束/尚未恢复”，execution_present=false，不伪装思考、不计运行时间，已完成成员仍可展开。真正恢复时先恢复开放头和必要未结束成员，由原 Core 决定中断/恢复事实，再推进展示；不制造空 ChatItem、不重跑历史副作用。

## 26.5 展示协议与同切面交付

公共展示协议首版 presentation_version=1，严格匹配，错误版本明确拒绝。DisplayBlockRef 绑定 database_id/block_id；DisplayBlock 携稳定 id、history_pos 和 body；LiveDisplayBlock 携 id、block_order、body、closing。body 为 Work（WorkSummary/members 引用）或 Single（轻量 atom/可空 completion_id）。WorkSummary 增量保存 total/terminal/running/waiting/failed/cancelled/transferred、可证明时间及有界思考概要/引用。

LiveDisplayWindow 携 revision、history_through=P、execution_present、有界 blocks 与可空 older。超过帧预算从最新块头向前选一页，显式提供“更早实时片段”；older 绑定原 read 资格及块结构代次，token 不换代，结构变化后 stale 只刷新 live 窗口，不重建历史。

TimelineBatch 携 presentation_version、Set/Prepend/Append、blocks、before、from_pos、through_pos 及可空 live。GUI Timeline feed 仅交付 State/Timeline/Failure/Closed，不同时交 Chat/Activity 让 Flutter 合并。原 completedHistoryVersion=1、Thread State schema17 及原完成 feed 语义保留给完成级消费者。

1. 先登记观察再捕获 `(P0,live0)`；首 Set 建立同切面历史页与 live。
2. 后续固定目标 `(Pt,live_t)`，按预算追赶冻结头，不追逐无限变化目标。
3. 每帧一次追加本帧历史 blocks，并按相同 block_id 退役对应实时块；未交付块保留。
4. 未追至 Pt 的 live=None 表示保持剩余 live；只有追至 Pt 才替换完整 live_t。
5. P 不变但 live 变化时发送空 blocks、from_pos=through_pos=P、live=Some 的 Append，不枚举/操作历史 controller。
6. Prepend 不带 live、不推进订阅位置；独立查询不需要流 ACK。

SDK 与 Flutter 将历史插入和 live 退役作为一次可观察接纳提交：两者完成后才发一次视图更新并 ACK，不能先清空再异步查历史，也不能一帧双显同 ID。Dart 接纳不等待 Flutter 绘制。

watch 只保存最新切面并唤醒；漏中间通知不漏冻结头，后者在原 pending/SQLite。慢 GUI 只阻塞自身有限在途帧，不反压执行保存。query 短锁准入后锁外 IO，不等 events/credit；request_close 同步撤销准入并唤醒，close 汇合在途资源。旧成功、错误、finally 和 ACK 都复核原 lease，保护 A→B→A。

## 26.6 业务引用由 State 交付

ThreadBusinessRefs 只含 `plan: Option<CurrentPlanHead>` 与 `interactions: Option<CurrentCollectionRef>`，必填于 ThreadSnapshot；BusinessRefsChanged 整体替换两个引用，沿原 epoch/revision/信用接纳，不建第二订阅或业务 ACK。原 State.interactions/runtime.plan 保持可操作业务事实；引用仅供详情读取，不反向重建业务。

引用由原 Plan/交互 owner 在同一切面先建立可读内容后发布，只有真实领域变化才换代；token、查询、保存 ACK 和 GUI 组交接不推动它。冷读以同一短事务取得领域字段、Plan 引用和交互集合，不把无执行 owner 当成无业务引用。

plan=None 为真无计划；Some/document=None 为有计划无文档。interactions=None 为未建立资源，已初始化空集合可有有效引用，不能吞失败为空。交互集合的 interaction_collection_revision 随原 Core checkpoint 保存，描述 permissions/interactions 联合集合，不用剩余单项最大 revision 或无关 effect 序号代替。transfer 与 resident 剪裁实际改变集合时分别 checked 推进，重复剪裁不推进；旧 schema6 缺字段只初始化 0，不猜过去代次或重写原件。

原 reader 的 read_business_refs 与 State 基线共用领域投影。一次性工具可查询，GUI 持续跟踪只消费 State，不在命令/Timeline 后补偿刷新。不恢复 ChatBatch.current，不把组和正文放进 State。

## 26.7 内容、成员窗口与资源

listContents/readContent/readAttachment/watchContent/pageCurrent 沿原 reader、权限、范围和短读租约。大正文按 offset 读取，不先拼全文再截取。ContentRef 绑定库/资格和原 ItemPayload/Body；ContentBlock 从 active 到 seal 移交不改名复制全文，追加不换 generation、替换才换。普通内容窗口保留 offset、bytes、generation、availableThrough、sealed。

DisplayMemberWindow 为 Latest 或 Before{member_order}。DisplayMemberPage 携块引用、revision、sealed、有界轻量 entries 与 before。句柄首次 next 返回当前页，后续在该块成员结构/状态或封存资格改变时返回完整最新页；单个在途 next，接纳后再取。交付身份为 `(revision, sealed)`：仅封存不改变成员 revision，未封存页可接同 revision 的封存页，不能误判为重复；普通重复、版本倒退及封存后新数据仍是错误。token 不触发成员列表重读；切换窗口替换观察，不拼不同 revision 的可变页。sealed 历史页固定，不保持无用 watch。

DisplayMemberHead 含稳定 member_key/order、轻量 ChatAtom、可空 completion_id。真实中断无完成正文可为 None，不伪造成功。组总数来自头，不用窗口长度覆盖。实时到历史 ref/member_key 不变，原展开需求继续借用同一 reader；展开意图由 display lease 按 block_id 保存，不依赖跨父 Widget 移动自动保留 State。

完成卡的 Deferred payload 是原件定位，不是把业务卡降级为原始 JSON 的展示类型。实际挂载且仍有资格的 Single 卡或展开成员，沿原 `read_completed` 以 completion 身份、有界预算读取 canonical envelope，核对原件、atom、来源及完成身份后，复用原业务解码和 renderer；保留外层 block/member key、展开意图与 Main controller，不把解码结果回写展示头或另建消息列表。折叠 Work 不枚举或预读成员原件；正文、输出和媒体仍由原引用按各自窗口读取。metadata 单次读取采用现有 64 KiB 预算；若返回仍为 Deferred、身份矛盾或解码失败，明确呈现该限制或错误，不自动扩大预算、累计任意全文或把截断信封当作业务卡。离页、收起及资格换代撤销局部读取，迟到结果不得恢复已退役视图。底层原文范围查看器不承担业务 envelope 解码。

交互 Deferred 请求是结构化信封：沿原独立资格按窗口累计最多 1 MiB 后解码，超预算明确失败，不截断或显示原始 JSON。跨窗验证 ref/generation/总长/sealed，按字节累计后 UTF-8 解码。展示/复制仅用 canonical 解码及敏感过滤结果，无原始信封复制/下载旁路。旧 Plan 引用读原版本或 stale，不静默换最新文档。

引用换代只退役受影响详情；折叠、换窗或离开撤销本视图资格并汇合读取，不关闭其他观察或执行。搜索区分借入 cursor 与新建未交付资格，失败回收后者，完整结果成功后才退休旧资格，不驱逐其他 scope 或突破原上限。清理失败保留待 join 义务，不掩盖业务错误。

原 Main/Run/Children 完成查询、read_completed 与内容工具继续服务原子用途，Run 列不删除、不反写；GUI 不再用它们分组，也不提供失败后回落旧 Run 的旁路。原件读取的预算、parent 资格和精确完成身份仍有效。

## 26.8 Flutter 状态栏与唯一组件集合

Main 每个 DisplayBlock 对应一个 Message.custom，metadata 唯一持已加载块。Set 一次 setMessages，Prepend 批量前插完整旧块，Append 批量追加冻结块；没有历史尾组 merge/update 或“隐藏最后组”。纯 live/token 帧不枚举 Main。布局补载沿块页继续，无总页数上限，ACK 不等布局或用户展开。

实时栏采用类型化的纯呈现状态，由原 ViewModel 一次投影，Widget 穷尽匹配。区域隐藏/内容/问答占用与内部有序片段分层：可以并存 closing Work 和后继正文，不能压成只能显示一种内容的单一阶段枚举。状态提示来自真实 State，准备、思考/等待、压缩、停止、保存阻塞及冷读未恢复不替代块生命周期。

问答占用只遮蔽实时区域，不清数据或补终态。保存阻塞、停止、审批提示可与内容共存；无执行 owner 不画运行计时。展开、滚动与跟随输出属于局部 UI 状态；成员读取和媒体资格由原 display lease 持有。复用同一种 Work/Single 外观及成员 renderer，不维护 rawAtoms/groups/messages 三份完整内容，不新增状态机依赖或第二消息 store。

## 26.9 热路径成本与验收

纯 token 更新只触及原正文范围与必要有界预览：原历史 SQL=0、display 写入=0、Main controller 操作=0，不访问已完成成员集合。成员真实终态只更新该成员和所属组小头；边界从内存冻结头，不查历史/成员正文。Plan/交互以真实 revision 缓存共享材料，token 不遍历或重序列化。

折叠 10 万成员组只读有界头；主列表不 JOIN/COUNT、不读正文媒体。测量单事件节点、候选/选中行、编码字节、正文驻留、controller 操作和真实 UI 时间，区分 SQL 条数与扫描成本。首内容沿现有参考平台 p95≤500ms 目标回归，实际报告平台、范围与未覆盖项。

验收映射 #316 A01–A32，覆盖等待边界、正文开始 H 不变、逆序终态、空正文、后台/输入独立推进、同事务重放与回滚、冷读/真实恢复、慢消费、max_items=1、资源关闭和迁移保全。生产 Rust→FRB→SDK→View 证明与概念稿、参考模型分开；截图来自本次运行，不能代替帧级接纳断言和 SQL/内存证据。

## 26.10 迁移与保全

schema18→19 在原 migration runner 和同一事务建立展示表/索引及水位。旧完成数据按 seq 键集每批 128 个轻量头读取，复用已确定 run_start/ordinal 和 typed 类别，一次生成冻结 legacy 块及成员引用，history_pos 按旧可见段顺序分配，Hidden 无块。迁移可一次累积旧组摘要，但不读取正文/图片、不改原 ID/seq/payload/metadata/content，不猜 v18 从未保存的开放状态。

旧迁移和已 Applied 语义不改，受管归档全部保留。原待恢复工具/交互继续 Core 责任，后来真实结果形成新段，不回填旧冻结组。校验引用、唯一性和水位后写 Applied；失败整体回滚。正常重开只读快照，Applied 后缺表/头或矛盾明确失败，不删建、不全历史 fold、不回落旧分组。
