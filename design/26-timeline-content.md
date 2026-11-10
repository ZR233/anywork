# 26 - 不可变完成历史与连续段读取

本文维护 Native 完成内容、读取与呈现契约，依据 [#311](https://github.com/ZR233/anywork/issues/311) 及其最终补充，替代 #272 的持久工作组、来源排序、整组交接和组头更新方案。这里定义目标，不以文档更新冒充实现或性能验收。ACP 外部历史及协议保证不变。可靠执行保存归 [15](./15-session-storage.md)，存储迁移归 [17](./17-studio-storage.md)，传输归 [07](./07-streaming.md)，客户端资源归 [25](./25-frontend-state.md)，视觉归 [19](./19-studio-ui.md)。

## 26.1 完成事实与唯一所有者

显式用户文件展示沿原工具完成记录封存，不增加独立历史 writer。`builtin.show_files@1` 的 renderer 消费 [09](./09-tool-runtime.md) 定义的 `pl.tool.files@1`，保留成功／失败顺序，成功附件从同一回执的可靠资源引用派生。归档资源的读取资格同时覆盖驻留、pending 和持久回执，冷重开不重新执行工具或读取源文件。旧图片展示格式保留必要只读解码。

新文件展示工具的原子由原 Native owner 标记为 `Independent`，沿既有分类规则产生 `Single`，使文件格直接出现在主时间线，而不隐藏在默认折叠的工作记录中。保留原 Turn 来源、调用身份与完成顺序，不由 Flutter 解析 payload 后重新分类；普通工具及旧图片历史的分类不变。

图片复用原图片 owner；Markdown 和保存按需读取原资源，二进制不进入 ViewState。来源定位元数据不能授予额外读取权限。外部交付状态归发送领域，不回写不可变完成记录；历史打开、GUI 重绘和重新订阅不得发送外部消息。渠道交付使用 [27](./27-bots.md) 的明确来源绑定，不以时间线可见性或附件存在推导外发资格。

Markdown 语法与流式未闭合内容由上游渲染组件解析，采用其 CommonMark 与扩展语法，不在客户端维护第二套修复解析器。解析规则升级只改变展示，不改写已保存原文；普通纯文本继续保真选择与复制。不安全链接不得取得交互手势，来源标签与图片沿原受控访问入口处理；上游支持 HTML 或新增语法不授予额外外发、资源读取或执行权限。

**完成一次，记录一次；历史内容不更新；工作组只是界面组合。** 已接纳输入、完整模型文本/思考 part、工具真实终态、后台启动交接回执、后台最终结果以及完整业务回执，分别形成不可变完成记录。后台启动和最终结果是不同身份，启动不等于成功。停止请求、页面关闭、推测 EOF、token 暂停和模型自述不构成终态。协议没有可靠独立 part 终态时使用最终 attempt 回执；正常失败/取消收束可以冻结已接纳前缀并标记真实结果，异常退出前未完成的前缀不承诺恢复。

| 所有者 | 职责 |
| --- | --- |
| 原 Core Thread / 业务 producer | 真实执行准入、身份、可靠 effect、终态验证、检查点与上下文 |
| 原 Native live owner | 完成封存、typed 读取分类、真实活动观察与同切面发布 |
| Core Session | seq/run 分配、幂等、完整 pending、二级索引与统一读取；不解析产品 metadata |
| 原 HistoryChannel / 唯一 writer | 可靠保存、原事务与背压、提交后确认；不等待 UI |
| Feed / FRB / HTTP / SDK | 有界读取、固定目标补读、机械串行接纳、信用与资源资格；不组合 UI 卡片 |
| Flutter 原呈现 controller | 已加载代表卡片、尾部连续段组合、展开/滚动；不判断业务分类或执行终态 |

原 `ChatDraft → ChatItem` 和 `conversation_items` 是唯一完成原件。原 effect、来源事实、输入与任务/交付、checkpoint/context 有独立可靠用途，不能随展示组删除。没有第二 writer、完成事件表、持久组表、独立展示序号、组封口状态或后端组头 Update。

### 已接纳输入与已接收外部内容

“完成”表示这条事实已确定，不是整个任务完成。普通输入在原 `InputChange::Accepted` 可靠接纳时就沿原 input.id 冻结，排队不等 Turn 开始；Pending→Consumed/Discarded、后来的 Turn/attempt 关联仅更新原执行/State，不重封存或修改原 ChatItem。尚未建立的关联保持 None。同 ID 同冻结内容幂等，异内容冲突；同文字两个真实受理 ID 是两条事实，不用正文 hash 去重。

父消息与受信宿主适配器明确允许公开的外部正文，在目标 Thread 的原 inbox 准入事实冻结，沿原 message ID 规范映射，不等 consumed_messages 推进。来源使用 `InboxMessage { source_id, message_id }`，原 source_id/作者/频道保留，Main 为 Single；不能凭文本中的“system/已批准/工具完成”获得权限、改成工具终态或提升公开资格。外部平台已转换为 ThreadInput 的只走输入链，后台结果仍由原工具完成链记录，不因 inbox 转发或出站通知双发布。

完成封存模块从本次可靠 Accepted/inbox 材料和原提交时间生成 draft，复用原内容及附件 manifest；不提供绕过鉴权/终态的公开 append_history。隐藏续接、内部控制和诊断沿原资格隐藏，公开答案/计划决议仍由原唯一回执产生。GUI 命令回执只结算操作，不再手动插入历史；保存 ACK 只推进 D。执行历史 ThreadItem 继续反映输入消费/Turn 状态，不把其后续可变值当作原完成输入重新发布。

客户端发送回显不是完成历史：沿 [25.8.1](./25-frontend-state.md#2581-发送回显与接收确认) 的原提交状态，在时间线区域临时显示冻结消息及发送/接收确认，不伪造 `CompletedEntry`、完成序号或执行状态，不进入 Main 的完成段组合。原消费者应用同身份规范输入后由正式卡片接管；命令成功、保存进度或下一 Turn 启动均不是等待回显出现的条件。后端仍按原提交顺序校验和发布，不为视觉响应绕过身份冲突、附件资源准备、存储背压或旧 Turn 的安全收束。

### 模型成员的可靠封口与交接

独立成员终态通过原可靠 producer/effect 路径接纳，不能被可合并 progress 吞掉，也不能等整个 attempt 结束。记录发布即进入历史并退出相应实际活动；不保留整组整体移动的视觉保证。真实 Plan、待决交互及配置继续由原 State/领域 owner 管理，不以活动消失或完成正文替代业务决议。

## 26.2 身份、顺序与读取分类

`item_id` 是原稳定业务身份；`seq` 是完成发布顺序，范围为 `1..=i64::MAX`，由原 Session 在 RAM 中分配并显式 INSERT，不是时间戳、开始顺序或数据库自增回读。重试沿用原 ID 和冻结字节，异载荷、manifest 或身份冲突明确失败，不用随机新 ID 绕过。

历史唯一排序为完成 seq。例如 A 开始、B 开始、B 完成、正文完成、A 完成，历史为 B→正文→A，A 不插回旧段。真实来源顺序、effect 位置与 transport delivery sequence 保留各自用途，但不决定历史排序。

Core 的通用读取提示只有 `Hidden`、`Single`、`Adjacent { key }`。Native 唯一分类同时给出提示与 `MainPresentation`，首次封存、迁移、SQLite header 恢复和传输共用；读取 hint 的便捷入口仅取同一结果，不维护第二个分类器。

| typed 事实 | 提示 / 主列表类别 |
| --- | --- |
| conversation 类公开输入、非空正文、仅附件输入/响应 | Single / Single |
| 非 Independent 的同一 ForegroundTurn Reasoning、ToolCall、FileChange、Skill，以及其后台启动交接 | Adjacent，以完整 ChatSourceId 的规范编码和 `native-work-source` 域为 key / ForegroundWork |
| BackgroundResult 的 ToolCall 最终结果 | Adjacent，固定域 `native-background-results`、值 `terminal` / BackgroundResults |
| Plan、Interaction、Compaction、失败/取消 Turn 回执、Raw/Agent/Unknown 等独立公开信息 | Single / Single |
| Inference、内部诊断、非 conversation 类、正常成功 Turn 回执 | Hidden / Hidden |
| typed content_present 明确为 false 且确无正文/附件的 Text | Hidden / Hidden |

Hidden 不分隔可见连续段，Single 自成一段。相邻只指可见完成序列；同来源被其他可见记录隔开后另起段，不因同 Turn 跨正文合组。正文仅开始尚未完成不分段。`parent_id != NULL` 不等于隐藏；Children 是按真实父域读取同一记录，不是组成员表。合法未知 payload 不改变 typed 分类；坏 metadata 是存储错误，不能静默变 Hidden。

记录头具有 `read_hint` 与可空 `run { start_seq, ordinal }`。Single 的 start=seq、ordinal=1；Adjacent 与最后可见记录 key 相同时沿用 start、ordinal 加一，否则起新段；Hidden 的 run=None 且不改变最后可见值。Session 只保留有界 `last_visible` seed。整批在私有候选中完成算术、身份和预算校验后原子发布；幂等命中不推进 head 或 seed。

已知文本的可见正文与保全原始请求的内容域不同。Accepted/Inbox 的原 payload 引用及字节继续保留；
文本组件仅展示规范正文角色与附件，不把通用内容清单中的原始请求域逐项当正文，也不根据 JSON
外观过滤用户文本。原 payload 引用若复用真正正文，不能因此隐藏正文。文本的 `content_present`
只计正文角色的非空内容与附件，不由原始请求封装或其他保留域变成 true。

## 26.3 完整 pending 与保存交接

H 是已发布完成上界，D 是已确认落盘连续前缀，pending 完整覆盖 `(D,H]`，不是可淘汰缓存。可见、段、class/parent 及内容索引只引用同一冻结 Arc，不复制正文或保留已保存全组。冷绑定从一个短快照取得 head 与最后可见轻量头，已初始化 Session 不反复查询 seed。

原 writer 仍把 effect、checkpoint/context、完成记录与内容放在同一事务。首次 INSERT 同时写 run 两列，原字段与新列随后不变；重放核对原字节、seq/run/hint，不 OR REPLACE 或吞冲突。保存 ACK 只确认本批实际连续前缀，不能取最新 H；没有 completion 的 effect 不推进 D，也不产生第二次 Append。

COMMIT 后释放 pending 及辅助索引引用，已捕获短读 Arc 可以自然读完。磁盘失败保留原义务并沿既有背压处理，不能先清 pending、丢旧记录或无限扩容。批处理阈值、flush、关闭和副作用前保存屏障沿原机制，不加新保存定时器。内存发布不承诺抗进程崩溃，不能保证工具副作用 exactly-once 或重执行历史工具。

冻结材料的计量依附其原所有权，可共享精确编码长度，但实际变化必须重新计量；共享元信息也计入预算，不以共享掩盖驻留成本。传输实际编码与驻留估计分开，失败或算术溢出拒绝。原执行身份集合及可靠预算不因删除展示 fold 而弱化。

## 26.4 按需分页与 continuation

原查询增加 `Records`、`RunHeads`、`Run { start_seq }` 选择。Records 保留 class/parent 语义，parent=None 为整个 class；RunHeads/Run 必须 parent=None，非法组合入口拒绝。Native Main/Run 使用 conversation 查询类。

一次读取先在 Session 短锁捕获 H、D、资格及所需 Arc，再解锁打开新的 SQLite 短读快照，只补 `seq <= captured_D` 的不足前缀。禁止先开旧 SQL 快照再捕获新 RAM 水位，不用最新 D 替换 captured_D，不跨 await 持锁。存储错误、缺记录与失效资格不是 EOF；查询不 flush、不激活执行、不读完整 checkpoint。

Main 首页固定 H0；旧页 upper=min(H0,before-1)。在可见 pending 索引取 upper 内最后一条代表，再令 upper=代表.start_seq-1，直接跳段。跨 RAM/SQLite 的同段只返回一次。内存够条数或字节预算时 page/existence SQL=0；不足部分才在新 SQL 快照对 min(captured_D,upper) 用可见 seq 索引递归跳读。候选窗口最多64个且不超过剩余 max_items，不 OFFSET、COUNT、GROUP BY、全组聚合或扫描全成员。选择降序、返回升序；下一页 before=最早代表的 start_seq。

Run 使用 `(start_seq,seq)` 索引按原完成顺序页读，首次取得该 cut 最新一页，再向上读旧成员。新成员沿其 tail Append；不匹配记录也推进内部 through_seq，不能将过滤为空误作已检查全局上界。

continuation 沿原不透明 codec 升为 v2，绑定 database_id、thread_id、read_epoch、Main/Run/Children scope、index_version=1、ceiling 和 before_exclusive。u64 沿既有无损传输，不经浮点；Dart 原样保存回传。非空 before 不保证下一页非空，最后一次空 Prepend 可返回 null；短页/字节截页不等于 EOF。错误不改 cursor；库替换、旧 epoch、scope 不符明确 stale/invalid，不重绑当前选择。

## 26.5 批次、呈现类别与零正文主列表

`CompletedEntry` 包含 record_id、completion_seq、可空 run、main_presentation 和原 ChatAtom。完成引用与 atom 内嵌完成身份/序号必须一致；旧记录缺内嵌 seq 时由 adapter 机械补齐，不写回 payload。atom.id 仍为真实执行/来源身份，不能替换完成主键。

`ChatScope` 为 Main、Run（database_id/index_version/start_seq 引用）、Children（真实 typed parent）。Run 打开校验引用对应真实段首，不把任意整数当空组。`ChatBatch` 为 Set/Prepend/Append，携 entries、before、from_seq、through_seq；不再有 Update 或 Item/Source 展示联合协议。

- Main Set/Prepend 每段一个代表；Main Append 每条新可见完成记录，不只交付最新代表。
- Run/Children 返回原子记录；Children 可读其业务资格内的 Hidden，主列表类别不替代真实父域资格。
- **Main 的 ForegroundWork/BackgroundResults 在所有 placement 中只交付轻量头与 Deferred 引用，工具参数、结果、思考正文、图片读取/内联字节均为零，即使只有1项。** Single 可按预算内联自己的小 payload，大内容仍 Deferred。
- Run、Children 与显式按完成 ID 读取才允许预算内小信封；大正文继续范围读取。按 ID 读取走有界 header 路径，不用 publication 的整记录校验入口物化全文。
- max_items 限实际 entries 数，max_items=1 合法；max_bytes 包含全部实际编码字段。
- Set.from_seq=None、through_seq=H0；Prepend.from_seq=None、through_seq=原 ceiling，不推进实时接纳前缀。Append.from_seq=上次检查位置，through_seq 严格前进，before=None 不覆盖旧页游标。
- 空 Append 可推进完成前缀，但不调用 controller 插入；无进展不发送。过滤产生的 seq 间隔不补虚假记录。

## 26.6 被动打开、活动切点与有序推送

open 先登记原 Session/活动通知再捕获 `(H0,activity0)`，events 只安装消费者，不延迟登记。首个 Main Set 到 H0，接纳后才交付 activity0。后续每次固定一个 `(Ht,activity_t)`，从 consumer_through 补读到 Ht；受预算可分多批，完成本目标才捕获更新目标，不追逐无限更新。

ActivitySnapshot 含 revision、completed_through、execution_present、entries；每项含 typed ActivityIdentity 和未分配完成 seq 的活动 atom。身份为 ModelPart、ForegroundTool、BackgroundTool 或真实 Other 域。唯一完成适配给出可证明的关联：普通工具终态/真实后台启动交接退出 ForegroundTool，后台最终结果退出 BackgroundTool；无可靠关联的旧记录返回 None，不拆字符串补造。

每批完成接纳后同步退休精确对应活动，不等整组；只有检查到 Ht 后才交付 activity_t。活动 completed_through 必须等于已接纳 through，revision 不倒退；低于 through 的快照丢弃，高于 through 的由 Feed 补读后交付，不让 Flutter 补偿查询。仅 token 变化时 H 不变、revision 前进，可只交付活动。

原 live owner 保存有界最新值，watch 仅唤醒，不保存完成日志、旧正文或可靠展示 cut 队列。完成记录来自原 Session pending/SQLite。活动内容换代按 stale 拒绝，不为旧快照永久展开留全文。冷浏览无热 owner 时活动为空、execution_present=false；真实待决交互与 Plan 从原轻量业务状态取得，不清空、不激活执行、不制造终态。

保留原 State 的可靠业务事实与慢接收者 Lagged/重同步语义，不把全部 State 降为 latest-only。基线携同切面的待决交互，准备与订阅登记的竞态不得漏事实；State 慢消费者不反压执行保存。原 observation slot、来源 ABA、初次准备失败、来源退役与 pending 交接仍须明确处理，不能吞错为空页。

原 State 的 `ThreadActivity`／`ActivityChanged` 仍交付同一执行 owner 的类型化阶段摘要，
用于尚无内容时的准备、思考、压缩、等待和停止提示；首份热基线与后续通知都不得丢弃。
它不携带完成成员、不决定正文退休，也不能替代 `ActivitySnapshot` 的完成 through 屏障。
冷打开没有执行 owner 时保持摘要为空；客户端不得仅凭 `execution_present` 猜测阶段，
也不以较早摘要清除或复活已经完成的内容。

状态与内容使用独立 Frame 身份、投递序号及有界信用，交付和关闭规则见 [07](./07-streaming.md#710-会话推送交付确认与关闭)。状态通道交付 State、Failure、Closed，内容通道交付 Chat、Activity、Failure、Closed；首个 State 声明 completedHistoryVersion=1，不支持时明确 ProtocolVersionMismatch，不双解码。各通道 ACK 在实际接纳完成且原资格有效后推进，不等布局、query、详情或 SQLite，也不等待另一通道消费。低层已读位置不冒充外层 ACK；内容连续性丢失关闭原内容资格，新内容句柄以 Set 重同步，状态失连续只重建状态基线。

### 业务引用由 State 交付

`ThreadBusinessRefs` 只含 `plan: Option<CurrentPlanHead>` 与 `interactions: Option<CurrentCollectionRef>`。ThreadSnapshot 必有 business_refs，不用 serde 默认空值兼容旧协议；本次 Thread State schema 从16升至17，沿原版本检查拒绝不匹配端，不另加业务引用版本字段。`ThreadNotification::BusinessRefsChanged { references }` 使用原 epoch/baseRevision/revision、Frame 信用和串行接纳，整体替换两个读取头，不建第二订阅或业务 ACK。

这些引用由原 Plan/交互 owner 同一已接纳切面形成：先让原 reader 可解析，再发布 State。仅头或引用实际变化才通知；token、工具进度、查询和保存 ACK 不推动它。订阅前已有引用进入首个 State；业务操作资格不等 Chat 追平或工作段展开。冷读在同一 SQLite 短事务取得领域字段、完整 Plan 引用与交互集合，无执行 owner 不意味着无业务引用。

plan=None 表示真无 Plan，Some/document=None 表示有 Plan 但真无文档；interactions=None 表示尚无已建立资源，不掩盖失败，已初始化空集合可有有效引用。原 Snapshot.interactions/InteractionChanged 仍是可操作问题唯一模型，runtime.plan 保留原业务摘要和命令资格；引用仅供详情读取，不反向重建状态。Plan head revision 是资源版本，不替代原命令 CAS。

旧 current.collections 的 interactions 收敛到专用字段；tools/members 退出通用业务集合交付，活动内容沿 Activity entries/atom.contents，完成明细沿 Run。current.previews 不成为业务引用来源，logical_status/active_turn 沿原 Thread/Turn State；不恢复 ChatBatch.current，不把旧组/正文放入 State。

## 26.7 内容与当前集合按需读取

原 feed facade 持 feed 和独立 read lease。load_older、read_completed、内容/附件/范围与真实 current 查询通过短锁准入、克隆租约、锁外 IO 和原 TaskTracker 汇合，不获取阻塞于 recv/credit 的长锁；query Future 不进入事件流或等待 ACK。

原 reader 的普通 `read_business_refs` 与 State 基线共用同一领域头投影函数，只返回 ThreadBusinessRefs，不保存第二 current 或创建 observer。一次性内容工具可查询；GUI 持续跟踪仅消费 State，不在每次命令/Activity/Chat 后补偿刷新。pageCurrent 保留原形状，只读真实业务集合，引用校验不依赖已删除的 current.collections。

集合变化只推进自身资源 revision，Plan 不让无关交互页失效，token 不让 Plan 换代。continuation 绑定库、reader、collection/revision；过期明确 StaleContent，不混接旧新页。新 State 引用只退役受影响展开资源，保留历史 controller、其他窗口与草稿；State 真丢连续性仍沿原重同步。旧 Plan 引用读原版本或 stale，不静默替换最新文档；缺块、跨库或权限错误不返回空结果。

交互集合的版本由原 Core 业务 owner 随 `ThreadSnapshot`/checkpoint 保存为 `interaction_collection_revision`，只描述原 `interactions` 与 `permissions` 联合集合，不是新的全局 State revision 或额外观察器。不能取剩余成员的最大单项 revision，也不能在冷热投影各自计数、以内容 hash 或任意无关 commit 的序号替代。成员内容/身份变化在原 transfer 捕获前推进；原 resident 剪裁实际删除成员时再推进。因而同一 effect 中可读的 resolved transfer 与随后不含该成员的 resident 有不同版本，重开所用 pruned checkpoint 必须得到与 resident 相同的版本；重复剪裁不推进。正常变化及必要剪裁的版本分配使用 checked arithmetic，耗尽时沿原失败路径明确拒绝发布后续资源切面，不能回绕、饱和后复用旧版本或默认为空集合。

该字段为原 checkpoint 中的增量领域元信息：旧 schema6 Core 状态缺失时只初始化为0，表示升级后首次基线，不根据旧材料猜测过去的集合代次；后续由原 owner 真实变化推进。此初始化不重写 `conversation_items` 原字节、不另建表或迁移流水线，也不改变 Native State schema17 的必填 `business_refs` 与版本拒绝。Runtime 的热源、冷源和 `business_refs_at` 直接消费所属切面的同一版本；恢复补存旧 transfer 不得把已经公开的新资源切面倒退。

listContents 取得 manifest，readContent 按 range 返回窗口，watchContent 观察有界当前窗口，pageCurrent 读取 revision 绑定的真实业务集合。它们不是聊天列表，不强制塞入 ChatBatch。ContentRef 区分原 ItemPayload 与 Body，绑定库/资格；按 offset 索引只读目标和必要边界块，不能先拼全文再切片。窗口保留 offset、bytes、generation、availableThrough、sealed。

可见文本正文的展示不由长度或 Inline/Deferred 传输方式决定：挂载的正文直接读取有界窗口，复用普通消息的 Markdown、选择/复制、自动换行及安全链接/媒体策略，不增加正文键名或字节数折叠栏。一个窗口已包含完整正文时不显示范围导航；超出窗口仍明确显示范围和下一段操作，不自动累计无限全文。工作卡、工具和思考详情的语义折叠保持不变，只有其已展开内容才取得读取资格；原始 ItemPayload/诊断查看器仍按原始内容展示，不将 JSON 信封误当作 Markdown 正文。

已知用户 Input 的公开 Body 声明独立于外层 ItemPayload 的内联预算：即使信封 Deferred，也按已声明的正文引用直接展示，不要求先展开原始信封。只使用明确的正文角色与归属于当前完成输入项的正文目标，不把其他消息的正文、`accepted.payload` 等保全域、未知内容或未声明域推断为用户正文。缺少公开正文声明时保留原诊断边界，已解码信封中的附件仍沿原附件呈现；正文读取不自动解码或公开原始请求。

交互详情是结构化请求，不把单个正文窗口当成完整 JSON。对 Deferred 的一个交互请求，UI 在原独立查询资格内以窗口读取、累计最多1 MiB完整信封后才解码；超过预算明确报告该详情资源过大，不截断伪装成功，也不显示原始 JSON。窗口之间须保持引用、generation、总长度与 sealed 条件一致，按字节累计后统一解码 UTF-8；引用换代、折叠或关闭立即撤销资格并汇合在途读取。显示与复制均只允许 canonical 解码和敏感字段过滤后的公开内容，不提供原始交互信封的“复制当前段”、下载或错误回显旁路。普通正文窗口的分段复制行为不因此改变。

有 item 身份的正文从 active 沿用同一内容 owner，完成 seal 移交原共享块/manifest，不改名复制全文。追加不换 generation，替换才换；非 item 当前文档绑定原域/id/revision，过期 StaleContent。manifest 由 producer 显式提交，不解析未知 payload 找引用。正文、媒体和敏感/redacted 权限保持；完成内容随原件保留，活动内容随原 owner 退役并允许已接纳短读结束。

request_close 同步撤销准入，close 异步等待全部原在途任务/资源；页面离开只关闭读取，不取消执行。open/首批失败也由原 read owner 收束 permit，不因 Future 丢弃冒充已 join。A→B→A 的第一份 A 不写入第二份 A；await 后、游标发布及 ACK 前复核捕获资格，旧 finally 不撤销新 lease。

会话搜索保留借入 cursor 与新建未交付资格的区别：失败收束后者，完整结果成功构造后才退休旧资格并转交新 continuation，沿既有16个 scope 上限，不驱逐其他读者或另开超额 scope。清理失败保留原待 join 责任，不掩盖先发生的操作错误。

会话内容工具 `read_session_messages` 首次可指定 Main/Run/真实 Children 的 scope（省略 Main），返回独立 readScope 与 State/Activity；之后沿原资格读取旧页、manifest、正文范围或业务集合。`readBusinessRefs` 是该 readScope 上的普通业务头查询，不触发历史刷新；scope 只在打开时选择，不能用旧 before 偷换范围。`get_session` 从同一 reader 获取业务引用与交互详情，不回传永远空的旧 current。搜索需要工作成员时沿原 Run 分页，不把 Main 最后代表当完整库存。

## 26.8 Flutter 连续段组合与组件消息集合

唯一组合器位于原呈现 controller。SDK 只机械交付，Widget/Riverpod 不解析 payload、source 或 ordinal 猜业务类别。Main 卡片值只含稳定 messageId、代表 CompletedEntry 与 CompletionRunRef；messageId 使用原库身份和 run.start_seq 的无歧义编码。`Message.custom.metadata` 唯一持有已加载卡片，成员仅由展开的独立 controller 持有，不另存 rawAtoms/groups/messages 三份集合。

| 输入 | 操作 |
| --- | --- |
| Set | 每个代表一个 Message，一次 setMessages，无动画 |
| Prepend | 前插 Rust 返回的完整旧段代表，无接缝追读 |
| Append Single | 插入独立卡片 |
| Append 同尾卡 start_seq 的工作记录 | updateMessage 替换代表/计数，身份与展开意图不变 |
| Append 新 start_seq | 插入工作卡 |
| 空 Append / Activity | 不枚举历史、不调用插入；分别推进前缀或更新独立活动区 |

Append 只看尾卡，不找旧组。start_seq 回到非尾位置、相同 ID 不同内容、ordinal 倒退是连续性错误，不静默排序去重。一个成员的 ForegroundWork 仍用可展开工作卡。计数为代表 ordinal；工作标题“工作记录 · N 项”，后台“后台结果 · N 项”。未读成员不显示全组统计，详情统计标为“已加载部分”。Single 复用原 renderer，附件-only 不丢，读图结果仍在工作明细内。

### 按连续段的布局补载

沿原 Chat 公共能力按实际布局请求旧页、补满与回最新，不写自定义 ChatController/像素补偿，不设固定总页数上限。满屏后停止读取；Main 已跳过整段，不能为找组头继续扫描。主列表随浏览增长，不宣称总内存恒定，切换关闭释放旧 controller。

### 26.8.1 代表自足与成员按需读取

展开通过原 openRun 打开独立 Run feed，有自己的 Set/Prepend/Append 与游标，Main count 不被已加载成员数覆盖。查询 IO 在串行应用段外，结果与流共用接纳链；错误保留原 cursor，同方向 single-flight，成员页不改变 Main continuation。

### 26.8.2 活动与成员展开的资源边界

工作卡/活动首次呈现默认折叠，不因执行或内容变化自动展开。折叠同步撤销成员、正文和图片资格，再 cancel/join；不预建隐藏 Element，不保存已释放成员快照或全局展开表。再展开重新取得有界 Run 页，不重跑执行或恢复组状态。活动区可以按 typed source 临时组合进行中条目，但不维护 sealed、历史段身份或可恢复成员树，也不保证活动 Widget 整体迁入历史。

同一展示代次的附件通过原资源账本差量更新；挂载实例使用独立所有者身份，旧组件卸载只释放自己的引用，最后使用者退出才释放资源。父 lease、引用或显示代次失效同步撤销子窗口资格，后续异步回调不得登记到新 lease。加载中不可借用成员不等于零成员；接纳完成仍缺事实时明确失败，不以 loading 掩盖。

## 26.9 工具当前契约与单条降级

当前执行 schema 与专用 renderer 各一套。展示契约标识在请求冻结时确定，同名字段不证明兼容。未知/旧标识或非法业务正文仅该项降级，保留身份、顺序、合法公开原文和可靠通用事实，不虚构时间、状态和参数。

Deferred、合法截断预览、custom/freeform 非 JSON 与真正 Malformed 区分；首屏不自动拉全部详情。generic MCP 通用形状不依赖在线目录。数据库错误、缺内容块、身份冲突和恢复错误不吞成“不兼容”。工具形状变化不改通用 SQL 列或保留历史 decoder；续聊使用冻结上下文，不从 UI payload 重建或重跑历史工具。

### 26.9.1 修改补丁的片段展示

`builtin.apply_patch@1` 展开后仅呈现请求中的修改片段：按文件和片段分隔，以绿色背景及 `+` 标记表示新增、红色背景及 `-` 标记表示删除，中性背景表示补丁已有的上下文。保留缩进、空行、代码选择与长行横向滚动，适配明暗主题；不读取完整文件、不计算另一份文件差异，不推断原文件行号。文件移动展示原路径与目标路径；删除声明没有旧内容时只表达删除操作，不补造被删内容。

此展示只消费当前契约的 freeform 补丁正文或 JSON `input` 信封内的同一正文，不显示原始参数、信封、补丁控制标记或重复的成功输出。补丁是请求修改的事实，不是落盘结果；真实执行状态和必要失败、拒绝诊断保持可见，失败片段不得表述为已应用。其他工具与未知契约不按名称启用此渲染。

直接正文与已声明正文使用同一片段语义，读取仍由原有展开资格和有界窗口持有，不在界面累计全文或读取工作区文件。截断窗口不得伪装成完整补丁；缺少片段归属或无法完整解析时明确提示不可用，保留既有范围与下一段操作，不猜测归属，也不回退公开原始参数。原始诊断查看器的既有独立入口与权限不因此扩大或改变。

## 26.10 验收与只读诊断

具体测试及平台证据边界归 [24](./24-testing.md)。覆盖 #311 的 I01–I30，包括发布、幂等、事务故障、读写交错、长段跳读、活动因果、慢消费者、ABA、真实业务恢复、非空迁移、原生与 HTTP/bot 完整故事。

真实入口记录 SQL/pending 候选与返回行、正文/媒体和 FRB 编码字节、writer 事务、未落库引用、controller 操作。内存足页 page/existence SQL=0，身份/seed 查询单列；折叠 Main 不 COUNT/聚合，1至100000成员工作段的成员正文/媒体字节=0。EXPLAIN QUERY PLAN 与真实候选成本共同证明跳段，不以 SQL 条数少掩盖扫描。纯 Activity 枚举历史=0，同段新增只局部更新。

普通当前库打开不读完整 context/checkpoint，不 quick_check、不激活工具/SSH、不 flush。性能在同设备同构建测 selection 到同代有效内容 layout，冷打开/切换目标 p95≤500ms；首次迁移、展开、满屏/EOF、长时浏览分别报告。起点来自原选择成立前的单调时钟，布局见证排除骨架/错误/未呈现正文，帧末只复核资格；不跨时钟相减或伪造样本。

诊断只借真实 controller/挂载窗口，不发起隐式 IO、展开或建历史镜像；加载、失败与未覆盖分开，运行中事实必须在当时读取资格下证明。通用范围查看器只复制实际显示的当前段，不标成全文，不为验收自动追读。原生、模拟供应商、真实供应商与各平台结果不互相替代。

## 26.11 内容迁移与保全

正式迁移归 [17](./17-studio-storage.md)。旧历史按原完成 seq 与新分类显示，保留原始字节、身份、资源和可靠恢复事实，不承诺保留旧展示位置、组标题或折叠偏好。无完成 receipt 的中断占位不伪造原子，其真实来源/Core 中断事实仍保留；迁移和浏览不制造业务终态或重跑副作用。

旧迁移及其历史 fold 只在冻结迁移边界使用，普通 reader/writer 不依赖旧组恢复头。Applied 后坏列/索引/引用明确拒绝，保原件，不自动补建、回填或切换旧架构。后续分类规则改变需要正式版本迁移，不在正常读取中重算历史。

Accepted/inbox 新封存和业务引用出口随尚未发布的 schema18 同批切换，不另建引用表或第二迁移。旧完成记录原字节不改；过去只有执行/收件历史的材料继续原位保全，不补猜完成顺序、不回填当前可操作问题。真实新 Accepted/Inbox 重放复用原冻结稿/已存完成项，不能按今天的消费状态重新编码。
