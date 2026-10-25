# 25 - Repository、呈现状态与资源生命周期

Rust 持有业务事实；纯 Dart Repository 归并领域镜像；生成式 AsyncNotifier 编排功能呈现；
Smart Connector 绑定意图；Dumb View 只渲染数据。本篇是 Dart 层次、状态所有权、命令、
草稿与导航的唯一权威契约。可靠历史见 [17](./17-studio-storage.md)，实时协议见
[07](./07-streaming.md)，产品资源见 [18](./18-studio-state.md)，阅读与内容见
[19](./19-studio-ui.md)、[26](./26-timeline-content.md)，证明边界见 [24](./24-testing.md)。

本文描述已批准的目标架构，迁移是否完成以生成一致性、契约测试与原生验收为准。

迁移保全已有成果后按领域补齐与替换，不重复删除已完成的新结构，也不以兼容 facade
维持中间可编译状态。主线新增业务必须迁移至同一目标分层，不能因旧路径删除而丢失能力。
尚未确定的共享接口由架构owner统一裁决；局部实现不能自行引入第二事实源或改变业务语义。

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
Timeline与Thread域的已知失败分类和retry disposition复用同一typed枚举；不在FRB另一条
路径保留bool与可空延迟的平行表示。字段变化不改变原可重试语义或缺省值含义。

领域错误详情保留协议已发布的 typed 变体，不降级为通用错误、字符串或任意 JSON。机器人
详情包含非空 `code`、可空 `platformCode` 与 `guidance`；目录游标过期详情包含游标签发时
绑定的非空整数 `revision`，用于 delegation/statistics 目录查询。adapter 逐字段保留取值与
可空语义，整数转换不得丢失精度；领域层新增详情变体时同步其协议对应关系，不新增第二套
错误表示。

数据包按配置、目录、模型、额度、会话、草稿、模式、资源和更新等真实领域组织 Repository。
每个 Repository 封装本领域 reducer、查询与写入，不通过一个巨型 Client 暴露全部 transport、
可写 store 和命令对象；不增加一层仅转发旧 facade 的 Repository。应用只消费分域公共入口，
领域内部 reducer 和可写 source 不对外导出。领域值只保留一条 canonical 公共路径。

Flutter 按 workspace、conversation、settings 的功能划分呈现。每个功能区分 Screen／Connector、
ViewModel、ViewState、View／Widget；数据／领域层已经位于独立 Dart 包，Flutter 侧不为目录
对称再建一套同构 Repository。公共视觉组件、格式化、platform、adapter、diagnostics 各自归属。
功能不穿透另一功能的私有 ViewModel／State，也不让 diagnostics 反向依赖功能内部实现。

机器人领域同样由 Rust owner 持有业务事实，每 AppGraph 的 Bots Repository 独立拥有 topic、
read model、首配/查询/发送 actions 和未完成操作。VM 编排呈现，离开设置页不关闭物理
机器人，不清理当前聊天资源；注册取消是显式业务动作，退出须等待其真实收束。机器人
配置 revision、领域 revision、查询尝试和发送 operation ID 不互相替代，完整契约见
[27](./27-bots.md)。

会话模型路由的 bot 归属来自原 Thread Configuration 具名读取：SDK 保留 nullable
`ReadText botId`，同一 scope 按需物化为 nullable `String`，不从全局当前机器人或最新
配置补齐。无可用详情、读取中或失败不等于已确认 botId 为空；只有原详情证明不受
bot 托管时，呈现才可提供普通路由编辑。bot 托管入口导航到该精确身份的设置，既有
本地 Stop 能力不因此被禁止；Rust 仍执行最终写入权限校验。

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
产品读取引用离开feed封套后必须携带原owner epoch/incarnation；单独entry/revision不能
证明来源。只读物化值和last-known同样保留原origin，旧command reply不能从最新feed补
来源身份，跨owner的旧值不能提升成当前ready或满足动作准入。

## 25.4 观察、导航与需求

领域观察同步登记接收者并返回登记时的当前值；检查当前状态与注册 predicate 之间不能 await。
观察接口只暴露 read／observe，不暴露 publish 或 reducer setter。观察 lease 只拥有自身的
listener 和预算，取消它不能关闭底层会话。latest-value 只用于可覆盖的状态；可靠事件不能
套用 pause 后只保留最新一条的语义。

共享 resources 层负责 ReadText 的连续 UTF-8 分块与产品来源状态的机械物化，各域复用同一
typed 读取规则。此能力无状态，不开关 scope、不另建任务/预算/缓存，也不取得新的当前来源；
调用始终处于原领域已登记工作与捕获的 immutable scope 内。各域的成员顺序、delta、窗口、
空引用策略和 canonical reducer 不并入通用读取框架。

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

目录选择有两个方向且都由同一选择 owner 发布：**用户选择**把目标置为已打开，**冷恢复
选择**把目标置为待打开。恢复选择是同步、纯选择的入口：校验选择组合与 sealed 状态，
推进唯一 selection generation 使旧在途导航失效，但不读 metadata、不打开 Session/Timeline、
不恢复执行；只有用户显式打开后才读取原目标并开放。它没有原生写入或 CAS，因此不产生
提交回执。应用层不得自持第二份 `needsOpen` 或替代选择控制器，也不得只提供「打开」而
让待打开状态不可达。
尚未创建出 Session 的选择准入失败由 ConversationRepository 发布只读 activationFailure，
携原 threadId、selectionGeneration 与 typed 错误；它是失败证据，不是第二个可写选择来源。
Workspace 呈现只接受与唯一当前选择身份匹配的失败，不能把 active=null 一律显示为加载中。
显式重试仍由原 Repository 核验同一选择及其失败后重新准入，不重选目标、不调用 ensure，
也不重放业务命令；已存在 Session 的域连接错误继续由各域状态负责。
同一Session的各域共享projection incarnation：新incarnation出现后旧域失去新帧准入，
旧值只作为last-known保留，不能跨incarnation混为当前ready。Repository封闭时结束其
选择/激活失败publisher的观察准入，但未决原Session的资源与清理责任持续保留至真实收束。

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
提交操作通过组合专用 demand 能力保留原具体 Session 的 execution 观察，不借路由选择
维持其寿命。已有 Thread 提交只借 ready 且原 incarnation 匹配的源；新建收到真实成功
receipt 后可在原 Session 建立 execution-only 基线，选择已改变也不需临时激活该 Thread
或打开 Timeline。借用释放只归还原需求，不能代表 Session／native 查询已完成关闭。
新建后的持续观察由原创建任务提供非激活源能力，固定原执行 owner／projection；它不是
普通 live 模式或 cold checkpoint 的别名。真实首基线提供来源身份，receipt 不补造它未携带
的版本字段；源已失效就保留已确认结果与读取失败，不按相同 ID 重建或换到 latest。
取消 native、等待 stream 结束、查询退出与正文回调收束可以并行推进；不能先等回调结束才发
native 取消。typed close 报告必须属于原连接；只有 native Clean 且 Dart 已登记工作全部结束后
才 dispose opaque 和释放 permit。Unresolved 保留完整 typed issues、原 handle 与资源 owner。
进行中的清理请求共享同一次真实收束；可重试的 Unresolved 不能被已完成 Future 永久封住。
显式重试只继续原 owner 的未完成清理，不新建连接、不重放业务命令，也不清除尚未解决的
诊断。已证不可恢复的终态故障保持明确的不可重试分类，不能仅改标签后宣称 Clean。
原始错误的 retryable 与清理动作能否恢复不是同一事实：关闭报告保留原始 typed 诊断，并
分别表达继续等待原工作、显式重试原清理调用或不可恢复终态。不能因为原异常标为可重试，
就假定第三方 stream 的取消操作具有重试能力；也不能因此丢弃原始错误分类。

Timeline 失败诊断对外暴露具名只读身份 `TimelineFailureIdentity`（Dart 运行期类型，不是
协议／FRB 字段）：它绑定失败 attempt 与原始失败对象，提供 `isOriginal(error)` 精确判定，
消息相同但引用不同的对象不为真；新 attempt 不继承旧身份，借出的诊断值在原 attempt 退役后
仍保持原身份。该身份只用于诊断归属，不打印、不序列化私有 cause，也不得替代 typed
`StudioFailure` 的错误码／可重试／correlation 语义。
同一身份同时提供 `diagnosticError`：typed 失败取其 `failure` 投影，未知异常取原始对象，
供读取运行时类型名使用。断连诊断只输出类型名与 typed 三字段（未知异常的三字段为 null），
永不调用被捕获异常的 `toString()`；类型名对 `StudioFailure` 取稳定公开名，其余取运行时
类型名，避免泄漏生成镜像的私有类名。

Rust Thread 与产品读取 scope 共用一个 runtime 生命周期内核和同一组 64 个在途读取责任，
但保留各自 typed wire identity 与材料。scope 计费按真实 Thread 或产品资源／原业务 scope
分组，跨 incarnation 共用原 8 个额度，不能把新 ref／代次当作新配额。Thread 的 Cold lease
与驻留 pin、产品的不可变材料 pin 都在真实查询 join 后释放；公共内核不解码业务载荷。
runtime 关闭独立封闭并监督这组 scope，不以 Thread framework 关闭成功为执行前提，
所有未决问题仍进入原 finalizer 之前的同一次报告，不新增关闭协调器。

归档在首次异步边界和写 lane 等待之前捕获全部实际拥有的原对象，而非 Sidebar 窗口。
捕获能力只用于组合层：项目与 Thread 分型，准备原归属、接受真实归档结果与异步释放
准备责任分开；Unknown 保留原捕获，不重发。确认后的 UI 清理绑定原具体 Session 与选择
需求代次，不能关闭较新的 UI 需求或操作证据。草稿清理还核原 owner、stamp 与附件代次，
晚编辑完整保留；只释放原草稿一侧引用，不减少已冻结操作或 Unknown 的附件引用。

Conversation 的组合 context 以具名 ThreadMetadata 借用返回原目录读取能力，而非仅返回
值 Future；值就绪与读取资源真正收束独立。Session 在进入 Recovery 检查前可保留原纯
metadata 结果，但不能因此放开 UI、执行或恢复准入。UI 与归档准备借用同一实际工作时，
共享其原结果和真实关闭责任；关闭超时保原读取 owner，不由一个值返回推断 Clean。
单实体 metadata 的成功基线必须恰含目标实体；lookup／物化失败通过原目标的 typed
读取错误公开，即使还没有实体引用，也不能伪造引用或发布健康空值。
跨领域捕获由同 AppGraph 的具名 typed 能力组合，所有绑定完成后才开放动作；不使用
当前 ID 回查、空 capture、另一个资源池或关闭协调器来绕过未完成的草稿与附件 owner。

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

设置页显式重试依据当前来源同步状态和真实读取需求，不以保留了旧 header 证明来源健康。
源失败后仍展示 last-known 时，恢复入口必须进入该领域已有的纯读取／订阅恢复路径；不能
只重试已满足的可见字段，也不能调用业务 reload／保存来代替恢复。重试保原 VM 会话与资源
责任，在途请求合并，恢复失败继续显示真实错误，不由源通知自动重复业务动作。

编辑 VM 在数据更新时只推进该目标的 canonical 基线，保留未提交输入；不能每次 invalidate
重新初始化而丢 dirty draft。提交在同步阶段冻结 payload／目标／revision，旧完成不能清新字段。
交互答案编辑同样遵守此规则：相同编辑目标重建观察不构成显式 discard，原答案、fallback、
reason 和 feedback 不得被空初始值覆盖；不同完整目标不自动迁移这些输入。关闭确认绑定
具体编辑生命周期、完整目标、editRevision 与最新意图，不能仅比较 Notifier 对象或一个
可能跨重建复用的 revision；清草稿和关闭面板前分别核对原身份，旧确认不作用于新会话。
keepAlive、family key、保留与丢弃规则按编辑会话明确；不把永久缓存作为“防止丢状态”的方案。
模式 JSON 与图共享同一 Freezed 编辑状态和最多 64 次撤销／重做历史；解析、校验或保存失败
保留输入，graph controller 只拥有坐标及交互投影，不成为另一业务 owner。

Settings 的局部 tab 与整页离开共用同一导航请求所有权和 Mode dirty 确认入口。Smart 在
等待确认前捕获原导航请求、具体 Mode VM、编辑会话代次、目标、editRevision 和 latestIntent；
确认返回后必须在任何保存／丢弃动作之前核对这些身份及请求仍有效，失效仅拒绝本次离开，
不得处置新草稿。同一个 Notifier 实例重新 build 不代表原编辑会话仍存活，须核对真实代次。
已准入的保存继续结算原操作，导航 owner 在其完成后再次核对原请求，才交接编辑生产者并
隐藏／切换页面；Widget dispose 不自动保存或丢弃。跨功能入口由 Settings 的 curated
presentation API 提供，app 只将它注入唯一 router，不另建导航或退出 owner。

Smart Screen／Connector 用静态 ref.watch／select 观察 VM，用 ref.listen 或 typed action result
执行导航、对话框和提示；不直连 transport 或可写 store。Dumb View 只接收 immutable props、
UI-only Controller 与 typed callbacks；不得收 Ref、Repository、Client、native handle 或 provider。
Dumb 可保留焦点、composing、局部展开及动画，不做业务查询或重试决策。

速度、上下文与稳定状态消费各自小型 state／值相等 selector。高频速度更新不携带 plan、
workflow、catalog 或正文，也不使这些消费者重建。页面级 VM 不持有第二份完整 Message 列表；
渲染、controller、lease 与 Live/History 以 [26](./26-timeline-content.md) 为准。

## 25.7 命令、观察与效果

Stop 是 Conversation 的独立操作呈现，不归草稿发送的 pending、附件或路由写入通道。
Smart 在原页面、具体 Session 和 Execution 来源上捕获动作，点击时只从该原来源的
Ready 帧冻结同一 active Turn 的 origin/read ref；普通 revision 更新不更换 Turn，
旧页面回调不能按 Thread ID 借用新 Session。资源能力与观察句柄不进入 Freezed 状态。
Stop 呈现分别消费原 ticket 的受理、Observed、Effective 与错误；结果 Future 完成
不等于 Effective，不显示 Durable，也不由 canonical idle 补造丢失的命令结果。
发送、平台读取及交互编辑不应挡住原可停止目标；运行中的 child 与交互面板保留独立
Stop 入口，不因此开放原只读输入。bot 归属不增加 Stop 禁令，退休 planner 保原只读提示。
页面遮盖或卸载只退休本页动作与观察，SDK 已受理工作继续归原 Repository；重新可见
不重发命令、不凭同 ID 的 latest 操作恢复旧呈现。Unknown 不自动重放；用户基于当前
原来源再次明确点击是新的操作意图，原未知结果不被改写为成功或拒绝。

领域动作接收 typed intent，立即冻结目标、expected revision 与 OperationId 并登记只读
operation ticket；UI 不能修改其 reducer、permit 或自动重放。相同资源冲突写串行，不同资源
可并行；停止不排在长写入 FIFO 后，分页／详情不占配置写 lane。

CommitReceipt 至少携带 OperationId、Applied／NoChange、目标 ResourceStamp 和 effect point。
Accepted、AwaitingObservation、Observed、Effective、Durable 独立。模型配置对 next Turn／
future Session 生效，不代表正在执行调用已切换；durable 只由真实保存确认推进。

领域 owner 可在登记操作时冻结额外的显式身份观察要求；它与原生 receipt 的身份观察
要求取并集，不改写 receipt、目标 stamp 或已确认的 effect/durable。Configuration 的
两目标及 Profile/reload 的三目标必须全部实际同步后才发布该证据；仅 receipt 中的
stamp 被覆盖不能提前推进公开 observed 或释放 pendingOperation 额度。要求默认为关闭，
不改变其它领域的原语义；无 receipt 的确认仍须真实身份观察，不能因默认值自动满足。

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
自定义模型改名迁移原压缩阈值覆盖，并清除旧 ID 的连接覆盖；wire API 改变也清除该连接
覆盖，删除则清除该模型的两类覆盖。切换模板重建表单是显式的模型配置重建意图，才可清除
原手动声明与全部连接/阈值覆盖；即使切回原模板也不能把已发生的重建误判为普通字段编辑。
这些意图仍由 ConfigurationRepository 在最新 canonical 账号上合并，不由 VM 回写旧全表；
最终容量、连接支持、重复 ID 与阈值有效性仍由 Rust 校验和解析。

账号模型启用开关是目标为 `(accountId, modelId)` 的独立字段意图，切换立即交给配置 Repository
命令 owner，不等待账号编辑页保存。目标字段操作串行，CAS 冲突重读当前资源后只重施
本次意图，不能回传陈旧账号快照覆盖凭据、目录或其他覆盖。pending/failure 由 mutation
owner 持有，canonical enabled 仅由配置/目录响应和事件更新；旧完成不能覆盖新意图。
页面退出只取消观察，已受理操作参与 Repository 关闭 join，失败和未知结果沿用上述语义。
启用、计费类别和手动模型删除的窄请求均显式传递本次 OperationId；Runtime 回执原样返回，
Repository 不改写不匹配的回执来强行关联。基于明确 CAS 拒绝的重试仍属于同一业务意图，
不因刷新 revision 丢失操作身份；未知结果不自动重放。

Configuration mutation 经具名调用资源交接结果，不只返回失去原生材料保活责任的纯
回执 Future。原调用持有同次提交的 Configuration／Models 配对材料，SDK 的原写入
owner 持有该调用，先取得纯值回执，再同步两个原 target，完成相应观察后才关闭调用。
adapter 不在返回回执前等待消费者释放，也不在返回时提前释放 pin；原生结果已就绪
不等于 SDK 已取得读取材料。Unknown、同步未完成与关闭失败分别保留真实责任，正常
成功不把每次调用保留到应用退出。callId 区分每次调用，OperationId 保持原业务意图；
资源留存范围内的加入／冲突和显式关闭边界遵循 [20](./20-config.md#2021-模型启用计费类别与分发默认)。
调用的结果查询也属于原 owner 的在途责任：与关闭封口原子登记，已接纳查询真正完成或
取消前，producer 已结束也不能单独使 close 报 Clean 或释放原 evidence/permit。
同一次显式清理重试对同一原调用只推进一次 native retry；失败保留为本次 Unresolved，
由下一次显式重试接续，不能因经过多个资源收束层而再次隐式重试或掩盖第一次失败。

已登记命令的真实执行收束与目标的呈现观察是两件事。应用退出会封闭普通来源、feed 与
读取准入；若原结果因此未完成观察，仍保留已提交／未观察的准确阶段与原操作证据，
加入原工作并单独报告清理结果，不能为了报告 Clean 而伪造 observed 或重新发送命令。
原退出协调器可据真实未决问题给出 Degraded，不能安装更新；该路径不授权恢复已关闭
的全局读取或把一份 material header 当成完整 canonical 观察。正常开放来源下的成功
仍必须完成两个原 target 的同步与观察，不能借退出语义免除日常结果消费责任。

模型资料与评价详情是按账号模型身份有界的查询资源，不在 Widget 或配置 reducer
合成另一份模型目录、评分或可用性；迟到详情响应不得写入已切换的模型。智能体列表
直接消费 typed 冻结模型标识，字段参与镜像比较，不以 Profile 当前值填补历史未知。
根会话的智能体成员集合由 canonical AgentDirectory 的根归属与父子身份确定；侧栏
ThreadDirectory 的分页窗口和 session 热集合不代表完整成员，不能与它们取交集后再
渲染菜单或计数。Repository/展示投影按稳定身份消费目录成员，已有 Thread 元数据仅补充
相应展示，不伪造缺失 Thread、路由、权限或工作区事实。切换根会话保持成员隔离，
冷成员仅在显式选中时按需取得其会话数据；列举本身不激活 owner 或订阅全部 Timeline。
导航以用户最新选择意图为准；新意图一经接收，就使旧的按需读取失去发布选择的资格，
不能等串行命令真正执行才使旧意图失效。迟到结果不得并入目录、改变选择或启动已过时
成员的历史观察；切项目、切根、选兄弟成员及新建会话遵守相同边界。当前有效选择的
读取失败保持原错误可见，但过时读取的错误不覆盖较新的导航结果。

账号详情模型列表的阈值编辑只拥有原始输入、短暂防抖与最新意图身份；原始覆盖由配置 reducer 拥有，
最终上下文解析结果由模型目录 reducer 原样接收。有效输入和恢复自动触发同一
account 原子保存，配置 Repository 在串行写 lane 内从最新 canonical account 应用目标模型变更，
CAS 重试也重新构造，不携带未改动字段的陈旧副本。其余模型的持久覆盖必须完整保留，包括
因在线目录暂时撤下而不可见的覆盖。旧响应可推进自身操作记录及 canonical 水位，不能覆盖
较新原始输入、清除较新 pending/error 或让不同模型的修改互相丢失。
页面离开前将已产生的有效意图交给 Repository；已经提交或排队的操作由其持有并参与退出 join，
不能由 Widget dispose 取消。输入无效时不提交、保留校验错误；已知保存失败允许显式重试，
未知结果按既有 UnknownOutcome 语义处理，不自动伪造成功。

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

会话域负责已有 Thread 的四类写入动作：手动压缩、Thread 模式切换、会话模型路由写入与
交互响应提交。四者都由领域动作发起，首次 await 前冻结 Thread、target 与 operation；
typed 结果只结算原操作，未知结果保留冻结输入且不自动重发。动作成功后由对应 facet/read
的 canonical 更新生效，不用聚合刷新或本地推断替代。

四者的版本证据强度按原生能力如实区分，不把本地检查宣称为原子 CAS：模型路由写入与交互
响应提交携带调用方冻结的期望版本，原生在写入前原子校验，冲突按同一意图与新的期望版本
显式重试，`NoChange` 由回执说明而不从 revision 相等推断；手动压缩与模式切换的原生入口
只确认原操作被受理并执行，原生在自身执行时做并发检查，SDK 因此只报告原生确认与其回执，
不承诺不存在的外部期望版本校验、`NoChange` 判定或目标 stamp。

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

StartDraft 与 ComposerDraft 有独立逻辑寿命，不随页面 observer 消失。freezeForSubmit 在
同步阶段冻结 DraftStamp、项目/Thread 身份、文本、模式、工作区、完整 route、解析后的
分发模式/偏好和附件 ID 集合。
新建 Thread 直接提交该 route，不先写全局默认设置再读取缓存。已有 Thread 提交携带所观察的
route extension revision，受理 CAS 的语义见 [18](./18-studio-state.md)。

新会话的分发模式和偏好是项目草稿内两个独立可选覆盖；空值表示跟随 canonical 设置，
不复制一份默认值保存为覆盖。创建提交在首次 await 前解析并冻结两者，之后设置变化
不能改写已提交值；成功只清理仍匹配 DraftStamp 的草稿，失败保留选择和附件。固定
模式保留偏好选择但不应用提示词。已有会话的分发策略只读，不因路由观察者销毁而重置。

markSubmitting、accepted、observed 和 durable 均关联同一 DraftStamp + OperationId。
提交期间可继续输入和修改草稿；旧 ACK 只清理仍属于该提交且 revision 相符的字段。
TextEditingController 保存 composing/selection，draftId 变化时替换；同一草稿的普通重建不反复
重写 controller.text，旧完成也不能直接清空当前 controller。

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

### 25.8.1 附件原文件读取

附件读取是无 producer 的具名 query scope，不建立假 feed 或 ACK。打开时冻结 draft 或
Thread/attachment 目标，Rust 先核验原资源权限，再持有同一个文件句柄及其长度；读取
不接受任意路径，工具媒体仍须来自该 Thread 的完整 typed delivery 授权。完整性校验与
后续分块读取使用同一句柄，不校验路径后重新打开另一个对象。

读取身份包含真实 scope、runtime epoch、incarnation 与 typed target。每块默认 64 KiB、
上限 256 KiB，长度参数范围为 1..262144；offset 等于原长度时返回空末块，大于原长度
为 InvalidArgument，提前 EOF 或完整性破坏为真实 Storage 失败。字节缓冲归调用方独占，
不进入 canonical 或 Freezed ViewState；不得先整块读取再在 Dart 切片。

关闭校验使用打开时从原 native 句柄取得的独立 scope 标识，不依赖完整业务描述符能否
转换。描述符数值或目标不可表达时，原查询仍失败，但不能在已验证的 native Clean 后
永久保留同一转换错误作为清理责任。adapter 保留原 scope 标识用于关闭前后核验；无法
取得真实标识时仍为 Unresolved 并保留句柄，显式重试只能读取该原句柄，不能从 close
报告反推期望标识、补造 epoch/incarnation 或新开替代对象。

Thread 读取计入该 Thread 的原 scope 预算；所有 draft 在同一 runtime 共用 8 个 scope，
opening、校验和读取共用原 64 个 read-call 额度，不另建查询池。删除与打开按原资源 owner
线性化；删除路径不等于已有句柄已结束。requestClose 同步封准入，close/retryClose 真正
等待 late open、blocking IO 与在途调用结束，Unresolved 保留原 owner 和完整 issues。

FRB 映射同一 opaque scope、身份、长度和 typed chunk。HTTP 的
`POST /api/v1/attachment-reads/draft` 与 `/thread` 创建对应 scope；
`GET /api/v1/attachment-reads/{scope_id}/bytes` 接收 offset/maxBytes 并返回原始二进制，
`Anywork-Offset` 标记本块位置，非末块携带 `Anywork-Next-Offset`。合法 EOF 为 200 空 body，
不伪造 Range 语义。具名 `/close` 与 `/retry-close` 返回原关闭报告；请求断开不丢 native
责任。旧 whole-read 接口在消费者迁移后删除，不能以兼容转发保留第二条读取链。

### 25.8.2 草稿命令的实际完成与回收

附件准入与新建会话各自拥有具名运行时任务；进度观察不是命令本身。派发前冻结调用身份，
原生先登记责任再执行副作用，真实任务及结果在显式交接或收束前由原 owner 持有。取得
句柄的回复丢失后，只能按原身份查询、加入原任务，不重新派发；查询暂无结果不证明拒绝。
这些能力是既有业务生命周期的窄适配，不建立新的通用调度、持久化去重表或消息总线。

HTTP multipart 暂存与 clipboard 暂存同属宿主输入准备，不冒充已经受理的原生附件命令。
Server 在读取上传体或创建临时文件之前，以调用方操作身份登记具名上传 owner，并持有
原普通请求名额、上传体任务及临时文件清理责任。完整 context／sources 形成并冻结后，
才向原生登记附件准入并计入原生 64 个命令名额；这两个阶段的责任和预算不可混称。
上传流不可重读比较，重复上传入口不凭相同 ID 接纳第二份 body，而是拒绝该次新请求；
恢复通过原上传身份的只读查询／结果加入，不重新上传、计算新摘要或重放原生准入。
关闭与断连不能丢失已登记的暂存或已受理原生工作；实际文件使用与清理 join 前不释放
宿主名额，清理失败保留原 owner 和可重试报告。既有上传数量、字节与文件名规则不变。

附件仍按原模型策略整批准入，只有完整 batch 校验成功才发布全部元数据。失败回滚的
每个残余文件都必须保留实际清理责任和 typed issue，不能吞错误或虚报资源已释放。
删除返回“目标已无 entry”是幂等结束，不是清理失败；真正 IO 失败保留原对象以供显式
retryCleanup。原生完成但交付未知时，Dart 保留 reservation，直到原任务结果与归属确定。

创建任务接受后，断开观察或关闭页面不取消创建；全局创建准入只在实际创建任务结算后
释放，不以 stream EOF 或 Widget dispose 释放。成功回执和原执行源是两种证据：后续读取
执行源失败不撤销已受理输入。原创建 owner 捕获真实 projection，非激活借读只能附着该
原源，不能按 Thread ID 重新激活或借用新 incarnation。已打开 feed 独立持有其原源 pin，
创建 owner 收束不关闭已交接 feed。普通错误不自动证明未受理；提交阶段须有真实证据。

SDK 的附件 ledger 分别登记 draft 与 frozen operation 引用；移除草稿引用可以立即更新
本地草稿，但未清理责任仍通过 cleanupIssues 与原 operation 可见。创建、附件准入、临时
文件 staging、读取和删除均参与同一次关闭。临时文件清理错误不得只写日志后返回成功，
已知业务结果与后续清理结果分开记录。客户端沿原 pendingOperation 预算，原生附件准入
与创建共用每 runtime 64 个未释放调用名额；它们不是 read scope/read-call 配额，关闭
前不能只因已发出结果就归还。创建单提交准入仍独立保持，不以排队扩大原输入、上传
或模型限制。结果观察关闭不删除已交接给草稿的有效附件，也不取消已经受理的创建。

### 25.8.3 原提交的执行身份交接

输入观察属于原提交的 `SubmissionExecutionLease`，不属于 UI 选择或详情需求。原 lease
可在其具体 Session、Execution attempt 与来源身份内读取该次交付的 Turn；公开 Session
详情读取仍须满足原 UI 准入，不能借提交修复放宽所有详情读取。提交读取与 UI 读取进入
同一 Session read owner 和八个 scope 限额，关闭与失败责任也在原 owner 内登记。

Execution 的必要交接在 ACK 前完成：每次向原 lease 交付该帧的不可变 active/recent Turn
引用，去重后最多两项。消费者只读取原 header 与匹配冻结 inputId 所需的有界文本，不
物化失败正文或完整 Turn，不在 latest watch 中启动未等待的读取。交接只等待本次读取，
不等待未来 Turn、ticket 终态或同一 baseline 完成后才会发布的 ready。读取或交接失败
保留原操作诊断，不 ACK 失败交付；不能用稍后的 latest、替换 attempt 或重开 source 补证。

Composer 在派发前同步绑定消费者；Start 在原创建 source 首次 baseline 交接前绑定，
包括空 Turn baseline 的来源初始化，不先等待 ready 再注册。已有 execution 基线只有
在其绑定 source 与本次原创建 source 为同一对象时才能复用；仅 Thread/incarnation
相同不够，普通 UI feed 不能完成该创建 lease 的 ready。只消费真实收到且匹配原
Thread/source/input 的 typed Turn：queued 仅证明 observed，running 或带 startedAt 的
terminal 可证明 effective；任何 Turn.saved/terminal 都不证明 durable。durable 仍仅由
原 history input、requestDigest 与 accepted sequence 的一致证据推进。

当前原生输入在 gate 等待时尚无 Turn，开始时直接为 Running；ThreadStatus.Queued 不
证明某个 input，也不能改造为伪 queued Turn/ref/time。本修复保留 SDK 的 typed queued
消费契约，但不新增 native Pending 身份协议或声称其端到端已实现。

lease 的同步关闭先封其 Turn read 准入，真正加入已登记的 late open、query、交接与
原 history 查询之后才释放观察责任。Unresolved 保原 scope、permit、issues 与显式重试；
不以 UI 退出、超时或 Future 取消意图当作工作完成。只关闭该 lease 的读取，不反向等待
正在等提交 lease 释放的整个 Session.close，避免形成关闭环。
观察者构造失败即使发生在创建结果已确认之后，Draft work 也必须加入失败构造 owner
的真实清理并保存报告；不能只靠后台释放 permit，而让 work 永久停留在证据未收束状态。
原失败通知、观察取消或需求/permit 释放抛错时，也须保留该步骤的显式重试责任；
已成功步骤不重复执行，失败步骤不能因为“曾尝试”就永久跳过。恢复成功只消除该步骤
的未完成 issue，原业务失败与首次结果保留；真实 terminal join 故障不能被顺带清除。

## 25.9 启动与应用退出

bootstrap 由应用生命周期明确发起，成功／失败由唯一启动状态发布。首个目录／catalog 基线
到达前的失败包含 typed code 与 correlation，不困在 Widget 的局部等待标志；显式 retry 不
创建第二套初始化。启动后局部目录失败保留可用 shell 和最后有效数据。

Updates 仓储构造不打开 native feed，也不初始化库；原 RuntimeReady 后的显式读取需求才
开始订阅。自动更新 gate 同步登记观察后，等待与当前 header 的 origin／ref 匹配的完整
canonical value，不能只见 header ready 就派发自动任务。调用动作前再次核同一准入条件；
只读 gate 失败可以在显式启动重试时恢复，不自动轮询或重放业务。runtime 已 Ready 而领域
attach 失败时，保留原 Ready 结果，显式重试只恢复未完成 attach，不重启 native 或把提前
标记 attached 当成功；已受理自动任务始终复用原 ticket，包括失败与未知结果。

手动更新的操作与准备任务归更新领域服务，请求同步发布 pending，ViewModel 只编排并呈现，
页面不持有准备任务。已有后台下载时复用同一次准备；准备操作与进度流真实完成后，才把更新后
重启意图交给同一退出协调器。首次退出固定普通退出或更新后重启意图及绝对期限，应用 close
幂等并复用首次 future；后续请求只加入，不重新启动、延长期限或改变意图。

退出先封闭业务与编辑生产者，加入已受理操作；同时发布展示无绑定并卸载路由子树，不能等全部
close 完成后才解绑。独立 session、feed、update 和附件任务并发取消，在首次期限内等待真实
完成及展示 lease 的释放确认，随后才销毁 UI 控制器。尚未解决的任务与资源出现在 CloseReport，
不能释放未确认的 permit；provider container 与 opaque dispose 位于真实异步收束之后。

有真实阶段依赖的领域仍保持关闭顺序：Updates 先取消并 join 已受理任务，再收束其 feed／
read scopes。共享资源生命周期提供无副作用的当前责任报告快照，供前一阶段期限耗尽时
合并尚未收束的后一阶段；读取快照不封准入、不取消、不启动清理或释放资源。快照只说明
当时已登记的责任，不证明整个领域已关闭，也不替代原 future 的真实 join。

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

### 25.9.1 生产与 Driver 的单一装配入口

生产启动与 Driver 启动共用同一个装配入口，只由调用方选择是否需要 Driver 装饰；
不建立第二套 AppGraph、第二份 owner 或仅在某一入口补齐的分支。该入口只产出
composition owner（AppGraph、Bots Repository、托盘控制器）与应用装配结果，不承载
任何领域业务方法，也不成为可变 Client facade。

装配顺序按依赖固定：原生库加载 → 各领域 port 与 Repository → 操作登记与资源预算 →
生命周期、退出宿主与自动更新 gate → 应用装配。原生库只在 owner 存在后由启动流程加载，
不在进程入口提前初始化；装配阶段不触发平台通道、不打开领域 feed、不发起业务命令。

退出协调器与装配共用同一批 owner，包括托盘与退出宿主；装配不得创建退出流程不会
回收的实例，也不得让退出流程另建替代 owner。自动更新 gate 的启用与否由装配决定，
不改变各自领域契约。

装配失败按 bootstrap 的既有启动失败链发布 typed code 与 correlation，由统一启动状态
呈现并可显式重试；不新增第二套错误通道，也不把装配异常降级为空 owner 或默认实例。

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

Configuration 的 typed 来源也由原 ConfigRuntime 发布边界捕获，不从旧聚合 Settings
订阅或异步 latest 消费重建。无密钥配置材料、账号成员身份、来源状态和相容模型引用在
同一提交边界确定；配置、目录、来源与投影水位各自独立。同 ID 删除后重建获得新成员
身份，凭据只公开存在性。配置命令回执指向该次原提交捕获的目标，不以随后 current
冒充原结果。配置字段、嵌套列表和长文本按具名不可变 scope 读取，复用产品 8 scopes、
64 read calls 与既有交付窗口，不建立另一份 Settings owner 或无限历史缓存。

配置／目录配对凭证持有原两份不可变材料，并由原生核验所有目标与双水位。只有 current、
未 ACK 交付、实际读取和尚待消费的命令调用 owner 持有强引用；历史定位不延长材料寿命。来源或捕获失败必须
真实报告，不发布假相容 pair。Configuration 与 Profiles 仍是独立领域来源，不能因共享
设置页面把它们合并成一个事实源。

Models 的 Catalog、来源状态与精确详情在 FRB/HTTP 中均通过原 origin/ref 或完整配对
target 独立打开。HTTP 不得要求先取得活 Catalog feed，或从当前 feed 补齐、替换请求
身份；命令结果所持原配对也可合法打开详情。运输层只持原 opaque、打开/查询/正文消费
责任及原额度，不保存另一份 Models 业务状态。feed 关闭不撤销已交接的独立 read scope。

HTTP handle 的能力类别与原身份必须保持可核验，不能用 scope ID 前缀或同为 Value 的
版本种类区分 Catalog 与精确详情。错域请求明确拒绝，已释放身份不承诺永久保留。来源
状态的 revision 与目录业务 revision 独立；过期原材料不能用最新来源状态替换。
Catalog 沿原 2 未 ACK／1 latest 窗口，ACK 释放额度必须唤醒等待发送的 HTTP body；
最后 control 交付不等于正文消费者已结束。真实打开、查询、消费者与关闭全部 join 后
才释放原资源；同一应用退出仍沿既有绝对期限和 finalizer 汇总未收束责任。

产品 Dart adapter 复用同一个机械打开/资源 owner，通过明确的 ProductReadVersion
区分 value 与 source-status，不把所有 scope 限定为 Value，也不把 Thread identity
强转为 Product identity。raw scope/call 身份先于可能失败的完整 descriptor 转换保存；
转换失败不消除原 opaque 的关闭责任，关闭报告必须核原始身份。已受理命令的 result
转换参与原 owner 的 join，但不使用普通只读 query 的关闭后取消检查丢弃已知提交阶段。
ConfigurationPort 完整实现具名读取、原配对、两种 feed 与三个调用资源；构造不启动
来源、reload 或 probe，不在 adapter 重算 Start 策略或制造额外 observed/receipt。
ModelsPort 同样由无构造副作用的生产 adapter 完整提供 Catalog/Templates feed、各自
具名 read、Models source-status 与精确 Delegation read 六类入口，复用上述机械 owner。
不以临时叶工厂冒充完整 port，不另加 probe/load mutation，不重算 native 模型资格。
精确 Delegation read 单独提供原生 scope ID，独立于完整 descriptor 转换与查询准入，
在 Clean/dispose 后仍可核验关闭报告。完整 identity/target 查询继续严格校验原配对；
查询失败不转成清理身份失败，不补造 descriptor，也不从关闭报告反推期望 ID。

目录发布完整成员与后端计算的类型资格。所有会话、Mode、系统角色与 Agent 使用同一公共
模型查询；GUI 不另算能力、预算或默认值，不满足资格的既有选择保留并显示原因，不自动换模型。
目录与配置 revision 独立，账号参数变化只更新受影响路由，旧响应不能回滚新目录。
编辑时的effort建议和新Profile的首个文本模型建议由原immutable目录scope中的Rust纯查询
提供，不从Dart部分页选全局first或重写模型策略；建议结果携原查询目标，由原编辑意图
核验后消费。它们不读取最新配置，也不改变配置保存的严格effort校验或空值省略语义。

系统角色的配置存在性与缺省建议由 Configuration 的专用不可变配对读取提供。Rust 在
同一配置 owner 捕获配置／完整模型目录及真实双水位，并发布可按需读取的配对引用；
任一来源改变都使配对目标更新，不要求普通配置字段随目录变化重新读取。旧 scope 只读
原配对材料，不在读取时偷偷改用 latest 目录。原 role key 存在即返回原 route，包括空或
不可解析的 effort；只有该 key 确实缺失才建议完整目录中的首个文本模型，真实无候选与
未知／失败分开。UI 不从部分目录页推断全局 first，也不把 role 展示查询当最终 Start 解析。

账号模型的资料与最终评价详情使用同一 Rust 签发的配置／目录配对凭证，而非把两个独立
latest target 放入一个值就声称相容。详情请求还冻结 account/model；原生核验配对引用、
原配置与目录目标及双水位后 pin 原材料，已过期或不相容时明确失败，不替换成 current。
复用的是来源配对证据，详情仍使用具名 Models scope，角色查询不成为通用 resolver。
详情的执行资格由原配置捕获边界按既有原生规则确定，仅保留与原 account/model 成员
绑定的无密钥结果及不可用原因。凭据存在性、展示 descriptor 或编辑建议不替代实际
资格校验；不得在读取旧配对时重读 current，也不为此保留整份运行时配置或已解析路由。
资格变化参与原 Models 材料及成员版本判断；普通不可用是成员事实，不伪装成全来源
捕获失败。它不授权改变模型启用、连接、effort、凭据或工具能力的既有准入规则。
本地性能与评价窗口在该次详情 scope 打开时捕获，之后只读该不可变窗口；这不承诺它们
与配置／目录属于同一个跨数据库事务。后续显式读取可以取得更新的评价窗口。

新建路由也通过独立的 Start 只读能力消费该原配置／目录配对。路由规则保持原产品行为：
先读当前 mode 的配置路由，缺失时使用 mode.simple；显式模型意图优先，非空 effort
意图优先，否则只在模型相同的情况下继承原 effort，最终空 effort 使用该模型的原生
默认。显式换模型的 effort 归一化复用模型层已有建议规则；缺失或禁用模型明确不可用，
不能选择全局 first 代替，也不把候选列表的类型筛选新增成此查询的准入条件。

Start 查询不读取 Mode 定义：上述规则只依赖 mode 标识与原配置／模型材料。Mode 的
实际存在、创建资格和执行定义仍由原创建命令检查，不新增虚假的 ModeCatalog 事务保证。
查询不会保存默认设置或修改路由。SDK 在提交前通过显式读取需求物化结果，原来源或
编辑意图改变即失去提交资格；submit 只同步冻结仍相容的已物化完整路由，不在首 await
之后重新解析或替换。读取失败保留原始编辑，晚结果不覆盖新意图。

Models 的不可变材料与成员身份连续性在原配置 owner 的发布边界同步捕获和推进，再由
产品观察消费；latest watch 只能通知，不负责从最终值重建遗漏的删除／重建历史。即使
观察者未及时 poll，同 ID 删除后重建也必须取得新成员身份。材料寿命只由当前发布、原
未 ACK 窗口、已 pin 的读取 scope 与原命令调用承担，不建立无界日志或第二份配置事实源；查询不能
用 current 配置补旧引用。Models 捕获不携带账号密钥或整份 Settings 的序列化副本。

模型目录的全资源来源状态表示原配置 owner 中已校验目录的可用性，不表示所有账号的
联网探测均成功。该状态由同一 ConfigRuntime 持有并在原发布边界推进；transport 不在
查询或订阅时临时构造 Ready，不借配置／目录业务 revision 充当来源状态 revision。
初始化成功才有 Ready，原 owner 关闭产生 Stopped；成功发布更新原观察时间。初始化
失败不发布假空目录。逐账号 probing、缓存来源、检查时间和错误完整保留在账号目录中，
不聚合成没有真实操作 owner 的 Loading／Refreshing／Degraded，也不制造全局探测 ID。
八态类型保持穷尽运输，但不要求一个只有同步目录发布的来源人为经历所有八态。

来源元数据、业务材料和投影交付的身份及水位相互独立，并在同次发布中相容捕获。
来源状态按需读取只读原不可变元数据，不发起联网探测或配置 reload。投影捕获失败、
预算耗尽与运输失败沿各自真实错误路径报告，不能冒充账号探测失败，也不能因来源仍
可用就发布缺损业务材料；恢复仍遵守失败后的成员身份失效与原引用寿命。

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

跨功能的SSH编辑、密码和远程目录弹窗通过Settings具名Smart入口复用同一呈现owner的
身份分配与结束登记；Workspace不导私有VM或自建弹窗ID来源。添加远程项目的名称编辑在
原确认意图中冻结，与目录一起进入真实open→rename→activate批次，不在打开后补写名称；
成功返回只说明该原批次与本次查询借用已经完成，不触发第二次打开或第二个选择来源。

## 25.13 开放工具产物的呈现边界

ThreadItem及其已知字段仍使用封闭typed值；只有原工具`output_artifacts`是有意开放的JSON
值序列。Rust保留原值，传输逐项编码，Dart领域用具名不可变opaque文本值表达，不在Repository
或reducer还原成动态协议对象。该边界不允许已知DTO退回JSON聚合，也不扩大Timeline常驻或
详情读取预算。

网页卡片仅在专用呈现适配中使用标准JSON解码器，从已交付的开放产物提取原有最多六个
去重链接；保持原遍历顺序和http(s)前缀选择语义，不新增URL过滤或自动读取完整大产物。
解码对象只是临时呈现材料，不进入canonical镜像、ViewState、Driver或另一个正文缓存。
原tool arguments与Raw payload content保留各自opaque文本语义，不被此边界自动解析。

模拟 transport（`infrastructure/frb/demo/`）实现的是原生侧的 wire 合同，它自有的
`base64url` 续页游标信封由自己写入并读取；解析该信封属于 transport 内部行为，既不解释
业务载荷，也不扩展本节的产物边界。其他 Dart 侧位置仍不得解码已知协议 JSON。

## 25.14 附件二进制读取

附件读取是独立只读资源，不是事件 feed、业务提交或另一份附件账本。Rust 在原 draft
登记、Thread 附件目录或工具 delivery 授权边界取得具体文件，并持有同一文件句柄与
真实长度；后续块不按路径重开、不按 ID 查询 latest，也不先读取整块再伪装分块。
工具资源保留原长度与摘要校验，校验和读取使用同一文件对象。删除与新打开在原 owner
边界裁决；已打开对象的寿命与路径是否仍存在分开，文件错误不能伪装为正常空内容。

二进制 scope 使用独立的真实读取身份，不捏造 Thread facet revision。Thread 读取与其
原详情共享八个 scope 配额，draft 读取由同一 AttachmentDraftRuntime 共用八个，而非
每个附件各八个；opening 与块查询共用 runtime 的六十四个在途读取配额。封闭先拒绝
新请求，真实等待打开、完整性检查、块读取与底层工作结束后才释放文件及许可。

每块默认 64 KiB，允许 1 B 至 256 KiB，按原始二进制字节计量，与 JSON 详情预算是
不同合同。UI 所需完整字节只沿这个原 scope 组装，结果由调用方独占，不进入领域值、
ViewState、Driver 或常驻第二缓存。该读取合同不改变模型附件准入、上传限额、提交
引用转移或草稿／操作双归属；这些仍由原业务 owner 与唯一 ledger 负责。
## 25.15 Bots 产品域

Bots 与 Configuration／Models 同级的独立产品域，不从 Conversation 或 Settings 内部
借道。SDK 的 Bots Repository 是该域 Dart canonical 镜像的唯一 writer：它持有 typed
product topic 的基线、事件与来源状态，并把命令回执、凭据操作和配对进度作为独立的
值发布。设置界面、启动路径与演示模式只消费该 Repository 暴露的值和动作，不自建
第二份 bots 状态、注册尝试队列或凭据缓存。

- 产品主题载荷以具体 bots 类型表达，不回退到通用动态 JSON；`BotsBaseline` 与
  `BotsStateChangedPayload` 属于产品主题联合的一部分，与其他域同样按最多两个未确认
  交付、明示来源版本和真实关闭责任处理。
- 命令动作覆盖保存、启用、连接重试、注册开始／取消、信任用户／会话，以及 bot 会话
  线程的创建与分页读取；每个动作冻结自己的目标、operation 与期望版本，回执只结算
  原操作，未知结果不自动重发，也不据错误文案推断未生效。
- 凭据操作、注册尝试与诊断是独立值：可用性、进行中操作和最终失败分别保留，不用
  一次成功快照清除仍在进行的凭据责任。
- 原生适配层只做 FRB 边界转换与类型映射；生产、演示与测试替身共用同一端口语义，
  不据 demo 数据伪造成功回执。App 侧以生成式 AsyncNotifier 承担编辑、校验、pending
  与最新意图，View 只消费不可变状态与类型化回调。
- 设置页的 Bots 分页、发布侧会话菜单入口与 Driver 投影都读取同一 Repository 事实；
  Driver 只暴露已发布值的只读投影，不新建第三条状态链。
## 25.16 产品域原生读链的分层

每个产品域（Configuration、Models、Profiles、Templates 之外的 Workspace、Bots、
Modes、AccountUsage/Statistics、Updates、Startup、Recovery、Persistence、Remote、
MCP、LSP、Skills）都按同一四层实现，不设通用产品内核：

1. **域内 source**：`pl-studio-runtime` 的域模块各自持有不可变材料登记，负责任务
   性引用签发、实际发送与引用可达性的同次提交、有限历史 pin 与 seal/finish。
   引用要么由原 feed 的真实发送暴露，要么由原命令自身的结果暴露；后续按 ID 查询
   current 不能替代这两条来源。
2. **域 feed/read**：`open_*` 返回 typed feed 与具名 read 连接，共享既有交付窗口
   （含 baseline 的两个未确认额度、连续前缀确认）与既有读 scope 预算；目录扩展沿
   原生 frontier，不重建偏移。
3. **协议 DTO**：跨 FRB 的读形状归 `pl-protocol` 的产品读模块，runtime 构造、
   bridge 只做映射；同一形状不保留两套定义。
4. **Bridge 与 Dart 适配**：bridge 只映射句柄与错误，Dart 端口实现负责类型转换、
   冻结目标、回执校验与关闭责任；不为旧调用点保留兼容入口。

跨域 FRB DTO 名称必须互不重复：生成器按 Rust 短名合并同名类型，不同来源的同名 DTO
会被随机合并成同一身份。Thread facet 的配置形状以 `ThreadConfiguration` 前缀区分于
产品域的账号配置形状；产品目录查询与筛选以 `ThreadDirectory` 前缀区分于旧列表传输
形状。新增同名形状时应改名为带领域前缀的唯一名称并迁移消费者，不通过重命名生成物、
手工改生成代码或合并语义不同的 DTO 规避。

读 scope 预算以稳定的业务标签区分（如同一目录查询形状、单 Thread 元数据），
不得以引用、代次或 feed 身份作为键绕开原配额。

## 25.17 呈现保真与共享壳层契约

分层重构可以更换组件边界、状态形状与读取路径，但用户可见的呈现不得随之改变：
页面/面板的区块顺序与分组、控件类型、几何常量（内边距、间距、行高、图标尺寸、
圆角、断点、最大宽度）、入口位置、菜单项集合与窄窗行为都以重构前基线为准。
旧界面断言不得因实现改动而放宽；实现与断言冲突时改实现。基线新增能力（如委托
摘要行、自动选模、最终评价入口）必须保留，但其插入不得挤压原有呈现的既有地位。

**设置页壳层单一契约。** 所有设置分页共用一组呈现组件，分页自身不重算间距：
`SettingsPageLayout` 负责居中 `maxWidth`（默认 1040）、水平内边距（窗口 `< 700`
取 16，否则 28）、标题区垂直 22、toolbar 下间距 16、footer 分隔线高 1 与垂直 12；
`SettingsHeader` 负责标题字级/字重/行高、副标题 `labelSmall`/variant 色与 `< 620`
的 trailing 换行；`SettingsSectionPanel` 负责区块标题 `titleSmall`（w600）、垂直 16、
标题后 12；`SettingsGroup` 负责以 1px 分隔行承载分组；`SettingsPane` 只是
「标题 + 副标题 + 正文」的薄适配，`SettingsPane.scrolling` 生成带
`ValueKey('settings-pane-scroll')` 与底部 24 内边距的滚动体（Driver 行程依赖该身份）。
分页不得再使用自带间距的第二套壳层；新增诊断/来源状态行不得出现在健康态常态布局中，
只在真实读取失败时以页面内错误呈现。

**交互 dock 契约。** 计划确认、工具授权、问题回答、无问题文本与终态共用同一外壳：
`StudioPanel`（`surfaceContainerLowest` 背景、`outlineVariant` 边框、`lg` 圆角、无阴影）、
`< 460` 的紧凑内边距、头部图标 + 标题 + 副标题 + trailing、头部后 13、以及只在存在操作
时出现的 footer（提示与操作在 `< 560` 时分行）。动作组统一为右对齐、间距 8 的 `Wrap`。
状态呈现只表达「可提交 / 在途 / 已受理未观察 / 读取失败 / 未知」这几种真实阶段；
在途只用禁用表达，不使用会在受理后长期存在的不确定进度动画。

**交互读取的挂载准备。** 交互读取是分页的：`open` 只拿 header，问题、选项、身份文本
（ids、hashes、名称）与应答记录各有独立分页。dock 在挂载后执行一次幂等的挂载准备读取：
先补 header，再按有界循环补齐首屏问题页、其选项页与全部 `requiredInteractionTexts`，
每层都以「本次是否推进偏移/字节」为守卫，不推进即停止，不排帧、不空转。应答记录仍按需
读取，因为它只出现在终态结算视图。提交准入仍以 `readIncomplete` 判定实际已读材料，
不以「用户先点加载」为前提；显式重试走同一准备路径，且不重发任何已受理命令。

## 25.18 AST 边界门禁的判定锚点

边界门禁与反例 fixture 是 §25.10 的静态检查环节，只判定可判定的语法事实；运行时归属仍
由 §25.4、§25.5 的观察与关闭契约以及 Client、adapter 套件证明。为避免把合法的新架构判成
违规，也不以类型名称拼写推断所有权，门禁与代码共同遵守以下锚点：

- **owner 由声明判定，不由名称后缀判定。** Freezed value、enum 及其生成的伴生名是值类型；
  即使名称以 `Owner`／`Connection`／`Binding`／`Controller` 结尾，也不构成运行时 owner。
  Repository、Session、permit、任务、连接、native handle 与 UI-only controller 才是资源
  owner。领域值之间的引用属于值语义，不因命名相似被禁止。
- **UI 层声明的类型是 UI 词汇。** 功能 `views/`、`widgets/` 与 `ui/` 内声明的 Widget、
  State 与 UI-only controller 是 Dumb 视图的合法 props（§25.6），不是业务 owner；业务
  owner 只在领域包、adapter 与 app 组合层声明。功能内 UI-only controller 与其 Dumb 视图
  同层声明，不放入 `state/`，也不进入 Freezed ViewState。`vyuh_node_flow` 的图词汇
  （`Connection`、`Port`、`Node`、`NodeGraph`）只表示图形投影，仅在导入该包的文件中合法，
  不构成第二个业务 owner。
- **provider 生命周期只 detach 自身观察。** `ref.onCancel`／`onResume`／`onDispose` 内允许
  取消自身观察、终止自身计时器与合并 helper、清空自身集合、调用自身 `_dispose*` 私有清理；
  禁止关闭 Session、放弃草稿、取消已受理业务操作、释放 orphan、改变业务 demand、归档项目
  或写配置。门禁锚定这些具名业务动作，不把集合清理与自身 helper 释放当作业务关闭。
- **旧 Client facade 不再准入 owner。** provider 不得通过旧 Client／transport 绑定按 id
  取用第二个 owner；Repository 的具名 `session(id)`／`composer(id)` 等公共查询按 §25.2
  由 Repository 拥有并登记资源，是 ViewModel 的合法领域入口，不属于该禁令。
- **adapter 不写第二份 canonical。** 镜像写入锚定 adapter 的 `publish`／`markObserved`／
  `markDurable` 一类镜像发布动作；`dart:core` 的 `Iterable.reduce` 折叠、集合运算与自身
  缓冲区维护不是 reducer。adapter 向自己拥有并只读发布的 latest-value holder 写入是
  producer 侧的观察发布，不构成第二份 canonical。
- **手写 `part`／`part of` 不是模块边界，但可以是模块内部组织方式。** 允许范围限于与库
  文件同目录，且该库位于 `anywork_client` 领域 `data/` 模块或 `infrastructure/frb/` 适配层
  子树内；跨目录拆分、跨模块共享或在 `features/**` 内手写 part 仍被拒绝。生成物 part
  （`*.g.dart`、`*.freezed.dart`）由 §25.10 的生成边界负责，不在手写检查内。

需要调整以上锚点时先改本节，再改门禁实现与反例 fixture；不得通过删除规则、把规则降级为
warning 或把检查移出门禁来让代码通过。
