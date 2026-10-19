# 25 - Client、前端状态与资源生命周期

Rust 持有业务事实；应用实例持有纯 Dart Client；Riverpod 适配只读观察；Widget 呈现并发出意图。
本篇是客户端所有权、命令、草稿和导航的唯一权威契约。可靠历史与迁移见
[17](./17-studio-storage.md)，版本化流见 [07](./07-streaming.md)，领域和关闭见
[18](./18-studio-state.md)，呈现与阅读位置见 [19](./19-studio-ui.md)，验证边界见
[24](./24-testing.md)。规范不把源码实现或纯 Dart 测试等同于真实 native 与平台验收。

## 25.1 分层与应用实例

```mermaid
flowchart LR
  V[View] --> C[Connector / Riverpod]
  C --> A[anywork_client 公共 API]
  A --> P[Typed transport ports]
  F[FRB adapter] -.实现.-> P
  F --> R[Rust runtime / pl-core]
  R --> F
  A --> C
  C --> V
```

`anywork_client` 的运行依赖只有 Dart SDK，不依赖 Flutter、Riverpod、FRB、Ref 或
BuildContext。生成 DTO 和 native 句柄留在 adapter，Client 只消费 typed domain 契约。
feature 不导入生成代码、adapter、transport 或 Client 私有实现。应用装配入口同时认识
Client 与 adapter，其他层只认识各自的公共依赖。

每个 AppGraph 创建自己的 Client、transport 订阅登记、read models、命令板、草稿和附件
owner。禁止 module-level Client、业务 Map 和跨 ProviderContainer 共享的会话资源。
原生库的进程初始化与宿主退出仍归 native host，不能借此共享两个 Client 的观察句柄或草稿。
ProviderScope 借用注入的实例，只拥有自己的观察注册。

## 25.2 所有权与唯一写入

| 事实或资源 | 权威 owner | Dart owner / 唯一写入入口 | 身份与结束条件 |
| --- | --- | --- | --- |
| 项目、目录、配置、catalog、服务状态 | Rust 对应领域 | 各领域 read model reducer | 各自 ResourceStamp；领域关闭或应用退出 |
| Turn、activity、interaction、runtime、storage | Rust Thread | Client session 的状态 reducer | Thread 与 owner epoch；选择变化结束观察，不结束 Turn |
| 正文、saved、terminal、omitted、字段变更 | Rust Session | 有界尾部 reducer、历史页与详情 query | 内容订阅 stamp；逻辑 demand 变化或退出 |
| 当前项目、会话与 Settings 导航 | Client 本地意图 | Workspace / Selection controller | 选择身份；旧异步命令不能覆盖新选择 |
| 输入、参数、route 与附件引用 | Client 草稿；受理后可靠附件由 Rust 持有 | Draft owner 与附件 ownership ledger | DraftStamp + OperationId；明确转移或放弃 |
| 提交、pending overlay 与未知结果 | Rust mutation owner / Client operation owner | MutationBoard | OperationId 与目标 stamp；真实结果分别记录 |
| Live/History 与已加载消息 | 当前展示 lease | InMemoryChatController 公开操作 | ThreadId + 展示代次；显式回实时或切会话释放旧集合 |
| 光标、composing、焦点、折叠与即时滚动几何 | Widget / UI controller | 局部 UI controller | draftId / reading generation；Widget dispose |

同一 canonical 资源只有一个 reducer。命令响应若携带该资源的权威 snapshot，进入同一个
reducer；命令状态和 overlay 不成为第二份 canonical。bootstrap 只负责启动恢复，不能在
命令成功后读取聚合状态掩盖缺帧。Demo 分领域发布 baseline/frame，不能把生产缺帧通过
本地成功回读补齐。可靠历史、SQLite、checkpoint 和 writer 始终由 Rust 持有。
Demo 的模式目录同样由独立、带版本的 catalog baseline 交付，组件不以本地默认列表补全缺失的能力。

启动的 loading、ready 与 typed failure 由 Client 持有并供只读观察。应用生命周期调用一次
bootstrap；目录与 catalog 均就绪后才显示可用 shell。首个 baseline 前的失败也必须显示其
typed code 与 correlation，不能困在 Widget 的局部等待标志里。显式重试复用同一 Client，
清除失败尝试后重新启动；路由重建和普通查询不自动重试启动。
启动成功后，目录观察失败保留最后有效目录与可用 shell，并显示该领域的显式重试入口；不能
退回无操作的启动页。Thread 状态流的同步状态与 ChatUiState 分别属于各自观察通道；正文
重连或预算阻塞不污染 runtime 同步状态，正文恢复也不能把仍失败的 runtime 标成 ready。

## 25.3 版本域

- ResourceStamp 由 ResourceKey、OwnerEpoch、Revision 组成。仅同资源同 owner 可比较。
- ViewStamp 由 ThreadId、ViewId、ViewEpoch、Version 组成。新 view 的版本不能与旧 view 比较。
- AttemptId 是一次客户端异步绑定身份，不能充当业务 owner epoch。
- OperationId 是一次业务提交身份，首次 await 前产生，未知结果不换 ID 自动重放。
- DraftStamp 是 DraftId 与字段或项目 revision，不能用窗口版本替代。

配置与 catalog 的 revision 独立；Thread model route revision 是 route extension 的 CAS，
不是 Thread 通知序号。`saved` 与执行终态独立。页查询不推进订阅基线，不存在用窗口版本猜测分页回执的语义。owner 更换后必须接受新 baseline，旧 epoch 的回执不能由新 epoch 满足。

## 25.4 观察与导航

观察 API 同步登记接收者并返回当前值，检查当前镜像与注册 predicate 之间不能有 await。
显示观察暂停时，每个观察者只保留最新快照；可靠事件仍使用有序交付，不套用 latest-only。
订阅取消只移除自己的观察，不能关闭跨路由 Session、内容连接、草稿或附件。

AppGraph 通过逻辑 demand 管理资源。进入 Settings、切换设置标签和 Widget 暂停不改变当前
内容订阅 demand，不清理新会话或 Thread 草稿。明确切换 Thread 才 retire 旧内容资源；关闭项目、
归档与应用退出显式结束相应需求。provider keepAlive 不能承担 native 资源所有权，也不能让
每个曾访问会话永久保留正文。轻量 owner 缓存、观察者和镜像均受预算约束。

## 25.5 Timeline 连接与关闭

内容连接保留 open、initial、next 生命周期，按 [26](./26-timeline-content.md) 提供尾部订阅、
无状态历史页和详情查询，不再提供 focus/load/expand 窗口回执。每次 attempt 在首次 await
前登记 demand、原始 open Future、候选句柄、取消、pump、查询、close/join 和预算许可。
句柄返回立即归属该 attempt，每次 await 后核对 Thread、attempt、demand 与 retired 状态。

initial 建立新订阅自己的基线；同一订阅最多一个 next，reduce 后才继续取帧。内容缺口只
重同步当前连接，不重放业务操作，也不把旧 lastGood 当新基线。状态流和内容订阅独立，
一方恢复不把另一方标为 ready。页／详情结果只作用于捕获的展示代次；旧 A→B→A 请求
成功、失败或 finally 均不能清新 A 的 loading、内容或错误。

retire 先封闭发布与查询准入，再取消并 requestClose，等待泵、在途查询、sink 与句柄真实
ACK。失败保留 unresolved owner 和预算；取消等待不等于资源关闭。返回过晚的 open 仍由原
attempt 收束。关闭内容连接不关闭 Rust Session、Turn 或 writer；provider 只取消自己的观察。
Settings、标签页或 Widget 暂停不改变逻辑 demand，Thread 切换、项目关闭与退出才 retire。

观察重连采用有界退避和显式 retry；许可不足只在真实释放通知后恢复准入，不轮询或增加
容量。opening、active、retiring、unresolved 及查询等待均计入预算，失败不能用清空容器伪装
完成。已知 CAS 冲突只重建 runtime binding，保留独立的内容连接和草稿。

## 25.6 Read model 与呈现

设置、项目、目录、选择、Thread 轻状态和内容各有唯一 reducer。ThreadWorkspace 的 Thread
仅用于身份，目录元数据以 directory owner 为准；状态流不反写正文，保存与终态不互相推导。
状态流快照不反写目录行；updatedAt 不充当跨资源版本，同秒晚到快照不能回滚目录终态。
mode 等身份变更由 Rust 提交目录增量并推进所属水位。

普通问答与计划确认回执由 canonical 工具条目的 typed 问答历史派生，沿用同一身份与内容版本；
adapter 保留问题、答案列表、脱敏标记和权威状态，不让 feature 重新解析工具载荷。
composer pending interaction 队列只服务待处理交互，resolved 后不留队，不另建回答缓存。
页、尾部订阅和重开都从同一 Session 内容源恢复回执；局部展开不写回业务事实。敏感值
只接受后端脱敏投影，详情、摘要、复制和辅助语义均不得泄漏原值。

Client 只持有有界尾部基线及 typed 查询状态，当前 AppGraph 展示 lease 将内容投影为唯一
InMemoryChatController 消息集合。库负责列表与滚动；Live/History、消息稳定身份、分页、
详情及显示预算以 [26](./26-timeline-content.md) 为准。无服务端几何窗口镜像、跨层阅读锚点
或另一份完整历史 rows/body cache；页查询不改变尾部订阅基线。

Connector 读取查询并调用稳定目标 action，向纯 View 传唯一 props，不从 provider fallback
重读同一业务值。features 不得穿透 Client 公共边界直连 FRB、transport 或 SQL。详情、图片和
菜单等平台交互归适配层或 UI controller。显式回实时或发送创建新列表代次；旧代次只在其
子树释放与资源收束后销毁。Thread 切换释放旧展示集合，Settings 往返不关闭展示 owner。

## 25.7 命令、观察与效果

首次 await 前冻结目标、expected revision 和 OperationId。停止命令捕获 ThreadId + TurnId，
不按排队执行时的当前选择重定向。同一资源的冲突写串行，不同资源可独立推进；停止不排在
长任务 FIFO 后。分页和正文查询不占用设置写 lane。

CommitReceipt 至少携带 OperationId、Applied/NoChange、目标 ResourceStamp 和 effect point。
接受、观察、生效、持久化是独立事实：Accepted、AwaitingObservation、Observed、Effective、Durable
不能彼此替代。模型配置可对下一 Turn 或未来新会话生效，收到配置响应不代表正在执行的
调用已经切换。durable 只由可靠保存确认推进。

身份型回执按 [18](./18-studio-state.md) 的 Turn/interaction 谓词观察，不伪造 revision 或
通过空目标绕过屏障。观察拥有预算，并在确认、失败或 owner close 时释放；草稿提交的保存
确认继续等待对应 input 的 `saved`，不能以 terminal 代替。观察未到达时阶段仍为
AwaitingObservation，已知 Effective/Durable 单独保留。

Rejected 表示明确未受理；UnknownOutcome 表示提交可能已执行但缺少确定结果；SyncFailed
表示已知结果的观察失败。未知结果的非幂等命令不自动重放。局部 conflict、lagged 或失败才做
对应领域 typed resync；正常成功不执行 readStudioState 或聚合 reload。

MutationBoard 分开保存每次真实结果与每个目标的 latest intent。旧 operation 不能清除新 overlay。
观察 predicate 原子检查当前镜像并注册，使帧先到和回执先到均不漏确认。观察水位只在相同
owner epoch 和资源域合并。

供应商详情模型列表的阈值编辑只拥有原始输入、短暂防抖与最新意图身份；canonical 默认、覆盖、
生效与安全上限仍由 Settings/catalog reducer 拥有。有效输入、拖动结束和恢复默认触发同一
provider 原子保存，Client 在串行写 lane 内从最新 canonical provider 应用目标模型变更，
CAS 重试也重新构造，不携带未改动字段的陈旧副本。其余模型的持久覆盖必须完整保留，包括
因在线目录暂时撤下而不可见的覆盖。旧响应可推进自身操作记录及 canonical 水位，不能覆盖
较新原始输入、清除较新 pending/error 或让不同模型的修改互相丢失。
页面离开前将已产生的有效意图交给 Client；已经提交或排队的操作由 Client 持有并参与退出 join，
不能由 Widget dispose 取消。输入无效时不提交、保留校验错误；已知保存失败允许显式重试，
未知结果按既有 UnknownOutcome 语义处理，不自动伪造成功。

阈值的持久覆盖由 Settings revision 所有，模型预设和容量由 catalog revision 所有；两者的
canonical 合并必须使用各自最新水位投影默认、安全上限与生效值。仅目录推进时也重算这些
派生读数，不沿用旧配置快照中的模型预算；较旧目录不能借配置响应回滚新读数。只读投影
保留原始覆盖 Option，即使目录默认暂时恰好等于覆盖也不删除选择；等默认归一化只发生在
显式写意图及 desired provider payload。模型撤下时仅保留其存量覆盖，派生预算均未知；
同 slug 重现时从新元数据重算并恢复该覆盖，不触发补偿回读或自动配置写入。

### 25.7.1 供应商用量需求

供应商标签的 feature 状态负责自动加载策略，Client 查询 owner 负责按实例启动、去重、
pending/error 和在途任务，额度事实仍只经 ProviderUsageStore 的唯一 reducer 接收 canonical
响应或事件。Riverpod 展示适配只观察 Client，不直接调用 transport，不以另一份 AsyncValue
缓存取代同一 canonical。焦点、筛选、选择、FormKey 和编辑草稿继续由局部 UI owner 管理。

标签首次可见为每个当前查询身份发起一次检查；每个实例完成即发布，不等待其它实例。
同 provider ID、同 `usageQueryRevision` 的重叠自动/手动检查合并，不同身份的旧结果不能清理
新 pending 或覆盖新结果。查询身份由 Rust 所有，定义见 [18.2](./18-studio-state.md#182-公共-snapshot)。
标签可见期间，新增或查询身份变化只补查对应实例；隐藏时停止产生新的自动请求，重新可见
只补查未加载或失效身份。失败也计入本轮已尝试，不由重建、默认值变化或自动重试形成请求
循环。页面状态真正重建允许再次加载，手动刷新可明确发起新尝试，刷新全部复用同一实例能力。

页面只声明需求，不能在每次 Widget build 中创建请求，也不在保存回调中等待额度。已有在途
请求由 Client 持有并在应用退出时 join，页面取消观察不丢弃任务；删除实例清理其需求及操作
身份，迟到响应不得复活删除项。保留的标签状态往返不重复检查，不清当前 Thread／内容连接
或草稿；跨 AppGraph 不共享请求、需求、加载集合或结果镜像。

## 25.8 草稿与附件

StartDraft 与 ComposerDraft 有独立逻辑寿命，不随页面 observer 消失。freezeForSubmit 在
同步阶段冻结 DraftStamp、项目/Thread 身份、文本、模式、工作区、完整 route 和附件 ID 集合。
新建 Thread 直接提交该 route，不先写全局默认设置再读取缓存。已有 Thread 提交携带所观察的
route extension revision，受理 CAS 的语义见 [18](./18-studio-state.md)。

markSubmitting、accepted、observed 和 durable 均关联同一 DraftStamp + OperationId。
提交期间可继续输入和修改草稿；旧 ACK 只清理仍属于该提交且 revision 相符的字段。
TextEditingController 保存 composing/selection，draftId 变化时替换；同一草稿的普通重建不反复
重写 controller.text，旧完成也不能直接清空当前 controller。

附件 ledger 分开记录逻辑草稿引用和冻结提交引用。提交成功只转移冻结引用，较新草稿继续
引用的相同附件 ID 仍有效。只有最后一个 owner 释放后才请求 native 删除；删除失败保留 owner、
诊断与预算。未知受理结果保留冻结引用，不因页面退出、放弃当前草稿或全局 orphan sweep 删除。
本地 clipboard 暂存和晚到 admission 也由同一 ledger 收束。关闭过程等待在途创建和清理，
不以销毁 provider 代替异步资源回收；可靠附件与旧数据保留规则见 [17](./17-studio-storage.md)。

## 25.9 应用退出

AppGraph.close 幂等，重复调用复用首次 close Future 和绝对 deadline。先封闭草稿生产者，
加入在途提交，再收束会话、topic、update operation 和附件任务；独立取消并发启动，共用剩余
预算。每个未解决 operation 和资源出现在 CloseReport，不释放仍未确认关闭的 permit。

StudioExitCoordinator 的应用实例状态不跨图共享；宿主出口只路由到当前协调器。Client 的
CloseReport 在 Rust finalizer 前并入 externalIssues，只有所有真实 ACK 和可靠保存均确认才可
报告 Clean。超时不得另起期限或在 runtime 宣布 Clean 后追加失败来掩盖提前释锁。

## 25.10 验证与删除项

验证层次、证据边界与正式门禁以 [24](./24-testing.md) 为准。纯 Client fake、Riverpod adapter、
真实 Flutter 路由、FRB DTO fake、真实 native 和各平台 GUI 不相互替代。Driver 只保留诊断与
可见投影，不维护另一套业务生命周期或可写 canonical。

已被新 owner 替代的 provider 资源租约、第二份正文 baseline、成功后聚合回读、全局附件清扫、
宿主 Timeline fallback 和直接 FRB feature 入口应随调用方迁移删除，不保留永久回退分支。
