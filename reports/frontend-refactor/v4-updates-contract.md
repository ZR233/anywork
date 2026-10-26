# v4 更新领域操作与单一进度来源

适用R/D3/A/U1/U3/C；服从[批准计划](./implementation-plan.md)、[产品读取](./v4-product-read-ports-contract.md)、
[关闭恢复](./v4-lifecycle-contract.md)及[应用退出](./v4-application-lifecycle-contract.md)。本文件
固定更新操作接缝；v5允许按模块实施，实际架构阻塞交root裁决，不等待全局合同齐备。

## 1. 事实与职责

- Rust `StudioUpdateRuntime`是唯一业务权威，拥有检查、可信manifest、下载、校验和安装包lease。
  D3 `UpdatesRepository`是唯一Dart镜像writer；删除旧StudioUpdateClient/UpdaterStore双层owner。
- 所有canonical进度只走Updates feed。删除手动operation的第二份snapshot stream，以及其
  bridge progress channel/forward task；不能从任务结果直接捏造Downloading/Ready。
- 操作owner只报告真实完成、原版本读取目标、取消和join。下载业务失败可正常完成并产生
  canonical InstallFailed；它不等于task panic/join失败，更不等于安装包Ready。
- 现`verified_update`检查是`actualRevision >= expectedRevision`且完整cached update的version
  相同，**不是相等CAS**。允许下载进度推进后的同版本选择；不得把它改成每个bytes更新都冲突。
  后续install锁仍校验完整cached update一致，只有合法phase才允许准备；不由Dart比较manifest。
- 手动准备若已有同一后台准备owner，沿用其取消token并等待原工作，不启动第二下载。
  原完成Ready可复用已校验lease；失败重试仍由显式新操作准入，不靠清理重试重跑业务。
- 平台启用策略是本地能力，不是canonical状态。当前production确为Windows且
  `dart.vm.product || ANYWORK_DRIVER`且非`ANYWORK_DEMO`；demo默认禁用。U3迁移该条件，不
  扩成所有平台自动启动，也不把本地disabled或未收到baseline伪造成Rust Disabled/Idle(rev0)。

来源：`app/app_graph.dart:44-50`、SDK`studio/update_client.dart`、bridge
`handlers/updater.rs`、runtime`runtime/updater/mod.rs`与`lifecycle/external_state.rs`。

## 2. D3公开值与能力

产品State继续使用字段册的`UpdatesState`，其value/读取错误、source状态与transport sync分离。
以下新增值由updates/domain定义；共享Operation/Close/ReadTarget仍复用唯一D0类型：

```text
UpdateControls {enabled:bool}
UpdatePreparationResult {readyVersion:Option<String>}

UpdatesRepository
  controls:UpdateControls
  state:ReadonlyLatestValue<UpdatesState>
  check()->OperationTicket<Unit>
  prepare()->OperationTicket<UpdatePreparationResult>
  cancelPreparation()->OperationTicket<Unit>
  loadSummary()->Future<UpdateSummary>
  loadDetails()->Future<UpdateDetails>
  seal()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>

// 只从updates_ports.dart给U3装配；不是VM自动build副作用。
UpdatesLifecycle
  startAutomaticOnce()->OperationTicket<Unit>
```

无原生CommitReceipt，以上action只走acknowledged/acknowledgedSyncFailed或真实dispatch失败，
不伪造effect/durable。prepare首await前冻结当前Updates source revision、完整已读summary的
version、OperationId与attempt，并同步登记全部owner/permit；尚未物化summary不可准入。
同一进行中check/prepare返回原ticket，不发第二请求；check与prepare互斥，取消不排其后。
仍有未解决旧准备owner时拒绝新的prepare，不因换VM清掉旧attempt。

readyVersion仅在**该操作完成目标**的canonical状态是Ready且version匹配冻结version时有值；
业务失败或已确认取消为None。成功完成后读取目标失败是acknowledgedSyncFailed，不抹掉已知
完成，不自动再check/reload/prepare。任务result不是新的canonical writer，结果读取材料只按
原origin/reference进入Repository归并；晚reply不能覆盖较新feed，必要last-known单独保留。

本地disabled时action在dispatch前以typed InvalidArgument拒绝；VM根据controls隐藏/禁用
控件，不显示虚构Rust状态。sealed优先Cancelled。source未知/缺summary时不可安装；原
InstallerLaunched不重复prepare。Native仍复核全部phase/version/锁条件。

## 3. 操作port：先取得owner，再开始工作

只供D3/A使用，不向VM暴露native handle。与feed不同，这些owner没有events/ACK；全进度
继续由独立Updates feed承载。三个具名open方法返回同一能力，因为结果均为UpdatesReadTarget，
不是用任意字符串kind或dynamic payload派发命令：

```text
UpdatesPort
  // 既有openUpdates/read/subscope签名沿产品读取合同。
  openUpdateCheck(OperationId operationId)->Future<UpdateTaskConnection>
  openAutomaticUpdate(OperationId operationId)->Future<UpdateTaskConnection>
  openUpdatePreparation(OperationId operationId,
    {required int expectedRevision,required String version})->Future<UpdateTaskConnection>

UpdateTaskIdentity {runtimeEpoch:String,taskId:String,operationId:OperationId}
UpdateTaskCloseReport {identity:UpdateTaskIdentity,outcome:FeedCloseOutcome}
UpdateTaskConnection
  identity:UpdateTaskIdentity
  start()->Future<void>
  finish()->Future<UpdatesReadTarget>
  requestCancel()->void
  close()->Future<UpdateTaskCloseReport>
  retryClose()->Future<UpdateTaskCloseReport>
```

Rust/protocol字段snake_case、serde camelCase；FRB对应BridgeUpdateTask/BridgeUpdateTaskIdentity/
BridgeUpdateTaskCloseReport与具名`open_update_check/open_automatic_update/open_update_preparation`。
taskId由native生成，不是可持久去重凭据；Dart OperationId原样往返。CloseReport是该operation
身份封套，复用FeedCloseOutcome/issues，不把非feed任务伪装成有baseline的feedId。

这是目标新接口：R拆分原register_update_operation的登记/启动边界，复用原lifecycle gate、
强registry与owned completion，不声称旧bridge已具有open/start。原后台wait后读当前状态
也必须改为completion持有同次完成快照/原origin；D3逐实例一次ticket是新增职责，不是旧API。

- open只注册/返回未启动owner；即使reply丢失也不执行检查/下载。opening本身仍由原bridge
  registry与Dartattempt监督，运行时退出需收束未知open，不以无业务写入冒充资源已释放。
- 原native lifecycle gate中原子登记owner、completion槽与exit latch；返回句柄后才准许start。
  start只允许一次，第二次为Conflict，不是重放能力；requestCancel/close优先封准入。
- start确认的只是启动受理，不是检查/准备完成；调用者先安装finish错误/结果观察再start。
  finish在start前可登记等待，close-before-start使该等待以Cancelled结束并可Clean关闭。
  startreply丢失后仍只等待原owner，不再start；无法确认结果保UnknownOutcome和同一owner。
- finish真实等待原工作及内部projection completion，成功时返回在原command锁内捕获并登记
  的最终UpdatesReadTarget。ReadTarget必须携原origin，不从当前feed补来源，也不在解锁后
  随便再读被另一check覆盖的新快照。共享后台owner的准备读取其保留的同次完成目标。
- 完成记录保留到该句柄close；业务错误分类和CloseReport独立。明确业务拒绝/取消可以
  伴随Clean；task panic/投影失败/缺completion是terminal issue，不能当业务失败吞掉。
  特别是canonical InstallFailed且原工作/projection均真实join时owner可Clean；业务失败
  本身不能被重复计为terminal清理问题。
- requestCancel同步通知原token且不等待；close封准入、广播取消并等待全部登记工作。
  finish结束不自动dispose，只有native及adapter的真实完成均确认、报告Clean后释放一次。
  retryClose严格沿CleanupRecovery，不清空所有cancel Future一律重跑；不重开任务。

## 4. 自动任务、取消和退出

U3在runtime Ready、Updates订阅已登记且收到首个canonical值后，显式调用startAutomaticOnce。
每个Repository只准入一次，native仍保原进程一次标记；重复装配调用借原ticket，不重新检测。
native标记在实际start准入边界改变，不在无业务的open阶段消耗；失败/未知不自动重放。
自动owner一直归应用，页面离开不关闭它；其start RPC结束不释放代表后台工作的permit。

cancelPreparation先同步冻结当前手动attempt；有手动attempt时取消该原owner（若共享后台
token则真实取消同一工作），否则取消应用仍持有的自动owner。两者都没有时为本地已知no-op，
不伪造native receipt。取消请求须在opening阶段被记住，晚句柄一到即requestCancel/close。
不因期间另一次prepare成为active而改取消目标。确认取消与Ready竞争时，以原完成目标为准；
不把完成后的Ready重新改为Cancelled，不销毁可信安装包lease。

关闭先seal，再同时取消所有check/automatic/manual opening及工作，join之后收束Updates
feed/read scopes；全部问题交U3，必须在唯一native finalizer前汇总。首次应用绝对期限不续期，
超时保原task和permit，awaitCompletion继续等；没有能力的永久失败保持terminal。

准备成功不启动安装器，也不自行退出。仅Smart根据prepared结果调用U3的updateRestart；
普通exit发现Ready同样按原规则handoff。Clean runtime shutdown与installer启动结果正交，
Degraded退出不可安装；签名/hash/文件lease、resume/重试/下载15分钟边界均保原实现。

## 5. Native内部进度的有界化

复用当前Tokio mpsc/JoinHandle/取消token和downlowd，不新增任务总线或下载器。除了删除
bridge第二路snapshot转发，原download→canonical projection的unbounded channel也改为容量64
的有界mpsc：

- Started/Verifying/Failed是有序阶段事实，异步producer使用send等待可用槽；receiver丢失
  必须传播owner失败并取消原download，不能忽略send错误继续宣称Ready。
  install/transfer缓存与失败路径的所有原同步send一并迁为async链中的send().await并传播错误。
- downlowd同步on_progress回调保持现250ms节流，使用try_send；Full仅可舍弃此时的中间
  Progress数值，不阻塞回调、不新spawn任务、不丢阶段终态；Closed通知取消并保owner错误。
  回调中的bytes==total早于文件sync/长度确认，不能作为权威完成进度；该回调只交付
  downloaded<total的中间值，最终total值由下述可靠异步路径发送。
- download成功或命中完整缓存后的最终`Progress(total,total)`改为异步可靠send，之后才发送
  Verifying。失败的最后事实是Failed；不可为凑100%伪造完成。队列FIFO保Started先于进度、
  最终进度先于校验；native状态机已有单调/长度校验不删。
- 下载future不因select/drop提前消失；仍由downlowd回调观察取消，等文件flush/close。
  projection JoinHandle真实join后才发布Ready并保可信lease。该64是内部事件数界，不假称
  FRB wire或RSS预算；外部Updates feed仍按产品合同的可靠阶段/高频合并与256KiB预算。

## 6. 迁移与最终验证映射

R一次迁移runtime updater、底层download sender签名、bridge owner/退出collector；A只转换新
task与唯一feed，不保read_studio_update_state失败兜底/旧progress_stream；D3删旧client/store；
U1真VM保存request pending/error/latestIntent，U3拥有平台能力与自动启动/退出；C迁所有替身/
Driver/消费者。HTTP只保原检查动作及替代旧read/topic的typed Updates feed/read，不新增
桌面prepare/install/automatic/cancel或task open/start/finish端点；Server内部check仍须监督
实际任务，但不把其句柄变为新HTTP安装能力，不允许普通检查调用触发installer。

最终阶段覆盖：首Data前不自动启动/启用条件、未知source不造Idle、同版本进度推进仍可准备、
手动共享自动owner、满进度队列/阶段顺序、业务InstallFailed且ownerClean、panic terminal、
opening取消/晚句柄/丢startreply不重放、finish后读取失败、旧reply隔离、显式清理恢复、准备
与退出/installer结果分离。此处仅冻结测试需求，本阶段不运行测试/编译/生成。
