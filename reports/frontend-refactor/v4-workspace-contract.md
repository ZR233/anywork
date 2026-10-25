# v4 Workspace目录、选择与项目动作

D3是Workspace事实/选择唯一writer，U3只装配并以VM编排用户界面。字段采用产品类型册，
观察与关闭采用产品read ports/生命周期合同；本册不增加另一selection provider、启动时
猜测选择或把UIController搬入SDK。

## 1. 选择与目录借用

```text
WorkspaceState {selection:WorkspaceSelection,selectionGeneration:int,sealed:bool}
WorkspaceSelection {projectId:String?,threadId:String?,needsOpen:bool}
WorkspaceIntentStamp {generation:int}
ThreadDirectoryScope = query{query:DirectoryQuery} | thread{threadId:String}

WorkspaceRepository
  state:ReadonlyLatestValue<WorkspaceState>
  projects:ReadonlyLatestValue<ProjectDirectoryState>
  agents:ReadonlyLatestValue<AgentDirectoryState>
  queryThreads(DirectoryQuery query)->ThreadDirectoryQuery
  thread(String threadId)->ThreadMetadata
  readProject(String projectId)->Future<ProjectRecord>
  readThread(String threadId)->Future<WorkspaceThreadRecord>
  openProject(String path)->WorkspaceOpenBatch
  openRemoteProject(String alias,String path,{String? name})->WorkspaceOpenBatch
  selectProject(String projectId)->OperationTicket<WorkspaceSelectionResult>
  selectThread(String threadId)->OperationTicket<WorkspaceSelectionResult>
  selectAgentThread(String threadId)->OperationTicket<WorkspaceSelectionResult>
  openSelectedThread(String threadId)->OperationTicket<WorkspaceSelectionResult>
  beginNewThread(String projectId)->OperationTicket<WorkspaceSelectionResult>
  restoreThread(String threadId)->OperationTicket<WorkspaceSelectionResult>
  renameProject(String projectId,String name)->OperationTicket<ProjectRecord>
  archiveProject(String projectId)->OperationTicket<Unit>
  renameThread(String threadId,String title)->OperationTicket<WorkspaceThreadRecord>
  archiveThread(String threadId)->OperationTicket<ArchiveThreadResult>
  seal()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>

ThreadDirectoryQuery                      // runtime借用，D3监督实际工作
  query:DirectoryQuery
  state:ReadonlyLatestValue<ThreadDirectoryState>
  loadMore()->Future<void>
  retry()->Future<void>
  requestClose()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>
ThreadMetadata                           // 同资源的单实体观察借用，不激活执行owner
  threadId:String
  state:ReadonlyLatestValue<ThreadMetadataState>
  retry()->Future<void>
  requestClose()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>
ThreadMetadataState {
 projection:ProductProjection<ThreadDirectoryHeader>,
 sourceStatus:ReadValue<ProductSourceStatus,ProductSourceStatusRef>?,
 value:ReadValue<WorkspaceThreadRecord,ProductEntityRef>?
}
WorkspaceSelectionResult {
 intent:WorkspaceIntentStamp,selection:WorkspaceSelection,disposition:SelectionDisposition
}
SelectionDisposition = selected | unchanged | superseded
```

WorkspaceState/Selection/IntentStamp/Result及ThreadMetadataState为Freezed值，query/metadata
借用不是Freezed。初始选择空且needsOpen=false；threadId非空必须有它真实的projectId，
needsOpen仅有已选Thread时可true。选择不从缺页、目录排序变化、Field读取失败中猜默认。

queryThreads/thread创建按需只读借用并登记预算，不发activation/扫描/联网或业务写入。
ThreadDirectoryScope.query保原root过滤/搜索/keyset；scope.thread仅读取该既有Thread
完整目录元数据，允许原已存在的child详情能力，不使用query的root-only谓词隐藏它。
它仍是19资源中的ThreadDirectory，不添加第20个业务feed，也不启动model/tool/continuation。
单实体初开不存在按原read_owned_thread语义报NotFound/权限错误，不以空集合假成功。
其baseline有一个实体，hasMore=false、cursor=None；后续原目录事实变化正常推送。

`readThread`通过本域单实体scope读取完整元数据，不把当前Sidebar window查不到视作
不存在；readProject同理使用ProjectDirectory完整scope的lookup。缺页不激活任何Thread。
读取与query/metadata借用都由同一Repository登记、取消/join；释放一个借用不关闭其它
query/Session。相同业务值可共享immutable对象，不能另建可写Thread overlay store。

## 2. 选择时序与最新意图

所有选择入口首await前登记WorkspaceIntentStamp并冻结请求ID/当前根关系；每次新的明确
选择意图递增generation，包括A→B→A及撤回尚在途B而回到当前A。没有其它在途/未知目标
且目标已经成立的纯同步no-op可复用当前generation。目录数值更新不伪造用户意图。异步结果只有generation
仍当前、Repository未sealed且目标仍合法时才提交selection；旧结果只结算原操作并返回
superseded，不将已发生的native activation说成已撤销。

- selectProject保原显式activateProject能力；相同项目已选中可返回unchanged而不重复
  native调用。选中项目后的默认root采用原目录排序中的该项目首个未归档root，查询条件为
  projectId、archived=false、filter=all、search=None；不把当前Sidebar搜索/分页缓存当完整
  业务目录。没有root才选项目起始态；这是原_selectProjectDefault“首个项目root”语义的
  明确来源，删除旧只有当前窗口内才找到root的缓存依赖，不按updatedAt或任意ID猜最新。
- selectThread是本地选择，不为了统一操作模型额外activation；后续Conversation demand
  按真实selection/needsOpen启动。目标元数据必须来自已确认的目录读取；无值先读，读完
  重查本意图，不使用当前选择替换请求ID。
- selectAgentThread保原限制：仅当前root所属的目标，不借旧回调切入其它root。先冻结
  原root关系，再取目标元数据并重查generation；不是只比最后threadId。
- openSelectedThread只对仍为该threadId且needsOpen的当前选择清门控，不成为新的选择者。
- beginNewThread显式以冻结projectId进入该项目起始草稿，不清其它项目/Thread草稿。
- restoreThread是原native restore动作，成功后也按原generation裁决选择；迟到恢复不能
  抢回新导航。不能把该有副作用动作伪装成readThread。

这些操作无原通用native receipt者使用acknowledged(WorkspaceSelectionResult)，仅确认
本次领域动作及明确的selection disposition，不伪造native写入或durable。纯本地unchanged
不调用transport，也不声称发生了native mutation；unknown activation保原operation并停止
自动重发。图/路由/VM只读取WorkspaceState，不能自己assign selected IDs。

## 3. 打开项目的独立步骤批次

原open/remote-open可包含打开、可选rename、activation三个真实动作，不能把前一步成功
和后一步失败折叠成false或伪父receipt。Repository持有批次，不靠VM寿命继续。

```text
WorkspaceOpenBatch                       // runtime，不是Freezed
  operations:List<OperationObservation>
  result:Future<WorkspaceOpenResult>
WorkspaceOpenResult {steps:List<WorkspaceOpenStep>,selection:WorkspaceOpenSelection}
WorkspaceOpenSelection = applied{value:WorkspaceSelectionResult}
 | notAttempted{reason:StudioFailure} | failed{error:StudioFailure}
WorkspaceOpenStage = open | rename | activate
WorkspaceOpenStep = opened{operationId:OperationId,result:CommandResult<ProjectRecord>}
 | renamed{operationId:OperationId,result:CommandResult<ProjectRecord>}
 | activated{operationId:OperationId,result:CommandResult<Unit>}
 | notStarted{operationId:OperationId,stage:WorkspaceOpenStage,error:StudioFailure}
```

local open固定open→activate；remote open有name时固定open→rename→activate，无name省rename。
首await前冻结path/alias/name与selection意图，登记每步独立ID/permits，无法完整准入则不
部分dispatch。新建/打开Project结果与activation结果分别可见；任一步rejected/unknown/
syncFailed都停止后续，未dispatch明确notStarted，不回滚删除已经创建的Project。

name已等于native open返回的canonical name时，rename步骤可acknowledged同ProjectRecord，
明确没有native rename；不用虚假CommitReceipt.NoChange。全部必要native步骤确认后才
按generation采用默认选择；若此时已superseded，原创建/激活成功仍保留，不能谎称取消。
原openRemoteProject捕获任意错误返回false的路径删除，SSH认证/网络/文件错误保持typed。
后续读取/选择失败通过WorkspaceOpenSelection.failed返回，不能从result Future抛错而
丢弃已成功步骤；前面步骤未成功时selection为notAttempted并保真实原因。

## 4. 目录mutation与归档

WorkspacePort除产品读取能力外具有以下具名方法；异常按CommandDispatchFailure区分
未受理/未知/已知成功后失败，不用StudioFailure.code猜提交点：

```text
openProject(String path)->Future<ProjectRecord>
openRemoteProject(String alias,String path)->Future<ProjectRecord>
activateProject(String projectId)->Future<void>
renameProject(String projectId,String name)->Future<ProjectRecord>
archiveProject(String projectId)->Future<ProjectRecord>
restoreThread(String threadId)->Future<WorkspaceThreadRecord>
renameThread(String threadId,String title,{required OperationId operationId})
  ->Future<RenameThreadCommandReply>
archiveThread(String threadId,{required OperationId operationId})
  ->Future<ArchiveThreadCommandReply>
RenameThreadCommandReply {thread:WorkspaceThreadRecord,receipt:CommitReceipt}
ArchiveThreadCommandReply {result:ArchiveThreadResult,receipt:CommitReceipt}
ArchiveThreadResult {archivedRootId:String,removedThreadIds:List<String>,nextRoot:WorkspaceThreadRecord?}
```

上述ProjectRecord/Thread结果是本次明确动作的immutable结果，不是全目录/Studio snapshot。
返回值不直接覆盖canonical镜像；目录push及本册原source stamp观察保持唯一归并路径。
原Project archive runtime可返回None，FRB/HTTP成功路径都把缺Project转错误，因此新port
成功返回非空ProjectRecord；它是被归档项目，不是默认后继项目。

原rename/archive输入约束与root/recovery/busy准入保留，Rust重复核真实当前状态；Dart
目录status不代替Execution实时准入。Thread rename/archive receipt见专册，Project动作
没有通用receipt，不用线程目录receipt冒充。停止与只读分页不排在目录长写lane后。

项目归档必须按所有**实际拥有的**project关联Session/草稿/query收束，不按当前已加载
Sidebar窗口的IDs假定全量。首await前捕获原owner身份，已确认native归档后释放对应本地
需求；不能清同ID替换owner或用户后来新建的草稿。未知操作冻结附件引用仍归原提交，
归档/放弃另一个draft不删除它们。用户数据/工作树的删除范围继续由原native租约/CAS约束。

native归档结果与原目录显式删除/归档事实驱动选择失效；窗口暂未加载不当删除。迟到归档
只能影响它明确归档的ID，不能把后来的新选择强制换成旧nextRoot。原Project被移除后的
后继选择规则保持独立，不由Widget自己猜并回写。
Project显式移除后的后继为当前canonical项目集合按原String id.compareTo排序的首个项目，
选项目起始态（threadId=null、needsOpen=false），不隐式activation或删除其草稿；项目集合
未知/只加载一页不能据此选择后继，应完成必要的源查询。Thread archive优先采用native
结果nextRoot（原同项目root序列中先后一个、无后一个再前一个），不让较迟的普通remove
回调覆盖它；无对应归档结果的明确remove采用该项目原排序首个剩余root。都须核当前选择
仍属于被移除目标及原generation，原结果不能抢走后来的新选择。

## 5. 创建Thread后唯一选择接缝

D1冻结新建前借用一个root装配能力，不持有Workspace reducer：

```text
WorkspaceSubmissionSelection             // 仅workspace_ports可写能力
  capture(String projectId)->WorkspaceIntentStamp
  adoptCreatedThread(WorkspaceThreadRecord thread,WorkspaceIntentStamp expected)->bool
```

capture同步核当前仍是该项目的起始选择并返回generation；adopt仅在同generation、未sealed、
thread.projectId匹配原项目且原意图未被取代时由Workspace唯一writer发布。返回false只表示
未采用导航，不否认创建/提交已经成功。该能力由组合根注入D1，UI/VM不能取得其writer。
D1传真实已确认的新建结果，不能从prompt标题猜ID或为选择重发创建。

## 6. 本册剩余闭合

- [x] 默认项目/root与归档后继规则已明确，原cache窗口不再冒完整目录。
- [ ] Project/Thread命令结果中大载荷的跨FRB/HTTP有界读取（尤其removedThreadIds），
      本册列齐语义，不把整列表返回说成已满足所有wire预算。
- [x] Query/metadata工厂及ThreadDirectoryScope输入已同步到产品read ports/HTTP合同。
- [ ] 对应Workspace/Sidebar VM的完整Freezed state、动作和Dumb props。

本册不放行全量编码；未运行编译、测试、生成、格式化或GUI。
