# 25 - Repository、呈现状态与资源生命周期

Rust 持有业务事实；纯 Dart Repository 归并领域镜像；生成式 AsyncNotifier 编排功能呈现；
Smart Connector 绑定意图；Dumb View 只渲染数据。本篇是 Dart 层次、状态所有权、命令、
草稿与导航的唯一权威契约。可靠历史见 [17](./17-studio-storage.md)，实时协议见
[07](./07-streaming.md)，产品资源见 [18](./18-studio-state.md)，阅读与内容见
[19](./19-studio-ui.md)、[26](./26-timeline-content.md)，证明边界见 [24](./24-testing.md)。

本文描述已批准的目标架构，迁移是否完成以生成一致性、契约测试与原生验收为准。

## 25.1 分层与应用实例

```mermaid
flowchart LR
  W[Dumb View] -->|typed callbacks| C[Smart Connector]
  C -->|intent| V[Generated AsyncNotifier]
  V -->|public domain API| D[Repositories / Session services]
  F[FRB adapter] -->|typed events| D
  D -->|typed ports| F
  F --> R[Rust owner / Session]
  R --> F
  D -->|immutable domain state| V
  V -->|Freezed ViewState| C
  C -->|props| W
```

`anywork_client` 是不依赖 Flutter、Riverpod、FRB、Ref 或 BuildContext 的 Dart 数据／领域包。
不可变领域值使用 Freezed；必要的纯 Dart annotation 与代码生成依赖不破坏无 Flutter 边界。
运行时对象、资源 permit、任务与连接不是 Freezed value。FRB 生成 DTO、native handle 与
生成异常只存在于 adapter，进入 Repository 前转换为 typed 领域模型或错误。

数据包按配置、目录、模型、额度、会话、草稿、模式、资源和更新等真实领域组织 Repository。
每个 Repository 封装本领域 reducer、查询与写入，不通过一个巨型 Client 暴露全部 transport、
可写 store 和命令对象；不增加一层仅转发旧 facade 的 Repository。应用只消费分域公共入口，
领域内部 reducer 和可写 source 不对外导出。领域值只保留一条 canonical 公共路径。

Flutter 按 workspace、conversation、settings 的功能划分呈现。每个功能区分 Screen／Connector、
ViewModel、ViewState、View／Widget；数据／领域层已经位于独立 Dart 包，Flutter 侧不为目录
对称再建一套同构 Repository。公共视觉组件、格式化、platform、adapter、diagnostics 各自归属。
功能不穿透另一功能的私有 ViewModel／State，也不让 diagnostics 反向依赖功能内部实现。

应用 composition root 只装配领域实例、adapter 与展示资源，并协调 bootstrap／shutdown，
不承载各领域业务方法。每个应用实例有自己的 Repository、操作登记、草稿、资源 registry 和
展示 coordinator；禁止 module-level 可写业务 Map 或跨 ProviderContainer 共享这些实例。
原生库的进程初始化不授权共享两个应用实例的观察、句柄或草稿。

## 25.2 唯一写入与职责

| 事实或资源 | 权威 owner | Dart 唯一 owner | 身份与结束条件 |
| --- | --- | --- | --- |
| 配置、catalog、目录、资源状态 | Rust 领域 owner | 对应 Repository reducer | resource key + owner epoch + revision |
| 执行、交互、上下文、指标与计划 | Rust Thread 的唯一投影 | 分域会话 Repository | Thread + facet + feed generation；无正文副本 |
| 正文与 saved／terminal | Rust Session | 有界内容连接与唯一归并入口 | subscription + 内容版本；查询版本独立 |
| 当前业务工作区目标 | 应用意图 | Workspace session coordinator | 目标 generation；旧动作不能重定向新选择 |
| 页面与 Settings 导航 | go_router | 路由 owner | 路由；局部 tab 不存第二份全局导航状态 |
| composer 文本、路由与附件引用 | 逻辑草稿 | Draft service + 附件 ledger | DraftStamp + OperationId；显式转移或放弃 |
| 账号／模式等页面编辑 | 未提交的编辑会话 | 对应 AsyncNotifier ViewModel | editor key + draft revision；明确结束编辑 |
| operation 结果与水位 | Rust mutation / Dart operation registry | 操作记录 | OperationId；不随 observer 消失 |
| pending／错误／最新意图呈现 | 功能呈现 | ViewModel 的 Freezed state | target + operation；不写回 canonical |
| 已加载 Message 与 UI 控制器 | 当前展示 | 展示 coordinator 的 lease | Thread + 展示代次；子树解绑后释放 |
| composing、焦点、动画、局部展开 | Widget | UI Controller | draft identity / reading generation；Widget dispose |

canonical reducer 不混入页面 pending／表单错误。命令回执中的权威数据和推送事件进入同一
reducer，旧 operation 仍可结算自身事实，但不能清除较新的呈现意图。不存在成功后聚合回读、
第二份可写 canonical、第二选择控制器或第二附件账本。

多字段保存如仍由多个native字段命令完成，就保留每一步独立结果、部分成功和未开始项，
不伪造父事务receipt或回滚。字段意图在受理前完整冻结并归领域owner；页面销毁不丢已
排队步骤。一次真实成功后的同步失败与不确定是否受理分别呈现，不能根据错误code或文案
决定自动重放。native提交阶段须提供typed结果证据；adapter不把任意Bridge异常当未受理。

Interaction编辑器以Thread、投影incarnation、interaction ID和revision为完整身份，读取
进度、问题游标、答案/理由和反馈归同一VM；Plan阅读组件不另持一份回应草稿或操作记录。
键盘和按钮共用VM提交准入；读取完整不收紧原有空答案语义。Mode图形、JSON原文、校验和
undo/redo同属一个编辑VM；图形Controller只管理UI坐标/交互并提交typed编辑意图，不拥有
第二份可保存文档。异步保存仅更新它冻结的编辑基线，不清掉期间产生的新编辑。

## 25.3 身份与版本域

- ResourceStamp 由 ResourceKey、OwnerEpoch、Revision 组成，只在相同资源与 owner 内比较。
- Feed identity 表示一次订阅；可靠数据基线与 delta 使用该 feed 的连续性水位。
- DeliverySequence 只标记传输已交付前缀，用于归还 FRB 在途额度，不是业务版本或持久化确认。
- AttemptId 是一次异步绑定身份，不能替代 owner epoch；展示 generation 也不能替代业务身份。
- OperationId 在首次 await 前生成，未知结果不换 ID 自动重放。
- DraftStamp 标识逻辑草稿与字段／项目 revision，不能用页面版本代替。

配置、模型目录、账号模板与模型 route revision 各有 owner。route CAS 不是通知序号；
页查询不推进尾部订阅版本；saved 与 terminal 独立。epoch 更换必须建立新基线，旧 owner
的 observation 不满足新 owner 的 receipt，反之亦然。数值转换保留精度与单位，不能钳制溢出。

## 25.4 观察、导航与需求

领域观察同步登记接收者并返回登记时的当前值；检查当前状态与注册 predicate 之间不能 await。
观察接口只暴露 read／observe，不暴露 publish 或 reducer setter。观察 lease 只拥有自身的
listener 和预算，取消它不能关闭底层会话。latest-value 只用于可覆盖的状态；可靠事件不能
套用 pause 后只保留最新一条的语义。

Timeline 的状态观察与正文交接是两种能力。只读状态观察用于连接状态、诊断与可覆盖的领域
镜像，不承担展示正文的可靠交付。内容服务同步登记唯一的可等待正文消费者，返回只拥有自身
登记与在途回调的 lease；登记返回前不重入回调，重复登记明确拒绝。消费者重新接入已有需求
时建立新基线，不重放最后一条 Patch。如果当前 attempt 尚未开始消费首个 baseline，新消费者
可以承接这个已登记 opening 的首基线，不为同一份未消费基线重复创建句柄；一旦基线已开始
归并，重新接入必须退役原 attempt 并建立新基线。关闭封闭消费者准入，不返回无工作可收束的
新 lease。解绑消费者不改变业务 demand，不清草稿或关闭 Session。
没有展示消费者时可以继续归并领域事实并确认数据，但不积累供未来界面重放的正文队列。

Session 可用性、资源不足与恢复通过同一真实 owner 的 typed 状态发布。ViewModel 登记时立即
消费返回的当前值，不等待下一帧，不用页面跳转、菜单重开或局部 refresh 补漏。

业务 demand 由 Workspace／Session coordinator 与领域资源服务管理。进入 Settings、切标签、
Widget 暂停不改变当前会话内容 demand，不清新会话或 Thread 草稿。显式切 Thread、归档项目、
放弃草稿与应用退出分别结束自己的需求。Provider keepAlive 不替代 native 资源所有权，也不能
让每个曾访问会话永久保留正文；owner、观察者、查询和镜像均受预算限制。

route 与当前业务目标有不同职责，不各自维护可写 selectedThread。路由若携带业务 ID，只将
它传给唯一 activation 入口；旧异步 activation 结果不反写新的路由或目标。局部 TabController、
焦点和菜单状态不放入跨页面业务 provider。

## 25.5 Session、feed 与关闭

实时状态与正文均消费 [07](./07-streaming.md) 的 typed push。内容连接提供 events、page、
readDetail、requestClose、close；没有 Dart initial/next 轮询泵。Rust 内部的异步事件等待不是
接口轮询。状态、指标、内容按各自版本域观察；某一 feed 恢复不能把另一 feed 的失败标为 ready。

首次 await 前登记 attempt、demand、原始 open Future、候选 handle、查询、取消、close/join
与预算。句柄返回后立即归属于原 attempt；每次 await 后核对 Thread、attempt、generation 和
retired。页、详情与 frame 的迟到成功、失败和 finally 只能结算原身份。

Repository 完成 typed 转换与领域归并后确认 delivery prefix；需要顺序应用内容的展示接缝还要
完成有界交接，不能在未 await 的 future 链中积累正文。ACK 不证明 operation observed、effective
或 durable。内容缺口只重同步受影响连接，不重放业务动作；History 保留已有展示，新基线不能
偷偷替换冻结消息。

同一内容连接至多一个在途正文消费回调；转换、连续性归并或展示写入失败均不 ACK。等待回调
后仍核对原 attempt 与消费者代次，只能确认原 handle。consumer lease 的 requestClose 同步
封闭新回调，close 等已经受理的回调结束；回调不能等待自身所属 lease／Session 的 close，
以免自等待。展示服务的可等待边界只包含消息写入与错误收束，不等待布局、绘制或动画。

retire 先封闭发布与新查询，再广播取消和 requestClose，随后等待 producer、sink、查询、
open 与 handle 的真实 ACK。失败或超时保留 unresolved owner 和 permit，不清容器伪装完成。
关闭内容 feed 不关闭 Rust Session、Turn 或 writer。容量不足只在真实释放后恢复准入，不轮询。
取消 native、等待 stream 结束、查询退出与正文回调收束可以并行推进；不能先等回调结束才发
native 取消。typed close 报告必须属于原连接；只有 native Clean 且 Dart 已登记工作全部结束后
才 dispose opaque 和释放 permit。Unresolved 保留完整 typed issues、原 handle 与资源 owner。
进行中的清理请求共享同一次真实收束；可重试的 Unresolved 不能被已完成 Future 永久封住。
显式重试只继续原 owner 的未完成清理，不新建连接、不重放业务命令，也不清除尚未解决的
诊断。已证不可恢复的终态故障保持明确的不可重试分类，不能仅改标签后宣称 Clean。
原始错误的 retryable 与清理动作能否恢复不是同一事实：关闭报告保留原始 typed 诊断，并
分别表达继续等待原工作、显式重试原清理调用或不可恢复终态。不能因为原异常标为可重试，
就假定第三方 stream 的取消操作具有重试能力；也不能因此丢弃原始错误分类。

## 25.6 ViewModel、Smart 与 Dumb

页面与交互 VM 使用生成式 AsyncNotifier；build 可登记只读观察或执行必要读取，不执行
提交／写配置／自动重放。同步、值相等的纯 selector 仍用派生 Provider，不为类型名称堆叠包装。
ViewModel 只依赖领域公共能力，不认识 Widget、BuildContext、FRB、SQLite 或具体 adapter。

Freezed ViewState 表达可渲染数据、编辑意图、校验及按 target／operation 区分的操作呈现。
首次无数据可使用 AsyncLoading／AsyncError；有 last-known 的重连、局部保存失败不让整页
变成空白。不要用 AsyncValue 与平行 isLoading 表达同一个状态。领域同步错误与页面操作错误
分别表达，不能把 unknown 改成空值或零。

图片展示工具产生独立的图片卡片呈现项，只派生所属调用、typed 附件和参数中的展示文案；
图片字节仍由 Thread 附件缓存按身份读取，呈现层不缓存字节，也不因卡片存在而改写工具条目。
活动、图片与重连的 GUI 分组由唯一展示 lease 派生，不改变后端逐条保存；组内定向观察与
展开意图不成为第二份正文缓存。正文归并、消息集合及显示预算以 [26](./26-timeline-content.md)
为准，不恢复旧 Client 的正文副本。

编辑 VM 在数据更新时只推进该目标的 canonical 基线，保留未提交输入；不能每次 invalidate
重新初始化而丢 dirty draft。提交在同步阶段冻结 payload／目标／revision，旧完成不能清新字段。
keepAlive、family key、保留与丢弃规则按编辑会话明确；不把永久缓存作为“防止丢状态”的方案。
模式 JSON 与图共享同一 Freezed 编辑状态和最多 64 次撤销／重做历史；解析、校验或保存失败
保留输入，graph controller 只拥有坐标及交互投影，不成为另一业务 owner。

Smart Screen／Connector 用静态 ref.watch／select 观察 VM，用 ref.listen 或 typed action result
执行导航、对话框和提示；不直连 transport 或可写 store。Dumb View 只接收 immutable props、
UI-only Controller 与 typed callbacks；不得收 Ref、Repository、Client、native handle 或 provider。
Dumb 可保留焦点、composing、局部展开及动画，不做业务查询或重试决策。

速度、上下文与稳定状态消费各自小型 state／值相等 selector。高频速度更新不携带 plan、
workflow、catalog 或正文，也不使这些消费者重建。页面级 VM 不持有第二份完整 Message 列表；
渲染、controller、lease 与 Live/History 以 [26](./26-timeline-content.md) 为准。

## 25.7 命令、观察与效果

领域动作接收 typed intent，立即冻结目标、expected revision 与 OperationId 并登记只读
operation ticket；UI 不能修改其 reducer、permit 或自动重放。相同资源冲突写串行，不同资源
可并行；停止不排在长写入 FIFO 后，分页／详情不占配置写 lane。

CommitReceipt 至少携带 OperationId、Applied／NoChange、目标 ResourceStamp 和 effect point。
Accepted、AwaitingObservation、Observed、Effective、Durable 独立。模型配置对 next Turn／
future Session 生效，不代表正在执行调用已切换；durable 只由真实保存确认推进。

身份回执按 [18](./18-studio-state.md) 的 Turn／interaction predicate 观察；不能空目标自动满足。
输入提交的 durable 匹配原历史输入身份、接受序号与原生请求摘要，不以任一 Turn 的 saved
或 terminal 替代。原索引仅在输入离开Pending后写入，未取得证据时保持未证明，不伪造
提交即持久化；其证据只针对输入身份，不承诺该输入未来全部输出已保存。真实storage持久化
通知只触发有界按需身份读取，不作保存证明或轮询；关闭等待该读取真正结束。
操作 registry 保存每次真实结果，latest intent 单独标识；页面 overlay 不再混放在配置 canonical state。

Rejected 表示明确未受理；UnknownOutcome 表示可能执行但缺少确定结果；SyncFailed 表示已知
结果的观察失败。未知结果不自动重放。只有已知冲突／缺口／明确重试才局部 resync；成功不
readStudioState 或聚合 reload。错误保留 typed code／correlation 与原始 cause，不用文案推断。

账号模型阈值编辑保留原始输入、防抖和最新意图。有效输入和恢复自动进入同一
账号原子保存；领域层在串行 lane 内从最新 canonical account 构造变更，CAS 重试也重构。
其它模型覆盖，包括在线目录撤下的成员，必须保留。离开前把已产生的有效意图交给领域层，
已提交／排队操作参与应用退出 join；旧响应不覆盖新输入或清新 pending/error。

原始阈值覆盖由配置 revision 所有，最终上下文解析策略由 catalog revision 所有；Rust 配置
owner 在同一锁内读取两者，影响策略的配置与目录更新推进目录水位。Repository 独立合并
两个水位，只接收模型层解析的可用性、硬输入容量、最终压缩阈值与调整原因，不从容量、
最大输出或原始覆盖重算策略。配置旧响应不能回滚新目录策略，撤下模型的原始覆盖继续保留，
只在 Rust 显式写边界归一化。输入无效不提交，已知失败允许显式重试；未知结果不伪造成功。
空闲会话消费当前 catalog 结果，在途请求与历史保留各自冻结绑定；设置返回立即显示 canonical。

手动压缩通过会话领域动作进入与自动压缩相同的准备、提交、计量和持久化路径，不构造隐藏
用户消息。ViewModel 只呈现 canonical 可执行资格、操作进度与错误，空闲且有可压缩历史时
发起一次请求，重复意图合并或拒绝；后端重查准入。压缩失败保留原错误，成功由 context
feed 更新当前读数，不用聚合刷新或本地估算阈值补偿。

### 25.7.1 账号用量需求

额度事实只由 AccountUsageRepository 归并；同账号 ID、usageQueryRevision 与 owner epoch 的
并发自动／手动查询去重，不同查询身份的旧结果不清新 pending 或覆盖新结果。

Usage ViewModel 管可见需求与本轮已尝试身份。首次可见为当前身份分别发起检查，每个结果立即
呈现；可见时只补查新增／变化身份，隐藏时不产生新自动请求，重开只补未尝试或失效身份。
失败也计入本轮已尝试，不因 rebuild、名称／catalog 更新或默认值变化重试。显式刷新可以新尝试，
刷新全部复用单账号能力。不要在 Widget build 中发请求或保存回调中等待全部额度。

已受理查询由 Repository 持有并参与退出 join；页面销毁不丢在途任务。删除账号结束需求，
迟到结果不得复活删除项。两个应用实例不共享请求、结果或已尝试集合。查询身份由 Rust 所有，
不暴露凭据或其哈希，定义见 [18](./18-studio-state.md)。

## 25.8 草稿与附件

StartDraft 与 ComposerDraft 具有独立逻辑寿命。freezeForSubmit 同步冻结 DraftStamp、
Project／Thread、正文、mode、workspace mode、完整 route 和附件 ID。新 Thread 直接携带
冻结 route，不先保存全局默认再回读；已有 Thread 带 observed route revision。

submitting、accepted、observed、durable 均关联相同 DraftStamp 与 OperationId。提交期间允许
继续输入，旧 ACK 仅清理属于该提交且 revision 仍相符的字段。TextEditingController 保留
composing／selection；只在逻辑 draft 改变时替换，普通 state 更新不反复重写 controller.text。

新会话环境准备属于冻结提交的临时状态，由草稿／提交服务按 `inputId`、项目及提交身份
维护唯一事实镜像，Composer ViewModel 派生卡片呈现。Settings 往返或观察销毁不取消
创建命令。阶段来自同一次 typed 创建流，成功／失败终态只结算一次；终态前断流保留
UnknownOutcome，不自动重发。旧提交的进度和 finally 不覆盖新尝试或较新的草稿，成功结果
仅在导航意图仍属于原提交时自动选择新 Thread。成功移除准备镜像，失败保留原阶段和原因；
准备信息不成为目录事实或聊天历史，也不承担取消与工作树资源释放责任。

附件 ledger 分开持有逻辑草稿引用和冻结操作引用；成功仅转移冻结引用，较新草稿仍引用的
附件继续有效。最后 owner 释放后才 native 删除；失败保留 owner、诊断与预算。未知结果保留
冻结引用，不能因页面退出、放弃另一个草稿或 orphan sweep 删除。clipboard 暂存、drop 回调
借用和迟到 admission 都由明确 owner 收束，不持有平台临时路径到回调结束之后。
关闭过程等待在途创建和清理，不以销毁观察适配代替异步资源回收；可靠附件与旧数据保留
规则见 [17](./17-studio-storage.md)。

## 25.9 启动与应用退出

bootstrap 由应用生命周期明确发起，成功／失败由唯一启动状态发布。首个目录／catalog 基线
到达前的失败包含 typed code 与 correlation，不困在 Widget 的局部等待标志；显式 retry 不
创建第二套初始化。启动后局部目录失败保留可用 shell 和最后有效数据。

手动更新的操作与准备任务归更新领域服务，请求同步发布 pending，ViewModel 只编排并呈现，
页面不持有准备任务。已有后台下载时复用同一次准备；准备操作与进度流真实完成后，才把更新后
重启意图交给同一退出协调器。首次退出固定普通退出或更新后重启意图及绝对期限，应用 close
幂等并复用首次 future；后续请求只加入，不重新启动、延长期限或改变意图。

退出先封闭业务与编辑生产者，加入已受理操作；同时发布展示无绑定并卸载路由子树，不能等全部
close 完成后才解绑。独立 session、feed、update 和附件任务并发取消，在首次期限内等待真实
完成及展示 lease 的释放确认，随后才销毁 UI 控制器。尚未解决的任务与资源出现在 CloseReport，
不能释放未确认的 permit；provider container 与 opaque dispose 位于真实异步收束之后。

退出结果分别承载关停报告与安装交接结果；安装器启动失败不能改写可靠保存的结论，也不能
被关停 Clean 隐藏。更新退出先在原期限内恢复既有主窗口，确保托盘隐藏时提示仍实际可见。
界面显示更新版本、停止会话和保存提示；关停失败与安装交接失败均在
首次退出的剩余期限内留出一次渲染和最多 1.2 秒阅读时间，随后按既有退出期限结束。

退出提示在 `MaterialApp.builder` 内替换整个 Router 子树，促使当前及被覆盖的页面真实卸载，
再由原展示 owner 等待 lease 的释放确认。被 Settings 覆盖的聊天页面可能因 Riverpod 的
`TickerMode` 暂停观察；不得依赖隐藏页面收到状态刷新才能退出，也不得在子树仍挂载时
提前销毁 controller 或伪造释放确认。退出提示与应用 owner 位于 Router 之外，持续负责
进度、失败提示和同一次有界关停。

Dart CloseReport 在 Rust finalizer 前并入 externalIssues；只有真实 ACK 和可靠保存确认后才可
报告 Clean。超时不另起期限，不在 runtime 宣布 Clean 后追加失败掩盖提前释锁。原生进程退出
总期限与 Windows 托盘隐藏语义以 [19](./19-studio-ui.md) 为准。

## 25.10 验证、依赖与删除项

验证以 [24](./24-testing.md) 为准。纯 Dart、adapter、VM、受控路由、native FRB、Driver 和平台
进程证据各有边界。AST 门禁检查 Dumb／State／VM／adapter 依赖，反例 fixture 证明门禁会拒绝
违规；编译通过不能代替状态时序、资源释放和用户能力验收。

迁移后删除巨型 facade／巨桶导出、公开可写 store、旧观察转发链、第二份选择／附件账本、
聚合 StudioState、Dart next 泵、旧 API／路径／provider 与兼容别名。领域模型、Freezed、FRB
和消费者通过统一生成入口同步；不能手改生成代码或保留旧 barrel 掩盖孤儿产物。

统一 `generate-gui` 同时拥有应用与纯 Dart 领域包的生成边界：各自在自己的 package 目录运行
官方生成器，`.g.dart`／`.freezed.dart` 都纳入 canonical 文件集合与内容比较、行尾规范化、
格式化和孤儿清理；应用另含 FRB 与 l10n。移走手写输入或删除 part 声明必须同步移除旧产物，
不能依赖开发机的 build_runner 缓存才能发现孤儿。生成失败与 canonical 变化必须传到最外层。

领域包运行依赖仅精确许可已选定的 `freezed_annotation` 公共入口；生成工具为 dev dependency。
manifest 及 AST 许可不能因此放开其它第三方运行依赖、Flutter、Riverpod、FRB 或 annotation
包的私有路径。两包依赖快照均为 canonical；检查与 `build-gui --check-generated` 使用已审
lockfile，允许同步缺失缓存，不重新选择版本或改写 lockfile，也不从 SDK 安装目录执行命令。

## 25.11 模型目录一致性

目录发布完整成员与后端计算的类型资格。所有会话、Mode、系统角色与 Agent 使用同一公共
模型查询；GUI 不另算能力、预算或默认值，不满足资格的既有选择保留并显示原因，不自动换模型。
目录与配置 revision 独立，账号参数变化只更新受影响路由，旧响应不能回滚新目录。

模型 key 使用 account ID＋model ID；显示名不是身份。统计先按该 key 接收 canonical 汇总，
effort 是组内细分，发送／返回模型仅是冻结诊断；未知历史身份不能由当前目录补写。
账号模板只负责创建默认值，不参与已有账号或历史统计身份。

## 25.12 远端目录查询资源

`RemoteRepository`监督远端目录查询，每个`RemoteDirectoryQuery`持有自己的游标、已接纳
请求和清理责任；typed listing的`nextCursor`是唯一续页依据，不从偏移重新扫描目录。
目录选择器替换当前页，换目录、切换服务器或销毁时由查询owner释放旧游标，以请求代次
拒绝迟到结果；晚返回的游标仍交回原owner关闭，不能因不再展示就丢弃。

Repository关闭先封闭查询、等待已接纳请求交接，再并行关闭仍持有的游标；失败保留对应
owner与恢复能力，不以页面销毁报告远端清理成功。游标、连接与关闭任务是运行时资源，
不放入Freezed ViewState；展示层不创建SSH连接。以上继承远端HTTP/2 v9能力与清理语义，
不恢复旧RemoteActions或巨型Client。
