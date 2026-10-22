# v4 应用启动、退出与安装器边界

本文件固定D3/A/U3/R之间的应用生命周期接缝；[完整计划](./implementation-plan.md)与
[资源关闭合同](./v4-lifecycle-contract.md)不变。它不替代Workspace目录/选择及Updates
完整动作合同，未列齐的部分继续由root定稿，不授权实现者自由补接口。

## 1. 唯一owner与装配面

- StartupRepository属于SDK workspace领域，只持本应用实例的显式启动尝试/观察/读取。
- ApplicationExitCoordinator属于Flutter app装配层，唯一持首次退出意图/期限及跨域收束。
  不在SDK另建ShutdownRepository，不让Updates或WorkspaceRepository执行全应用finalizer。
- ApplicationLifecyclePort/StartupPort只从workspace_ports提供给组合根和adapter；VM/Widget
  仅借只读状态及向组合根发意图。所有native句柄/库初始化/task/stream由A的实际owner持有。
- WorkspaceRepository.close仅关自己的目录/查询/选择需求，不暗中关闭其他Repository。
  app root可遍历已明确持有的领域实例进行收束，不重建一个代理全业务方法的Client。

## 2. 显式启动

```text
StartupRepository
  state:ReadonlyLatestValue<StartupState>
  start()->OperationTicket<RuntimeReady>
  readRecovery(RuntimeStartupReadRef reference)->Future<StartupRecovery?>
  readActiveTurns(RuntimeStartupReadRef reference,{int offset=0,int limit=32})
    ->Future<StartupActiveTurnPage>
  seal()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>

StartupState = idle
 | starting{attemptId:int?,phase:StartupPhase}
 | ready{attemptId:int,result:RuntimeReady}
 | failed{attemptId:int?,error:StudioFailure}
StartupPhase = loadingLibrary | preparingAttempt | native{stage:StartupStage}
StartupStage = preparing | waitingForSteps | closingResources | backingUp | resetting |
 startingServices | openingStorage | loadingConfiguration | readingProjects |
 preparingResources | ready | failed
RuntimeReady {revision:int,readyAt:int,details:RuntimeStartupReadRef}
RuntimeStartupReadRef {entry:int,revision:int}
StartupRecovery {backupPath:String,reason:String,createdAt:int}
StartupActiveTurn {threadId:String,turnId:String}
StartupActiveTurnPage {
 reference:RuntimeStartupReadRef,offset:int,total:int,
 items:List<StartupActiveTurn>,nextOffset:int?
}
```

StartupState/phase及上述业务值使用Freezed；ticket/Repository/连接不使用Freezed。
readRecovery/readActiveTurns只在已登记固定版本的RuntimeStartupReadConnection上组装领域值，
不是第二native查询入口或另一snapshot owner；scope使用完仍真实close/join，不仅返回值后丢句柄。
loadingLibrary/preparingAttempt是明确的adapter本地阶段，不冒充Rust StartupStage。
删除旧Dart虚构的indexing/readingState阶段；LSP indexing是真实另一域的进度，不能混入启动。

`start`仅由组合根显式发起，首await前登记本地operation/尝试、预算与待返回open，重复在途
start复用同一真实ticket，不并行启动。Ready后不发新native attempt；真正退出开始后不再
允许启动。失败后仅显式start可以向native申请新attempt，原native拒绝原因不得吞掉。
第一次library初始化必须包含在该动作内；不在getter或readRecovery中隐式RustLib.init。

原生装配port：

```text
StartupPort
  initializeLibrary()->Future<void>
  prepareStartupAttempt()->Future<int>
  openStartupProgress(int attemptId)->Future<FeedConnection<StartupProgressFrame>>
  startStudioRuntime(int attemptId)->Future<RuntimeReady>
  openStartupRead(RuntimeStartupReadRef reference)->Future<RuntimeStartupReadConnection>
StartupProgressFrame = Data{deliverySequence:int,stage:StartupStage}
 | Failure{error:StudioFailure}
 | Closed{reason:StartupCloseReason}
StartupCloseReason = requested | attemptReplaced | completed | runtimeStopped
```

进度连接绑定open时的attempt，不每帧重复它。保原先订阅后启动的时序：initializeLibrary →
prepare → open progress → 实际listen认领 → startStudioRuntime。进度使用同一FeedConnection
ACK/取消/真实join能力；最多2个未ACK Data、可靠64帧/8MiB、单Data256KiB。十二个阶段
不因latest覆盖丢失，native Ready/Failed是有序Data，不绕过窗口；其后最多一次Closed。
控制Failure不与Closed叠发，取消不被窗口堵住。阶段Failed本身没有原不存在的error payload，
真实失败详情由start调用结果提供；仅stage Ready不足以结算启动成功。
首个Data是同登记边界取得的当前阶段并占ACK额度；注册后的每次阶段发布可靠入队，源本身
不能先用latest watch合并后再声称无损。R在原STARTUP owner发布边界接入已有feed队列机制，
保单一当前阶段及尝试权威，不另造启动状态机/总线。注册前不追补虚构的历史阶段。
阶段按真实来源事件呈现，不承诺enum顺序单调：当前prepare的初始阶段是OpeningStorage，
runtime随后可发布Preparing。VM不按enum排序、补造中间阶段或把这个顺序当Protocol失败。

`RuntimeReady`是本次明确新增的窄结果，不声称旧代码已有此DTO。R从原实际RuntimeSnapshot
确认state为Ready且同attempt/runtime未退出，取原revision和state.at，登记details后返回。
旧RuntimeSnapshot的startup_recovery/state/active_turns字段通过以下不可变scope完整可达，
不是删掉它们，也不是继续返回Studio聚合bootstrap。

```text
RuntimeStartupReadConnection
  header()->Future<RuntimeStartupReadHeader>
  activeTurns({int offset=0,int limit=32})->Future<StartupActiveTurnReadPage>
  text(int fieldId,{int offset=0,int maxBytes=65536})->Future<TextChunk>
  requestClose()->void
  close()->Future<FeedCloseReport>
  retryClose()->Future<FeedCloseReport>
RuntimeStartupReadHeader {
 scope:RuntimeStartupScopeIdentity,reference:RuntimeStartupReadRef,
 revision:int,state:RuntimeStateRead,startupRecovery:StartupRecoveryRead?,activeTurnCount:int
}
RuntimeStartupScopeIdentity {scopeId:String,ownerEpoch:String,attemptId:int,revision:int}
RuntimeStateRead = uninitialized{at:int} | initializing{at:int} | ready{at:int}
 | shuttingDown{at:int} | stopped{at:int} | failed{failedAt:int,error:SourceStateErrorRead}
StartupRecoveryRead {backupPath:ReadText,reason:ReadText,createdAt:int}
StartupActiveTurnRead {threadId:ReadText,turnId:ReadText}
StartupActiveTurnReadPage {
 offset:int,total:int,items:List<StartupActiveTurnRead>,nextOffset:int?
}
```

header/页/文本沿产品typed读取256KiB预算、页1..100、UTF-8块边界及共用runtime64在途call；
scope占readModel，每个启动来源最多8个scope。成功open pin原启动结果，不因其他业务
source推进失效；原版本已不可得Superseded、原runtime关闭Cancelled，close真join。
新scopeId用原new_id("startup-read")，ownerEpoch用原runtime epoch，不增加历史ID长度限制。
这里保留一次有界按需诊断读取，不建立全局RuntimeSnapshot镜像或新的持续消息总线。

已Ready同attempt调用的幂等检查、失败attempt不可复用、退出invalidate启动令牌继续复用
原STARTUP owner。prepare/start过程中退出，原任务仍由A/R登记并等待，迟到结果不能安装
新的业务域或把StartupState改回ready。已成功runtime但adapter映射/登记失败属于已知成功
后的同步失败，不自动再启动。start无通用native CommitReceipt，正常结果acknowledged。

生产初始Workspace selection固定为空（projectId/threadId=null、needsOpen=false）；真实
Rust启动快照没有selected IDs。demo/fake不向生产注入选择恢复能力。启动成功后各域独立
建立自己的feed基线，不再用readBootstrap/readStudioState一次写全域mirror。

## 3. 退出port与精确结果

```text
ApplicationLifecyclePort
  beginRuntimeExit({required int remainingMs})->Future<void>
  shutdownRuntime({required int remainingMs,
                   required List<StudioShutdownIssue> externalIssues,
                   required ExitIntent intent})->Future<StudioExitReport>
  finishShutdownDiagnostics()->Future<void>

ExitIntent = exit | updateRestart
StudioExitReport {shutdown:StudioShutdownReport,updateHandoff:UpdateHandoff}
StudioShutdownReport {
 outcome:ShutdownOutcome,issues:List<StudioShutdownIssue>,persistence:PendingPersistence
}
ShutdownOutcome = notStarted | clean | degraded
PendingPersistence = unknown | pending{count:int} | drained
StudioShutdownIssue {
 stage:String,code:String,message:String,retryable:bool,correlationId:String
}
UpdateHandoff = notRequested | launched{version:String} | failed{error:SourceStateError}
SourceStateError {code:String,message:String,retryable:bool}
```

SourceStateError/其Read形式由D0 resources定义一次，保持原三字段；不是缺correlation的
StudioFailure降级别名。StudioShutdownIssue同生命周期合同同一类型，不复制第二定义。
时间余量是毫秒非Unix时间；pending count是原可靠保存工作数，不用Dart队列长度替换。

U3协调器的root-only能力固定为
`exit(ExitIntent intent)->Future<StudioExitReport>`。首次调用冻结原intent和native宿主已武装的
30s绝对deadline，重复调用等待同一退出责任，不续期/替换intent。native清理上限28s，诊断
预留2s；remainingMs始终来自原native宿主剩余时间，不从Dart调用时重新起30秒计时。

退出顺序与边界：

1. 同步封所有Dart领域/operation/启动/更新准入，登记正在open、consumer/query、Controller
   和附件清理；立即发beginRuntimeExit。native arm latch/失效startup/广播取消，不是finalize。
2. 解除实际展示挂载并requestClose相关连接，独立owner可并行join，保留全部未发布candidate
   与未知操作归属。一个领域close不能阻止其它owner收到取消。永久失败仍保原typed issue。
3. 所有Dart外部报告（包括关闭/进度观察本身）必须在shutdownRuntime前形成externalIssues；
   剩余工作明确pending/deadline问题，不能先宣告Clean再追加。尚有原任务时保留owner。
4. shutdownRuntime是唯一native finalizer入口，合并externalIssues后join桥端订阅/更新owner
   并调用Rust runtime收束。调用方超时不drop真实退出任务、不重复启动第二finalizer。
5. finishShutdownDiagnostics独立收尾，在原期限内结束。安装器handoff结果独立于可靠退出；
   窗口/进程结束不是清理成功证据。临时UI observer销毁不作业务保存确认。

## 4. Clean、Stopped与installer条件

| 已确认事实 | 必须返回/保留的语义 |
| --- | --- |
| issues为空、persistence Drained、store closed，且FinishShutdown成功 | runtime发布Stopped并释放实例锁；可报告Clean |
| 任一external/internal issue、保存Unknown/Pending、store未闭、FinishShutdown失败/期限耗尽 | Degraded；不发布Stopped、不提前释放实例锁，不启动installer |
| runtime根本未安装、gate已取得、无被拒绝的迟到安装、无external issue | NotStarted；不是将进行中的启动当成已Clean |
| Clean + exit + 没有Ready更新 | shutdown保持Clean，handoff NotRequested |
| Clean + updateRestart + 没有Ready更新 | shutdown保持Clean，handoff Failed(updateNotReady) |
| Clean + 已Ready + OS派生成功 | shutdown保持Clean，handoff Launched(version) |
| Clean但installer派生失败/剩余期限耗尽 | shutdown仍Clean，handoff Failed；不冒充安装成功 |
| 已InstallerLaunched | 不重复派生，不证明安装完成或新程序已就绪 |

原runtime的`launch_ready_on_exit`仅处理Ready/InstallerLaunched，桥端只在Clean后调用。
Degraded不尝试handoff，其结果仍NotRequested。普通exit可交接已Ready更新，不能改成只有
updateRestart才安装。失败保原缓存/诊断，不因本次重构删除安装包、用户数据或凭据。

事实来源：`code/anywork/rust/src/api/studio/handlers/lifecycle.rs`的prepare/start/begin/shutdown、
`types/runtime.rs`、`types/shutdown.rs`；`code/pl-studio-runtime/src/studio/runtime/lifecycle/shutdown.rs`
的report与FinishShutdown/FailShutdown，`runtime/updater/mod.rs::launch_ready_on_exit`。
这些是源码核对，不是本次实现或运行验收证据。

## 5. 迁移与剩余项

- R迁移手写protocol/FRB启动结果、typed进度、按需启动详情及原真实退出接口，不改变core
  Runtime事实；A承担library/start/opaque映射并删除隐式ensureReady read入口。
- D3提供StartupRepository，U3只组合/退出；旧StudioBootstrap、同构selected IDs、
  StudioUpdateClient以及多处独立退出流程按原所有权表迁走/删除，不建转发alias。
- server保持原read/check/topic能力；不为桌面exit/updateRestart添加未授权server endpoint。
- Workspace所有动作/selection generation、Updates命令owner与VM完整ViewState仍待root
  接缝册闭合；本文件没有自动补齐它们，也没有开始任何实现或验证。
