# 26 - 原子完成时间线与原生列表

本文是 Timeline 完成事实、统一读取、完成事件、Flutter 展示分组及读取预算的唯一权威契约，依据 [#220](https://github.com/ZR233/anywork/issues/220)。本文描述批准的目标架构，不以文档更新冒充实现或原生验收通过。存储升级归 [17](./17-studio-storage.md)，传输流控归 [07](./07-streaming.md)，客户端资源所有权归 [25](./25-frontend-state.md)，视觉与交互归 [19](./19-studio-ui.md)。

## 26.1 完成事实与唯一所有者

Timeline 只包含不可变的最小完成事实：已接纳输入、完整文本或思考摘要段、一次执行结果、一项确定文件变更、技能激活、交互回执、计划快照、压缩回执或终止回执。最小事实应可独立理解、标识与读取，不按 token、换行或 patch 行拆分。运行正文、参数生成、工具进度、活动计时、待决交互、当前计划和保存状态属于相应实时领域，不进入完成历史。

Runtime 依据可靠业务事实封口。文本只采用模型适配与 Runtime 确认的语义结束；没有独立 part-completed 事实时以最终 attempt 输出为依据，不按停顿、标点、换行或 UI debounce 猜测完成。无内容的等待不产生历史占位。中断时已冻结的保留文本须明确标记为中断内容，失败或停止原因另以独立终止回执表达，不重复附加到正文和工具组。

一次调用的启动收据和后台任务最终结果是两个不同事实。工具 A 完成、B 仍运行时立即发布 A，B 留在实时活动中；跨 Turn 后台执行不因 Turn 完成而变为历史中的可变成员。

Rust、数据库、FRB、HTTP、分页和 SDK 领域类型不包含展示 group ID、组边界、标题、members 或封口策略。真实 turn/call/来源身份及时间可作为发布时已确定的元数据；输入发布时未知的消费 Turn 不得后补修改。改变展示分组只影响 Flutter，不改变原子身份、数据库或 FRB。

核心层 `Session` 是完成集合、pending 与统一读取所有者，保持产品无关；业务封口与可变执行事实归 Runtime。HistoryStore 与既有 writer 负责事务、恢复和可靠预算。SDK 仅传递完成页及有限未交付批次；唯一 Flutter 呈现所有者持有当前已加载原子引用并决定分组，ViewState 不拥有 feed、Session 或查询句柄。

### 模型成员的可靠封口与交接

厂商已经给出独立、权威的成员结束事实时，必须按该成员封口，不能因为整个模型调用仍运行而继续等待 attempt 终态。例如 Responses 的 `output_item.done` 所携完整 message、reasoning summary 或 raw reasoning 成员，经模型层校验后可成为独立完成来源；通道切换、增量 block 关闭或单纯出现下一个 index 都不是等价来源。没有可靠成员结束事实的协议仍遵循本节的最终 attempt 输出规则，不猜测边界。

模型层先完成该成员的身份、权威内容、重复冲突、输出与 replay 预算校验，再向 Core 交付类型化的完成事实。该交付与可合并的实时 progress watch 分开：watch 只表示最新预览，不能承担逐条完成事实或充当接纳确认。交付使用现有模型调用所有权内的有界可靠通道；满载产生背压，等待不持锁，不增加平行历史库、通用事件框架或第二个模型调用执行者。

Core 在原调用仍运行时接纳这些事实，保留真实 attempt、恢复 generation、provider item 与 part 身份，立即形成现有不可变 effect/checkpoint 交接；不提前推进模型上下文、调用用量或 Turn 终态。Runtime 只沿原 prepared handoff、可靠预算和 writer 路径生成、发布并保存完成项，不能由模型回调直接写产品历史。完成通道的在途载荷及新 effect 必须由同一次调用已有的可靠输出准入承担；接纳前失败保留原责任，接纳后失败沿同一 pending 重试，不把内容移入无预算旁路。

模型最终回执再次包含同一成员时，按相同完成身份和冻结载荷幂等，不重新分配完成序号；冲突明确失败，不能改写已经发布的历史。后续模型失败、停止或恢复不撤销已经接纳的成员，原因由独立终止事实表达。调用结束，包括取消和失败，须先收束生产者并交接已接纳的成员，再撤销相应观察；恢复只能依据已保存的 effect/checkpoint，不重发旧请求来重建成员。持久化结构的升级与旧数据未知来源处理仍遵循 [17](./17-studio-storage.md)。

成员从 live 退出由 Runtime 同源完成交接决定，不由 progress 端提前删正文或由 Flutter 猜测。发布对应完成上界后才生成不再含该成员的活动快照，并沿已有 Activity Commit 与完成批次协调交付。已结束成员不得继续累积在活动元数据中直到撑满帧预算；修复此类累积不能靠提高帧上限、静默丢成员或减少输入规模。

## 26.2 身份、顺序与不可变性

产品完成项包含稳定 `id`、`append_seq`、可选 `source_effect_seq`、可选 `sealed_at`、冻结来源与强类型完成载荷。载荷没有 `streaming`、`running`、`queued`、`pendingApproval`、动态 elapsed、`saved` 或内容 revision。最终耗时、返回码、错误及稳定资源引用属于完成事实，可以保存。

稳定 ID 从业务来源及部件封口身份派生；相同身份且内容相同为幂等，不同载荷为契约错误，不 overwrite。一次 effect 可生成零项或多项，一段文本也可能由多个 effect 累积；`append_seq` 不等于 effect sequence 或执行 ordinal。

`append_seq` 在 Session 的短临界区中校验整批、分配并原子加入可查询集合时递增。后开始先完成的 B 必须排在之后才完成的 A 前，完成记录不得按启动位置插回旧历史。序号严格为正且不超过 SQLite 有符号 64 位范围，溢出明确失败；FRB/Dart 保持精确整数，不经 JSON double 转换。

`timelineEpoch` 标识完成集合的运行代际：进程重启或重建可能重用未落盘尾部序号时必须换代，不能只用 cursor 是否超过当前 head 判断有效。它不同于 Session/incarnation、领域 revision、活动 generation/revision 和传输 deliverySequence。迁移无法确认的原始 effect 或首次封口时间保持未知，不把最后修订时间、零或迁移时间伪装为封口时间。

## 26.3 内存可见性与落盘交接

Session 维护完成可见上界 H、已成功提交的连续持久化前缀 D，以及按序不可变 pending。Runtime 一次准备完整冻结载荷，Session 原子发布后整个批次立即可查询，事件生产者直接取得同形载荷；同一 PreparedEffect 再交现有 writer。writer 成功提交原有事务后推进 D 并释放相应 pending，保存 ACK 不产生历史内容更新。

分页、详情及 Rust 内部事件补发统一采用以下次序：

1. 在同一短锁内捕获 `timelineEpoch`、H 和请求范围内有界 pending 引用。
2. 锁外开启新的短数据库读，限制 `append_seq <= H`，不可复用捕获之前建立的旧 SQLite 快照。
3. 按身份与序号校验、去重、排序并按条数及字节预算裁剪；epoch 已变则拒绝旧请求。

若提交/回收发生在捕获后，读取仍持有不可变引用；若发生在捕获前，后开的数据库读已经能看见；两边命中只返回一项。不得先取走 pending 再等提交，不跨 await 持锁，不先 flush、不靠 Dart 二次查找弥补空洞。候选为 limit 加一等有界选择，不克隆全部 pending；同 ID 或序号不同载荷必须报错。

内部 after-range 起点不早于捕获的 D 时可只读 pending，latest 候选足够证明结果时也可走内存；旧历史允许数据库 I/O。“立即可查”指不等待本项落盘，不承诺所有查询零 I/O。此能力不是客户端实时补查循环。

pending 的条数和实际字节沿用可靠队列预算。保存失败保留已接纳完成事实、继续允许读取并报告独立存储故障；预算用尽在既有安全点背压，不能丢最旧项或无限增长。正常关闭等待 flush；尚未提交的 RAM 在崩溃后可能丢失，不能同时承诺不等待可靠写入和崩溃零丢失。

## 26.4 独立历史分页与冻结详情

历史查询通过 thread 与不透明原子 cursor 独立执行，不挂在 feed、ACK credit 或订阅 attempt 上。整个请求持有注册的同一 Session 与 epoch，不跨 await 重解析目标。显式存储 preparation 完成后才发布当前 reader；冷历史不激活模型、工具或执行所有者，不创建缺失历史库，不重放副作用。准入、身份和 durable checkpoint 栅栏继续归存储所有者；迁移失败、损坏、Busy 和真实空页不可混淆。

独立查询 scope 持有同一注册 reader 的强引用，覆盖分页、详情及在途打开；不能仅在单次 Future 内保留引用，让冷 Session 在两次查询之间被回收并更换 epoch。FRB 只提供该 reader 的薄句柄，关闭先封闭查询准入，再通过 Tokio 的任务跟踪能力等待已受理读取结算并释放引用，不另建历史缓存、读取队列或通用生命周期框架。

分页只支持 Latest 与 Before，返回升序原子 items、`beforeCursor`、`hasOlder` 和 epoch；默认 32 项，显式 limit 为 1..=100。游标绑定 Thread、epoch 和严格完成序号，不按 offset、展示组或 Chat Message 数推进。短页不自动等于 EOF；字节预算截页仍保留真实更早边界。客户端首屏由事件 Baseline 自带小页，不先 query 再 subscribe。

普通完整文本、结果说明与必要元数据直接随页面和完成事件交付，不让每条普通消息再读正文。超大日志、附件、明确折叠扩展或超预算正文可用冻结预览、准确总字节数与稳定详情引用。第一版允许存一份冻结展示快照；不能指向可 upsert 的执行行或会被覆盖的临时文件后宣称不可变。

详情绑定 record、field、不可变内容身份和 UTF-8 安全 continuation，无历史 revision。默认块 64 KiB，范围 4 字节至 256 KiB，非空块须推进；不存在字段与空字段分开，错误不伪装 EOF。取消不发布部分结果，关闭查看器或读取 scope 释放自己的缓存和在途责任；不后台预热全部正文或原图。已关闭智能体仍可按相同保存事实读历史，不要求绑定工作树存在，也不因此续跑执行。

## 26.5 完成页与传输预算

沿用有界预览入口：核心单项结构及正文合计不超过 256 KiB，产品常规正文总预览 32 KiB、工具参数与结果各最多 4 KiB，单页总预算 2 MiB；低于预算的普通正文完整交付。预算同时覆盖 UTF-8 正文、静态来源/判别数据、身份、字段槽位、长度声明及详情引用，不以返回条数证明内存有界，也不把预算估算等同精确 wire/heap/RSS。

不可省略的身份、来源和强类型决定不得截断。计划批准/修订/取消决定等判别事实不因正文裁剪退化；无法容纳不可缩结构时明确报告 Overloaded，不删字段、不偷偷超限。自由正文按 UTF-8 边界裁剪并保留准确长度和稳定详情入口。Demo 执行同样的产品条数、正文和错误语义，不复制另一套权威序列化器。

SDK 不保留 recent tail 或历史镜像；传输仅保留 credit 范围内未完成交付批次。实时内容、pending、完成页、在途帧、图片与详情各自受所属预算约束。已加载历史随访问页数增长，不宣称列表惰性构建使业务数据恒定内存；第一版小页、有界预览，不引入双向窗口、尾部裁剪或 around-anchor。

## 26.6 事件首帧、恢复与接纳

会话事件包含以下封闭语义，不以 HeadChanged 或 revision 通知要求客户端查询：

| 事件 | 语义 |
| --- | --- |
| Baseline | 最新完成小页、epoch、before/hasOlder、completedCursor 和各域初值 |
| ResumeStarted | 最新域快照与目标完成 cursor，不把最新页直接插入旧窗口 |
| Update | 完成批次及相应实时/当前态变化；正常在线的完成交接使用同一提交回合 |
| CompletedBatch | fromCursor、throughCursor 与实际连续交付的不可变 items |
| CatchupComplete | 已交付到的连续完成位置 |
| TimelineReset | 新 epoch 与最新小页，仅替换历史窗口、分页和分组派生 |
| DomainSnapshot、Failure、Closed | 所属域恢复或明确失败/关闭 |

初订阅先登记观察再捕获基线；建基线期间出现的完成事实由后续事件连续覆盖。同代重连携带唯一呈现 owner 最后实际连续接纳的位置，Rust 从完成集合按预算补发，不能跳到当前 head 或在 SDK 收到时提前推进 cursor。实时恢复与完成追赶公平调度，不让 token 饿死完成项；不重放旧 token、命令或另存全量 UI 日志。

SDK 的唯一消费 owner 准备整帧，唯一 presentation consumer 接纳完成原子，当前态 Repository 提交，再公开更新和标记 ready；各 owner 只写自己的数据。live 结束不能先公开、再异步等待历史查询。提交回合不等待数据库、Markdown 绘制或动画。连续 ACK、两帧窗口、分块 snapshot 和主动取消见 [07](./07-streaming.md)。presentation detach 必须取消未完成交付并退订，不能提前 ACK 或永久占 credit。

实时 long text 的 Append/Replace/Remove 与 generation/revision 仅由 SDK 对应 Repository 归约；失配从所属域事件 snapshot 恢复，不调用详情 query。完成历史完全不使用该可变协议。

活动正文只共享当前运行成员的 canonical `ContentBlock`，摘要不变但正文增长也须通知；已完成成员退出须与所依赖的完成上界协调交付，不回填已提交正文。工具输出沿原始 part 身份与顺序逐段传递：区域键为真实 `(call_id, part_id)`，元数据声明每段字节数，SDK 保留同形分段值，Flutter 用标准布局逐段展示；不得在每次变化时将多个 part 物化为累计全文或另存合并镜像。无输出事实与已观察到空输出保持区别。

活动来源可早于 Turn：以真实 `ActiveExecution.id` 标识准备、存储等待、准入等待与停止，`execution_id` 和 `turn_id` 分别按真实可用性填写，Turn 尚未建立时 `turn_id` 为未知，不借上一 Turn 或占位字符串伪造。进入 Turn 后仍引用同一 execution；跨 Turn 后台工具和待决交互用自身已知 Turn 事实。准备与存储等待不冒充等待 API，停止须来自真实取消事实。实时活动没有历史完成序号。

## 26.7 Flutter 两端纯展示投影

Flutter Model 先按原子分类/相邻分组，再映射 Flyer Message。用户输入和完整助手文本独立展示并分隔活动组；同 Turn 的相邻完成思考、执行和技能可组成一张 CustomMessage。问答、计划、压缩和终止回执独立；不解析 ID 文本或本地化标题猜来源。正文含多个附件仍为一个原子/展示项，内部复用媒体组件，不制造附件兄弟拓扑。

`projectAppend` 只观察现有尾组，最多返回一个边界替换和若干新增；`projectPrepend` 对首组对称。不拆旧组、不把新项拉回跨正文的旧组、不做成员迁移、全历史 diff 或通用重排。组内技能/工具配对及静态摘要只由本组稳定成员纯计算。

组初建选已见原子作为固定 anchorRecordId，之后两端扩展保留该 ID；单活动原子即使用组壳，第二项到来不换消息类型。页边界不是组边界，整页可能全并入首组而不新增 Chat Message，但原子 beforeCursor 必须推进；摘要只描述已加载成员，不冒称未知历史总数。

只用 Flyer 公共操作：首屏 setMessages 不动画，旧页 insertAllMessages 不动画，完成批次追加，边界组调用 updateMessage，其余旧消息不动。token、进度、计时与保存 ACK 不产生历史 controller 操作。Message 和呈现模型共享不可变原子引用，不另复制正文。分组策略在生命周期内固定；显式换规则只对已加载引用一次重新投影，不做身份/展开迁移框架。

分页和完成接纳串行提交；旧页返回时按当前首边界分组，不用请求时旧组覆盖已到事件。保留一个页面请求 generation、一个在途标志和连续完成 cursor，拒绝 A→B→A 的旧回包。历史 query 不抢 feed credit，也不冻结实时更新。

## 26.8 阅读、原生组件与布局

数据层没有 Live/History 两种模型。用户可跟随最新或阅读旧位置；阅读期间完成项仍追加或扩展尾组，回到最新使用 Flyer/Flutter 公共能力，不清 controller、不重开业务基线。首组前插、尾组扩容、组内阈值和缩放下的阅读位置需要原生证据；稳定 ID 不等于任意高度的像素保证。

继续使用 Chat、ChatAnimatedListReversed、InMemoryChatController、Builders、ExpansionTile、SelectionArea 和标准布局/滚动组件，不自写 Sliver、RenderSliver、像素锚点、逐行测量、滚轮倍率或持续帧末预取。真实滚动/度量/分页事件可合并触发不足一屏补页，不按帧轮询。普通空基线也挂载标准 Chat；键盘、滚动条、焦点与减少动画沿用 Flutter。

Markdown、回答和 Plan 卡片的视觉归 [19](./19-studio-ui.md)。所有正文服从有限宽度，优先使用现有 Markdown 的 wrap、公开 builder 与 Flutter 原生软换行；不新增解析器或文本修复算法。换行不改变原文、缩进或复制。工具参数/结果按字面代码显示，只有语义正文使用 Markdown。安全链接和授权图片边界保留。

## 26.9 只读展示诊断

诊断从公开状态派生，不建立第二事实源或控制业务。分别记录已接纳原子数、展示项/组数、原子分页及连续 cursor、完成发布至接收/Model/controller/首帧延迟、页查询延迟、build/raster、预览/pending/在途字节、实时全文发送量、数据库事务与写入量。

无新完成原子或分页时，token、计时和保存 ACK 的历史 controller 操作应为零；活动更新及展开的实时详情 query 应为零。区分原生、静态概念稿、模拟供应商、真实供应商及平台覆盖，不以日志采集或组件构建成功替代人工观察结论。
