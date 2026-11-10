# 26 - 原子完成事实与增量展示快照

本文维护 Native 完成内容及 GUI 展示契约，依据 [#316](https://github.com/ZR233/anywork/issues/316) 及其补充修订 #311 的展示时机，保留其不可变完成原件、唯一保存链与 State 业务引用。这里定义目标，不以文档更新冒充实现或性能验收。ACP 的外部协议保证不变。可靠执行保存归 [15](./15-session-storage.md)，存储迁移归 [17](./17-studio-storage.md)，传输归 [07](./07-streaming.md)，客户端资源归 [25](./25-frontend-state.md)，视觉归 [19](./19-studio-ui.md)。

## 26.1 两个完成点与唯一所有者

**开始与结束事实分别保存；工作组在可靠正文开始等真实边界立即冻结，不等待成员全部结束。** 内容完成与展示冻结有独立序号，不能把完成记录数当成历史卡片数。同一未封存组内的开始和结束可合并为一行；封存后的成员、状态、内容、摘要和计时保持边界切面，迟来的结束在当前新组形成新记录。

显式用户文件展示沿原工具完成记录封存，不增加独立历史 writer。`builtin.show_files@1` 的 renderer 消费 [09](./09-tool-runtime.md) 定义的 `pl.tool.files@1`，保留成功／失败顺序，成功附件从同一回执的可靠资源引用派生。归档资源的读取资格同时覆盖驻留、pending 和持久回执，冷重开不重新执行工具或读取源文件。旧图片展示格式保留必要只读解码。

新文件展示工具的原子由原 Native owner 标记为 `Independent`，沿既有分类规则产生 `Single`，使文件格直接出现在主时间线，而不隐藏在默认折叠的工作记录中。保留原 Turn 来源、调用身份与完成顺序，不由 Flutter 解析 payload 后重新分类；普通工具及旧图片历史的分类不变。

图片复用原图片 owner；Markdown 和保存按需读取原资源，二进制不进入 ViewState。来源定位元数据不能授予额外读取权限。外部交付状态归发送领域，不回写不可变完成记录；历史打开、GUI 重绘和重新订阅不得发送外部消息。渠道交付使用 [27](./27-bots.md) 的明确来源绑定，不以时间线可见性或附件存在推导外发资格。

Markdown 语法与流式未闭合内容由上游渲染组件解析，采用其 CommonMark 与扩展语法，不在客户端维护第二套修复解析器。解析规则升级只改变展示，不改写已保存原文；普通纯文本继续保真选择与复制。不安全链接不得取得交互手势，来源标签与图片沿原受控访问入口处理；上游支持 HTML 或新增语法不授予额外外发、资源读取或执行权限。

**完成一次，记录一次；历史内容不更新；工作组只是界面组合。** 已接纳输入、完整模型文本/思考 part、工具真实终态、后台启动交接回执、后台最终结果以及完整业务回执，分别形成不可变完成记录。后台启动和最终结果是不同身份，启动不等于成功。停止请求、页面关闭、推测 EOF、token 暂停和模型自述不构成终态。协议没有可靠独立 part 终态时使用最终 attempt 回执；正常失败/取消收束可以冻结已接纳前缀并标记真实结果，异常退出前未完成的前缀不承诺恢复。

| 所有者 | 职责 |
| --- | --- |
| 原 Core Thread / 业务 producer | 真实执行准入、成员开始/终态、来源事实、可靠 effect、检查点与上下文 |
| 原 Native live owner | 完成封存、读取分类、增量展示段与成员关系、同切面发布 |
| Core Session | 原件 seq/run 分配、精确幂等、完整 pending、统一原件读取；不解析展示 metadata |
| 原 HistoryChannel / 唯一 writer | 原件、内容、检查点与冻结展示增量同事务保存，原背压及提交确认 |
| Feed / FRB / HTTP / SDK | 有界读取、固定目标补读、机械串行接纳、信用与资格 |
| Flutter 原 controller / display lease | 一冻结块一卡、局部展开与滚动、历史插入和实时退役的同次公开 |

原 `ChatDraft → ChatItem` 和 `conversation_items` 是唯一完成原件；`conversation_atom_facts` 分别保存轻量 start/terminal 事实，不以展示合并覆盖原件。边界时原 owner 从同一 effect 捕获未结束成员的公开状态、参数和内容前缀，沿原 immutable chunks/content store 保存派生显示快照。它证明当时显示了什么，不是第三条业务事件或执行状态来源；展示头只持小头、身份、引用及计数。无新 actor、线程、全局注册表、writer、可靠展示队列或保存定时器。真实 Plan、交互和配置仍由原领域 State 管理。

会话资源沿原 Session → AgentRuntime → NativeResources 持有，执行与检查点继续归 Core owner；展示投影属于原 Native observation，不建立另一份成员登记。关闭先同步撤销发布和新读资格，再由原会话关闭任务汇合订阅、观察及在途读取。冷读只借已保存快照，不物化 Native、不重算分组、不推进计时。

State 与内容是独立资源：Repository 是 Dart State 唯一写入口，State feed 独立确认、恢复和关闭；Timeline、完成内容及成员读取不转发第二份 State，也不因暂停内容信用阻塞状态终态或统计。GUI 的展示流替代旧完成内容流承担卡片交付，不替代 State feed；非 GUI 完成级消费者继续使用原内容接口。本次整组交接规则替代旧版“活动临时组合、不延续历史身份”的约定，而不是撤销状态/内容分域或会话资源所有权。

当前正文／思考活动的资格由原 owner 已可靠准入且仍 Active 的同 Turn、同 attempt 原子决定；有界 progress 只为这些原子提供当前摘要，不单独创造活动资格。缺少 progress 窗口不撤销真实 Active 原子，已结束原子的残留 progress 也不能恢复旧正文或思考。State 独立交付不等于绕过可靠开始准入，测试中的合成 State 必须建立与其声称活动相符的可靠事实。工具的 `background` 是相对当前前台阶段的补充计数，不是持久的“曾转后台”标签：仅余工具且工具本身成为活动主体时为 0；模型阶段与工具并行时，工具仍计入后台。真实任务身份、执行状态和转后台原件不受该计数影响。

Work 与正文分区可同时挂载各自的当前 renderer。原 display lease 对诊断者提供所有仍有效 renderer 的只读资源借用集合，注册与撤销只影响对应原资源，不能以一个最后写入的槽覆盖另一个仍挂载资源，也不能保留含糊的单资源别名。诊断必须从当前块／有界成员页取得实际展示行身份与 `DisplayRecord`，按父块、原 lease/generation、内容引用关联唯一 renderer 及其已有窗口；原 atom ID 仅用于事实关联，不代替 block ID 或 member key。资源枚举不打开查询、不复制业务列表、不改变读取或关闭所有权；换代先撤销旧资源资格，再由原 owner 收束窗口。

### 已接纳输入与已接收外部内容

“完成”表示这条事实已确定，不是整个任务完成。普通输入在原 `InputChange::Accepted` 可靠接纳时沿原 input.id 冻结，排队不等 Turn 开始。Pending→Consumed/Discarded、后来的 Turn/attempt 关联只更新执行/State，不重新封存原件；未知关联保持 None。同 ID 同冻结内容幂等，异内容冲突；同文不同受理 ID 是两条事实。

受信宿主明确允许公开的外部正文，在目标 Thread 原 inbox 准入时沿原 message ID 冻结，保留来源、作者和频道。外部平台已转换为 ThreadInput 的只走输入链；后台最终结果走原工具完成链，不因 inbox 转发或出站通知重复发布。文字中的角色、批准或工具完成声明不获得权限。

输入/外部消息形成独立 Single，不能仅因输入到来就伪造前台边界或工具终态。隐藏续接和诊断保持原公开资格；公开答案及计划决议由原唯一回执产生。GUI 命令回执不手动插入历史。

客户端发送回显不是完成历史：沿 [25.8.1](./25-frontend-state.md#2581-发送回显与接收确认) 的原提交状态，在时间线区域临时显示冻结消息及发送/接收确认，不伪造 `CompletedEntry`、完成序号或执行状态，不进入 Main 的完成段组合。原消费者应用同身份规范输入后由正式卡片接管；命令成功、保存进度或下一 Turn 启动均不是等待回显出现的条件。后端仍按原提交顺序校验和发布，不为视觉响应绕过身份冲突、附件资源准备、存储背压或旧 Turn 的安全收束。

### 模型成员的可靠封口与交接

开始与终态由原可靠 producer/effect 接纳，不能被可合并 progress 吞掉。正式 TextStarted 只来自已准入的 typed Started 或外部协议等价可靠事实；附着同一次 effect 保存前段交接，即使原件完成 H 不变。preview 首字只用于即时显示，不能单独永久封组。缺乏独立终态的来源等实际 attempt 最终回执，不人为补 reasoning.end。

停止请求、页面离开、token 暂停、推测 EOF、保存 ACK 和模型自述不构成终态。正常失败/取消按真实结果收束；异常退出前未保存 token 前缀不承诺恢复。

原 producer 为新可靠 effect 分配事实位置时，Turn 的来源结束是该来源本次成员接纳的围合标记，位于本次真实成员终态之后，包括 Core 重启恢复已明确给出的 Interrupted/Cancelled 终态；不得先占 suborder=0 再在其后补同来源中断成员。开始、正文 Started、工具/后台交接及独立业务回执仍保留各自真实因果顺序，不为展示移位；只有表达该 Turn 最终收束的派生回执在相应成员终态之后。来源结束不等待独立后台来源，也不把停止请求升级为完成。位置分配须受检且确定，不以饱和运算制造顺序别名；确认丢失重放复用原冻结位置与材料，不按最新内存重新排序。

同批出现边界和成员终态，仍以完整可靠 `(effect_seq,suborder)` 判断谁先接纳：只有终态不晚于该边界时，才可免去该行未结束观察的捕获；同批较晚终态不能使边界前观察消失。所需不可变材料由原 owner 在退役前保留到 PreparedEffect，禁止从稍后原件或最新动态引用补读。新捕获失败仍使原 effect 失败，不能借“不可用”吞掉内部缺失。

## 26.2 展示身份、来源与真实边界

原件 `item_id` 是稳定业务身份，`seq` 是完成发布顺序，范围为 `1..=i64::MAX`，由原 Session 在 RAM 分配，不是时间戳或开始顺序。原件历史始终按完成 seq，不反向改写。

展示 lane 直接使用 typed `ChatSourceId`。关联身份由来源、真实 atom/call/part ID 与责任阶段组成；展示行身份 `member_key` 属于具体 block 的一次记录，不能直接复用全表唯一的关联 key。前台责任和后台最终结果分属不同阶段，同 call 的交接和最终结果不能命中同一槽。新块/行 ID 使用库身份、来源、段首可靠事实位置和组内首事实的无歧义编码；旧库保留已发布 ID，旧 `legacy-run` 域不改名。不得用墙钟、正文 hash、成员数或查询次数生成身份。

每个来源维护当前未封存 Work、仅指向该组的关联索引及有序待发布段队列。结束只查询当前组同关联身份的开始行：存在则补充该行结束引用，不存在则按本次结束事实创建新行；合法 terminal-only 来源不补造开始。封存立即撤销旧组可更新资格，后续 progress/terminal 不回查历史、不命中旧成员位置。事实幂等和矛盾检查仍在原接纳/PreparedEffect 层，不因新组无开始而重复显示结束。同来源只推进 ready 队首，不重排已发布块。

| 事实 | 展示处理 |
| --- | --- |
| 首个思考/工具/文件/技能开始 | 创建 Work；后续同来源成员加入无边界的开放 Work |
| 成员真实完成 | 原件立即发布保存；当前组有同关联开始则合并，否则新增结束行，保留成功/失败/取消/Transferred 区别 |
| 全员完成但无边界 | 组保持开放；不按 running=0、超时、下一帧或保存 ACK 封组 |
| 正式正文开始 | 立即冻结前 Work 的状态、内容和计时并建立 Text 实时段，不等未结束成员 |
| 正文流式变化 | 原正文 owner 范围更新，不写展示表、不插入历史 token |
| 正文可靠结束 | 内容完整；同来源前段均已交接后整段进入历史 |
| 正文活动期间或之后再次工作 | 创建当前新 Work，及时显示在 Timeline 工作区，不重新打开旧组，不为布局另造边界 |
| 同来源独立业务回执、真实来源结束、停止/失败终态 | 形成有据边界并冻结当时切面；未结束观察不补造终态 |
| 前台转后台 | 前台成员以真实 Transferred 收束；不代表后台成功 |
| 后台最终结果 | 每个真实终态独立冻结一段，不封前台、不回填历史尾组 |
| 页面关闭/观察取消 | 释放读取，不取消执行、不构造边界 |
| 权限/问答待决 | State/dock 保持可操作；遮蔽实时区不销毁展示状态 |

冻结条件是可靠真实 boundary；发布 history_pos 还须同来源更早段已交接，二者均不要求 unfinished_count=0。被更早未结束正文挡住的已冻结组仍是不可变快照，以类型化待发布段呈现，不能恢复更新资格或冒领历史位置。组经过时间从本组第一条新信息的可靠创建/接纳时间起算，在边界立即冻结；晚结束新行不借用旧开始时间作为新组起点。原执行总耗时保持业务含义，缺失时间保持 None。

逆序例：`R开始 → A开始 → T正文开始 → T完成 → A完成 → R完成`，原子 seq 仍为 T/A/R；T 开始就冻结 G(R,A)，其中 R/A 为“封存时尚未结束”。T 完成按原来源顺序进入历史，A/R 的迟到结束在新组各形成结束行，永不回填 G。独立输入及后台来源不受该前台阻塞。

### 空正文与附件

真实空正文开始仍分隔前后工作组。可靠结束且 producer 证明正文与附件均为空后，标记 SkipDisplay；到达同来源队首时直接弹出，不分配 history_pos、不推进 P、不发空卡。冻结增量显式 RemoveEmpty，只删除该未分配位置且确无可见内容的派生块/成员，先成员后块；原件、内容、可靠边界和执行事实全部保留，删除与原 effect 同事务、同重放凭据。live 结构 revision 仍更新，即使 P 不变也交付 live 变化。

仅附件消息有效。图片读取仍属原工具成员；媒体失败不拆组、不制造顶层工具失败、不改变业务终态。Hidden 分类不能通过文本外观猜测边界。

## 26.3 增量状态与保存交接

原 live owner 持有唯一 PresentationState：来源队列、按创建顺序的开放块、当前组关联索引、待保存冻结材料及 P/Dp。加入或结束成员只触及当前行及组小头，平均 O(1)/O(log n)；边界捕获该来源未结束观察，复用不可变 chunk，不遍历已完成原件正文。ready 前缀每段处理一次。

- H/D：原子完成发布上界及已保存连续前缀，原 Session pending 完整覆盖 `(D,H]`。
- P/Dp：冻结展示发布上界及已确认持久前缀；待保存索引引用原 PreparedEffect 中同一冻结材料，覆盖 `(Dp,P]`，不是另一可靠队列。
- PreparedDisplayDelta 绑定 effect_seq，只保存本次变化的块/成员冻结行及必要 RemoveEmpty；writer 不读取最新内存状态，也不查询原历史计算摘要。

原 writer 在一个事务保存 effect、checkpoint/context、原件、内容、展示增量及水位，任一失败整批回滚。精确重放复用同冻结材料和原提交凭据；不允许 OR REPLACE、无条件旧头覆盖、OR IGNORE 吞冲突或异步修复队列。同一 writer 批次可合并同一小头中间写值，但保留所有成员和原业务增量。

成功确认只对应实际批次，释放相应 pending；保存确认不等 GUI ACK，也不制造新的展示事件。组交接且保存确认后释放成员索引，短查询共享引用自然结束。开放大组的轻量索引允许随成员数增长，计入原预算，不能保活已落盘完整输出或用任意丢弃阈值掩盖占用。

## 26.4 展示快照、冷打开与恢复

冻结观察的公开 payload 复用原聊天内容编码器的 `anywork.chat/1` 信封、类型描述和
`bodies` 清单。内部 `ThreadItemState` JSON 不能直接作为公开 payload；正文 chunk
已经保存也不表示缺失正文清单的 payload 可读。观察入口按边界切面的真实活动状态编码，
包括 Streaming 和工具仍在运行、等待的状态；完成原件入口仍严格拒绝未终态成员。
两入口共享类型与正文编码规则，不伪造 completion、终态或结束时间来套用完成入口，
也不在投影或客户端建立第二套 codec。

原 owner 先保留同切面的公开状态和不可变内容材料，展示块及成员身份确定后，再在原
PreparedEffect 内生成观察 payload。参数、摘要和正文清单中的内容引用均属于该
DisplayObservation 自有命名空间，不借用当前 atom 或未来完成原件；捕获时刻和可靠
位置仍表示观察切面，不充当业务完成事实。公开信封和正文引用必须由真实 producer
路径及原 reader 的内容窗口验证，不能仅用带人工正文的 descriptor 证明可读。

存储表和迁移归 [17](./17-studio-storage.md)。块小头保存种类、来源、boundary、计数、真实时间、有界概要和内容/成员引用，不保存全成员 ID 数组、全部 ChatAtom、正文、完整 payload 或 ThreadSnapshot。成员保存展示行身份、关联身份、顺序、可空开始/结束事实引用及类型化内容来源。完成原件使用真实 completion_id；未结束观察使用独立命名的 sealed 显示快照，不分配 completion ID 或 finished_at。冻结引用不得指向会变化的当前 atom，也不能仅存 generation/长度后再读最新前缀。

历史 Main 只按冻结 history_pos 查询块头，不 JOIN 成员、不 COUNT、不读正文。短锁捕获 P/Dp 与必要 pending 共享引用；内存足页不查库，不足则在捕获后新建 SQLite 短读快照，只补 captured_Dp 前缀。continuation 绑定库、资格、初始 ceiling 与排他位置；坏 ref/换库/旧资格明确 stale/invalid，错误不推进 cursor。

热 current 头和摘要直接读内存；成员轻量头按序页读。历史/冷成员从展示索引读取，不用原完成 seq 范围猜组。明确请求的成员正文、payload 与媒体才按 completion_id/ContentRef 走原 RAM 优先、SQLite 补齐及范围预算。

冷打开直接读取展示头和需要的成员页，不扫描原子历史、不加载完整 checkpoint/context、不激活模型工具。history_pos=NULL 必须区分开放组与已冻结待发布段，不能据此推断未恢复。冻结未结束行明确为“封存时尚未结束”，不画运行标识、恢复异常或活动计时；真正开放但无 execution owner 的块才显示尚未恢复，execution_present=false。恢复只重建开放关联资格及原执行所需状态，不恢复封存组更新资格，由 Core 决定中断/恢复事实；不制造空 ChatItem、不重跑历史副作用。

## 26.5 展示协议与同切面交付

公共展示协议升级为 presentation_version=2，严格匹配，错误版本明确拒绝。DisplayBlockRef 绑定 database_id/block_id；DisplayBlock 携稳定 id、history_pos 和 body；LiveDisplayBlock 携 id、block_order、body 及类型化可变资格（开放或已冻结待发布），删除 closing 等待全员终态的旧义务。body 为 Work（WorkSummary/members 引用）或 Single（轻量记录）；二者使用相同的事实引用及内容来源语义。WorkSummary 增量保存 total/terminal/running/waiting/failed/cancelled/transferred、可证明时间及有界思考概要/引用；冻结后 running/waiting 是边界时观察数，不表示当前执行数。

LiveDisplayWindow 携 revision、history_through=P、execution_present、有界 blocks 与可空 older。超过帧预算从最新块头向前选一页，显式提供“更早实时片段”；older 绑定原 read 资格及块结构代次，token 不换代，结构变化后 stale 只刷新 live 窗口，不重建历史。

每个 `LiveDisplayBlock` 同切面交付可空、类型化的 `source: ChatSourceId`，直接来自原 `DisplayHeader.source`，不是从块 ID、摘要或成员原件反推。原 reader 对内存头和已保存开放头使用同一字段映射；缺少可靠归属时保持未知。字段仍是有界头元数据，不新增查询、成员读取或第二份归属事实。

TimelineBatch 携 presentation_version、Set/Prepend/Append、blocks、before、from_pos、through_pos 及可空 live。GUI Timeline feed 仅交付 Timeline/Failure/Closed，不转发 State，也不同时交 Chat/Activity 让 Flutter 合并；状态沿独立 State feed。原 completedHistoryVersion=1、Thread State schema17 及原完成 feed 语义保留给完成级消费者。

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

状态与内容使用独立 Frame 身份、投递序号及有界信用，交付和关闭规则见 [07](./07-streaming.md#710-会话推送交付确认与关闭)。状态通道交付 State、Failure、Closed，完成级内容通道交付 Chat、Activity、Failure、Closed，GUI 展示通道交付 Timeline、Failure、Closed；首个 State 声明 completedHistoryVersion=1，不支持时明确 ProtocolVersionMismatch，不双解码。各通道 ACK 在实际接纳完成且原资格有效后推进，不等布局、query、详情或 SQLite，也不等待另一通道消费。低层已读位置不冒充外层 ACK；内容连续性丢失关闭原内容资格，新内容句柄以 Set 重同步，状态失连续只重建状态基线。

plan=None 为真无计划；Some/document=None 为有计划无文档。interactions=None 为未建立资源，已初始化空集合可有有效引用，不能吞失败为空。交互集合的 interaction_collection_revision 随原 Core checkpoint 保存，描述 permissions/interactions 联合集合，不用剩余单项最大 revision 或无关 effect 序号代替。transfer 与 resident 剪裁实际改变集合时分别 checked 推进，重复剪裁不推进；旧 schema6 缺字段只初始化 0，不猜过去代次或重写原件。

原 reader 的 read_business_refs 与 State 基线共用领域投影。一次性工具可查询，GUI 持续跟踪只消费 State，不在命令/Timeline 后补偿刷新。不恢复 ChatBatch.current，不把组和正文放进 State。

## 26.7 内容、成员窗口与资源

listContents/readContent/readAttachment/watchContent/pageCurrent 沿原 reader、权限、范围和短读租约。大正文按 offset 读取，不先拼全文再截取。ContentRef 绑定库/资格和 ItemPayload/Body；原执行内容向完成原件的 ContentBlock 移交不复制全文，追加不换 generation、替换才换。边界派生观察使用独立命名空间并共享 immutable chunks，不覆盖 canonical atom 内容；CurrentAtom→FrozenObservation 可更换内容引用，稳定不变的是所属块/行身份。普通内容窗口保留 offset、bytes、generation、availableThrough、sealed。

DisplayMemberWindow 为 Latest 或 Before{member_order}。DisplayMemberPage 携块引用、revision、sealed、有界轻量 entries 与 before。句柄首次 next 返回当前页，后续在该块成员结构/状态或封存资格改变时返回完整最新页；单个在途 next，接纳后再取。交付身份为 `(revision, sealed)`：封存若仅改变资格，可接同 revision 的封存页；若捕获改变了记录或内容引用，须推进 revision。普通重复、版本倒退及封存后新数据仍是错误。token 不触发成员列表重读；切换窗口替换观察，不拼不同 revision 的可变页。sealed 表示显示快照不变，不等于全部 terminal；固定页不保持无用 watch。

DisplayMemberHead 含稳定 member_key/order、轻量 ChatAtom、可空开始/结束事实引用和类型化内容来源：CurrentAtom、FrozenObservation、CompletedOriginal。CurrentAtom 只用于开放行；FrozenObservation 绑定本库、本块/行及 sealed 内容命名空间，缺失旧切面明确 Unavailable，不回退最新内容；CompletedOriginal 使用真实 completion_id。同组开始/结束可同一行，跨组必须新 member_key；同一行实时到历史 ref/key 不变。组总数来自头，不用窗口长度覆盖。展开意图由 display lease 按 block_id 保存，不依赖跨父 Widget 移动自动保留 State。

共享形状统一为 `DisplayRecord { atom, start_fact: Option<ChatFactPosition>, end_fact: Option<ChatFactPosition>, content_source }`，Single 持一份 record，成员头持 member_key/order 及 record，不另复制可空 completion_id。`DisplayContentSource` 为 CurrentAtom、FrozenObservation{captured_at: Option<i64>, available: bool} 或 CompletedOriginal{completion_id: String}；FrozenObservation.available=false 明确旧切面不可用，不能授予动态内容读取资格。公开 payload/Body 引用在捕获时重写到 `ContentOwner::DisplayObservation{block_id,member_key}` 的独立 owner，沿原内容存储和权限读取；真实完成原件和媒体资源继续原身份。Live 的 `DisplayBlockState` 为 Open 或 Sealed，后者只表示已冻结待发布，不是 closing 等待成员结束。事实引用仅表示该展示行实际接纳的事实：跨组 terminal-only 新行的 start_fact 为 None，即使 atom 保留原执行 started 时间也不能声称本组收到过开始。

`available=false` 不仅约束正文：无法证明的旧等待/运行状态、公开参数和摘要也不得呈现为边界事实，显示中性“旧边界观察不可用”；能证明尚未终态时可同时说明“封存时尚未结束”。WorkSummary 增加 `unavailable` 计数，此类未知观察不计入 running/waiting，也不借较新摘要或计时填补。新边界捕获必须完整，不能以 Unavailable 掩盖捕获失败。

`DisplayMembers` 是查询 scope 交出的有界只读观察能力，声明在 Client 公开会话领域接口；transport 使用同一能力类型。Feature 通过公开查询 API 使用它，不为取得类型导入底层传输端口。

完成卡的 Deferred payload 是原件定位，不是把业务卡降级为原始 JSON 的展示类型。实际挂载且仍有资格的 Single 卡或展开成员，沿原 `read_completed` 以 completion 身份、有界预算读取 canonical envelope，核对原件、atom、来源及完成身份后，复用原业务解码和 renderer；保留外层 block/member key、展开意图与 Main controller，不把解码结果回写展示头或另建消息列表。折叠 Work 不枚举或预读成员原件；正文、输出和媒体仍由原引用按各自窗口读取。metadata 单次读取采用现有 64 KiB 预算；若返回仍为 Deferred、身份矛盾或解码失败，明确呈现该限制或错误，不自动扩大预算、累计任意全文或把截断信封当作业务卡。离页、收起及资格换代撤销局部读取，迟到结果不得恢复已退役视图。底层原文范围查看器不承担业务 envelope 解码。

正文是否直接显示不取决于长度或外层信封的 Inline/Deferred：已挂载正文沿原有界窗口复用 Markdown、选择复制、换行与安全链接/媒体规则。已知用户 Input 的公开 Body 声明独立于外层预算，按明确归属于当前输入项的正文引用直接显示，不先要求解码原始信封；未知域及 `accepted.payload` 不推断为正文，缺声明保留诊断边界。工具和思考详情仍按语义折叠。文件卡继续消费显式 `pl.tool.files@1` 与原附件资源身份，保留 ready/failed 区别、跨布局读取资格和敏感内容边界，不复活旧工具实现或从 opaque 外观猜格式。

交互 Deferred 请求是结构化信封：沿原独立资格按窗口累计最多 1 MiB 后解码，超预算明确失败，不截断或显示原始 JSON。跨窗验证 ref/generation/总长/sealed，按字节累计后 UTF-8 解码。展示/复制仅用 canonical 解码及敏感过滤结果，无原始信封复制/下载旁路。旧 Plan 引用读原版本或 stale，不静默换最新文档。

引用换代只退役受影响详情；折叠、换窗或离开撤销本视图资格并汇合读取，不关闭其他观察或执行。搜索区分借入 cursor 与新建未交付资格，失败回收后者，完整结果成功后才退休旧资格，不驱逐其他 scope 或突破原上限。清理失败保留待 join 义务，不掩盖业务错误。

原 Main/Run/Children 完成查询、read_completed 与内容工具继续服务原子用途，Run 列不删除、不反写；GUI 不再用它们分组，也不提供失败后回落旧 Run 的旁路。原件读取的预算、parent 资格和精确完成身份仍有效。

正文窗口已包含完整正文时不显示范围导航，超出窗口明确显示当前范围及下一段操作，不自动累计无限全文。正文不增加键名或字节数折叠栏；原始 ItemPayload/诊断查看器仍按原始内容展示，不将 JSON 信封当 Markdown。缺少公开 Body 声明不阻止已合法解码信封中的附件沿原附件路径呈现，正文读取也不自动公开原始请求。

已声明公开 Body 的 Input 在 canonical metadata 恢复之前即可沿原内容窗口呈现；metadata 读取只补足附件等已公开元数据，不是正文准入条件。恢复等待、64 KiB 预算限制、解码失败或身份错误均不得遮蔽这份独立且合法的正文；metadata 的限制或错误单独明确呈现，不回显原信封。恢复成功后仍只有一份正文组件和原正文读取 owner，沿同一 item/ref/generation 保持读取资格，不重复显示或再读同一窗口；附件按原成功身份核对后才取得读取资格。没有公开声明的 Input 仍沿原 canonical 限制，不能把其他域当正文绕过。读取资格判定在原呈现模型内复用，不在包装器与 Widget 各复制一套放宽规则。

## 26.8 Flutter 状态栏与唯一组件集合

Main 每个 DisplayBlock 对应一个 Message.custom，metadata 唯一持已加载块。Set 一次 setMessages，Prepend 批量前插完整旧块，Append 批量追加冻结块；没有历史尾组 merge/update 或“隐藏最后组”。纯 live/token 帧不枚举 Main。布局补载沿块页继续，无总页数上限，ACK 不等布局或用户展开。

发送临时回显继续归原 Composer 提交 owner：同步冻结 inputId、正文和附件，保留“正在发送 / 已收到，等待同步 / 发送结果待确认”及防重发语义。临时回显不是 canonical 输入或工作成员；原输入接纳后按 inputId 结算，不按正文去重、不因封组重复插入、不扫描历史或新增持久消息仓储。回显与正式正文共用现有 Markdown 展示能力。

工作组统一位于 Timeline 工作记录区域：冻结历史与当前开放工作区明确区分，当前工作区直接映射 Native live Work，不分配虚假 history_pos、不另建消息事实源。正文输出区只呈现真正正文及必要特殊提示，不再包含 Work。原 ViewModel 一次投影类型化呈现状态，Widget 穷尽匹配；问答遮蔽不清数据。冻结待发布段保持原来源顺序和静态语义。

### 折叠呈现与文案

- 实时 Work 初次呈现默认折叠；每个折叠组只有一行：左侧语义图标或真实活动指示，中间为有界思考概况或当前状态短文案，右侧对齐“执行了 2 分 5 秒”等组时长及展开入口。不再为同一组叠加一行普通“思考中”提示和一行“工作记录 · N 项”，也不默认展示成员列表、计数明细或终端输出。摘要单行省略，完整语义仍可通过无障碍说明或提示访问。
- 准备、思考及压缩使用对应轻量状态；压缩不伪造工作组。已有同源当前正文 renderer 时不再叠加普通“正在输出”。上一正文可靠结束后，权威 owner 清除该正文活动资格及旧摘要，不从有界窗口缺正文推断无活动，也不从已有 response parts 推断仍在输出。
- 普通工作提示合并必须证明目标为开放 Work，其前台 Turn、当前 active Turn 和提示 Turn 三者相同，且原 owner 提供的该组完整摘要仍有 running 或 waiting 成员。来源未知、其他来源、旧 Turn、冻结组或全成员终态组不得吸收当前活动；不读折叠成员、不解析 block_id 猜归属，也不由有界成员页缺项推断全部结束。全成员终态的开放组保持真实结果及中性组头；Turn 自身仍在等待或执行的提示留在原独立状态面，不能用它覆盖组内成功、失败、取消或 Transferred 的静态结果。此限制只决定提示归属，不封组、不补终态、不停止组经过计时，也不增加跨 feed 屏障。保留安全有界概要，缺少才用阶段短文案。输出去重与工作提示归属分别处理，保存/停止/审批/错误/冷读提示独立保留。
- 摘要被明确标为 unavailable 时，不具有普通活动提示的吸收资格；提示继续使用原独立状态面，不能把缺证据当成活动或完成。
- 已冻结历史 Work 默认折叠，主标题为“工作了 2 分 5 秒”等同口径完成态文案，不以“工作记录 · N 项”、裸小数秒或原始进度数替代。失败、拒绝、取消、交接等真实结果保留必要的语义图标、短标记或可访问摘要；正常停止保持中性，不伪装错误或成功。
- 点击才展开原成员窗口；按稳定 block_id 保存的用户展开意图跨 live→history 交接保持，不能因“默认折叠”强制收起用户已打开的组。实时展开区沿原有界阅读区滚动；历史展开内容跟随主时间线，不另设固定 186 像素高的小型纵向滚动容器。
- 窄窗和大字号下优先压缩或省略摘要，保留图标、时长与可操作的展开入口，不靠缩小字号、重复标题换行或裁掉操作掩盖溢出。复用现有主题、字体、图标和交互组件，不另造预览专用外观。

### 组计时口径与所有权

用户可见组时长从**工作组第一条信息创建的真实时刻**起算，包含此后组内等待空档，不是累计活动区间、最近一次思考耗时或整轮请求耗时。原 owner 在首次创建 Work 时，以创建该信息的已有可靠 effect 时间事实冻结 `createdAt`（与现有 atom 时间一致，Unix 秒）；后加入成员、折叠、展开、离页重开均不能重置起点。

`WorkSummary.createdAt` 与 `elapsedMs` 是有界头中的可空时间证据。`elapsedMs` 表示原 owner 最近可靠更新时观察到的组经过毫秒数，即可靠时刻与创建时刻的秒差经受检运算乘以 1000；真实边界 effect 立即冻结最终值，不等待成员终态或 history_pos。全员完成但无边界时组仍开放，时间继续增长。冻结未结束成员只展示当时观察时长，不以旧业务 started_at 继续走钟；晚结束新组起点为首条新信息的接纳时刻，原执行总耗时另保业务含义。原 `durationMs` 累计活动区间不冒充组时长。

创建与冻结事实随原 PreparedEffect、唯一 writer 和展示快照同事务保存；确认丢失重放使用同一时间事实，不在查询、重放或 UI 挂载时重新取创建时间。计时显示复用可见组件的显示时钟，不按秒写展示表、推展示 revision、遍历成员或操作 Main。历史仅格式化冻结 `elapsedMs`；冷读无执行 owner 不启动时钟，可显示最后已保存的经过时间及未恢复提示。旧数据没有可靠创建时间时保持未知，不用迁移时间、当前时间或零补造。

零及不足一秒使用“执行了不到 1 秒／工作了不到 1 秒”；已知时长按分钟、秒本地化格式化，未知或时间证据倒序则省略时长。工具成员自身原有“用时”与推理成员“思考了”文案保留各自含义，不通过全局替换误改。

问答占用只遮蔽实时区域，不清数据或补终态。保存阻塞、停止、审批及真实错误提示仍须可见，不得被普通组概要合并或折叠隐藏；无执行 owner 不画运行计时。展开、滚动与跟随输出属于局部 UI 状态；成员读取和媒体资格由原 display lease 持有。Work/Single 复用原成员 renderer，不维护 rawAtoms/groups/messages 三份完整内容，不新增状态机依赖或第二消息 store。

## 26.9 热路径成本与验收

纯 token 更新只触及原正文范围与必要有界预览：原历史 SQL=0、display 写入=0、Main controller 操作=0，不访问已完成成员集合。成员终态只更新当前组合格行或创建新行及小头。边界从原内存切面捕获未结束观察和共享 immutable chunks，不查历史、不重读或拼接全部正文；快照成本计入边界 effect，不转嫁每 token。Plan/交互以真实 revision 缓存共享材料，token 不遍历或重序列化。

折叠 10 万成员组只读有界头；主列表不 JOIN/COUNT、不读正文媒体。测量单事件节点、候选/选中行、编码字节、正文驻留、controller 操作和真实 UI 时间，区分 SQL 条数与扫描成本。首内容沿现有参考平台 p95≤500ms 目标回归，实际报告平台、范围与未覆盖项。

验收映射 #316 A01–A32，覆盖等待边界、正文开始 H 不变、逆序终态、空正文、后台/输入独立推进、同事务重放与回滚、冷读/真实恢复、慢消费、max_items=1、资源关闭和迁移保全。生产 Rust→FRB→SDK→View 证明与概念稿、参考模型分开；截图来自本次运行，不能代替帧级接纳断言和 SQL/内存证据。

## 26.10 迁移与保全

schema18→19 在原 migration runner 和同一事务建立展示表/索引及水位。旧完成数据按 seq 键集每批 128 个轻量头读取，复用已确定 run_start/ordinal 和 typed 类别，一次生成冻结 legacy 块及成员引用，history_pos 按旧可见段顺序分配，Hidden 无块。迁移可一次累积旧组摘要，但不读取正文/图片、不改原 ID/seq/payload/metadata/content，不猜 v18 从未保存的开放状态。

旧迁移和已 Applied 语义不改，受管归档全部保留。原待恢复工具/交互继续 Core 责任，后来真实结果形成新段，不回填旧冻结组。校验引用、唯一性和水位后写 Applied；失败整体回滚。正常重开只读快照，Applied 后缺表/头或矛盾明确失败，不删建、不全历史 fold、不回落旧分组。

history19→20 追加具名迁移，加入组内记录身份、开始/结束引用、封存资格和独立显示内容命名空间。保全旧块/成员 ID、顺序、原件与内容；旧已冻结完成记录仍引用真实原件，旧开放组保持开放，升级不是正文边界。只转换已有材料能证明的切面，缺前缀明确不可用，不用未来完成全文补旧观察。产品库27、calls9不因展示升版。正常路径只消费新结构，不留 v19 运行回退。

这里“旧开放”指没有可靠 boundary 的 Work。v19 已有 boundary、因旧 unfinished 条件尚未发布的 closing Work 转为统一 Sealed 资格，保留 ID 和既有顺序；迁移不创建新边界或直接发布 history_pos。仅在迁移中按旧组成员索引定向读取独立事实，以完整 `(effect_seq,suborder)` 和可靠位置判断边界前终态，缺位置/占位不作证。边界前完成引用原件，尚未完成的行保留可证明开始及时间，不能将初始 Running 当任意边界状态；缺失切面标 unavailable。组经过时间只从可证明创建和边界原事实时间计算，不能反推被后来更新覆盖的 elapsed/duration/摘要。

旧 closing 行若已接纳 boundary 后的终态，保留原开始观察行身份，并为该真实结束派生新记录，按原事实接纳顺序归入边界后的当前组或新结束组；不得丢结束、重复结束或回填旧切面。旧已发布历史保持原样，不追溯拆分；仅对未发布段定向转换，必要时为新增记录调整未发布排序键，保持所有旧段/成员相对顺序和已发布位置不变。新记录身份由真实终态位置和目标组决定，迁移可重放且只在迁移边界解码旧形状。

既有库中的来源结束位置（包括旧 Turn end 的 suborder=0）和成员位置原样保留，不因新 producer 的围合规则重写或假定同批终态在其前。迁移依旧按实际位置识别边界后终态并形成新记录，缺失旧切面明确不可用；不能把规范修正变成旧事实重排或再次执行。
