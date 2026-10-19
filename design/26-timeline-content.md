# 26 - Timeline 内容源与原生列表

本文是 Timeline 读取接口、展示模式与预算的权威契约。执行与可靠保存仍归
[15](./15-session-storage.md)，Client 资源生命周期归 [25](./25-frontend-state.md)。
本文描述已批准的目标设计，不代表原生交互或性能已验收。

## 26.1 职责与唯一事实源

Thread 的唯一投影发布者将同一稳定身份的事实发布到 core Session，并交给可靠 writer。
Session 统一合并活动内容、可靠待保存事实与历史存储；状态流不携带正文，GUI 不自行合并
SQL 与实时 overlay。core 不依赖 Studio DTO、Flutter、消息排版或视口尺寸。

Session 只提供无状态 keyset 页、最新端订阅与按身份详情，不拥有可见行或阅读位置。
不再有 ChatView 几何窗口、Latest/Around 聚焦、双向对端裁剪、窗口下标 Splice、全文展开
意图或等待窗口落位的操作回执。缓存退出不构成事实删除。

SDK-only Client 拥有内容连接、版本基线、查询取消与重连；当前展示 lease 将 typed 内容
投影为库的 Message，唯一已加载消息集合由 InMemoryChatController 持有。不额外保留完整
rows/window/body 集合后逐帧做整表差异。库的内部消费列表不成为应用可写事实源。

## 26.2 页、订阅与详情

### 无状态历史页

页请求以 latest 或 before(cursor) 表达，普通首屏及每页以 32 条为默认值，服务端最多接纳
100 条。游标绑定 Thread 与严格顺序边界，不能跨 Thread 复用，不使用 offset 分页。结果
包括有序轻量条目、下一游标及 hasOlder；短页不能单独证明到头，边界来自真实存在性检查。

查询候选引用共享热预览与可靠待保存集，受这些源各自的既有预算约束，不复制整段历史
正文；候选引用数量不等于页返回条数。单次存储读取与页输出另受条目及预览字节预算约束，
验收分别记录候选引用、共享载荷和返回页，不能用返回 32 条证明只捕获了 32 个引用。
短存储读取后重新合入读取期间的新 revision、保存、终态与推测性内容释放事实。提交与
内存释放之间不能出现历史空洞，重叠按 identity/order/revision 收敛。保存交接和热缓存
淘汰不是撤回；真正释放的
推测性身份不得从旧读取引用重新进入页、初始／重同步基线或热缓存。
同一身份随后重新发布时，新成立的当前事实可以参与相应页的合并，但不能重新激活此前
已被释放的读取引用，即使重发后的顺序已不在该页边界内。
合并与缓存补种必须依据同一权威有效性证据，不能仅因曾持有一份预览就重新登记已撤回
身份。若有界发布连续性信息已不足以证明读取期间的事实，明确返回可重试 Busy，而不是
猜测删除、恢复旧快照或返回空页；不为读取保留无界撤回墓碑或启动执行 owner。
不存在的冷库可以返回空页；损坏、不可读、迁移失败与取消必须分别报告，不伪装成到头。

### 有界尾部订阅

订阅有独立身份与内容版本。initial 是与接收者登记一致的最新小页基线；next 同时至多一个
在途调用。初开可立即显示尚未落盘的已成立内容，不等待 writer 或 checkpoint。

后续批次以 identity/order 表达新增、原位变更与真实删除，字段仍使用 typed
Append/Replace/Remove/Unchanged；一次条目变更只提交一次内容 revision。批次 from 必须
等于该订阅已交付的版本，to 必须前进；内容 revision、订阅版本、saved、terminal 互不推导。
缓存淘汰不得产生删除当前消息的通知。保存确认只翻转同 identity/revision 的 saved。

每 Thread 热预览仍按最多 100 条及 8 MiB 约束；可靠待保存事实与活动引用另计其原有预算。
每订阅的基线、待交付变化及传输缓冲有界，不能通过保留订阅以来的全部消息满足连续性。
消费者落后到无法证明连续时返回显式新基线／重同步，不丢失后假称连续，不重放全部 token。
首字、终态、保存确认、字段删除与故障属于立即边界，普通正文复用固定合帧窗口；合帧
不得吞掉需要保留的终态事实。已退出热缓存的变化若不能连续交付，同样必须显式重同步。

### 展示预览

轻量条目包含稳定 item/block 身份、顺序、内容版本、必要展示字段、执行和保存状态、
省略声明及详情引用。工具参数、完整输出与原图不直接常驻每个 Message.metadata。
预览沿用每条不超过 256 KiB 的原始预算，展示摘要可更小；单页另受字节预算约束。

产品默认展示预览的正文总预算为 32 KiB，工具参数与结果各最多 4 KiB；它们与问答、
推理、原始记录等正文共同受条目上限约束。单次页的预览字节预算为 2 MiB，预算提前截页
仍返回真实的下一边界，不能把截页当作 EOF。静态身份与判别字段不得靠通用字符串截短
破坏；不可再缩减的结构超出预算时明确报告资源限制，不回退为完整大载荷。
预览额度约束实际交付的 UTF-8 字节；剩余额度充足时，空字段或短字段不能无故耗尽后续
字段的额度。计划确认的后端权威决定标记及其选项标签属于判别事实，不能因计划正文或
反馈的预览截断而丢失、变成另一种已解决状态；普通正文仍按预算省略并保留详情入口。
这些标签与答案来自同一条 typed 历史的内容域，不从已经清空动态正文的静态壳、当前
Plan 或待处理交互推测。对同一有界预览再次裁剪仍须保留判别事实，不能因首次裁剪丢掉
标记的识别依据；自由反馈、问题正文和描述仍可按预算省略。

### 预算计量边界

生产读取链使用 core 的统一预览驻留计量，页、热预览和订阅副本不能各自漏掉不同部分。
计量覆盖实际保留的正文 UTF-8 字节、静态 `meta` 字节、条目／Turn／字段身份，以及字段
槽位、长度声明和详情引用所需的保守结构成本；空正文与短正文的字段声明仍然计费。
这是一项确定性的资源准入估算，不是 HTTP／FRB 完整编码长度，也不是分配器 heap 或 RSS
的精确测量。结构成本的保守系数属于实现，不成为新的 wire 或持久化字段。

单条 256 KiB 上限覆盖上述结构与正文之和；正文还受产品 32 KiB 及工具每域 4 KiB 上限
约束，实际可用正文额度取这些约束的交集。不可缩身份、判别事实和字段声明自身已经超限
时返回 `Overloaded`，不能删字段、截身份或回退到完整载荷；自由正文可缩减时先按合法
UTF-8 边界缩减，保留总长与详情入口。权威计划决定标记先占用实际字节额度；若连这些
不可省略事实都无法容纳，同样报告资源限制，不靠无声超预算或改变决定维持成功。

core 向宿主提供 `ChatItem::preview_structure_bytes(&self) -> usize`，使产品裁剪复用同一
不可缩结构计量；最终有界条目仍由 core 校验。2 MiB 页与 8 MiB 热／订阅预算使用同一
总计量，不在 transport 再建立一套竞争的分页预算。生产 DTO 不新增只为重复计算 core
预算的字段，canonical 历史格式不变。

demo 没有 core 的 `meta` 编码，按自身 typed 表示保守估算静态结构与字段声明，并执行
相同的单条、页和连续性副本上限；不伪造 core 字节事实，也不复制 canonical 序列化器。
两个宿主的估算值无需逐字节相等，产品正文上限、错误分类、真实游标与 EOF 语义必须相同。
验收单列完整响应字节、canonical JSON 冷读解码瞬态和实际进程峰值；返回小预览不能
证明数据库未解码较大的单条原文，或整个进程恒定内存。

### 详情读取

详情请求绑定 item、field、revision 与 continuation；读取块默认 64 KiB，最多 256 KiB，
按合法 UTF-8 边界返回，continuation 为不透明游标而非 Dart 字符下标。内容变化导致版本
不匹配时明确报告并由用户重新读取，不把不同 revision 拼接成全文。完整内容可逐块读取、
选择与复制，不能把预览省略当成原文不存在。查看器关闭、条目切换或 lease 退役取消读取并
释放详情缓存；不在后台给每个可见历史条目自动读全文。

canonical ThreadItem 与历史原文格式保持不变。展示 DTO 不是新的持久化事实源，缺失或
无法解释内容时明确报告，不重渲染旧工具或用当前模型上下文补全文。
普通问答与计划确认历史保留 canonical 工具条目的 typed 问题、答案、状态和脱敏事实；回执按原工具
身份独立呈现，不藏入普通活动组，不从 pending interaction 队列或工具成功猜测回答。
摘要、详情、复制与辅助语义均遵守后端脱敏结果，历史迁移继续使用现有 v2 幂等事务。
计划确认使用计划专用回执，决策与修改反馈来自同一权威 typed 历史，不从当前 Plan 状态
推演；待确认时的计划工作区与历史卡去重遵循 [13](./13-plan.md)。

## 26.3 Live 与 History

Live 初始只显示最新小页，稳定消息原位更新，新条目向最新端追加。库反向列表的底端为
offset 0；应用不通过逐帧定位维持跟随。

用户主动离开真实底端时进入 History，冻结已展示的消息内容与结构。状态栏和新内容提示
可以更新，后台执行与可靠保存不暂停；最新内容仍由有界尾部基线观察，不保存待回放的
token、全文或无限事件队列。History 只允许通过分页前插更早消息，不自动裁剪另一端。
每个更早页展示其查询线性化时的权威事实；之后才发布的旧顺序条目也不补写冻结集合，
只提示后台更新，待用户显式换代后重新读取。History 不为将来回放积累尾部身份或正文。

只有显式“回到实时”或发送新消息才建立最新小页及新的展示代次。滚轮到达冻结集合的本地
底端不触发新代次，不跨越尚未显示的后台输出。重开会话从最新小页开始，不保存或恢复
跨会话像素锚点。尾部重同步在 History 中只更新连接与提示，不替换历史展示；Live 需要
新基线时采用同一种新代次语义，并明确显示重同步状态。

Live/History 是内容发布策略，不是滚动 owner。进入 History 的判断只观察真实用户滚动，
不能把 resize、惰性范围修正或详情布局变化解释为用户阅读意图。

## 26.4 原生组件与展示身份

固定使用公开 Chat、ChatAnimatedListReversed 与 InMemoryChatController，不替换库列表、
导入私有源码或维护 fork。历史回调 onEndReached 只查询并
insertAllMessages(index: 0, animated: false)；不接向新滑窗，也不在外层截获轮滚翻页。
短内容不足一屏时提供“加载更早”入口，复用同一分页动作。失败保留内容并可重试，EOF、
失败与取消必须结束 loading，不通过任意延迟或无关帧掩盖状态未收束。

原始条目身份来自 canonical item/block，GUI 展示身份与其分离：单项沿用原始身份，活动组、
连续图片组和同一模型 attempt 的重连组在当前展示代次分配稳定身份，不以首成员、成员 hash
或页边界重新命名。分页可以补充已有组；流式、终态与保存确认只更新相应成员与摘要。
展示项的增删使用公开 controller 操作，组内使用标准 Listenable 定向通知。
发送先切 Live 新代次，关闭库额外的发送强制滚动分支。

每代次有新的 Chat key、消息控制器与 keepScrollOffset:false 的标准滚动控制器；组件只在
初始化绑定控制器，不能仅替换 provider 值而沿用旧列表 state。应用拥有传入控制器并在旧
子树释放之后销毁。标准滚动控制器只用于库、Scrollbar、被动观察和诊断，应用不写 pixels
跟随或恢复；正常键盘、滚动条和嵌套输入仍使用 Flutter 原生滚动行为。

应用不直接使用 observer、每行 GlobalKey 测量、像素锚点、pin/settling、帧末预取、
ScrollPosition/RenderSliver 自研实现、轮滚倍率或高度估算补偿。先用无旧补偿的原生样板
验证此路线；库在新数据模型下若仍不能满足交互门禁，停止并报告能力缺口，不自动引入兜底。

## 26.5 展示、布局与内存

用户与助手正文、推理、工具、任务、交互和失败使用 typed 消息 builder。活动摘要紧凑，
Markdown 流式显示，选择与复制使用 Flutter 官方组件。工具详情与超大正文显式打开有界
内部区域或独立查看器；默认预览不因异步全文回包自动扩大历史行。图片先按需缩略图，
原图在查看器读取，不预热整段历史。

布局依父约束的逻辑像素自适应：阅读列保留最大舒适宽度，窄窗自然收缩，列表占导航、
输入和辅助面板外的剩余高度。不随窗口等比缩放文字、轮滚或正文，不因改窗自动回实时。

已加载 Message 的数量和必要预览随本次访问页增长，不宣称常量内存。后端查询／热缓存、
订阅缓冲、详情与图片缓存分别有预算；可靠保存不因显示缓存预算丢弃事实。显式回实时、
切 Thread 与 lease 退役释放旧展示集合，不为每个曾访问会话保留全文。性能证据区分请求
条数、原文解码量、实际载荷、Flutter heap、进程 RSS 与可靠输出预算。

## 26.6 transport 与关闭

HTTP 与 FRB 使用同一页／尾部／详情领域接口和转换。HTTP Timeline 页、events 与详情
共同使用 Session 内容源，不保留 GUI 热路径与纯 SQL 恢复的两套入口；旧 window/focus/
load/expand 操作回执接口及别名删除，并以破坏性 API 说明升级。

Client 首次 await 前登记 attempt、demand、查询及句柄所有权。页和详情响应只作用于其
捕获的 Thread／订阅／展示代次；旧 A→B→A 回包不能写新 A。retire 先拒绝发布并取消，
再等待内容泵、在途查询、sink 和句柄真正 close/join。失败保留 unresolved owner 和预算；
provider 销毁只取消自己的观察，不关闭跨路由资源。关内容连接不停止 Session、Turn 或
writer。存储迁移、数据与凭据保留继续遵守 [17](./17-studio-storage.md)。

## 26.7 D2 共享接口与升级边界

以下名称和语义是 Rust 内容源、产品协议及两个 transport 的共同边界，不是旧窗口的
兼容 facade。具体锁、容器、游标编码和通知算法由实现表达。

### core 内容能力

`pl_core::chat` 保留 `Session`、`WeakSession`、`ChatItem`、`ChatField`、
`ChatLifecycle`、`ChatHistory` 与生产／保存准入能力。`ChatItem` 的字段预览同时记录各字段
完整 UTF-8 字节长度；预览截断不改写原始长度、item revision 或稳定字段身份。
`ContentBlock` 继续承载共享不可变正文，详情块读取不得先物化整个前缀或剩余全文再截取。

| 能力 | 结果与约束 |
| --- | --- |
| `Session::page(ChatPageRequest)` | `ChatPage`：升序 `items`、`before` 游标及 `has_older`；请求只允许 latest 或 before，默认 32，显式 limit 合法范围 1..=100 |
| `Session::subscribe_tail()` | `ChatTail`：登记观察后取得一致的最新 32 条 `ChatTailBaseline`；冷历史补齐在锁外进行，并与等待期间发布的事实收敛 |
| `ChatTail::initial()` | 单次移交已捕获基线的所有权，含首屏 items、before 与真实 has_older；重复消费或未消费首帧就 next 明确报错，不再次查询或另行建立订阅；基线的 `version` 与 item revision、持久化水位无关 |
| `ChatTail::next(&mut self)` | `Result<Option<ChatTailUpdate>, ChatError>`；类型保证单消费者；错误不能变成正常结束 |
| `ChatTail::close(&mut self)` | 释放该观察的正文基线和 Session 引用；本体不派生后台任务，调用方先取消在途 future，再关闭或丢弃观察 |
| `Session::read_detail(ChatDetailRequest)` | `ChatDetailChunk`：稳定 item/field/revision、UTF-8 文本块、字段总字节数和下一 continuation；默认 64 KiB，显式块大小最小 4 字节、最大 256 KiB |

`ChatCursor` 表达严格 `(order, item_id)` keyset 边界；产品 wire 游标另绑定 Thread 并版本化，
消费者只能原样传递不透明 token。边界可以来自尚未保存的权威条目，因此新页游标不要求
其条目已经存在于 SQL，也不把数据库 applied-write 水位当作内容版本。旧 durable cursor
若仍被独立的 Turns 历史 API 使用，留在该存储边界，不作为 Timeline 的兼容输入。

`ChatTailUpdate` 只有连续 `Patch` 与明确 `Resync` 两类内容发布。Patch 的变更按身份表达
新增／权威条目、`UpdateItem` 和真实 `Remove`，不携带窗口索引。UpdateItem 保留字段级
Append/Replace/Remove/Unchanged、预期 revision、当前省略量与逐字段完整／预览长度等一次
提交的元数据；即使预览已封顶而正文继续增长，这些元数据也必须随 revision 更新。同 revision 的保存
确认是合法更新，不要求伪造新的正文 revision。退出热基线只释放订阅缓存，不发送 Remove。
同一 canonical revision 的预览完整度可以提升，字段因此可能 Append 或 Replace；预览
字节变化不等于新的 canonical revision。执行终态也不禁止后续可靠权威修订，字段 Append
只是一种差量编码，不能据此推断执行重新进入 streaming。producer 准入仍由 Session 负责，
读取端不重新猜测来源；消费者校验订阅连续性、expected revision、稳定身份／顺序与事实
不回退，不以旧窗口展开规则拒绝已准入的权威更新。item shell 的 Turn 关联允许随权威
事实更新，不把 Turn 关联误当作条目的稳定身份。
字段仍然存在但预览额度耗尽，不构成字段 Remove；保留字段身份、详情引用和真实总长。
若预览预算重新分配后无法证明连续更新不回退，应显式重同步，不把省略伪装成原文删除。
消费者结合原文总长与预览长度区分预算缩减和真实修订；更高 revision 的原文确实缩短或
字段确实删除时仍按权威变更原位应用，不能仅凭新字符串更短而一概拒绝合法修订。
Add 携带权威整条预览，不保证该身份从未被页查询加载，也不保证顺序在最新端。Live
消费者对已有身份按 revision、预览完整度和独立事实原位收敛，不等待一个未承诺会出现的
后续 UpdateItem；新身份按 canonical 顺序插入，不把旧身份追加成最新消息。不能证明与
已加载事实兼容时显式重同步，不回退内容或另存待回放正文。History 仍遵守冻结策略。
组合后的省略声明必须与逐字段实际预览相符，并继续满足产品预览预算；不能用某一输入
的整体省略量代替组合后的账目。无法同时证明字段完整度、账目和预算兼容时显式重同步。
尚未覆盖的更早范围不借尾部 Add 提前插入旧身份，以免在分页前缀中制造空洞；该身份及
后续 UpdateItem 不另存待回放正文，后续页查询读取当时的权威值。已覆盖范围内的新身份
仍按 canonical 顺序插入。Live 分页与尾部变化交错而无法证明合并兼容时显式重同步，
不静默漏掉已经纳入展示范围的事实；真实删除使行消失也不抹去已经覆盖的范围边界。
真实 Remove 是按 identity 自包含的幂等事实：即使身份不在尾部副本内，也必须交付删除或
显式重同步，因为消费者可能通过页查询加载过它；接收者本来没有该身份时删除为空操作。
没有实际交付 Patch 或 Resync 的内部通知只能推进 observed 水位，不能推进 delivered，
后续 Patch 的 from 仍以消费者最后真正收到的版本为准。

每观察的正文基线最多 100 条且不超过 8 MiB，只保留有限连续性信息，不另留无界事件日志。
首帧移交后不再永久保留一份旧 32 条首帧加上不断变化的 100 条连续性副本；runtime 与
bridge 的首帧缓存也在单次交付时释放，不通过多层 initial 副本绕过预算。待发送批次属于
独立有界 transport 预算，不是无限保留初始正文的理由。
若变化已越过可证明连续的范围，返回带原因和最新小页的 Resync。首字、保存、终态、故障
或真实删除在热缓存外变化时，也必须交付该事实或明确 Resync，不能以“本页无变化”跳过。
普通正文继续使用已有固定合帧窗口，不为每个消费者重新实现 token 队列。

详情 continuation 同时绑定 item、field、revision 和合法 UTF-8 边界；产品层增加 Thread
校验。非空块必须推进 continuation，空字段返回空正文且无下一块。不存在的字段与空字段
必须可区分；版本变化、非法 cursor、关闭和存储故障分别返回
类型化错误，不拼接跨 revision 正文。查询 future 取消不向展示发布部分结果；底层数据库
已受理的只读工作仍由现有连接池管理，不新增无人持有的查询任务。
详情冷读返回前也重新核对同 Session 的当前 revision；内存预览已在更高 revision、字段
被移除或等待期间发布变化时，不得拿较旧 SQL 正文满足旧 revision 的读取。

### 产品 DTO 与 transport

新的协议模块为 `pl_protocol::timeline_content`。`TimelineItem` 复用 canonical 的封闭
typed `ThreadItem` 结构来表达 **preview 值**，附带 saved、lifecycle、omitted_bytes 与逐字段
`TimelineDetailRef`（字段身份、revision、完整及预览字节数）。这个预览值不是完整原文
入口，不携带工具 output artifacts 或原始记录的完整大正文；这些正文有独立详情字段。
复用 typed 形状不授权向 Message.metadata 挂载完整 canonical payload。
详情引用的 revision 是其所属条目的当前 revision，不是字段独立修订流；条目推进时，
未变化字段也更新读取版本，保留该字段原有的总长与预览长度，不能留下必然过期的入口。

动态字段统一使用 `ThreadContentField`；在原有正文、推理、工具参数／结果和 typed 问答之外，
覆盖原始记录正文与工具 output artifacts，避免它们藏在静态 meta 绕过预算。
Dart 字段及问答子字段的身份按判别分支与逻辑索引使用值语义；独立解码的同值字段仍是
同一字段。详情查找、替换、删除及集合键不依赖 Dart 对象是否同一实例。
output artifacts 的开放载荷只在 canonical 映射／详情查看边界编码，不成为 reducer 的 raw
JSON 兼容入口。问题、答案、状态与 redacted 标记继续来自既有公开投影，不读取私有回执。
产物预览数组为空不等于原文没有产物；若相应详情引用仍存在，消费者保留按需读取入口，
不能仅以预览数组长度判断原始内容不存在。

| HTTP | 共享领域能力 |
| --- | --- |
| `GET /api/v1/threads/{thread_id}/timeline?before=...&limit=32` | `TimelinePageQuery` → Session 页 → `TimelinePage`（升序预览、before、has_older） |
| `GET /api/v1/threads/{thread_id}/timeline/events` | `TimelineTailBaseline` 首帧及 `TimelineTailUpdate`；SSE 事件为 baseline、patch、resync、error、closed |
| `POST /api/v1/threads/{thread_id}/timeline/items/{item_id}/detail` | typed `TimelineDetailQuery`，含 field、revision、continuation、max_bytes；返回 `TimelineDetailChunk` |

详情使用 typed 请求体而不是把带索引的字段 union 压进临时字符串路径语法。
每个尾部连接分配新的 `subscription_id`，首帧和后续更新都携带它；同连接 Resync 保持身份，
重连必须换身份。无 durable SSE replay，Last-Event-ID 不能当作可续读的事件日志，必须明确
建立新基线。SSE 待发送正文最多保留一个批次，并受上述字节预算约束；慢消费者恢复后由
core 判定连续性或 Resync，不在 transport 积累 128 份大正文。

runtime 的 `timeline_content` 是唯一 core → 产品预览／字段变化映射；HTTP 直接序列化该
结果，FRB 仅做机械 DTO 转换。`BridgeTimeline` 捕获同一个 Session 与尾部连接，提供
initial、page、next、read_detail、request_close、close；page/detail 不经过挂起的 next 锁。
FRB 的 initial 也只能消费一次；外部 initial 尚未消费就调用 next 返回 Conflict，不能因为
bridge 内部已从 core 取过首帧就绕过这道门。page/detail 不要求先消费首帧；关闭后调用
始终以 Cancelled 优先。同句柄同时调用两个 next 返回 Busy。
关闭先拒绝新调用并取消，再等待所有在途调用退出，
最后释放首帧、尾部基线和 Session；重复 close 不能提前确认。仅持内容订阅不 pin 执行
owner，不阻止其正常空闲退役，也不关闭执行 owner 或 writer。

错误沿用共享 `StudioError` 分类：非法参数／cursor 为 InvalidArgument，不存在的 item/field
为 NotFound，详情版本变化为 StaleRevision，关闭为 Cancelled，并发 next 为 Busy，预算
耗尽为 Overloaded，读取／损坏／迁移故障为 Storage。存储失败保留结构化原因与脱敏诊断，
checkpoint 栅栏未满足单独报告 Busy，不混同空库、EOF 或自动执行恢复。HTTP 与 FRB 不各自
猜测错误文本，损坏、不可读、迁移失败的原因不能在映射中静默丢失。

### 删除与不变项

- 删除所有旧 ChatView/ChatWindow 公共类型、focus、双向 load、expand、窗口操作回执及
  `/window` 路由；删除原纯 SQL Timeline 公开入口形状、Around/After 与整条全文读取入口，
  `/timeline` 只保留上述新查询契约，不接纳旧 query 或 cursor 别名。
- 保留独立 `/turns`、Turn 元数据及其 durable 历史用途；它不是 Timeline 的另一条正文源。
- 不新增派生 SQL 内容表，不变更 canonical payload 或 schema 版本；原文按页内条目按需
  解码，不扫描整个会话。单条大 payload 的临时解码成本必须在最终性能证据中单独报告，
  不能由“返回预览有界”推导整个进程峰值有界。
- 原始保存、v2 幂等迁移、普通问答回执补齐和脱敏安全点保持原有权威来源。

通知与取消复用当前锁定的 Tokio 1.53.3 watch 和 tokio-util 0.7.20 CancellationToken：
watch 仅保留最新通知值，不能充当可靠内容事件日志；通知不是状态，取消请求不是 join
完成。依据为 [watch 官方契约](https://docs.rs/tokio/1.53.3/tokio/sync/watch/index.html)
与 [CancellationToken 官方契约](https://docs.rs/tokio-util/0.7.20/tokio_util/sync/struct.CancellationToken.html)。

## 26.8 Client 与展示 lease 边界

SDK-only Client 的内容连接使用 typed `StudioTimelineConnection` 能力：initial、page、next、
readDetail、requestClose、close；同一连接捕获同一个 Session。现有 attempt、demand、
permit、唯一内容泵及 unresolved-close 所有权继续适用，但删除窗口操作回执泛型、
load/focus/expand 控制面与 anchor 恢复。page/detail 是有类型返回值的查询，不通过
“等待下一个窗口版本确认操作完成”收束。

内容连接只维护有界 tail 基线和连续性校验，Thread 状态观察不再携带一份决定历史展示
结构的 workspace.items。Client 不引入 Flutter、Riverpod、FRB 或新的运行时依赖。
当前 Dart 产品只需要真实 FRB 与 demo 适配，不因本次协议修改新建一套 Dart HTTP
transport；服务端 HTTP 仍完整实现 26.7 的独立公开契约。

只读 Timeline provider 仅暴露新的展示元数据类型，不保留窗口模型或兼容 provider；
此观察接缝在 Client 迁移时同步，确保 canonical 生成输入有效，生产列表与交互仍按
独立的界面迁移步骤替换。FRB／demo 不依赖 Driver 的界面投影：关停进度只经已有 typed
订阅交付，应用关停协调器记录其实际观察的进度和最终报告，不由适配层重复写 Driver 状态。
FRB 连接的首帧、尾部、页、详情及清理失败在适配边界统一为 SDK 的 `StudioFailure`，
保留类型化类别和可用诊断，不让生成的 BridgeError 穿过 SDK 暴露给 feature。

公共 Dart 模型沿用现有非负 int 表达顺序、revision、内容版本和 UTF-8 字节数；这些数值
不能混同各自的版本域或字符下标。FRB BigInt 转入前必须验证当前 Dart 平台能够精确表示，
不能静默截断或钳制；无法表示的有效 wire 数值明确报告 Overloaded。此约束只属于 Dart
适配边界，不改变 Rust u64 或 HTTP 契约，也不借本次迁移改写无关资源的数值类型。

拥有逐字段详情引用的呈现载荷先验证预览支配关系、账目与预算，再调用 SDK 同 revision
字段收敛。`ThreadItemView.convergeWith(ThreadItemView incoming, {required int omittedBytes})`
接收调用方已核实的合成省略字节数；不拥有字段总长的模型 helper 不自行猜测整体账目。

查询在首次 await 前捕获连接 attempt 与展示 scope，登记 pending-operation permit 和实际
future。scope 退役先拒绝新工作及迟到发布，停止后续详情块请求，再等待已经受理的查询
退出；不能用忽略 Dart 回包冒充 native close/join。取消／关闭失败或达到既有 deadline
时保留 unresolved owner、句柄和 permit，后续清理能继续等待同一工作，不创建替身成功。
普通观察者的取消不改变业务 demand，也不关闭 Thread、Session 或 writer。
已经确认退出的查询 scope 应解除其连接归属，不能积压到整个连接关闭才释放；仍在途或
清理失败的 scope 则继续保留真实归属与许可，供后续等待和清理。

`TimelineSessionOwner` 属于 app presentation，唯一当前展示为 `TimelineDisplayLease`。
每个展示代次拥有新的 `InMemoryChatController`、Chat key 与
`ScrollController(keepScrollOffset: false)`；公开给 view 的状态只包含模式、代次、
older cursor/loading/error、新输出提示及连接状态，不另附完整 rows/items/body 列表。
已加载预览只作为 controller 内 Message 的 typed 呈现载荷存在；无缓存的单条转换／
builder 可以保留，不保留 `TimelineRowProjector`、整表 rows/ids/versions 快照或全表 sync。
索引若确有需要只存稳定身份和位置，不持有另一套正文模型。

Client 的唯一泵交付 identity/field 增量；presentation 通过公开 controller 方法逐条应用，
页查询通过 insertAllMessages 前插。处理期间至多保留一个待消费通知或有界最新基线，
不能用未 await 的 future 链积累无限正文操作。消费者不能证明连续时显式按 Resync
处理，不以每帧比较全部已加载历史弥补漏帧。History 只更新提示与连接元数据，不向
已展示 Message 应用实时正文、结构或保存确认；分页也不抬高冻结展示的内容水位。
能够从增量证明是单独保存确认或空批次时，不制造“有新输出”。重同步及未提供变化差量的
权威整条 Add 可保守提示可能有后台更新，不承诺为提示对整条预览做深相等去重；也不为
区分提示另建正文副本或事件回放队列。

显式回实时（包括发送前）刷新内容连接 attempt，从新订阅的一致最新 32 条首帧建立
展示代次；旧 History 保留到新首帧成功，失败可见并可重试。采用新订阅避免将“页请求
返回前已交付的 tail”拼接成应用侧第二套恢复算法；重连产生新基线也使用相同代次切换。
自动分页和显式短内容加载共用同一个在途 future，异常正常收束并公开重试状态，不让
错误穿过库回调留下永久 loading。
分页 loading、错误和在途归属属于展示代次；新首帧成功后，新代次从自身的空闲状态开始，
不能继承旧代次的 loading 或错误。旧请求的迟到结果只在其原 scope 内收束。

demo 内容连接遵守同一小页基线与有界尾部契约，不把全部历史作为首次增量重新交付。
超出可证明连续性的变化明确重同步，不通过保留全量历史副本模拟订阅。
连接侧的身份连续性索引与校验工作同样有界，不为每次尾部交付重建全历史版本表。

发送继续由现有草稿 owner 同步冻结目标、payload、route revision 与 operation 身份，之后
才执行异步展示准备。其 submit 可以接收 SDK-only 的可等待 beforeSubmit 回调，由 app
传入 TimelineSessionOwner.prepareSend(threadId)：当前展示仍属于该 Thread 时，先按显式
回实时规则完成新首帧，再提交已冻结输入；失败保留草稿和原 History，不发送或伪造切换。
没有该 Thread 的当前展示时，不为发送抢占或重定向其他 Thread 的展示；命令仍使用原先
冻结的目标。回调不写 canonical 事实，不替代原提交回执、保存观察或附件所有权。
准备期间切换选择必须收束旧展示动作的等待，旧回实时动作以类型化取消结束，不能留下
永久 pending。仅选择变化不撤销已经冻结的发送：目标仍有效且已不展示该 Thread 时，
解除不再适用的展示前置，继续提交原冻结目标，不抢占新选择的展示。退出或真实准备失败
仍按已知未提交处理；旧动作的迟到结果不得发布新选择的状态。
展示准备失败发生在 backend 提交之前，属于已知未提交；不得标记 UnknownOutcome 或
永久封住该草稿的再次提交。保留原草稿与附件需求，同时按原 ownership 收束本次冻结。

视图通过真实子树卸载确认释放绑定；lease 退役先停止发布和查询，再等已挂载旧代次
解除绑定，最后销毁消息／滚动控制器并观察 stock operations stream 真正 done。
尚未挂载即退役的代次直接释放，不等待不存在的 widget 回调。挂载状态与 stream done
是不同事实；不能用 disposeRequested flag、sleep、固定帧数或 provider 销毁替代确认。
退役不等于已经释放；控制器尚存时发生的真实旧子树挂载仍须纳入卸载等待，已经释放的
代次必须明确拒绝可用绑定，不能静默忽略挂载后继续向子树交付已销毁的控制器。
AppGraph 关闭先发布无展示状态，使现存视图卸载，同时 Client 收束内容连接；重复关闭
等待同一释放结果，不能在树仍持有控制器时提前 ACK。

当前展示 lease 将原始预览增量组织为封闭的单项、活动组、连续图片组与重连组，并通过
Message.custom 呈现。每份预览只由所属展示项的成员持有，索引仅记录身份、位置或同一对象
的引用，不再保留一份 canonical Message 集合或逐帧重建全表。正文和独立回执划分活动边界；
同轮连续思考和普通工具形成活动组，图片读取只合并连续调用，其他可见活动结束图片组。
不显示正文的推理记账和文件引用不打断可见活动。

组的展示身份在代次内固定，分页前插只补充成员。合并保留较早创建的组；分裂时原身份
跟随锚成员（包括工具输出令展示类别变化），展开意图继承到分裂结果。删除锚成员后按新的锚位置
排序，ID 保持不变。结构与成员通知在所有成员归属和索引提交后发布，监听者不观察半更新状态。
原始 item 的身份、严格顺序、revision、saved、详情
引用与终态分别保存，不能由组摘要推断。普通追加和字段更新只访问受影响成员与相邻边界，
不扫描全部历史或为每个 token 复制整个组；折叠内容不构建，展开成员按需惰性布局。

模型重连提示在读取 DTO 中携带类型化的 attempt 来源及 retry/result 类别，由已有 canonical
身份派生；HTTP、FRB、Client 与 demo 使用同一语义。GUI 不匹配提示文案或解析内部身份。
同一 attempt 的提示归入当前代次同一展示项，摘要使用最新已加载记录的原文，展开保留逐次
明细；不同 attempt 不合并。所有调用与提示继续按原始时间和身份逐条持久化，不改变数据库
schema 或 canonical payload，也不将展示组写回后端。

稳定身份不要求保持相同 Dart 对象实例；去重优化不得因正文相同而吞掉 Turn、附件或其他
权威元数据变化。Driver 同时公开原始成员与展示组的只读诊断，原始顺序和完整性按原始成员
校验，不能用展示组数量冒充调用数量。
typed 普通问答、计划确认与等待继续以原工具身份独立展示，并划分普通活动组边界。
前端不再为工具摘要解析完整参数 JSON，默认
显示工具身份与有界参数／结果预览；完整字段在显式详情查看器读取。详情、复制和辅助
语义只消费后端公开脱敏结果，不回读私有交互回执。
typed 等待投影同样属于原工具条目的呈现载荷，与活动共享 [18](./18-studio-state.md) §18.8.1 的
事实契约，展示遵循 [19](./19-studio-ui.md) §19.9。它不新增等待消息缓存、历史扫描或控制器路线；
分页、尾部更新和重开继续消费同一保存的意图与结果，完整诊断字段仍按已有详情引用读取。
正文选择只包含所选内容域的文本；截断说明、加载详情按钮等界面提示不属于 canonical
正文，使用 Flutter 标准选择边界排除，不随跨块正文选择进入剪贴板。详情入口的点击、
键盘焦点与辅助语义仍保留；不通过改写复制结果或放宽正文 hash 来掩盖选择边界错误。

## 26.9 原生验收的只读展示诊断

Driver 只借用当前 AppGraph 的 Client 和 TimelineSessionOwner；绑定与读取诊断不创建
订阅、业务 demand、草稿、展示 lease 或正文缓存。每次请求同步读取当前 lease 的 stock
controller 与 typed 载荷，序列化后不保留投影。切换 Thread／代次后不能继续抓住旧正文。
非 Timeline 的工作区、计划、退出与远程资源生命周期诊断保持各自权威来源。
runtime 顺序的原生取证使用 Driver-only 有界记录器，被动观察已存在 Client Session 的公开
runtime read-model 发布；不创建 Session、不建立另一条 transport 订阅，也不改变业务 demand。
记录器只保存 Thread／Turn／attempt、发布 revision、观察 sequence 与轻量计量事实，不保存
Timeline 正文或整份工作区快照。登记与首个基线读取为同一同步边界，停止和退出只取消自己的
观察；最多保留 4096 个事实，溢出、观察异常、身份不符或缺少终态均显式失败。
当前 core 的执行期观察为 `live`，attempt 提交时清除 live 观察；验收分别证明同身份的多次
真实 Client 发布与递增 sequence，以及之后的显式清除。不伪造 authoritative 事件、终态
sequence 或计量值，不把无身份的 unknown 快照拼成同身份终态。快照轮询仅用于就绪，不能
代替发布回调证据；该证明不等于逐 token 的供应商原始事件或传输时延证明。

新的顶层 `timeline` 取代 `timelineWindow` 和 `workspace.timeline`，不提供旧字段别名。
它包含 `threadId`、`generation`、`ready`、`mode`、`connection`、`appliedVersion`、
`itemCount`、`itemIds`、`olderCursor`、`hasOlder`、`loadingOlder`、`olderError`、
`hasNewOutput` 与 `preparingLive`；其中身份与数量来自当前 controller，不从状态流猜测。
按需的 `items` 是同一批 Message 的轻量 typed 预览诊断，包含稳定身份、顺序、revision、
保存／终态、省略声明与逐字段详情引用，以及旅程需要的已脱敏正文、工具与附件预览；
不展开全文、不重新解析工具参数、不构造活动合并行或保留第二套 row 模型。
用户消息与工具输出的附件诊断均保持 SDK 公共附件的强类型边界，准确映射身份、模态、
文件名与字节数；不能因工具输出含附件而使整个只读快照失效，也不以字符串猜测模态。
文本条目另携带来自 canonical `ThreadTextItemStateView` 的 typed `channel`，序列化为
`user`、`parentAgent`、`commentary` 或 `finalAnswer`；非文本条目该字段为 null。
`kind == agentMessage` 不能替代频道判别，进度文字不计为最终回答。问答诊断始终携带
真实的 `isPlanConfirmation`，由同一公开 typed 问答的计划回执判别派生；待确认、已回答
与已取消均保留该判别，普通问答为 false。`planDecision` 保留该回执的权威决定，普通
问答为 null，不从当前 Plan、工具文本或字段缺失推测。

`timelineScroll` 只表达当前代次实际挂载的标准 ScrollController 几何：身份／代次、
`pixels`、`minScrollExtent`、`maxScrollExtent`、`viewportDimension`、`extentBefore`、
`extentAfter`、`atLiveEdge` 与 `isScrolling`。`atLiveEdge` 是反向列表 offset 0 的几何
事实，不等于 Live 模式；History 到本地底端仍是 History。删除旧 anchor、restore、pin、
settling、programmaticScroll、hasNewer 等恢复状态，不用固定假值伪装兼容。
滚动几何与 `isScrolling` 在诊断请求时直接读取当前 lease 实际挂载的标准 controller，
不由视图通知发布的旧快照代替。滚动结束通知与 activity／notifier 的状态提交顺序并非
同一时点；通知仅用于视图自身的用户意图处理，不承担另一份滚动几何缓存的更新责任。
反向列表在 offset 0 的 `extentBefore` 为零，`extentAfter` 可以仍包含全部更早内容；
贴底判定不能额外要求 `extentAfter` 为零。滚动条朝视觉顶部移动时 offset 增大，朝视觉
底部移动时 offset 减小；验收保留实际连续位移与同代次断言，不沿用正向列表的方向假设。
可见行位置与挂载数量由 Driver 在请求时观察实际 widget／render tree，不在生产建立
每行 GlobalKey、测量表、布局回调登记簿或每帧全表投影。
resize 验收分别确认所属原生窗口的实际尺寸与 Flutter 根布局已采用的尺寸；Timeline
子视口保留自己的坐标域，不能用其边距或底边反推整个窗口。侧栏、标题与输入区不属于
列表视口，可见行几何只承担内容位移证明，不承担根窗口尺寸证明。
已加载的消息身份与已挂载的行渲染对象是不同事实。验收访问已加载的离屏目标时，通过
正常滚动使其进入布局与可见范围；不能把等待帧当作访问进展，也不能仅因没有渲染对象
就推断历史尚未加载、身份丢失或必须继续读取更早页。

列表、canonical 消息、加载更早、分页重试、回到实时、详情查看／复制／关闭与图片操作
具有稳定 Driver keys。详情诊断只来自用户已经打开的查看器，区分加载、错误、累计字节
与结束；打开后在活动查询 scope 内逐块读取，关闭停止后续请求并等待已受理工作退出。
它不改变历史行预览，不为 Driver 额外读取全文。
查看器等待的是自己已经受理的读取 Future，不关闭展示 lease 的共享查询 scope。关闭
操作的完成边界覆盖关闭按钮、Escape 与路由退出；关闭后不再开始新块，迟到结果不再
发布正文或恢复复制能力。展示 lease 的退役与 AppGraph 关闭仍保留父级的真实 join 责任。
是否需要详情由同一字段的 `totalBytes` 与 `previewBytes` 判定。验收分别核对产品正文
共享 32 KiB、工具参数／结果各 4 KiB 的预览额度，不能以 core 单条结构加正文 256 KiB
上限替代；超过产品预览额度的正文须通过实际查看器读取与完整复制证明原文保真。
完整性证据须对照合成原文，而非只比较查看器与剪贴板两个实际副本；合法的快速分块
读取不要求每块之间产生可见帧。中间态是否被采样到只是观察记录，不能替代或否定
原文校验；由总字节数计算出的理论块数也不能冒充实际已读取块数。
跨渲染块选择的证明分别核对实际参与选择的渲染块数，以及整段剪贴板文本与 canonical
预览的精确一致性；渲染分块不要求在原文中插入分隔符或产生另一份“复制段数”。
验收报告字段缺失或类型不符须给出可诊断错误并收束资源，不能因索引不存在的字段 panic，
也不能用缺字段的默认假值把失败变成通过。分页与输入交叠须
记录输入发生时的真实在途事实，不能仅凭先创建分页 future 再发输入就宣称已覆盖。
宿主命令往返可能错过快速查询的在途窗口；该场景可在同一次 Driver 操作中调用既有
分页动作、核对实际加载状态，再经标准指针信号路由派发输入，并等待真实分页工作
收束。证据仍须区分输入与页面发布的前后关系，不延迟后端、伪造在途状态或以宿主
future 尚未返回替代应用事实；该验收组合不进入产品实现或增加滚动补偿。
字段身份 token 由共享 Driver key-values 边界统一格式化，视图入口与只读详情引用使用
同一规则，不依赖 Dart 类型名或 record 的 `toString()`。问答身份必须包含问题位置以及
header、question、answer 索引、option-label 索引或 option-description 索引，不能把
同一问题内的不同内容域合成一个身份；它不是服务端 continuation 或持久化字段。
活动展开／折叠跨流更新保持的证明，应读取 typed 内容 revision 或实际内容进展；推理
摘要、推理正文、工具进度与最终文本是不同内容域，不能只统计最终文本的长度就判定
整个流是否有新内容，也不能用重读同一快照替代更新证明。
Live 自然跟随的增长采样先于主动离底操作完成，并记录同一身份的多次真实内容进展；
之后的用户拖动、History 冻结与显式回实时独立判定，不能并发要求同一个展示代次既已
进入 History 又始终保持 Live。开始采样不能被无关截图消耗流式窗口，也不能以反复读取
相同快照、放宽原文校验、后端人为延迟或固定睡眠代替真实增长与模式事实。
查看器重试在同一仍有效展示代次重新取得活动查询 scope；连接 attempt 已失效不能永远
重用旧 scope。展示 lease 退役则停止读取并释放查看器缓存，不把旧详情自动迁往新会话
或新展示代次；版本变化也不能把新旧正文拼成全文。
已有展示内容时，重新连接、重同步与失败也须有紧凑的可见状态和重试入口，不能只写
诊断日志。重试连接不隐式把 History 切回 Live；明确的“回到实时”动作仍遵守原有新
首帧成功后才切换代次的约定，失败保留历史并可再次操作。

界面与只读事实迁移先冻结上述契约，随后迁移 Driver 旅程及 Rust 验收报告。旧 96 条
裁剪与锚点断言随旧能力删除；六尺寸真实位移、连续输入、身份完整性、错误传播和进程
回收的验收强度不变，不以字段更名或缺失诊断将失败变成跳过。
固定输入矩阵为六尺寸各 96 次 ±60、三个主要尺寸各 600 次连续输入／反转，后者合计
1800 次，不能按三个尺寸均分 600。深页读取记录实际已覆盖页数与 `hasOlder`，未读到
EOF 不宣称全历史已核验；冷开前分别确认 Turn 成功终态与可靠保存归零，不以空闲代替
成功，也不以执行完成代替持久化完成。
同一数据根的冷启动允许从无项目／会话选择的启动页开始；验收通过正常的项目、会话
选择与打开动作恢复目标，并核对仍是同一持久化身份。不能假定选择跨进程保留，也不为
使验收通过而引入选择持久化、自动恢复执行或新建替代会话。
