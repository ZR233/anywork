# 26 - 按需会话加载与有序聊天交付

本文是完成历史、按需读取、聊天批次、current 展示及组件消息所有权的唯一权威契约，依据 [#243](https://github.com/ZR233/anywork/issues/243)，替代 #220 的对外页/基线/完成游标和两端展示分组方案。本文描述批准的目标，不以文档更新冒充实现或性能验收。存储布局与迁移归 [17](./17-studio-storage.md)，可靠保存归 [15](./15-session-storage.md)，传输归 [07](./07-streaming.md)，客户端生命周期归 [25](./25-frontend-state.md)，视觉归 [19](./19-studio-ui.md)。

## 26.1 完成事实与唯一所有者

历史只包含可靠结束后的不可变最小事实：已接纳输入、完整文本/思考 part、一次工具调用自身终态、确定文件变更、技能激活、交互/计划/压缩或终止回执。不按 token、换行、停顿、EOF 或整组是否安静猜测完成；工具 A 完成不等并行 B 或整个 Turn。后台启动回执和后台任务最终结果是不同事实。

Core Thread 先向既有可靠队列准入 effect，再发布执行观察。Studio 单一产品投影按可靠 effect 顺序及批内稳定顺序冻结 draft，调用 Session 整批发布并分配完成 seq；同一冻结记录由 pending、短读和 writer 共享。完成发布立即可查询、可推送，不等待 SQLite；PendingHandoff 只是将准备结果附到已经准入的义务，不是首次入队或 durable 确认。

| 所有者 | 唯一职责 | 不承担 |
| --- | --- | --- |
| Core Thread | 执行事实、可靠准入 | 产品卡片、UI 分页 |
| Studio 产品投影 | 可靠封口、current 小投影和查询成员资格 | UI 窗口/像素/展示 diff |
| Core Session | 完成序号、完整 pending、幂等、scope 索引和一致读取 | 业务 payload/工具 renderer |
| HistoryStore 与原 writer | 初始化/迁移、独立短读、完整批事务和确认 | GUI 接纳或绘制 |
| ConversationFeed/传输 | 切点、Set/Append、有界传输与取消 | 已加载消息镜像 |
| SDK/Flutter 现有 owner | 机械映射、串行 applyBatch、current 发布、游标与资源资格 | 历史合并、业务完成归约 |
| Chat/current 组件 | 消息、布局、滚动及当前态呈现 | 存储一致性 |

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

query_class 由写入/迁移确定，未知 payload 保留原类别，不被 reader 隐藏。parent_id 使用无歧义类型身份，允许引用真实 Turn/Call 而非 item，不能加 item 自关联外键。Main 对应 conversation；Children 对应指定真实父域的 activity。折叠摘要只从可靠产品事实增量形成，不能在打开时扫描/分组全部历史；缺失旧统计、时间或来源保持未知。

## 26.3 完整 pending 与保存交接

pending 不是 UI 缓存，不随意 LRU 淘汰。主索引与 class/parent 有序辅助索引引用同一冻结记录，读取不能先扫描全部 pending 再过滤。预算沿原可靠准入/retention 计算，保存失败保留事实并背压，不能无限增长或丢最旧项。

writer 只提交已准备的连续 effect 前缀；事务成功后按本批实际完成项的连续前缀推进 D，不能读此时 Session.head 或取跨空洞最大值。没有 completion 的 effect 不凭空推进 D；保存 ACK 不产生第二次 Append。已提交项仍被已接纳短读引用而短暂存活是正常所有权，不强制销毁引用。

显示不等保存、writer 不等 Flutter。关闭等待原保存屏障；进程提交前崩溃可能丢失 RAM 尾段，不能承诺不等落盘和崩溃零丢失同时成立。批处理、回执、accounting 及故障恢复见 [15](./15-session-storage.md)。

## 26.4 按需分页与 continuation

一个读取需求包含 `max_items` 与 `max_bytes`：条数必须大于零，由当前展示需求决定；字节至少容纳一个合法轻量 envelope，否则返回 InvalidDemand。服务端校验资源上限，但不恢复固定 32 条或固定正文预览长度的 UI 合同。预算覆盖实际编码开销、身份、header/current 和引用；不能用返回条数或估算驻留量冒充传输字节上限。

latest 捕获固定 H0；before 还要求 seq 小于游标排他边界。一次读取如下：

1. Session 短临界区捕获 D、H、源资格及匹配 scope 的有界 pending 引用；所有候选不超过 H0，数据库上界为 `min(captured_D,H0)`。
2. 按 scope 索引倒序取预算内候选。内存已满足需求或任一预算耗尽，直接返回，数据库 page/existence 查询为零。
3. 仅匹配候选不足且条数/字节仍有余量时，锁外建立捕获之后的新 SQLite 短读快照，只补持久化前缀的同 scope 数据。
4. SQL 先按索引选择头部和 payload 长度，再一次或有界批次读预算内 payload，不逐项完整解码工具。两个天然不重叠区间拼接为 seq 升序消息。

不能跨 await 持 Session 锁、复用捕获前旧快照、查询触发 flush/执行恢复/完整性检查，或跳过较新的大项去库里凑旧小项；超预算 payload 以 Deferred 表达。捕获后 writer 清 pending 时短读仍持 Arc；捕获前清理则后开的 DB 快照已能看到提交。

before 是绑定原库身份、ChatScope、排他边界和读取作用域的不透明字符串，Flutter 原样回传、不解析来源或 seq。不返回 totalCount，不 COUNT，不为 UI 计算全历史空占位。

非空 before 仅表示可继续请求，不保证下一页非空。只有内存和库均已确认耗尽才返回 null；内存恰好够页时不为精确 hasOlder 额外查库。允许一次空末页返回 null，非空页 cursor 必须前进，空页不得原地 continuation；短页和字节截页不自动表示 EOF。

## 26.5 唯一 ChatMessage 与 ChatBatch

Rust 产品契约统一归 pl-protocol，FRB/HTTP 同语义；Core 仅持产品无关完成记录。

| 类型 | 字段/语义 |
| --- | --- |
| ChatMessage | `id`、动态 `payload` |
| PayloadData | `Inline(bytes)` 或 `Deferred(reference,byte_length)` |
| ChatBatch | `placement`、`messages`、`before`、可选 `current` |
| ChatPlacement | Set、Prepend、Append |
| CurrentProjection | source effect、逻辑状态、有界 active turn/活动、Plan/交互头部和内容/集合引用的具体快照 |

seq/query_class/parent_id 不原样放进每条外部消息；H/D/through/source incarnation 留在 Rust，诊断另行记录。Message.custom 是 Flutter 组件自己的类型，不能假定同名 FRB 类自动兼容；不复制 Flyer 的全部消息联合、oldMessage/index 或任意列表 diff。

| 来源 | placement | before | current |
| --- | --- | --- | --- |
| Main 首屏，messages 可空 | Set | 设置该 scope 的 continuation | 必须有具体快照，可明确空 active |
| Children 首屏 | Set | 设置该 scope 的 continuation | None |
| 旧页，末页可空 | Prepend | 替换 continuation，None 为已知 EOF | None |
| 新完整项 | Append | 必须 None，不修改原游标 | Main 可有；Children 必须 None |
| 纯 current 更新，messages 为空 | Append | 必须 None，不修改原游标 | 必须有，仅 Main |

`current=None` 始终保持不变，具体空快照才清空。完全无变化的空 Append 不发送。每个 handle 首个成功 Chat 必须 Set，之后只有 Append；重同步终结旧 handle 并以新 handle 取得 Set，不在原流偷偷 reset。合法组合由 Rust 构造与测试保证，Flutter 不再跑一套业务切点校验。

## 26.6 被动打开、首屏切点与有序推送

open 在 Rust 内完成观察登记、切点捕获和有界基线准备，events 仅安装唯一消费者交付既定序列，不能等 events 才登记。主 owner 串行边界一起发布 `(sealedHead,current)`；初始页固定 H0，之后变化进入有界待发区，后继 Append 只包含 H0 之后本 scope 的完成事实。打开不追逐最新 head 无限重试。

冷读在同一短快照中取得轻量完成水位、current 与初始页，不读/校验/解码完整 checkpoint/current_context，不激活模型、工具、SSH 或执行 owner。current 表示最后已提交的逻辑状态，是否真有执行 source 由 registry 判定，重启前 running 不冒充当前运行。

复用 ThreadObservations 的稳定 observation slot 登记并捕获单调 epoch/位置；冷读后复核，覆盖 absent→live→absent 的 ABA。来源判断看 resident/pending，不只看业务 running；idle 也可有未落库尾段。源退役先安全交接 pending/writer。可连续接续由 Rust 完成握手，否则以现有 Failure 明确要求 ConversationResyncRequired，旧分页资格同时失效，不能返回空页或吞错。

slot 已安装而首次 publication 尚未就绪时，open 同时借用该 owner 原有的 retained progress 结果：先登记接收资格，再检查已保留错误及完成状态，并等待同一结果或来源代次变化。不能另建 readiness 镜像、只等 broadcast 或借执行激活/flush 补救。原失败按原共享错误与 typed 分类传出，不将其格式化成新字符串而丢失 code、reason 或可重试性；无错误但 owner 已结束且仍无 source 时明确要求重同步。工具停止还必须能打断该窗口中的 open 和首批接收，不能被 opens 读写锁互相阻塞。

对 Main，本 scope 的完成消息先进入可查询集合，Append 同时携带该项和退役后的 current；先交组件，再发布同批 current。scope 外完成不为补 seq 混入 Main，只更新必要摘要，成员按 Children 读取。current 可合并中间状态，但不能越过尚未交付的本 scope 完成转换；无法在总预算内保持边界则明确重同步。

保留现役 Frame 的 thread/subscription/delivery sequence 和 State/Failure/Closed，只把 ContentBaseline/ContentUpdate/ActivityContent 合为 Chat。State 继续同步输入、workspace、元数据等其他领域，但不拼正文、推断 terminal 或覆盖 Main Chat.current；Children 不倒灌 Main current。

## 26.7 内容与 current 集合按需读取

公开读取复用原 read lease 与内容 owner：listContents 取得 manifest，readContent 按 range 返回窗口，watchContent 取得有界当前窗口，pageCurrent 读取 revision 绑定的当前集合页。它们不是聊天列表操作，不强行塞为 ChatBatch。

工具取得 feed/reader 后、交付首批前，就由原 read owner 接管资源及名额；首批失败或取消须请求关闭并汇合原资源。关闭失败仍由原表项和 permit 承担重试责任，不另建清理队列或因 future 被丢弃而宣称 join 完成。

会话搜索区分输入 cursor 借来的已交付资格与本次新开的未交付资格。读取、取消或结果编码失败时收束后者，并保持尚未提交退休的输入资格可重试；跨 session EOF 不在随后读取仍可能失败时提前关闭输入 scope。完整成功结果构造完成后才提交旧资格退休和新 continuation 的转交；过渡仍受原 16 个 scope 上限约束，容量不足明确拒绝，不额外开第 17 个或驱逐其他读者。退休不可逆，提交清理失败时保留原待 join 资源与 permit，不伪造旧 cursor 仍可读，也不以清理错误掩盖先发生的操作错误。

ContentRef 区分 ItemPayload(itemId) 与 Body(owner,key)，绑定原库/读取资格。ItemPayload 按 item_id 定位原 payload BLOB 范围；Body 按 offset 索引定位目标块及必要边界块，不能先读/拼全文再切片。ContentWindow 统一携带实际 offset、bytes、generation、availableThrough、sealed。

具有 item 身份的正文从 active 即使用 Item(item_id)，完成前没有完成 seq；seal 移交已有共享块/manifest，不改名复制全文。append-only generation 不随 token 改变，替换才变代；非 item 当前文档用 Current(domain,id,revision)，过期明确 StaleContent。当前集合以领域 position 稳定排序并绑定 revision，过期重取所需页，不混接不同代次。

current 只推有界预览和引用；展开时订阅所需正文范围，Rust 组装窗口，Flutter 不归约原始文本 delta。折叠/未订阅正文不推全文。manifest 由 producer 明确提交，不解析未知 payload 查引用；完成内容随 item 保留，current 随 owner 退役且保障已接纳短读结束，不另建全局 GC。存储布局、内容发布屏障和缺失投影处理见 [17](./17-studio-storage.md)。

`CurrentProjection.activeTurn` 同时保留原 Turn 身份、阶段及可空的 `childrenParentId`。该父域引用由原产品 owner 使用真实 Turn 身份构造，与完成 Turn 载荷中的父域引用相同；未知或缺失时不由客户端拼接、解析 ID 或借用其他 Turn 补齐。字段沿原 current、持久化和传输链交付，计入原编码预算，不创建第二份成员或完成结果集合。

当前活动展开后，用户可显式打开该真实父域的已完成成员，复用现有 Children scope、分页、串行接纳及组件 controller；首批 Set 后继续接纳本 scope 的 Append，不等待 Turn 终态或保存，也不查询触发 flush。current 的活动工具集合仍只表达其原活动事实，不能把其中的状态、typed wait 或 Deferred 条目解释成完整完成结果。完整工具结果由已接纳的完成 item 及其公开 manifest、正文范围交付；返回时的目标状态和取消标志只能读取该次可靠结果，不能由稍后状态反推。

未显式展开时不建立该 Children scope；折叠、原选择失效或 active Turn 换代时同步撤销其资格，再沿现有 owner 取消并 join。诊断只借用实际已展开 scope 与窗口，不创建 reader 或 IO。Main 接纳完成 Turn 并退役对应 current 后，其成员继续通过该 Turn 的同一父域按需展开；不将成员插入 Main，不缓存跨选择的 controller，也不保持两份该父域的展示集合。

`CurrentContentPreview.role` 只是展示分类，不是文本频道或出站许可。预览以可空的 `textChannel` 保留原 canonical 文本条目的 `ThreadTextChannel`；非文本或无法证明频道时为未知，缺失也只表示未知，不能由 `Response`、正文、ID 或所属活动补成 `Final`。该事实沿原 current owner、存储与 FRB／HTTP／Client 映射交付，不新增旁路查询或状态镜像；同样计入原有编码和传输预算，不改变正文引用、generation 或完成边界。[机器人出站契约](./27-bots.md)的 Final 资格必须由明确频道及原目标 Turn 共同证明，未知与 Commentary 都不能授权创建或更新回复卡片。

## 26.8 Flutter 唯一组件消息集合

使用已有 InMemoryChatController，不另写 ChatController；它持有当前会话实际加载的 Message，Chat 负责 Widget 惰性构建/释放。只保留一个 applyBatch：Set 调 setMessages；Prepend 以 index=0 调 insertAllMessages；Append 调 insertAllMessages；空消息更新跳过插入。初始/旧页无插入动画，正常新增不 set 整表，不手动重复发组件 operation。

一条 ChatMessage 对应一条 Message.custom，id 使用原 id；当前 payload 可靠提供作者/时间时使用真实值，未知/Deferred 用明确中性作者且时间为空。单项 card 由其 Message.metadata 持有，不另存全局 raw item/map/分组缓存。转换逐项隔离，未知/坏 payload 保留非零高度、不影响邻居、分页或订阅；真正读取错误不改成不兼容。

删除历史身份/顺序全表重验、跨页合组和追读整个 Turn 的机制；业务类别在 Rust LIMIT 前选择。折叠成员只按真实 parent 查询，不从加载的原子拼组。controller 的同步 messages getter 不通过异步 FRB 实现；SDK 保持纯 Dart，不依赖 Flyer 或 app 生成代码，仅一次 transport→SDK 机械映射。

查询 IO 在串行应用段外；分页返回和事件都进入现有串行接纳链。捕获原 lease/controller，组件 await 后、before/current 发布和 ACK 前均复核原资格；不能重新读取当前选择绑定旧结果。只在 Set/Prepend 更新 before；同方向 single-flight，Append 不改变旧页边界。错误保留原 cursor，EOF/失败/取消都结束分页 Future，不等待物理绘制或数据库保存。

首批条数按视口与估计行高决定；真实布局缺口才有界补读，EOF、不推进、错误、关闭或启动预算耗尽即停。不兼容/Deferred 不能因零高度被跳过后无限翻页。保留经真实输入验证的外层滚动信号，并与组件 onEndReached 共用同一 single-flight，不新增第二分页状态机或持续帧末轮询。

已浏览 Message 在本会话打开期间保留，长期浏览会增长，不宣称默认数据内存恒定；切换/关闭释放旧 controller 和 Message 的所有引用，不能仅 dispose 后继续缓存。列表前插仍有组件移动成本，不承诺无限长已加载列表 O(1)。阅读旧位置时继续接纳新增，回最新走组件公开能力，不重开订阅、不做像素补偿。

## 26.9 工具当前契约与单条降级

当前执行 schema 与专用 renderer 各只维护一套。展示契约标识在请求冻结时确定，随真实调用/结果保留；同名同形字段不证明旧语义兼容。当前 renderer 只解析它声明支持的契约；无标识/未知标识或当前完整正文非法仅该项不兼容，保留身份、顺序、合法公开原文和可靠通用事实，不虚构时间、状态或工具参数。

合法但截断的预览、Deferred、custom/freeform 非 JSON 正文与真正 Malformed 分别处理，首屏不自动批量拉详情。generic MCP 的通用形状不依赖在线目录；敏感/redacted 继续受公开资源规则约束。数据库错误、内容缺失、身份冲突及执行恢复错误保持独立诊断，不将所有异常吞入“不兼容”。

工具形状改变不改五列 SQL 或追加历史 decoder/别名，旧工具业务字节只在正式容器迁移边界处理；续聊使用冻结模型上下文，不从当前 UI payload 重建或重跑历史工具。

## 26.10 验收与只读诊断

普通当前格式打开的 full_context_rows、quick_check、execution_activation、tool_or_ssh_initialization、query_triggered_flush 均为零。相同需求下增加总历史、隐藏活动或上下文，不增加线性全量读取/检查/解码。记录 SQL/pending 候选与返回量、payload/content/编码字节、逐项解码数、controller/实际构建行数及排队时间；诊断只临时借用 controller/owner，不反建第二历史集合。

Driver 的当前展示诊断直接按 controller 的 Message 顺序读取单项 metadata，报告实际消息数、原 item 身份、兼容性、已加载的有界正文/引用以及真实显示代次；不查询未展开内容，不重建隐藏 item 或分组集合。seq/H/D 与源 epoch 留在 Rust 所有者的诊断边界，不为旧脚本伪造完成游标、顺序号或组成员；顺序及新增/前插证明使用实际稳定身份与操作接纳证据。

展开的 Children 通过原 Main 展示 lease 登记只读借用，记录真实 parent、局部显示代次、查询资格及实际 controller；查询 Driver 时才遍历该 controller 的已加载 Message。登记只持当前资源借用，不持另一份消息或订阅，不从 Main 的 Turn 卡片重建 Children。关闭、显示换代和 Main lease 退役同步撤销借用；旧回调不能重新登记到新 lease。Set/Prepend/Append 的接纳计数在原组件操作成功且资格复核后递增，不从当前消息长度或内容推测操作。

运行中详情同样只借用真实挂载的 current 资源：Driver 可读取用户已展开、原 scope 已接纳的有界集合页及正文窗口，并报告原集合引用、局部代次、展开/加载/错误状态和 continuation。读取诊断不能发起 page/watch、展开组件、复制完整 current 集合或保留跨代页面；折叠、引用 revision 变化、来源 attempt 变化和 Main lease 退役同步撤销资格。工具等待只按现役 `tools` 页中原 call 身份与 producer 提供的 typed wait 判断，不从工具名、完成记录或输出片段猜测；没有提供的 item 身份及终态结果保持未知。

各层验收证明其实际拥有的事实。独立工具结果在 Turn 结束前已可靠发布的证明使用持有真实 parent/读取资格的 Runtime 或 HTTP 路径，不要求 Flutter 为旧脚本恢复全 Turn 分组、提前制造终态卡片或另存结果镜像；原生界面另证实际展开内容及其生命周期，不能将后来的 Children 完成页或实时输出片段冒充更早的完整结果。需核对完整历史时，验收器逐个真实 scope 分页到明确 EOF 并即时记录证据，不以当前挂载的 Children 合集代表全历史库存，也不要求所有惰性行或缩略图同时常驻、回收后保留展开态。

性能主指标为真实 selection 到同 generation 首个实际内容完成布局，另报目标视口填充和 build/raster。迁移已完成、同硬件/构建模式下冷打开和普通切换目标 p95≤500ms；进程冷启动、read scope 冷打开、OS 页缓存、数据规模/样本量/p50/p95及迁移耗时分别报告。Rust/Dart 各用单调时钟经 trace ID 关联，不能跨时钟相减或用批 FrameTiming 回调到达时间代替各帧时间。

AppGraph 在规范的可见选择目标成立、发出该目标读取 demand 之前记下同一 Dart `Stopwatch` 的起点；这不是后来的 Set/owner-ready 时间。正文见证仅包裹已解码且实际呈现的非空内容，在该正文子树完成 layout 后捕获同钟时间，再于本帧末核对原 lease、代次及实际可见资格。帧末回调只做资格确认，不用回调到达时间替换已捕获的 layout 时间，也不持续申请帧。skeleton、Deferred 按钮、错误提示、空容器、未呈现内容及已经退役的布局不能完成样本；无有效见证保持未知。应用只留当前展示代次的小样本，外部验收采样器负责汇总，不建立应用内跨会话性能历史。

通用内容范围查看器浏览一个有界字节窗口，下一段只在显式操作时请求。复制操作明确标为“复制当前段”，仅复制当前实际显示的窗口文本；不将它标作全文复制，也不为旧全文断言自动追读所有段。完整公开原文仍可通过同一稳定引用逐段读取。验收脚本分别证明窗口读取、显式续读及当前段复制，未提供的全文复制能力明确列为不适用，不能用窗口成功冒充全文成功或伪造旧详情接口。

需覆盖内存足页零 SQL、提交/清 pending 交错、固定切点/持续新增、并发上翻、源 ABA、同批 current 退役、超长内容、未知工具、慢消费者、独立 query、A→B→A、关闭/保存故障和非空迁移。原生、模拟供应商、真实供应商及各平台证据分开，不以日志采集、组件成功或文档目标冒充验收通过。
