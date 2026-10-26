# v5 实施中的共享接缝决定

本文件记录实际实施阻塞的root裁决，不恢复整包合同细化前置。各writer只改自己范围，
未受影响部分继续实施；公共类型与下文实际字段不一致时报告root，不增加兼容alias。

## 1. 应用依赖注入与编辑意图交接（U3 / U1 / U2）

唯一公开注入入口为`code/anywork/lib/src/app/app_bindings.dart`，U3拥有。以下均是
`Provider<对应公开领域能力>`，不是canonical镜像或业务facade：

- configurationRepositoryProvider / modelsRepositoryProvider / modesRepositoryProvider
- accountUsageRepositoryProvider / statisticsRepositoryProvider
- workspaceRepositoryProvider / startupRepositoryProvider
- conversationRepositoryProvider / draftsRepositoryProvider
- remoteRepositoryProvider / mcpRepositoryProvider / lspRepositoryProvider
- skillsRepositoryProvider / recoveryRepositoryProvider / persistenceRepositoryProvider
- updatesRepositoryProvider / applicationExitCoordinatorProvider
- applicationEditProducerRegistryProvider

composition必须在创建功能VM前为每个ProviderContainer注入该AppGraph的真实实例；默认缺少
必要注入时明确失败可作为装配前置条件，不作为未实现业务占位或demo假数据兜底。feature
VM可从此处取得领域公共能力，不反向导入app_graph或另一feature私有VM。

U3在`app/lifecycle/exit_participant.dart`提供运行时能力（不Freezed）：

```text
ApplicationEditProducer.sealAndHandoff()->void
ApplicationEditProducerRegistry.register(ApplicationEditProducer)->ApplicationEditRegistration
ApplicationEditProducerRegistry.sealAndSnapshot()->List<ApplicationEditProducer>
ApplicationEditRegistration.unregister()->void
```

它仅登记应用现有自动保存生产者，不是操作registry或消息总线。Instructions/ModelLimits等
VM注册一次，显式离开/切target先将已形成有效意图交给Repository，再撤销登记；不得在
dispose中新开写入。应用退出先sealAndSnapshot拒绝新登记，再对每项独立捕获错误地调用
sealAndHandoff，之后才seal Repository/operations。snapshot强持有本次责任，期间unregister
不能让退出遗漏原producer；重复unregister幂等，sealed后register以Cancelled拒绝。
手动表单不自动保存、不注册成自动保存producer；已有ticket继续由原领域owner收束。

## 2. 公共UI与会话呈现边界（U0 / U1 / U2）

- 旧ConversationActivityView(kind/storage/wait)是复合呈现，不在SDK或共享l10n重建同构值。
  U2在conversation自己的VM/state/helper中承接组合、label/icon/isIssue；U0移除共享helper
  对旧复合值/旧巨桶的依赖，其余映射只引用真正所属领域的公开enum。
- ThreadStatus canonical定义在workspace领域；conversation引用同一类型。当前D1已采用
  workspace公开导入，不再根据早期中间文件认定仍有重复enum；其它任务不得再定义一份。
- `EffortSelector`新增`allowDefault:bool=false`。Profile Smart显式true，Conversation保持false。
  true时菜单具有明确null/default选项并回调null；false时null只是当前默认值展示，不凭此
  增加可选择能力。可选性由`allowDefault || efforts.isNotEmpty`与已有enabled/blocked共同决定，
  不替换未知选项、不自行归一化effort、不把null换首个字符串。该布尔仅表达两种现有UI能力。

## 3. 有界列表读取缺口的处置

U1已确认各Repo仅loadById不足以从未物化的collection建立可见列表。D2/D3需给root报告
具体领域的公开列表页/可见读取能力；不能让VM导入ports、把refs当完整值、自动物化全部
长正文或恢复旧全量snapshot。root按实际方法裁决后同步相关writer。此缺口只阻塞相关
列表，不阻塞已定的General/Instructions/Mode编排与其它独立功能。

### 3.1 D2具名读取能力

以下新增public Repository方法由D2实现、D0导出，U1只调用这些能力，不导入ports。页方法
返回`Future<void>`，唯一更新对应Repository state；默认limit=32，合法1..100，一次只读取
一个当前collection索引页及本页所需材料，不自动扫完整集合。无初始页时从首项开始，后续
调用从Repo保存的当前continuation前进；相同进行中页需求合并，完整时幂等，不创建operation。
首await前冻结origin/ref/continuation；旧页/delta按原版本链规则，不覆盖新scope。失败保留
last-known与typed局部错误；retry仍纯read，不重发命令。provider dispose只撤销观察，不
丢已经登记的读取工作，其真实收束仍归Repo。

```text
ConfigurationRepository
  loadAccountsPage({int limit=32})->Future<void>
  loadProfilesPage({int limit=32})->Future<void>
  loadDefaultAccountId()->Future<String?>
  loadModeRoutes()->Future<List<ModeModelRoute>>
  loadRoleRoutes()->Future<List<RoleModelRoute>>
  loadPermissionMode()->Future<String>
  loadMcpConfigurations()->Future<List<McpConfiguration>>
  loadProfileDiagnostics()->Future<List<ProfileDiagnostic>>
ModelsRepository
  loadAccountsPage({int limit=32})->Future<void>
ModesRepository
  loadModesPage({int limit=32})->Future<void>
AccountUsageRepository
  loadRecordsPage({int limit=32})->Future<void>
```

scalar方法也更新已有对应ReadValue；完整集合返回按现有typed嵌套页读取，不放宽单次运输
预算。已有loadAccount/loadProfile/loadModel/loadTemplates等继续存在，不用新增泛field读取。

Profiles列表不为了绘制一行自动加载systemInstructions：新增领域值`AgentProfileSummary`，
字段为`profileId,displayName,description,whenToUse,accountId,modelId,effort?,source,revision,
contentHash,system,enabled,workspaceMode`，类型与AgentProfileSnapshot对应字段相同。
`ProfilesState.profiles`改为`CollectionMirror<AgentProfileSummary>`；新增
`details:Map<int,ReadValue<AgentProfileSnapshot,ProductEntityRef>>`，key为原entry，value携原origin。
loadProfilesPage仅物化summary，loadProfile(id)才加载完整instructions并更新details。其它
未请求长正文保持Deferred；不以空串伪造完整值。原source/transport/read错误仍独立。

### 3.2 Models命令目标交接（装配能力）

```text
ModelCatalogTargetReceiver.synchronize(ModelCatalogReadTarget target)->Future<void>
createModelsRepository({required ModelsPort port,required ResourceBudget budget})
  -> ({ModelsRepository repository,ModelCatalogTargetReceiver targets})
createConfigurationRepository({required ConfigurationPort port,required ResourceBudget budget,
  required OperationRecorder operations,required ModelCatalogTargetReceiver modelTargets})
  -> ConfigurationRepository
```

工厂与receiver只从models_ports/configuration_ports导出，record两能力指向同一个Models
实例，不新建mirror或operation依赖。Config不能写Models reducer。synchronize登记原target，
经Models自己的feed/read路径确认同origin该ref或已覆盖它的较新版本；不加载所有模型正文，
不从最新feed补origin，不回滚较新镜像。Config真实commit后并行等待自己必要同步与该能力，
失败按已有committed/syncFailed结算，不重发保存；无receipt reload同理用已知成功同步失败。
该target读取/join由Models监督，Config只等结果，不取得其writer/关闭权。

### 3.3 Statistics公开接口与来源检查

```text
StatisticsRepository
  summaries:ReadonlyLatestValue<StatisticsSummaryState>
  history:ReadonlyLatestValue<StatisticsHistoryState>
  loadSummariesPage({int limit=32})->Future<void>
  loadHistoryPage({int limit=32})->Future<void>
  costs(String rootThreadId)->SessionCostsQuery
  seal()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>
SessionCostsQuery
  rootThreadId:String
  state:ReadonlyLatestValue<SessionCostsState>
  load()->Future<void>
  requestClose()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>
createStatisticsRepository({required StatisticsPort port,required ResourceBudget budget})
  -> StatisticsRepository
```

Statistics不依赖operations，不新加服务端筛选。summaries/history独立，VM按原AccountModelKey/
effort等已有控件对已取得材料做展示筛选，不Dart重算聚合，不把部分页当全量；需要完整
匹配时显式请求剩余有界页。页面所需首次read才启该来源观察；已登记工作由Repo持续监督。
costs是具体root的runtime借用，同root可共享内部canonical owner但每个借用独立close；关闭
一借用不关闭他人观察。原生scope/在途调用使用现有readModel和全局64预算，无额外池。

A负责native scope/open及响应的scope identity一致性；D2仍校原origin/ref/collection与本次
query generation，不因adapter校验就接受旧页。无需为此新增公共scope getter，fake同样
遵守port契约，不用缺字段给错误版本背书。

## 4. D0静态审查修复与后续证据诊断

- LatestValue谓词可能同步重入publish。求值前后必须核同一publication，过期求值的true或
  异常不能结算当前waiter；不是在已complete之后再丢弃旧通知。
- Freezed不可修改getter不等于复制输入。receipt targets、close issues/unresolved及其它
  会影响证据/资源不变量的外部集合在构造/受理边界作防御性快照；不能通过原List别名事后
  清空目标使操作完成或把Unresolved变Clean。必要构造器可非const，消费方同步迁移。
- observation登记键使用完整、类型区分的身份元组，不以`chat:$threadId:$viewId`分隔拼接
  作为唯一lookup身份；合法String不缩窄字符集。covers继续核完整owner/view身份与水位。

OperationWriter新增`evidenceFailed(StudioFailure error)->void`，OperationState新增
`evidenceError:StudioFailure?`：仅记录同一操作最后一条后续证据读取诊断，相同值幂等；它不
修改已完成ticket.result、不覆盖原failurePhase/error、不撤销accepted/observed/effective/
durable、不重发或把Unknown判拒绝。后续真实事实仍能更新原operation；evidenceError是
最后读取失败记录，不单独表示操作重新pending，不使清理报告变Clean或失败。证据owner
必须保持该operation的实际观察借用，未完成证据责任不能被无观察者淘汰规则丢弃。

ReadScopeIdentity采用Thread合同已定四字段，归D0 resources唯一定义；ConfigProjectionStamp
采用已定settingsRevision/modelCatalogRevision/closing，归D2 configuration；
ThreadStorageExecution归D3 persistence唯一定义并公开导出，不由D1复制。D1现有预算收费
只读publisher私有机制允许conversation/drafts在同一责任组内部复用，但不得公开为新共享
facade或跨入其它领域；没有证据不为搬代码再造D0通用框架。

## 5. Thread目录扩窗与Remote v9（R / D3 / A）

### 5.1 Thread固定窗口与扩窗

采用新不可变窗口，不使成功open的read scope变异。WorkspacePort的openThreadDirectory
返回专用`ThreadDirectoryConnection implements FeedConnection<ThreadDirectoryFrame>`，新增：

```text
extendWindow(ProductCollectionRef expectedCollection,{int limit=32})
  -> Future<ThreadDirectoryReadTarget>
```

origin、完整query与后端frontier由具体connection持有，不让Dart传任意后端cursor拼接窗口。
limit合法1..100；仅query scope可扩，thread metadata scope拒绝InvalidArgument。原窗口
hasMore=false时返回当前target；同一connection仅一个扩窗在途，同需求共享原工作，冲突
expectedCollection以StaleRevision拒绝。closing优先Cancelled，所有工作计同一64详情调用。

初始普通前缀32项；扩窗追加最多limit个此前窗口外的匹配非重复成员或到后端末尾。保原
root/archived/filter/search、热覆盖冷、普通时间+ID降序，配置pin匹配项作为配置顺序前缀
去重保留。已有query默认包含pin；默认root选择使用明确不含pin的query能力，不借Sidebar
缓存。完整scope增加`includePinned:bool=true`，只作用query；archived时不加pin前缀。

发布新的collection/ref与对应typed change后才返回target；业务Directory/Project来源
revision不因扩窗增长。旧read scope继续pin旧collection。源变化按同查询与已请求前缀长度
重算并发布或局部resync，不能把不同来源时刻页拼接。header.hasMore指后端窗口外仍有数据；
EntryPage.hasMore/nextCursor只指该固定窗口内尚有页，CollectionWindow.complete只表示该
窗口物化完整。loadMore先完成当前窗口页，再在header.hasMore时扩窗；两者均尽才是总结束。

read cursor由native以既有typed serde游标机制绑定scope/collection及pin前缀位置或原普通
keyset，不使用显示名构造、不兼容旧无scope字符串。native后端普通keyset语义不变。

R必须将目录读取置于覆盖实际persist→publish的来源发布屏障，不能只看两个revision读数。
优先复用原目录命令同步边界；若没有覆盖该区间的边界，采用该领域现有Tokio锁能力建立窄
读写屏障：所有目录写在persist前登记并持有到发布/失败处理结束，读取只在一致快照构建
期间持有读保护，成功pin后释放，不跨scope寿命持锁。不得同步Mutex跨await；目录/Project/
pin配置的捕获与锁顺序需R报告具体证明。失败持久化若不能恢复一致来源则明确失败/resync，
不可解锁后把部分持久结果盖旧source水位。控制取消不等待普通写FIFO，查询真join后才释锁。

### 5.2 Remote是分页查询，不是产品feed

按新main v9原生cursor，不新增伪Product origin/revision：

```text
RemotePort.openDirectory(String alias,{String? path,String? cursor})
  -> Future<RemoteDirectoryReadConnection>
RemotePort.closeDirectory(String alias,String cursor)->Future<void>
RemoteDirectoryReadConnection
  header()->Future<RemoteDirectoryReadHeader>
  entries({int offset=0,int limit=32})->Future<RemoteDirectoryEntryPage>
  text(int fieldId,{int offset=0,int maxBytes=65536})->Future<TextChunk>
  requestClose()->void
  close()->Future<FeedCloseReport>
  retryClose()->Future<FeedCloseReport>
RemoteDirectoryReadHeader {
  scopeId:String,path:ReadText,parent:ReadText?,nextCursor:ReadText?,pageEntryCount:int
}
RemoteDirectoryEntryPage {
  scopeId:String,offset:int,items:List<RemoteDirectoryEntryRead>,nextOffset:int?
}
RemoteDirectoryEntryRead {name:ReadText,path:ReadText,isDirectory:bool,isSymlink:bool}
RemoteDirectoryState {
  alias:String,path:String,parent:String?,entries:List<RemoteDirectoryEntry>,
  nextCursor:String?,loading:bool,error:StudioFailure?
}
```

ReadConnection仅pin本次native返回页，offset只物化这页，不重扫目录；其scopeId由原生分配，
无业务sourceRevision。关闭页scope释放页材料，不自动销毁已交接Query的native cursor。
Query持alias+真实cursor，continuation成功替换旧cursor，换目录/切服/关闭和晚返回按25.12
真实closeDirectory；未知close保原责任/恢复能力。scope与详情调用沿现有readModel/64预算，
各page/text256KiB预算。header返回前，opening owner持所有返回资源；交接失败也必须收束
该页和native cursor，不因Future丢失遗失资源。listing不宣称后端总数，删除total/nextOffset
旧全目录状态；UI loadMore更换页而非追加完整目录。

当前browseRemoteDirectories保原picker过滤`is_directory && !is_symlink`，不扩大为任意文件
浏览；R补DTO原is_symlink字段、A逐项真实映射，不把“过滤后应为false”当缺字段默认值。
Remote server列表/连接值是本域显式reload/test等动作结果，不贴伪ProductStamp。

Updates详情唯一公共类型采用字段册`UpdateDetails {summary,installer}`，D3
`loadDetails()->Future<UpdateDetails>`；修正旧文档StudioUpdate拼写，不加alias。

## 6. D3公开读取需求与Skills作用域

以下方法均`Future<void>`并只更新所属Repository的已有ReadValue/CollectionMirror；页参数
为`{int limit=32}`，沿§3.1单页/1..100/原origin/ref/旧页隔离/真实join规则。字段读取不产生
operation，不暗触发probe/discover/retry业务动作；所有长字段仍用typed page/text实际物化。

| owner | 具名读取方法 |
| --- | --- |
| WorkspaceRepository | loadProjectsPage、loadAgentsPage、loadProjectSourceStatus、loadAgentSourceStatus |
| McpRepository | loadServersPage、loadActiveServerIds、loadDesiredConfigFingerprint、loadAppliedConfigFingerprint、loadSourceStatus |
| LspRepository | loadServersPage、loadActiveServerIds、loadSourceStatus |
| RecoveryRepository | loadIssuesPage、loadSourceStatus |
| PersistenceRepository | loadValue、loadQueuePage、loadQueueLastError |

Project/Agent只在明确页需求物化，不把ID未加载当不存在。MCP/LSP为原全局来源，不能因VM
project过滤新造per-project权威。Persistence loadValue返回当前完整PersistenceStatus读值，
raw retry/resume结果仍不写versioned queue mirror。
Persistence/PersistenceQueue原header没有ObservedHeader或sourceStatus槽位，因此不提供
loadSourceStatus/loadQueueSourceStatus；删去先前误列声明，不用transport sync或保存五态
伪造Observed八态。真实保存状态/错误分别由loadValue/loadQueueLastError读取。

SkillsRepository是应用实例的唯一管理者，但不能只有一个可写projectId/currentState：

```text
SkillsRepository
  project(String projectId)->ProjectSkillsQuery
  discover(String projectId)->OperationTicket<SkillsReadTarget>
  search(String projectId,String query,{int limit=50})->Future<SkillSearchResult>
  seal/close/retryCleanup // 原生命周期签名
ProjectSkillsQuery
  projectId:String
  state:ReadonlyLatestValue<SkillsState>
  loadSkillsPage({int limit=32})->Future<void>
  loadWarnings()->Future<void>
  loadProjectDirectory()->Future<void>
  loadConfigFingerprint()->Future<void>
  loadSourceStatus()->Future<void>
  requestClose()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>
```

以该project借用替换旧SkillsRepository.state，不加alias。同project内部可共享一个镜像，
各query独立观察/关闭；项目身份首await前冻结，关闭UI借用不取消Repo已受理discover/search
或丢迟到结果/句柄。不同project响应永不写彼此状态，未知不回填当前选中project。

D2同理补具体source读取：Configuration.loadSourceStatus/loadProfilesSourceStatus、
Models.loadSourceStatus、AccountUsage.loadSourceStatus，均Future<void>且只是对应已公开
sourceStatus物化。AccountTemplates、Statistics summaries/history、SessionCosts与Mode catalog
原本没有ObservedResource/sourceStatus，不增加伪source状态或读取方法；统计继续按真实
pending/gap/readFailed字段呈现，不因该勘误丢失已有读取与诊断能力。

## 7. Conversation实际开源、scope与呈现装配（D1 / A / U2 / U3）

ConversationRepository/ConversationSession/Timeline公开面沿Conversation合同§1–2，不因尚未
落盘而由UI创建替身接口。ConversationObservationPort五个方法分别命名
`openThreadExecution/openThreadMetrics/openThreadContext/openThreadConfiguration/
openThreadAuthoring(String threadId,{required ThreadObservationMode mode})`，返回对应
`Future<FeedConnection<ThreadXFrame>>`。Session创建仅Dart镜像，select显式需求才开源，
同Thread的native五域共享原owner/incarnation。retry只重建失败域，不重发命令或重开Timeline。

Session新增具名scope工厂（除明确标注，返回Future<对应ReadScope>）：

- openTurn(TurnReadRef,{required ThreadFacetStamp origin})
- openActivity(ActivityReadRef,{required ThreadFacetStamp origin})
- openStorage(StorageReadRef,{required ThreadFacetStamp origin})
- openMetricsIdentity(MetricsIdentityRef,{required ThreadFacetStamp origin})
- openContext(ContextReadRef,{required ThreadFacetStamp origin})
- openConfiguration(ThreadConfigurationReadRef,{required ThreadFacetStamp origin})
- openTodo(TodoReadRef,{required ThreadFacetStamp origin})
- openWorkflow(WorkflowReadRef,{required ThreadFacetStamp origin})
- openPlanDocument(PlanDocumentRef,{required ThreadFacetStamp origin})
- openInteraction({required String interactionId,required int expectedRevision,
  required int expectedIncarnation}) -> Future<InteractionReadScope>
- loadInteractionsPage({int limit=32})->Future<void>

Session同时公开`interactions:ReadonlyLatestValue<InteractionIndexReadState>`，D1是唯一writer。
`InteractionListItem {reference:InteractionReadRef,interactionId:String,revision:int,
kind:InteractionKind,status:InteractionStatus,createdAt:int,updatedAt:int}`只物化索引所需身份，
不读全部问题/答案正文。`InteractionIndexReadSnapshot {origin:ThreadFacetStamp,
index:InteractionIndexHeader,items:List<InteractionListItem>,nextOffset:int?,complete:bool}`；
`InteractionIndexReadState {current:InteractionIndexReadSnapshot?,lastKnown:InteractionIndexReadSnapshot?,
loading:bool,error:StudioFailure?}`。lastKnown只保一份既有快照，不递归累积；未知current=null，
已知空需原index.total=0且complete=true。排序/页offset沿固定index的升序entries，delta与
旧页合并按原连续链规则，跨origin旧item不能混入current。U2只按current已物化身份建立
编辑key，不从数值entry猜wireID；lastKnown只显示，不准入回应。

scope的header/具名页/text完全沿Thread字段册；scope是runtime借用，不放Freezed。公开scope
具有requestClose、close({deadline})/retryCleanup({deadline})->Future<CloseReport>；adapter
具体ReadConnection的close/retryClose仍返回FeedCloseReport，由D1归并并管理permit，不能
UI自行dispose native。所有工厂冻结具体Session/origin/ref首await登记，拒绝异Session/
incarnation；不是用原ThreadId在await后重新借当前Session。

Interaction索引的引用/ID对应由D1唯一维护。ObservationPort另有纯query：
`resolveInteractionReadRef(String threadId,String interactionId,{required int revision,
required ThreadFacetStamp origin})->Future<InteractionReadRef>`，只在原execution owner已登记
定位中查确切ID/revision，关闭Cancelled、原版本不可取Superseded、不存在NotFound，不建库/
激活/写入。openInteraction先校编辑key与原Session incarnation，再解析并open原ref；不能
用current revision或remove补出成功。其它port工厂名为openXRead(threadId,ref,{origin})，
返回对应XReadConnection；configuration特用openThreadConfigurationRead与
ThreadConfigurationReadConnection/ThreadConfigurationReadScope，避免全局配置同名冲突。

D1装配注入纯只读`ConversationContextPort`（metadata读取形状按§33替换）：
`openThreadMetadata(String threadId)->ThreadMetadata`与
`readRecoveryAccess(WorkspaceThreadRecord thread)->Future<ConversationRecoveryAccess>`；
后者是allowed/blocked{StudioFailure}/unknown{StudioFailure?}的值，不是新store。
U3以D3目录/Recovery只读能力实现，不读取当前selection替代原thread目标；unknown
不准入，显式retry重新读。目标与attempt在等待metadata前已登记，晚结果不激活旧目标。
`parentThreadId!=null && role==planner`按原retired planner规则cold，其余按既定live准入；
Rust仍重复核真实状态/恢复准入。该能力不写D3镜像、不运行恢复动作、不用目录status冒
Execution忙闲权威。原scope完整读取/closing仍受真实owner监督。

U2移除feature内重复的conversation/drafts Provider声明，消费app/app_bindings.dart唯一
DI；TimelineActions与preparePresentation也由该入口具名注入，U3捕获本AppGraph具体
TimelineCoordinator（不按ID回查替代Session）。positional `AttemptId(int)`沿D0真实类型，
不得调用AttemptId(value:...)；nonconst CloseReport等沿§4迁移。
U2提供唯一公开`features/conversation/presentation_api.dart`，精确导出TimelineActions、
TimelineCoordinator、TimelineCanvasBinding与必要不可变TimelineViewState（不导私有VM）。
U3只从该入口取得呈现装配能力；app_bindings中新增`timelineActionsProvider`以及
`prepareConversationPresentationProvider:Provider<Future<void> Function(ConversationSession)>`，
后者绑定同一coordinator.prepareSend。删feature内重复Provider声明，不保转发alias。
Smart TimelineConnector所需display/canvas/query借用通过同一app_bindings的
`timelineCoordinatorProvider:Provider<TimelineCoordinator>`取得同一个AppGraph实例；仅Smart
可读取此UI资源能力，VM仍只使用窄TimelineActions，Dumb只收props/controller/callback。
不由feature另建Provider，不cast窄接口回具体owner，也不在Smart直接导入AppGraph。

Diagnostics采用依赖倒置：C在`diagnostics/contracts/timeline_diagnostics.dart`拥有只读
`TimelineDiagnosticsSource.capture()->TimelineDiagnosticsSnapshot`，snapshot只保原Driver
白名单字段/有界呈现诊断，不带Controller/lease/Future/native句柄/secret或完整正文缓存。
U2在feature公开适配入口实现该interface，U3注入具体实例；C不import feature私有coordinator/
ViewState。snapshot从实际展示owner即时取得，不新建mirror/生命周期；详情query仍使用D1
公开借用，不另认领正文consumer。C先发布原字段映射，U2据此实现，新增诊断字段交root。

## 8. Models有效策略与共享资源机制（D0 / D2）

ModelsRepository增加`loadWebSearch()->Future<EffectiveWebSearch>`和
`loadDeepSeekSearch()->Future<EffectiveDeepSeekSearch>`，仅物化已有对应ReadValue；Config的
configured编辑与Models effective结果仍分开，不借账号加载/target同步自动物化全根。

D2已实现的models_source/lifetime/read_owner/feed_owner不向其它领域开放私有import，也
不在四个后续域复制。D0接管其中无业务payload/reducer的预算观察、工作登记、固定读取与
product feed监督机制，目标为resources/data中的`ResourceSource<T>`、`ResourceLifetime`、
`PinnedReadOwner<C>`、`ProductFeedOwner<F>`，只从resources_ports导出。D0迁移时保留现实际
能力/错误/真实join契约，并修正与已审LatestValue相同的重入问题；不引入动态payload、第二
事实store、消息总线、后台next队列或额外预算池。领域Frame/State/ref归并仍各Repository。

该迁移是复用已有实现而非批准未审算法；新共享文件单独fresh静态审。D0先给实际新文件与
签名，D2随后切换并删除四个旧机制文件，不留Models*别名。转换期间不同时改同一源文件：
D2冻结这四份输入供D0只读，D0只写自身目标，D2拥有最终删除。D1自己的私有镜像机制现阶段
可继续按§4使用；待共享资源能力证明相容再定向迁移，不为形式把所有owner硬塞同一类。

## 9. Timeline正文与开放artifact的窄边界（D1 / A / U2 / C）

D1的`conversation/domain/thread_content.dart`是Timeline既有typed正文值的唯一领域入口，
必须保留原ThreadItem封闭变体、字段变更及完整嵌套语义，迁为Freezed而非恢复旧models目录。
该入口不以完整Turn历史新读取接口尚未确定为前置；现有Timeline帧和详情已经有明确来源。

原`ThreadToolOutput.output_artifacts`是有意开放的JSON值序列，不是未完成的已知schema。
Native现有`BridgeThreadToolOutput.output_artifacts_json:Vec<String>`继续逐项用serde序列化原值；
SDK使用具名Freezed值`OpaqueArtifactJson {json:String}`，`toString`不暴露payload，正文输出的
`outputArtifacts`为`List<OpaqueArtifactJson>`。A仅机械包装原字符串，SDK reducer/Repository
不decode、不递归识别字段、不将其改造成泛型Map。其原顺序、原值及空序列语义保留。
字段的Timeline预览/省略/详情预算规则不变，不能因wrapper把完整artifact无界推送或常驻。

U2唯一`features/conversation/presentation/artifact_links.dart`可使用Dart标准JSON解码器，
仅从这种显式开放artifact中派生原网页链接呈现，不作为业务协议解析入口。沿原规则递归
String、List和Map的values；字符串trim后以`http://`或`https://`开头即候选，按遍历首次出现
顺序去重，全部artifact合计最多6个。不新增严格URL验证、scheme改写、大小写归一化或其它
输入过滤。只处理当前已交付预览或用户显式读取的详情，不为显示卡片自动读取全部大字段；
临时解码对象不进入canonical镜像/ViewState/Driver，也不保留第二正文cache。

非法JSON是该显式边界的可见详情解码失败，不伪造空artifact成功、不影响其它typed行归并，
不记录原payload/secret。C的边界规则只允许此确切呈现helper对OpaqueArtifactJson解码，
不能据此放开其余feature/reducer的raw JSON已知DTO入口。`tool.arguments`与Raw payload的
`content`原本是opaque String，仍保原文本，不因本裁决将它们当artifact列表自动decode。

## 10. 共享资源工作的准入与失败保留（D0 / D2 / D3）

ResourceLifetime不提供以任意字符串标签绕过seal的新工作入口。普通领域工作使用
`run<T>(String label, Future<T> Function() action)`，在任何外部回调执行前同步检查准入并
登记完整completion。已准入操作的晚open/映射/交接属于这条原已登记Future的剩余责任，
不是关闭后重新登记业务工作的许可。

仅共享资源owner使用`accepted<T>(ResourceOwner owner, Future<T> Function() action)`；
受理时同时核对lifetime未seal、该具体owner已登记于同一lifetime且未释放，字符串只是
owner上的诊断标签，不作身份。feed构造在调用可能同步重入的open前，须把opening、consumer
及错误completion全部登记；不能先调用open再尝试登记consumer，遇同步seal就丢掉后者。
关闭同步封所有新登记，等待之前登记的完整工作；close报告完成后不能添加游离新工作。
领域resync/page/command不能改成伪ResourceOwner绕过准入，使用run并在拒绝时结算自己已
安装的本地pending/completer，防止留下永不完成的占位责任。

feed的已受理apply/ACK失败不因随后进入closing而消失。原owner保留typed诊断和原始私有
cause/stack，进入其issues/CloseReport；全lifetime最后异常字段不能替代该owner的证据。
关闭触发的普通流取消与已进入业务callback后的实际失败分开判定，不能吞掉后者或ACK失败帧。
如领域failure回调本身失败，同样保其证据且继续所有独立清理，不用异常退出跳过join。

清理恢复能力仍以生命周期合同§2–3为准：awaitCompletion等待原工作，retryClose允许原owner
重试清理调用，terminal保留。`FeedConnection.retryClose()`是既定显式恢复入口，按原owner
当前typed恢复能力继续等待或重试，不因方法名称将awaitCompletion等同重新发起清理。

## 11. Timeline公开借用与退役封口（U2 / U3）

`TimelineCoordinator.display(String threadId)`返回`TimelineDisplayBinding?`，不再公开返回
完整TimelineDisplayLease。binding是独立只读runtime借用对象，私有引用原具体lease，不能
将lease本身当成interface返回；不提供Session、DisplayContent、canonical写入、retire、
close或dispose。公开借用具有以下必要能力，仍由原lease监督真实工作：

```text
TimelineDisplayBinding
  threadId:String
  generation:int
  retired:bool
  appliedVersion:int?
  canvas:TimelineCanvasBinding
  detailFor(String itemId, ThreadContentFieldView field)->StudioTimelineDetailRef?
  readDetail({required String itemId,required StudioTimelineDetailQuery query})
    ->Future<StudioTimelineDetailChunk>
  addRetireListener(void Function() listener)->void
  removeRetireListener(void Function() listener)->void
```

Smart行/附件/详情与诊断适配使用该借用；Dumb仍只收TimelineCanvasBinding，不把detail能力
塞进canvas。Controller仅从canvas的既有UI能力取得，诊断只读同一Message元数据，不另建
正文索引。detailFor仅检查当前已有预览ref；readDetail先冻结原lease/query身份再await，
不交出共享query scope的关闭权限。VM只接受typed读取callback及当前性检查，不接UI lease/
canvas/controller；其closeReader只封本次需求并等本次已受理Future，不关闭共享scope。
原query登记、取消/join和permit仍由D1及具体display owner负责，不因窄包装丢失收束能力。

lease退役即同步拒绝旧canvas新mount及新detail读取；已登记mount仍能幂等unmount，旧binding
不能延长已封闭owner的寿命。coordinator输出changes在发布最后null后真实close，关闭完成
纳入同一join/期限和typed未决报告；暂停观察等导致close尚未完成时保原Future，不伪done。
退役监听失败不能阻断其它监听、原query退役及controller真实释放，失败归该owner保留。

## 12. 退出报告与宿主结束两种明确能力（U3 / U1 / C）

沿现有U3真实实现保留`exit(intent)->Future<StudioExitReport>`与
`requestHostExit(intent)->Future<void>`，同步生命周期合同§3。前者收束并给typed报告；
后者复用同一个首次intent/deadline/finalizer/installer结果，再发唯一宿主finishExit。
生产窗口/托盘/系统退出、更新重启和Driver真正退出均走requestHostExit，不把只返回报告
当作退出完成。受控测试可借exit观察结果，但不是不结束宿主或不回收资源的许可。
这不创建第二退出协调器，不改Clean/Degraded或安装器语义，不为Server新增退出端点。

## 13. 分层取消与已受理回调的故障归属（A / D1 / C）

Adapter output StreamController的onCancel不能把原connection.close返回Unresolved再造为
独立Protocol取消异常，导致Dart上层把可恢复native问题永久terminal化。同步生命周期合同
§5：output取消仍发起/观察原连接关闭，但原owner已有完整保留的同次关闭报告/typed调用错误
不重复抛成output故障。output观察解绑不冒充native清理成功；原native join、真正forwarding
subscription.cancel失败、未决query和permit仍由该连接close/retryClose完整报告。
真正forwarding cancel失败仍为terminal；不得删除原issue、重cancel、允许dispose或把它
改retryClose。也不得使用无条件catch吞异常，原owner必须证明错误属于该同次受监督关闭且
仍持原cause/typed诊断/恢复责任。保持现有能力，无新增通用异常总线或平行关闭registry。

D1已进入Timeline consumer交接或ACK后发生的真实错误，不因consumer已关闭/attempt退役
而丢失。原ConnectionOwner保留typed terminal issue及私有cause/stack；原任务完成后仍不得
假Clean或ACK失败帧。正常关闭导致尚未进入callback的取消与已进入callback的失败分开；
current判断只控制向当前UI发布，不决定旧owner的证据是否保留。对应严格测试断言保留。

## 14. Usage身份只读依赖与自动检查呈现（D2 / U1 / U3 / D0）

Configuration领域提供窄的`AccountConfigurationReadSource`能力：
`state:ReadonlyLatestValue<ConfigurationState>`及
`loadAccount(String accountId)->Future<AccountConfiguration>`。
`ConfigurationRepository`实现该interface，仍是同一个实际Repository对象；不新建转发store、
装配wrapper或第二Config owner，也不改变现有Configuration工厂返回类型。

```text
createAccountUsageRepository({
  required AccountUsagePort port, required ResourceBudget budget,
  required OperationRecorder operations,
  required AccountConfigurationReadSource configuration
})->AccountUsageRepository
```

U3注入本AppGraph的同一ConfigurationRepository作为这个窄只读能力；Usage只建立自己的
观察/按需读取，不调用Configuration写入、seal或close。真实query identity为
`AccountUsageQueryIdentity {accountId:String,usageQueryRevision:int,ownerEpoch:String}`，
来自同一当前Configuration账号值及其真实runtime epoch；不以Usage record revision、
settings revision、fingerprint或secret hash替代。该身份使用Freezed。

check首次await前登记原账号、具体configuration依赖、准备尝试、ticket与许可；未物化身份
只能做原来源的纯读取准备，不能联网check。取得身份时须证明账号值与当前原origin相容，
在native dispatch前冻结完整identity并传原expectedUsageQueryRevision。准备期间来源替换、
同ID重建或凭据revision变化使旧准备失效，不用await后的新选择代替原目标。未知/旧身份
不准入，native继续重复核验；已联网的旧工作仍归原job收束，不因隐藏或新identity丢弃。

自动与手动check共用同一真实调度/去重责任，不另建自动操作系统。为公开自动spinner/error，
AccountUsageRepository新增
`checks:ReadonlyLatestValue<Map<String,AccountUsageCheck>>`，每账号只呈现最新一次已受理
检查能力，map在发布边界防御性复制。`AccountUsageCheck`是只读runtime借用，包含
`accountId:String`、`identity:AccountUsageQueryIdentity?`和
`ticket:OperationTicket<AccountUsageRecord>`；因包含ticket，不Freezed/序列化/打印为领域值。
identity为null仅表示该次纯身份准备，绝不表示native已受理。身份取得/失效时原owner更新
只读借用映射；旧identity不能给新账户显示pending/error。旧未完成/unknown job的真实
责任独立保留，不因最新呈现映射替换而取消或丢证据。

U1观察checks中的原ticket.state显示实际pending/diagnostic，不从timer或canonical记录猜
自动进度，不复制一套OperationState writer。隐藏只停止新自动需求；原失败计attempt、
成功后仅目标物化、Unknown不重发等既定行为不变。普通source/feed读取仍更新原UsageState。
账号重物化的暂时identity=null不清除已消耗的自动attempt；纯准备取得身份后仍须重核同一
identity是否已自动尝试，不能因显示名等无关配置更新再联网，也不把未联网伪造成成功。
这不取消用户明确手动重试的原能力，不丢原ticket/失败/unknown证据。

手动重试不覆盖前述Unknown不重发：同一完整query identity仍有未决Unknown时，显式
check继续返回该原ticket，不因网络Future已经settled就另建一次联网attempt。已知拒绝
等原允许重试的结果仍可显式重试；真正的新query identity不被旧identity阻挡，旧Unknown
及其资源／证据继续保留。纯null身份准备失效不能压住真实新身份，这与业务Unknown
的禁止重发是两条独立规则，不能用“新ticket”规避后者。

Updates补`loadValue()->Future<void>`作为既有`UpdatesState.value`的显式物化需求；
summary-free CheckFailed可以读取其完整SourceStateError，不为此请求必然NotFound的summary。
只读原UpdatesReadRef/origin，不触发check/prepare、不伪造新sourceStatus；installer大详情
仍仅loadDetails按需读取，字段文本沿既定typed块预算。loadSummary/loadDetails原能力不变。

## 15. Timeline帧准入与已进入处理的分界（D1 / C）

Timeline的delivery前缀、baseline/subscription身份、patch from/to及成员revision连续性先在
无外部副作用的准入阶段完整核验。校验成功后才提交本attempt的metadata、完成ready或发布
connection state，并进入实际consumer/ACK阶段；不得在校验前半段改变可观察状态，再把
后半段失败宣称为纯拒绝。可使用临时有界metadata候选完成验证，不新增正文镜像或公共框架。

因此patch gap与changed-subscription若在上述准入阶段被拒，须保typed Protocol及last-good
内容/来源、不ACK、关闭原失败连接；真实join全部成功时允许CloseReport complete，不制造
没有清理责任的永久terminal项。C现有两条协议拒绝后的真实Clean断言继续保留，不改为
任意failure或删掉。此选择不允许以Protocol code/message判断“总是可清理”：已进入metadata
提交/外部发布、consumer callback或ACK之后的真实错误，仍按§13由原owner保留typed
processing issue，即使closing/noncurrent也不能丢失；真正cancel/native关闭失败仍独立保留。

## 16. Session创建前的准入失败呈现（D1 / U3 / D0 / C）

补齐既定“资源不足如实发布错误”的实际接口，不建立app第二选择或第二Session owner：

```text
ConversationActivationFailure {threadId:String,selectionGeneration:int,error:StudioFailure}
ConversationRepository.activationFailure
  :ReadonlyLatestValue<ConversationActivationFailure?>
ConversationRepository.retryActivation(
  {required String threadId,required int selectionGeneration})->void
```

失败值使用Freezed，仅含原需求身份及typed错误，不装Session/Future/permit。D1 Repository
是唯一writer；`active`仍保持具体Session借用。只有当前选择的Session创建/同步准入失败进入
此槽，直接session借用失败与已存在Session的五域/Timeline错误不复制进来。失败必须保留原
诊断/cause，构造中已取得的资源真实回收或登记，不以GC或active=null掩盖泄漏。

选择替换、needsOpen及seal使旧失败失效；所有可重入通知后的继续步骤都核原threadId与
selectionGeneration，不允许旧失败覆盖新选择。已接受的选择准入失败通过此槽发布，不仅
向装配抛异常/写日志后留下永久spinner；无效generation等调用契约错误仍按原typed错误拒绝。

显式retryActivation仅重试同一当前threadId/generation、needsOpen=false且仍无Session的
失败准入。封闭时Cancelled，过时目标/代次Superseded，同目标已经激活则幂等无操作。
不新建选择generation、不ensure/open Thread、不重连已有Session或重放命令。Workspace VM
同步watchLatest并按唯一Workspace选择过滤显示，重试携冻结的失败身份；Smart/Dumb仍只
接typed状态和callback。D0仅导真实值/接口；C保预算失败可见、旧代次不能重试新选择的覆盖。

## 17. 账号模型编辑的关联覆盖保全（D2 / U1 / C）

已核旧settings_account_tab的_updateCustomModel/_removeCustomModel与
AccountDraftFactory.changeTemplate/createAccount：模型改名/协议变化/删除及模板重建并非
仅修改customModels声明。原功能迁到D2当前canonical意图合并，不让U1复制旧整账号表。

`AccountEdit`增加必填`rebuildModelConfiguration:bool`；它是显式表单意图，不是native新
策略或新的持久化字段。普通编辑/创建为false；模板切换重建表单时为true且templateId明确
set，A→B→A仍保重建意图，不能通过当前模板ID相等推断false。D2在原Settings写lane每次
dispatch/CAS恢复都从最新完整canonical账号取基底；true时仅将手动模型/连接覆盖/阈值覆盖
的基底清空，再应用本次意图。账号ID、凭据三态及其它配置不因此重置。

普通模型意图按原序应用：删除清该ID声明和两类覆盖；upsert改名将原ID显式阈值覆盖移至
新ID（原无覆盖则不制造新覆盖），并清原ID连接覆盖；wireApi变化同样清该连接覆盖。
只改显示名/容量/输出等保留原覆盖，最终有效策略仍由Rust计算。再应用用户本次明确的
connections/autoCompactLimits意图；不从在线目录过滤掉未显示成员，不静默解决模型ID冲突。

U1只维护本次raw/dirty意图：改名或wireApi改变时撤销该旧模型尚未提交的连接编辑，删除
也撤销它的待提交编辑，防止合并后把已清覆盖重新加回；不得从旧canonical复制两张覆盖表。
模板重建位与字段意图一起冻结，只有同一次真实成功且未被新输入替代才清除。D2补实际合并，
C迁所有AccountEdit构造并覆盖改名/协议变化/删除/模板A→B→A及CAS使用最新值的语义；
不运行测试，最终由root统一验证。Rust现有AccountSettingsUpdate完整输入及校验不因这项
SDK意图补齐扩容或增加重复业务策略，A继续机械转换合并后的typed input。

## 18. 共享只读文本与来源状态物化（D0 / D3 / D2）

已核MCP、Recovery及Configuration/Models现有读取代码。重复的ReadText字节推进和
ProductSourceStatus八态物化属于现有resources类型的机械读取，不是新的Repository框架。
由D0在resources/data提供并仅从resources_ports导出两个无状态函数：

```text
materializeReadText(ReadText value,
  {required Future<TextChunk> Function(int fieldId,int offset) read})->Future<String>
materializeProductSourceStatus(ProductSourceStatusReadConnection scope,
  {required ObservedBrief expected})->Future<ProductSourceStatus>
```

文本沿原单块64KiB调用约定，核原fieldId/offset、UTF-8字节数、nextOffset真实连续推进及
最终ref.utf8Bytes完整性；不trim/截断/解JSON，也不额外限制完整字段长度。来源状态核原
header与expected brief全部字段一致，再按需读原operationId与SourceStateError三个字段，
完整保八态/Unix秒/operation及nullable语义。错误原样传播，协议不一致为typed Protocol。

函数不open/close/retry scope、不登记新任务、owner、缓存或预算池，不取得新的当前来源，
不catch吞错；调用方必须在原已登记工作与原scope.use内调用，保原64call计量及真实join。
各域origin/ref捕获、成员顺序、delta链、null-ref策略、集合窗口与reducer继续各域负责。
本次不接纳通用ReadValue rebind/collection框架提案，不能把MCP BTreeMap套到Recovery Vec。

D0先交真实函数及静态审查；之后D3迁机械副本，D2按确认相同语义迁对应重复部分，删除
无业务作用的旧转发副本，不扩大成所有read owner重构。已批准MCP中被迁文件需新内容身份
及定向复审，其余独立批准不失效。等待函数期间可继续各域合同/动作，不全停实施。

## 19. SSH弹窗公共入口与远程项目命名（U1 / U3 / C）

SSH编辑、密码与目录对话框的family身份和结束编辑责任仍归U1现有SSH呈现owner。U3不得
导入U1私有VM、自己从1分配counter、拼负数/hash namespace或另建App级弹窗registry。
U1从Settings公共呈现出口提供具名Smart helper，复用现有Flutter showDialog和同一
SshViewModel的准入/ID分配/结束能力；Settings自身也使用它们，删除重复编排：
跨功能唯一入口为`features/settings/presentation_api.dart`，不导出私有VM或分配器。

```text
showSshEditorDialog(BuildContext context, WidgetRef ref, {String? alias})
  ->Future<SshServerRuntimeEntry?>
showSshPasswordDialog(BuildContext context, WidgetRef ref,
  {required SshServerProfile server, StudioFailure? initialError})->Future<bool?>
showRemoteDirectoryDialog(BuildContext context, WidgetRef ref,
  {required SshServerProfile server, bool showProjectNameField=false})->Future<String?>
```

这些是UI平台编排，不是SDK facade或新的业务owner。helper捕获本容器具体SSH owner、原
目标和已分配身份，结束时finally归还同一登记；等待期间owner替换/关闭不借新owner结算。
保原managed编辑限制、busy/重复弹窗准入、密码三态与实际passwordOffered条件，不把任意
认证失败都变成密码弹窗。helper只结束自己的UI登记，native目录/任务仍由原Repo/query
真实收束；组件销毁不冒充query Clean。嵌套目录密码继续用原picker域的唯一身份。

编辑helper交付本次原save操作真实返回的`SshServerRuntimeEntry`，取消/未准入为null；
不是bool，也不从保存后的全列表差集、当前编辑器或时间排序猜目标。结果在结束原editor前
由原operation捕获，U3新建连接后按其profile.alias选中本次真实保存的连接，保原向导功能。
密码helper仍只表达该次认证成功与取消，不改变签名；保存失败/Unknown仍留原诊断和责任。

远程目录VM补原命名模式：nameRaw/nameEdited属于生成VM编辑状态，Controller仅同步
文本/光标。showProjectNameField=true时保原非空trim校验，未编辑名称随成功目录结果采用
最后一个非空路径段、无段时remote-workspace；用户编辑后换目录不覆盖其raw。确认时冻结
server、已验证path、可选trim名称与原意图，调用一次Workspace.openRemoteProject(alias,
path,{name})的真实open→rename→activate批次，不在已激活后另补rename。false时name为null。

helper仅在该批次真实成功并完成本query退出交接后返回已打开路径；失败保原独立步骤与
诊断供当前对话框呈现，取消返回null。U3向导调用showProjectNameField=true，返回路径后
只结束向导/处理已确定导航，不再次open/rename/activate；取消回到原向导上下文。U3的
非对话框Driver原始路径入口若直接调用Workspace批次，也必须在同一次调用中携冻结名称。

## 20. Conversation身份与准入收束补充（D1 / A / R / C）

落实既有同projection、不可变交付、纯准入与真实关闭要求，不新增共享框架：

- 某facet确认新的Session projection incarnation时，其它旧incarnation的feed立即失去新帧
  准入资格并按原责任退役；旧值仅last-known，不能继续ready发布或ACK为当前。各域revision
  独立不代表同Session可混用不同incarnation，迟到baseline/delta不能回退共享身份。
- Timeline有界metadata已缺某成员的前序revision时，不得将未知expectedRevision当已验证；
  应明确拒绝/重同步，而不是增加第二正文镜像。影响准入、顺序与ACK的Timeline/Interaction
  列表必须在构造或进入准入前防御性快照，transport保留的可变List不能改变已验证帧。
- itemShell必须匹配原item/thread/ordinal与补丁目标revision。开放artifact的非删除变更
  依赖同次权威typed shell提供新OpaqueArtifactJson列表；无shell时拒绝，不在SDK解JSON，
  也不能无声保旧内容而只涨revision。其它opaque字段遵守同样“不丢更新”的要求。
  生产端不得把已清空动态字段的static metadata当作该权威shell；须从同一具体item、目标
  revision的同次材料生成有界typed预览，沿原preview/omission/detail预算，不能抓取稍后
  latest item或把完整无界artifact/Raw内容塞回static metadata来绕过此边界。
- ReadScope必须先完成scope及返回实体全部身份校验，再提交已验证标记；失败header不能
  为后续text/pages授权。Turn/Activity核原Thread身份，Interaction核原Thread/interaction。
- SubmittedInputObserver的构造即接管原Session evidence需求；预算/观察登记失败也必须
  回滚已接管需求及局部资源，不把责任留给尚未存在的Drafts调用方。关闭失败的真实证据不丢。
- ConversationRepository.seal在最终null/失败撤回发布后关闭active与activationFailure
  两个publisher的新观察准入并结束本地观察；底层未决Session仍保原owner/permit/关闭责任，
  不能因为publisher结束而报告资源Clean。后续close/retryCleanup仍真实join原owner。

## 21. PageSwitch的原对象只读生命周期取证（U2 / D1 / C）

保留原三种独立证据，不以retired标记、page Future完成或全局预算下降冒充真实释放。
基于现有owner提供最小只读能力，不创建新owner、正文consumer或关闭权：

```text
TimelineDisplayBinding
  pendingQueries:int
  isReleased:bool
  observeRelease({required DateTime deadline})->Future<CloseReport>

ConversationTimeline
  lifecycle:TimelineLifecycleRead
TimelineLifecycleRead
  ownedAttemptCount:int
  observeRetired({required DateTime deadline})->Future<CloseReport>
```

display三个成员绑定同一个原display：计数来自它所有已登记scope的真实在途查询，不因
读取计数而open scope；isReleased来自原stock Controller operationsStream完成确认。
observeRelease只观察已登记的release/cleanup Future及真实issues，不触发retire/close/
retry，不改变demand。仍active、未卸载、lateopen/query/write未结束或有terminal issue
时不得报告Clean；deadline只结束本次等待，原责任保留。物理isReleased与报告无issue
是两个事实，不能用一个布尔隐藏已释放但仍有退役错误的情况。

TimelineLifecycleRead是独立runtime借用对象，绑定原具体Timeline，不返回owner自身以供
cast；无handle、close/retire/refresh、writer、正文能力。ownedAttemptCount读取原全部
attempt登记；observeRetired首await前捕获原已退役attempt及已启动join，覆盖opening
晚返回责任，不为观察发起清理或重试。未退役/仍在途不能假Clean，未决保原typed恢复分类。

C在真实第二次输入前冻结原B Session/Timeline借用与opening phase/AttemptId，回A后
仍读原对象，只有原报告Clean且ownedAttemptCount==0才证明openingReleased。原opening
phase只证明已登记opening阶段，不扩称native open Future必然未settled。oldDisplayReleased
只证明原display释放，不外推全部consumer/callback/未发布candidate均释放；更广的退出
责任仍由真实owner总收束与原CloseReport证明。所有等待Future只在runtime方法，不进入
Freezed诊断值；原RawTap、选中目标、真实pendingQueries与page未完成交叠断言仍保留。

## 22. Metrics发布取证与同一次退出监督（C / U3）

Driver-only记录器迁到已存在的具体ConversationSession.metrics，不创建Session、transport
订阅或业务demand；原runtime-evidence-start/stop命令名保留，schema整体升级且不留旧字段
alias。目标与实际读取身份分开，不能用ref.entry、请求turnId或incarnation伪造旧streamEpoch。

```text
schemaVersion:2, source:repositoryMetricsPublish
target:{threadId,turnId}
metricsOrigin:{runtimeEpoch,incarnation,facet:metrics}
phase, observerCancelled, readsJoined, scopesClosed,
overflowed, errorCode?, failure?, factLimit, factCount, closeUnresolved
facts:[{
  kind:baseline|live|cleared, threadId,
  metricsStamp:{runtimeEpoch,incarnation,facet:metrics,revision}, atUnixMillis,
  observedIdentity:{turnId,attemptId}|null,
  live:{observationSequence,completionTokens?,responseMillis?}|null,
  clearedPreviousLive:{turnId,attemptId,lastObservationSequence,lastMetricsRevision}|null
}]
```

failure仅安全typed元数据（type/code/retryable/correlation），不输出message/details、
toString/堆栈/正文/凭据。基线无live时observedIdentity/live均null，不把target写作原生事实。
同步watchLatest先登记并捕获基线；回调首await前捕原Session、完整stamp、ref与计量。
真实Turn/attempt由原openMetricsIdentity的header/同scope文本取得，核完整scope身份；
当前native明确以origin.revision创建sourceRevision，不能用D1暂缺校验来否认该约定。
同run可有界复用已验证的原ref身份关联，不是第二canonical镜像；不换当前Session/ref补救
Superseded，不自动resync或重放命令。事实与待处理metadata/已受理读取合计沿4096上限，
溢出显式失败，不裁剪或latest-wins，不并发冲破原scope/64call预算。
身份关联只在原具体Session及同epoch/incarnation/facet的同一immutable ref内复用；它只
复用已验证的纯ID，不把旧scope/header的sourceRevision冒作新stamp下的读取证明。

live证据仍要求至少两次真实回调、同真实Turn/attempt、递增observationSequence与Metrics
revision；baseline不计。cleared仅是同具体Session及同Metrics epoch/incarnation/facet内，
实际live之后更高revision发布ready且value存在、live=null，引用最后真实live身份与序号。
断线/failed/closed/无value、换源/attempt、读取失败、live-after-clear不能当清除或成功。
旧聚合帧active/latestTurn的原子同水位检查不再伪造；清除只证明原live被撤回，journey原
独立completed/durable前置仍保留，不把两域读或相等数字声称为原子证明。

start/stop返回Future，Driver必须await结果再序列化；首次await前占run claim，拒绝重复
start（包括starting）及复用结束run。stop同步封回调/取消自己的观察，再join封点前真实
受理的open/header/text/close；成功须全部scope Clean。重复stop可等原责任后报告alreadyStopped，
不新开读取。Unresolved保原scope/issues/recovery，observerCancelled不等于Clean；只排队
未实际open的metadata在shutdown封点明确取消，已受理工作不能丢。纯取证失败不伪造资源
未join，真实cleanup失败也不能被业务失败遮盖；retryCleanup沿原责任而非永久缓存旧报告。

U3的assembleApplication补可选`List<ApplicationCloseParticipant> additionalParticipants`
（默认空），构造边界防御性捕获并交同一个ExitCoordinator，不提供运行中追加registry。
Driver在装配前创建本次记录器及其真实seal/close/retryCleanup participant；start时再传本
Graph的具体ConversationRepository并冻结，构造本身不借Session或发读取。生产默认没有
该participant，具体工厂只透传这份装配输入，不另建退出owner。退出仍首次同一deadline，
真实未决问题先于唯一native finalizer；recorder的观察取消、scope join不能只挂在旧closeClient。

latestContextTokens从Metrics事实中删除，不留恒null alias；Context的独立诊断从原
Session.context的stamp/sync与canonical标量投影，保0/null、累计计量和权威数值，不拼入
旧Metrics事实或重算策略。C同迁driver_main、strict parser、realtime/stress/manual消费者与
原跨域更新回归，Context缺值不等于Metrics清除。所有输出仍有界、只读，无正文/全workspace缓存。

## 23. Models-only编辑建议的Rust权威查询（R / D2 / A / U1 / D1 / C）

先独立落地两个只依赖原immutable Models catalog的查询，不把role/default Start路由及
preparation所有权塞入Models。公共纯值与签名为：

```text
ModelSelection {model:AccountModelKey,effort:String?}     // Freezed值
ModelsRepository.effortAfterModelSelection({
  required ModelCatalogReadTarget catalog,required AccountModelKey model,
  required String? candidate})->Future<String?>
ModelsRepository.firstTextModel({required ModelCatalogReadTarget catalog})
  ->Future<ModelSelection?>
ModelCatalogReadConnection.effortAfterModelSelection(
  String accountId,String modelId,{required String? candidate})->Future<String?>
ModelCatalogReadConnection.firstTextModel()->Future<ModelSelection?>
```

Rust复用原已验证ModelInfo的effort_parameter/default_candidate：supported candidate原样
保留，否则模型默认，再按声明顺序首候选；无effort参数返回null，确实不存在account/model
为NotFound，来源未知/旧版本不可得仍为实际Unavailable/Superseded，不以null假装模型缺失。
不trim/case-fold输入，不新增候选值或默认选择权限；不能把strict resolve_candidate用于
替换这条原编辑建议规则，也不能在Dart重新从descriptor猜原始default字段。

firstTextModel沿该固定catalog的完整原账号/模型顺序和Rust文本资格找第一个可用非空key，
effort用同一candidate=null规则；全catalog确无合格项才null，不能从Dart已加载的部分页
选择“全局first”，也不能添加旧Profile创建没有的defaultAccountId优先级。

D2首await前冻结原catalog origin/ref、key/candidate，复用原pin/use/lifetime及相同完整键
在途合并，结果不写第二mirror。native scope保原版本已验证模型材料，查询不读取latest
Configuration、不网络发现、不写业务、不新增scope/任务/预算池；沿原shared64call与真实join。
A仅typed映射，native read owner尚未就绪时不得用旧聚合读或stub冒充实际接线。

U1新Profile仅在明确新建初始建议时调用firstTextModel；已有unresolved route/effort保原值。
显式换模型及D1 Start换模型时candidate=null，Start返回null/empty时去掉该mode的effort
intent，不将前模型effort带入新模型。UI/草稿owner核原editor/Session、目标、模式及意图
代次后才交接异步结果；建议查询不能自动清dirty、默认重选或重放保存。

**保存/执行政策不变**：已核旧Profile._save原样传_effort及design20的明确约定——空effort
表示省略，不从目录补默认。现有Profile与通用route的严格校验继续保留；Profile UI允许null
选项不等于本次授权把有候选模型的null保存改成默认成功。不要在build/save中调用本编辑
建议方法偷偷修复显式null或非空不支持值，也不放宽通用validator。

role已配置route展示/缺省建议与Start最终mode→simple→overlay冻结仍需Config+Models的
同源相容捕获（及必要ModeCatalog），另行裁决；现有route不因不可解析而fallback。两个
Models-only查询不承担project/draft/attachment/operation/UnknownOutcome/preparation责任。

## 24. Timeline失败的唯一retry表示（R / A / C）

Timeline的BridgeTurnFailureDto与Thread facet/read共用既有
`types::BridgeRetryDisposition`，字段统一为`retry:BridgeRetryDisposition`；删除该DTO旧
retryable与retryAfterMs两字段，不保兼容字段/别名。分类/provider kind也继续同一公共enum。
Rust仍映射同一个pl_protocol::RetryDisposition：Retryable的可空retry_after_ms原样保留，
Permanent不携延迟；不将None换成0、不改变业务可重试含义。A复用现有typed retry转换，
不再从bool+nullable重新组装第二种表示。生成输入与实际DTO消费者一并迁，统一生成后置。

## 25. Settings离开确认的原请求与编辑会话守卫（U1 / U3 / C）

Settings tab切换与整页离开复用现有SettingsNavigationViewModel的begin/owns/complete，
不建立第二router/导航writer。Settings对外curated presentation_api提供
`SettingsScreen(initialTab?)`与`confirmLeaveSettings(BuildContext,WidgetRef)->Future<bool>`；
app通过其既有router的settingsScreen/confirmLeaveSettings输入注入，不私导Settings VM。

Mode Smart helper采用
`confirmLeaveModeEditor(BuildContext,WidgetRef,{bool Function()? isCurrent})->Future<bool>`。
可选predicate只判断该调用方原请求仍有效，未传不新增调用方约束。helper首次await前捕获
具体VM、真实编辑会话lifetime、selectedModeId、editRevision、latestIntent；打开确认前以及
确认返回后、调用resolveLeave之前核对原请求/同VM/同lifetime/同目标及上述编辑版本，当前
AsyncLoading/AsyncError或busy不准入。已失效确认仅返回false，不调用save/discard，不以
弹窗选择覆盖新raw，也不自动再开确认。纯catalog通知不改变上述编辑身份则不误作新草稿。

现Mode VM已有内部_session且dispose/rebuild会推进，但尚无公共只读代次；允许仅增加与
Profile VM同类的`int get lifetime`只读访问该真实代次，不加第二计数器、不把owner值对象化。
仅比较Notifier实例不够：Riverpod可复用同实例rebuild，而新state的局部编辑计数可能重复。
Mode保存/丢弃/校验和Rust策略不变，helper守卫与resolveLeave之间不得再await。

Settings导航捕获原导航VM及request，向helper传同实例且owns(request)的predicate；任何
await后仍由原导航owner核owns再complete，complete先交接原编辑生产者再hide/切tab。已
合法准入的保存不因导航意图变化而取消/丢ticket，但迟到完成不能导航新请求。Screen的
active/visited panel、route与PopScope都走该入口，dispose不发业务写入。U1最小解冻Mode
helper与VM只读lifetime增量，并完成真实Screen/curated leaf；U3只负责唯一router装配，C
迁移过期请求/同实例新lifetime/新edit/保存后新导航等消费者与回归源码，执行验证仍后置。

## 26. Timeline UpdateItem同次有界预览的core接缝（root / R / A / D1 / C）

接纳R已核实的一文件core接缝：`pl_core::chat::TailChange::UpdateItem`新增
`preview:ChatItem`，由计算该次字段差量的同一个目标材料提供。原item_id、expected_revision、
revision、omitted_bytes、saved、lifecycle、meta-change信号和fields保留其语义。预览在原
同步timeline捕获边界内形成，原单条／tail horizon预算不变，内容块和meta共享不可变引用；
不读全文、不增加latest getter、缓存、任务、产品DTO依赖或存储迁移。patch交付后的retained
可能已淘汰该成员，不能把事后读取retained/current当作同次材料替代。

runtime先核preview与UpdateItem的item_id/revision/omission/saved/lifecycle相同；对原静态壳
在canonical重建前核id/thread_id/ordinal对应原reader Thread与preview身份／顺序，避免
重建覆盖错误身份而掩盖错绑。metadata变化及artifact/Raw需要权威typed值的非Remove
更新，复用既有有界材料化生成同目标revision的shell，包括预览封顶后仅长度／revision
变化的情况。普通字段仍用原差量，不给每个token无理由传整条正文；Turn关联可按当次
权威材料变化，不误作稳定身份。Raw/arguments保持opaque，artifact仍仅原serde边界。

保32KiB正文、arguments/result各4KiB、单条256KiB、tail100条/8MiB及原omission/detail
规则；完整artifact JSON不可得时沿原有界预览和详情语义，不解析半段JSON或把空预览当
不存在。最终native Timeline Data的真实8MiB JSON准入照常计算，Arc共享不证明wire免费，
不拆patch/清字段/放宽预算。无新protocol/FRB wire字段，HTTP与FRB仍共用该producer。

为遵守现有directory权限，root只修改`code/pl-core/src/chat/tail.rs`的最小类型和捕获点，
R继续其原权限内runtime消费及必要private helper；组合切片共同fresh审查，不能把core
改动当已审。既有pl-core/tests/chat_tail.rs公开行为入口补必要同次预览证明；因C当前
写权限不含core tests，由root维护该测试文件，C继续其范围内消费者。不新增测试钩子，
不把此前3个Interaction私有测试混入本接缝。所有运行验证仍统一后置。

## 27. 有序关闭的无副作用资源报告（D0 / D3 / C）

ResourceLifetime增加`CloseReport snapshotReport()`，只同步读取原已登记ResourceOwner、
未完成work、原resourceIssues与terminalIssues，按既有报告规则生成防御性快照；不seal、
不requestClose/cleanup/retry、不await、不新增attempt或任务、不移除owner、不释放permit，
也不改lastCause/lastStack。原close仍通过同一报告逻辑返回，不能复制第二套问题汇总算法。
没有已登记未决项仅表示当前快照为空，不证明准入已封或整个domain已close；报告不缓存。

用途是保留已有Updates合同的先task、后feed/read关闭顺序，不把两阶段改成并行取消来
得到完整报告。若原task阶段在首次绝对deadline内尚未join，D3合并原task报告及观察／读取
lifetime的snapshotReport，保全部typed issues和原恢复责任；不得为取报告提前触发第二
阶段清理。后续只能沿原任务和阶段继续，最终全部真实join后才能Clean。Snapshot不改变
领域seal／任务取消／内部已准入读取的职责，也不授权新pool、registry或应用退出owner。

D0只最小解冻resource_lifetime.dart及必要公共声明，现resources_ports已导ResourceLifetime
则不增加转发出口；D3在该真实方法落盘并局部审查通过后接入Updates，独立typed read／
mirror和Skills返工可继续。C补纯报告不触发任何关闭、未决owner/work仍可恢复及真实阶段
顺序的必要公开契约源码，运行验证仍统一后置。

## 28. 系统角色配置存在性与建议的原配对读取（D2 / R / A / U1 / D0 / C）

接纳只属于Configuration领域的专用配对scope，不把role解析塞进§23的Models-only方法。
公开不可变值与签名为：

```text
ConfigurationRoleReadRef {entry:int,revision:int}
ConfigurationRoleReadTarget {
  reference:ConfigurationRoleReadRef,
  configuration:ConfigurationReadTarget,
  catalog:ModelCatalogReadTarget,
  stamp:ConfigProjectionStamp
}
RoleRouteRead = configured{route:RoleModelRoute}
              | missing{suggestion:ModelSelection?}
ConfigurationHeader.roleRead:ConfigurationRoleReadTarget?
ConfigurationRepository.roleRoute({required ConfigurationRoleReadTarget target,
  required String roleId})->Future<RoleRouteRead>
ConfigurationPort.openRoleRead(ConfigurationRoleReadTarget target)
  ->Future<ConfigurationRoleReadConnection>
ConfigurationRoleReadConnection:
  header()->Future<ConfigurationRoleReadTarget>
  roleRoute(String roleId)->Future<RoleRouteRead>
  requestClose()->void
  close()/retryClose()->Future<FeedCloseReport>
```

这些值使用Freezed，不携owner/Future。pair ref由原Configuration registry登记真实配对
材料，所属origin是configuration.origin，catalog.origin独立保留，不能在Dart由两份latest
header拼成target。Rust复用ConfigRuntime同锁read_with_catalog/observe_projection_sources
的配置、完整已验证模型材料与真实settings/modelCatalog clocks；身份登记必须对应同次
捕获，产品incarnation不匹配则显式失败，不在事后从最新feed补refs/origins。可共享原
不可变材料，不另建canonical store、资源池或长期缓存。

ConfigurationHeader.roleRead随任一来源／origin变化发布新pair ref；仅目录变化不伪造
settingsRevision增加，也不强制普通ConfigurationReadRef及配置字段pins变更。来源尚不可
读取时roleRead为null，UI保unknown，不能按缺role或无候选展示。原scope一经接管只读
原pair，旧材料不可得为实际Unavailable/Superseded；不重新捕获latest来凑成功。

Rust按原roleId查原raw role map，不trim/case-fold或新增角色准入规则：存在key即
configured，原account/model/effort（包括空、unresolved、unsupported）不补默认、不改写。
只有确实不存在该key，才用此pair完整Models材料的§23首文本模型建议；missing(null)仅
表示完整固定目录无候选，unknown/错绑/读取失败仍typed error。查询不依赖Profiles target、
不校正配置、不发operation、不改变保存validator，更不承担Start/preparation。

D2首await前冻结完整target及roleId，经原lifetime.run和PinnedReadOwner.use登记，按
完整pair target pin，查询合并另包括roleId；header完整相等、configured返回原请求key，
不从当前mirror补字段。仍原scope预算/shared64call/late-open交接/真实关闭和未决责任。
此结果只读，不写第二canonical镜像；原roles raw读取能力按其实际消费者保留，不作策略来源。

U1替换系统行里的Dart presence/first/default推导，消费configured原值或missing建议；只有
missing(null)才保旧空account/model显示。首await冻结role/pair/VM lifetime及意图，pair
变化按可见需求重读，迟到结果不覆盖新pair；已有Models descriptor仅在target与pair.catalog
相符时用于显示，不决定是否configured或再算建议。最终Start的mode/simple/overlay与
ModeCatalog相容捕获仍未决，不把此scope扩成万能resolver。D0只在真实声明落盘后补窄出口，
A/R同步typed协议与原注册资源，C迁真实公开接口消费者；运行验证仍统一后置。

## 29. Native Models发布捕获与共用读取scope内核（R / A / D2 / C）

接纳R实际阻塞报告提出的两条必要接缝，沿用已有机制，不复制第二套产品资源池。Models
完整read owner/DTO/分页/建议查询继续实施；仅已有同步ModelSelectionMaterial不算native完成。

### 原发布点捕获与连续性

Models唯一材料／引用投影在ConfigRuntime原canonical发布边界同步推进：初次登记与原
相容捕获同锁，后续每次相关canonical变化在交付或watch合并前已经登记同次材料及成员
身份连续性。选择这个原owner内的具名能力，不另建可重入外部callback协议或通用事件总线；
锁内不await、网络、磁盘或调用外部消费者，唤醒／向transport交付在完整发布之后进行。

latest watch只作通知，不可在wake之后read current并按最终值diff来补连续性。账号／成员
删除后同ID重建必须新entry，改变后再改回也不能复用旧revision；消费者尚未poll不影响
这条事实。可维护有界当前成员身份与原不可变发布材料，不留无界tombstone／强历史表。
保原完整账号／模型顺序、已验证effort声明与文本资格、目录派生字段／effective search和
真实水位；不序列化全Settings再select，不把凭据带进Models材料。若捕获／资源准入失败，
显式保真实来源错误与身份失效，不伪造连续无变化或靠latest补旧ref。

当前材料、原最多2个未ACK Data／latest待发1份、已pin scope承担原材料寿命；已退役且
无责任的材料不保强缓存。旧版本不可得仍Unavailable/Superseded，禁止query时读新Config。
§28配对role材料同样来自这个原配置／目录相容边界，独立Config配对ref，不把role方法
加入Models-only连接。新决定不新增Start/default resolver或改变保存validator。

### 提升现有Thread读取生命周期，而非新建池

将thread_reads/lifetime.rs已有registry/group/owner的准入、计数、任务join、释放逻辑提升为
一个runtime私有共用内核；Thread层保必要的typed适配，Models等产品域使用同一内核。
只擦除释放责任，不引入Any/JSON业务payload或通用字段树。具体材料和wire身份仍由各域
拥有：Thread ReadScopeIdentity不能用假ThreadID包装ProductReadScopeIdentity，反之亦然。

计费键明确区分Thread(threadId)与Product(resource,原业务scope)。ref、incarnation、
当前页或新连接不是计费分片；同Thread跨Live/Cold及代次共8，产品同资源／原scope跨
incarnation的value/source-status/配对读取合用原8。runtime builder仅创建一个registry，
复用同一个ReadCalls64、实际BackgroundTask及原epoch/incarnation分配机制，不多计或
复制任务。Thread现Cold取源先登记lease、失败精确回滚、最后释放与新准入同锁的已批
不变量保留；material/residency/permit只能在真实query完成且原close条件满足后释放。

关闭准入在原runtime关闭边界同步封闭。共享scope/source封口与真实join由原关闭编排独立
监督，不能只挂ThreadObservations.finish的成功路径：threads.close_all失败或未结束不
阻止其它scope收到封口／取消；旧失败与新未决问题都保留，首次绝对deadline不续期，原
finalizer前汇总。不丢未决owner、吞失败或换一个finalizer，不改变全局close为假Clean。

R可改必要config/runtime发布点、既有scope内核／Thread薄适配、builder及原shutdown
监督接缝，并按有依赖的两个切片报告（共用机制与Models具体source/read）。原已批51受
影响者逐项记录新身份并定向复审；未受影响文件／producer／其它域批准不机械失效。A只在真实入口
落盘后接线，C按真实公共消费者补回归，运行验证仍统一后置。

## 30. 原提交与新建成功后的execution借用（D1 / D0 / U3 / C）

先独立补齐真实Drafts factory的一个确定前置，不把尚未定的附件／新建运输补成stub。
ConversationDemand增加两个组合专用能力，明确区分已有ready源与新建成功后启动观察：

```text
retainForSubmission(ConversationSession exact,
  {required ThreadFacetStamp expectedOrigin})->SubmissionExecutionLease
retainForCreatedInput(ConversationSession exact,
  {required SubmitPromptReceipt receipt,
   required CreatedInputExecutionSource source})->SubmissionExecutionLease
SubmissionExecutionLease:
  threadId:String
  attemptId:AttemptId
  execution:ReadonlyLatestValue<ThreadExecutionState>
  ready:Future<ThreadFacetStamp>
  release()->void
```

lease是runtime owner／借用能力，不Freezed、不暴露具体Session writer或close权。两入口
同步校验同一ConversationRepository持有的具体Session实例且未seal，先登记原attempt／
需求／ready责任再触发任何可重入通知或open。不能仅按相同threadId重查并换成新实例。
sealed为Cancelled，外来／已替换实例或来源为真实Conflict/Superseded，不隐式select。

retainForSubmission要求当前execution ready、实际源可用，expectedOrigin为execution且
runtime epoch/incarnation与当前原Session相符；冻结真实登记时的stamp。普通execution
revision推进不被误当新incarnation，不增加业务提交的execution-revision CAS；原submit
仍使用真实modelRouteRevision CAS。未知源不得通过这条能力打开后自动重试发送。

retainForCreatedInput仅供已收到真实新建成功receipt的原操作使用，核receipt.threadId与
exact、原receipt及source身份；不得把任意错误／无receipt的UnknownOutcome改作成功观察。
允许同原Session还未ready时通过§31原创建owner提供的能力建立execution-only需求，不ensure／重建
业务Thread、不改Workspace选择、不打开Timeline或为观察重连另外四域。若本Session已被
合法UI选择，其独立UI需求仍保留。ready绑定该次原attempt首个成功execution基线；取消、
release、来源替换或读取失败必须结算该ready，不悬空、不切新实例／新代次碰运气。

release幂等，只归还该lease自己的execution需求；其在途context/open/query与真实native
close仍由原Session／Repository监督。lease.ready失败时操作保原已确认结果及typed错误，
不能把新建成功改成rejected或重发。原SubmittedInputObserver继续在该具体execution源上
读取原input持久化证据，构造接管/失败回滚和cleanup carrier义务不变。

为让已有提交与新建操作都推进**同一个原operation**的证据，允许把私有
SubmittedInputObserver及其construction failure改为必要的泛型T，强持原OperationWriter<T>；
只调用原identityObserved/effective/durable/evidenceFailed，不另造子ticket、伪receipt、
dynamic cast或等值failure副本。该私有泛型不扩大领域公开错误／资源接口。

D1最小解冻上述demand/repo/Session与必要execution调度／observer接缝；已批Timeline准入、
read scopes等无关范围保持。D0待实际声明后在conversation_ports只补窄lease导出，UI领域
barrel不导该组合能力。完整Drafts factory、附件binary和新建原job控制仍需后续正式裁决。

## 31. 创建成功后的非激活execution源能力（D1 / R / A / D0 / C）

补齐§30实际发现的transport缺口，**保留旧UI live/cold语义**：普通live可以按原合同
ensure执行owner，cold仍是checkpoint快照；二者都不能被悄悄当作新建输入的非激活持续
证据源。也不能从SubmitPromptReceipt推造它没有的epoch/incarnation/sourceRevision。

采用原创建owner的具名runtime借用能力，而非按threadId重新查current的第三种模式：

```text
CreatedInputExecutionSource:
  threadId:String
  inputId:String
  runtimeEpoch:String
  incarnation:int
  openExecution()->Future<FeedConnection<ThreadExecutionFrame>>
```

该接口位于Conversation的data/ports层，不Freezed，不加入领域值或StartNewThreadResult。
原NewThreadCreation/preparation runtime owner在得到真实成功结果后提供与该次结果绑定
的能力；A持有原native创建句柄／原已登记源捕获，不能用普通openThreadExecution(live)
包装实现它。epoch/incarnation来自该native owner真实保留的projection identity，不从receipt
推导，也不暴露伪sourceRevision。D1同步核source.threadId/inputId与receipt/exact相同、保存具体source对象，
不得换成按ID查到的新对象。现有StartNewThreadResult的thread/receipt纯值结构保持。

native创建owner在原真实Thread初始化／结果交接内保留既有执行owner及其原projection
定位，借读只附着该既有源，不再次ensure／重建业务Thread，不按稍后的latest替换。源
确实不可取得时返回真实Superseded/Unavailable，关闭后为Cancelled；成功结果与该读取
失败分别保留。新feed首个真实baseline的epoch/incarnation必须匹配source，revision只取
该真实baseline，Dart不补值；其
身份仍描述live projection，不因此获得普通live的激活权限。原feed ACK／取消／close
以及共享预算／实际join规则不变，不新增独立观察池或body镜像。

新建后的借读是对已受理结果的只读观察，不经过会执行ensure的UI准入路径；旧UI／新
业务请求的Recovery unknown不准入规则不变。需要原metadata时仍只读，未知不能成为
更换原source或重建Thread的理由。原Session若已有同epoch/incarnation的execution ready源
可借用；不相容的新source
不得覆盖其已有未决execution借用，须明确失败，不以其它四域或cold重连兜底。

source open先归原Session attempt登记，晚句柄必须交回原owner真关闭。原创建owner在
转交完成前持有源责任；feed接管后独立保自己的原源pin，创建owner收束不关闭这个feed。
原open回复丢失／创建owner关闭仍须由native登记的原任务／pin真实join，不能靠GC或
断流放行全局创建gate。只有A/R真实能力完成才称native可用；D1现在可完成SDK的具名
接缝与监督，不写普通live fallback或假source实现。D0待声明后只补窄ports导出。

## 32. Updates的显式启动与完整value gate（D3 / U3 / C）

修正fresh审查确认的两条启动接缝，不放宽D3自动任务准入：createUpdatesRepository只
构造本域owner／初始未知状态，不capture/open native feed，不RustLib.init或check/prepare。
原RuntimeReady之后，U3先同步登记原Updates观察，再发显式loadValue需求启动唯一feed。
disabled本地能力不制造canonical Disabled／Idle，也不隐式启动不需要的自动工作。

AutomaticUpdatesStartup须等待projection ready且value为完整ReadyReadValue，其origin
与当前projection.stamp.origin相同、reference等于当前header.reference；不只检查header。
在真正调用startAutomaticOnce之前再次核同一条件，若等待期间目标改变则继续等待当前
合法值，不以旧gate证明新目标准入，不放宽SDK校验或从later值补原结果。生命周期与读取
都保原已登记Future／观察责任，seal能结束gate并join，不延长退出deadline。

只读订阅／物化／gate失败保持typed错误，不永久缓存失败Future让显式恢复失效。后续
显式ApplicationBootstrap.start可重试尚未受理自动动作的gate／attach，但不是源通知
触发的自动重试；任何已受理automatic operation仍复用原ticket，失败／Unknown也不再
发一次业务start。close只能join原责任，不把失败当未join，也不因清缓存丢在途责任。

ApplicationBootstrap分清已取得的原RuntimeReady结果与attach成功；_attached只在本次
attach真正完成后成立。runtime Ready后attach失败，保原Ready和错误，显式重试仅重入
未完成领域挂接，不再调用新的native启动／新attempt。同步登记和重新进入仍合并在途；
已完成的selection／其它挂接不能重复创建观察或writer，局部失败须保留或正确回滚实际
登记的责任。U3负责这条恢复与gate／assembly，D3仅去除构造期开源，双方分别冻结送fresh。

## 33. 原对象归档捕获与metadata读取责任（D3 / D1 / U3 / D0 / C）

采用D3与D1报告中的目标特定捕获能力，修正release为异步报告；不把实际缺失的Drafts
factory／附件ledger当作已经具备的空leaf。以下类型由D3 data声明，D0仅从workspace_ports
导出；domain/UI不取得捕获writer。它们是runtime能力，不Freezed，不产生新operation。

```text
WorkspaceArchiveCapturePort:
  captureProject(String projectId,{required WorkspaceState frozenSelection})
    ->WorkspaceProjectArchiveCapture
  captureThread(String threadId,{required WorkspaceState frozenSelection})
    ->WorkspaceThreadArchiveCapture
WorkspaceArchiveCapture:
  releaseWithoutArchive({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>
WorkspaceProjectArchiveCapture implements WorkspaceArchiveCapture:
  prepare(ProjectRecord originalProject)->Future<void>
  afterArchived(ProjectRecord archivedProject,{DateTime? deadline})->Future<CloseReport>
WorkspaceThreadArchiveCapture implements WorkspaceArchiveCapture:
  prepare(WorkspaceThreadRecord originalRoot)->Future<void>
  afterArchived(ArchiveThreadResult result,{DateTime? deadline})->Future<CloseReport>
```

### 捕获、确认与结果

D3先登记原operation/work并同步捕获，再进入任何await或同lane等待；捕获复制全部实际
owned对象身份，含retiring／unresolved／未返回open，不能调用session/composer/start补
对象。D3同时捕获自己的query/metadata；U3组合外部Conversation与Drafts leaf，不递归把
D3放入外部组合。准备阶段新产生的原metadata责任登记在本次原work内，不在确认后重扫
全域。WorkspaceState只冻结原selection及generation，选择发布仍仅D3。

prepare先核原目标，必要归属未知／NotFound／失败则不dispatch，不能当“不属于项目”。
Project按所有捕获对象的真实project归属筛选；Thread确认后取原捕获集合与native完整
removedThreadIds交集，不扫描Sidebar找业务全集，也不套用Project的busy规则。
真实结果与receipt先保存在原work，再afterArchived；重复相同确认只观察原清理，不同
确认Conflict。只有receipt而缺完整结果时保known-success/sync-failure和capture，不拼IDs。
后继仍按v4-workspace原规则：Project完整项目集按String ID首项起始态；Thread优先native
nextRoot，普通remove不能盖过它；均核原selection generation，窗口缺项不是删除。

明确未dispatch或Rejected时releaseWithoutArchive只释放捕获的准备／借用责任，不清UI
或草稿。Unknown保原capture、目标、冻结输入与原operation，不在finally丢弃或自动重发。
known-success的cleanup未决也保在D3原WorkspaceCommands work中，不因ticket结算移除。
首次成功结算前的同步失败使用原writer的syncFailed／acknowledgedSyncFailed保value/receipt；
已结算后的晚失败只进原evidence/cleanup诊断，不改Rejected/Unknown，不另造ticket。
release与retryCleanup只真join原工作或调用原可恢复close，不重新开源、猜业务结果或续期。

### 纯metadata值与实际owner

§8的ConversationContextPort值型readThread替换为具名
`openThreadMetadata(String threadId)->ThreadMetadata`，直接借用D3已有公开ThreadMetadata
能力；`readRecoveryAccess`不变。U3用同Graph的WorkspaceRepository.thread实现，不保旧
ContextPort readThread转发alias。WorkspaceRepository.readThread本身的其它消费者不删除。
这是同一原runtime的非激活目录读取，不ensure执行Session，不以当前selection代替ID。

单实体成功baseline必须恰有一个目标实体，不接受健康的null collection／零项或多项。
真实不存在／权限失败仍为typed失败，不用空集合表示。为表达尚未取得entity ref时的
lookup／物化失败，ThreadMetadataState增加可空`readError:StudioFailure?`，默认null；
它是本次原metadata读取错误，不改写canonical source状态、不伪造ProductEntityRef。
该错误只随匹配的原origin/ref/读取代次发布，新目标或新的显式读取不能被旧catch/finally
污染。初次自动读取与显式retry使用同一公开错误路径；错误不能只存私有lastCause。
D1/U3/C消费者区分尚无值与真实readError，不能因projection已ready而忽略读取失败。

D1在外呼前登记metadata准备工作，取得实际ThreadMetadata后先同步观察再取值；原纯结果
Future与真实close责任均保留，包含迟到返回、观察取消失败与Unresolved。纯读取成功的
immutable record在Recovery之前保留；UI仍独立核原generation、Recovery和live/cold，
不能把知道project当成业务准入。归档prepare可借原结果／在途纯读取；从未context或
created-source-only时仅建立这条metadata需求，不启动UI Recovery、五域或Timeline。
必要原工作已真实Clean则不复活它；跨seal继续尚未开始的准备须在capture时已准入，
否则明确失败。Composer无Session时也只借metadata，不创建Session找归属。

metadata owner沿原D3目录监督和D1已有准备责任登记收束，不新建查询池；值Future完成
不是底层资源Clean。原实际owner／close报告须随捕获保留，不能在确认后按ID换读取者。
原Session的metadata登记只包含纯读及其真实清理，不登记整个capture寿命，避免capture
等Session关闭、Session又等capture释放的自等待。失败重试仅显式纯读，不重放archive。

### 原UI需求与草稿引用

Conversation捕获原具体Session、原UI选择需求token/generation及已登记工作。确认时
只封闭/返还该原UI需求，current/selected移除同时核对象identity与原generation；较新
需求不动。原token的已准入open/query/consumer即使晚返回也真join，不只关闭首批句柄。
在原session_reads登记中标明具名detail scope的原UI需求，不用另一个registry或全域seal。
现SubmittedInputObserver的readAcceptance沿原ConversationCommandPort.readInputAcceptance
与operation owner，**不属于UI detail scopes**；execution lease及该原证据query不能被归档
取消。不为尚无消费者的“通用operation scope”新增框架；未来真实额外借用须明确归属。

Drafts leaf仅在真实owned registry/双归属附件ledger落盘后实现：捕原record identity、
expectedStamp、attachmentGeneration及原draft引用。确认时三者仍匹配才清原内容；同ID
新owner或晚文字/附件/mode/workspaceMode编辑均保留，不seal新编辑。只减captured draft
侧引用，不减capture后beginSubmission取得的operation引用，也不减Unknown引用。最后
真实引用释放才native删除，late admission仍先登记后按原generation采用或真实清理。
Thread archive不清同项目Start；Project也不清无关项目或全局startRoutes。

### 有序装配与本轮边界

D1 Conversation factory返回record增加`archive:WorkspaceArchiveCapturePort`；真实Drafts
factory未来提供自己的同型leaf。U3以具名typed闭包组合两leaf，所有绑定在Graph对外/启动
前一次完成；半装配动作返回typed unavailable，不空capture、service locator或裸late错误。
D3 factory最终仍返回同owner的repository/submissionSelection，required archiveCapture和
原port/budget/operations/只读Recovery；构造不调用未绑定capture或执行归档。

先发布D3声明/D0窄出口，再实施D1 Conversation metadata/UI捕获与U3 context适配；D3
29个已定非archive文件先独立审查，随后再改原work/归档/后继/factory。Drafts ledger和真实
leaf仍是生产归档的必要前置，不能注入Noop冒装配完成。C按实际新声明迁消费者，静态阶段
不运行；同ID替换、晚编辑、未知归属、Unknown、原scope/证据隔离及cleanup失败均须保全。

## 34. Settings原Configuration源的显式恢复（U1 / C）

fresh审查确认角色页卡片外Retry在header保留但feed失败时可能无动作。修复使用既有能力，
不新增SDK retry接口或另一关闭器：ConfigurationRepository.loadSourceStatus进入原mirror
capture；closing feed由原resync/cleanup监督，真实释放后重开，并等待原读取所需基线。
这条纯读取不是业务reload，不写配置、不新建操作ticket，也不重放失败或Unknown的写入。

U1显式retryRead须检查Configuration当前sync状态，不能仅header.reference==null才恢复。
失败源即使保留旧header且全部字段已物化，也要发起这条已有的source-status读取需求；
健康但roleRead为null仍保unknown，不从无target伪造role查询。原目标/lifetime/Repository
在外呼前冻结，失效不把重试交给后来VM会话；同一在途读取沿已有reading/lifetime机制合并。
恢复后角色需求消费实际新基线的原pair，旧目标晚结果仍无发布资格。错误、dirty/raw与原
业务操作结果保持；源通知本身不新增显式重试，不用自动循环掩盖永久失败。

C增强原真实组件用例：在真实source failure且旧header保留、字段已读的场景实际点击
卡片外入口，观察原feed取消/close真正完成、实际port再次open并取得合法新baseline，
再确认source/role状态恢复且无业务写重放。替身只提供受控的新native句柄与材料，不把
已closed的同一ScriptedFeed复用为新连接，不复制恢复算法；按钮存在不能替代恢复证据。
继续保留无target无role-local重试、真实source错误保真及合法role query失败可重试的断言。

## 35. ModelCatalog全资源来源的唯一owner与可用性语义（R / A / D2 / C）

已核实旧lifecycle/snapshot、product_subscription与state_query都在取得目录后临时用
ObservedResource::ready包装，ConfigRuntime只有逐账号Observation与目录snapshot，
不存在可供复制的全局探测operation或八态owner。本节将原可用性语义归位到canonical
owner，不采纳“任一账号出错即全局Degraded”等未经定义的探测聚合，也不删除既定
CatalogHeader.source或让Dart／FRB自行拼状态。§29业务捕获、成员连续性和读取内核不变。

### 唯一来源与真实转换

- ConfigRuntime原RuntimeState持有唯一目录来源元数据，复用现有ObservedResource类型
  表达可用性；可用`ObservedResource<()>`作为同锁目录snapshot的可用性见证，不复制
  一份Models业务值、不引入第二reducer。它与目录在同一guard形成相容snapshot。
- 只有原初始化完成配置／目录构造和校验后创建Ready。初始化失败保原typed错误，不创建
  可对外观察的Ready、健康空集合或假Loading。原同步初始化没有可借用的全局异步ID。
- 原owner每次实际接受并发布新的目录来源输入时，使用现有Observe转换记录真实发布
  时间；其独立revision在原状态基础上checked递增，不取settings/catalog/projection
  revision别名。读取、订阅、attach新Models source及watch醒来不推进状态；没有实际
  来源发布的重复通知不制造新revision。last_checked_at保持None：它不冒充所有账号
  已完成联网检查，逐账号checked_at仍由原探测owner负责。
- 单账号或多账号开始／结束probe、失败、缓存警告、无在线模型等仍完整保留在原账号
  status与effective模型材料。即使全部探测失败，只要已校验目录仍可读，全资源保持
  Ready；Ready不是供应商健康、路由可用或必有模型的声明。没有新的全局probe操作，
  因此不合成operation_id，不把任意账号的operation／错误提升为全局状态。
- 原ConfigRuntime关闭门实际封闭时记录Stopped和原关闭时间，再沿已有source封口及
  真join路径收束。runtime较早的取消门仍须立即拒绝准入，不能为等待状态帧延后取消；
  不承诺关闭期间必须再交付一个Data。Stopped本身不证明任何producer/query已join。
- 现有八态协议与按需metadata读取保持穷尽映射；本来源当前真实可达状态为成功初始化
  后的Ready及关闭Stopped，不为覆盖八态人为制造异步加载或错误聚合。后续若增加真实
  全目录异步操作，须另定其owner及操作身份，不能让adapter补齐。

### 捕获、失败与引用

Models source在§29原ConfigRuntime guard内捕获这份原metadata和同次业务材料。状态
材料独立不可变，ProductSourceStatusRef拥有独立身份／checked水位；metadata-only变化
不推进业务ref或entity revision，业务-only变化不借业务时钟伪造来源身份。header brief
与status读取必须对应同份元数据，旧status只由current／原2个unACK／latest1／已pin scope
持有，弱定位不能用current补旧ref。status读取与value读取合用§29原8／64预算与真join。

CapturedModels或身份分配失败仍用原ModelCaptureFailure／last_failure和真实feed失败
路径报告；不能发布缺损Data或伪装无变化，不能因canonical目录来源仍Ready而吞掉投影
失败，也不把投影错误改为账号错误或虚构全局StateOperation。失败后的成员身份重建、
已pin旧材料寿命及已成功业务命令结果保持§29语义。来源metadata计数耗尽同样显式使
该观察能力失效并保留真实typed错误，不回绕／saturating伪连续；不得因此改写已经提交
的配置业务结果。使用既有ObservedResource转换前须检查递增可用性，不改其全仓契约。

R先在原owner补真实来源，再完成Catalog feed／source-status scope／FRB与Server。
旧三个临时Ready包装入口在迁移保留期间只能消费同份原metadata，随后随旧聚合消费者
一并删除，不能形成第二writer。必要read35受影响文件按新身份复审；冻结待审read14与
Templates feed5不因本节自动解冻。A仅转换真实native metadata，D2现有sourceStatus形状
不变；C覆盖来源Ready与账号失败并存、真实关闭、旧status pin／metadata-only身份及
捕获失败不发缺损Data。继续static-only，不提前生成、运行测试或扩大供应商业务范围。

## 36. show_image既有typed媒体呈现先行（U2）

已核U2专卡报告与保全旧行为。先实施不依赖新增native字段的图片呈现，不等待caption／
web_search参数派生载体裁决，也不借此修改canonical payload或v2存储。

- `show_image`每调用独立左对齐卡片，最大宽700；只取typed附件原序第一个image，不能
  展示所有附件或按imageId字符串回查。调用身份与附件身份共同定位，跨调用同资源不合并。
- 无图保96高不可用占位与原工具状态；失败／拒绝／取消／中断等以实际typed lifecycle
  表达，不补不存在的wire状态。普通工具图集的调用序／附件序／重复occurrence规则不变。
- mounted卡片首次显示时由Smart沿原Thread+attachment typed读取获取媒体，而非先点
  metadata才能显示。未知尺寸用16:9，高不超过360，loading/error/success保持比例，
  成功图fit.cover。UI-only ImageProvider不进入Freezed／VM状态，不新建全局bytes缓存。
- 显式retry只替换仍属于原身份的失败读取，不清较新Future；Thread、附件或展示代次
  替换后，旧结果无发布资格。原query继续由现有owner真实监督，不以忽略回包假join。
- 点击等待原媒体Future，失败不打开；成功后重核mounted与原身份/代次，官方Dialog与
  InteractiveViewer保缩放0.5..5、文件名及原查看入口。不得增加第二Session／display owner。
- 本片只解冻U2必要row/attachment Smart与Dumb图片卡片文件；display2、dirty-close7、
  其它已批行为和SDK/Rust/A/C文件保持原身份。完整caption、web kind/details、hosted
  canonical生产链仍未裁决，不用JSON／regex／成功receipt-only或省略功能冒称完成。

U2按新文件身份提供受影响已审范围的delta及完整保护集合，随后fresh局部审查；真实GUI
行为和原生附件链在全部手写完成后的统一验收中验证，本片不能替代该证据。

## 37. 附件原文件pin与真正有界binary读取（R / D1 / A / D0 / C）

接纳A附件只读调查中已核实的存储事实：draft、普通Thread附件与已归档工具媒体最终
均为本地文件。只补原只读能力，复用标准文件API、已有read scopes/read calls与原退出
监督；不增加存储层、通用codec或附件账本。admission／部分补偿／结果交接与creation
仍另定，本节不使这些候选自动获准，不提前宣称完整Drafts factory。

### SDK只读接缝

```text
AttachmentBinaryPort:
  openDraftBinary(draftId:String)->Future<AttachmentBinaryRead>
  openThreadBinary(threadId:String,attachmentId:String)->Future<AttachmentBinaryRead>
AttachmentBinaryRead:
  identity:AttachmentBinaryIdentity
  byteLength:int
  read({required int offset,int maxBytes=65536})->Future<AttachmentBinaryChunk>
  requestClose()->void
  close()->Future<FeedCloseReport>
  retryClose()->Future<FeedCloseReport>
AttachmentBinaryIdentity {
  scopeId:String,runtimeEpoch:String,incarnation:int,target:AttachmentBinaryTarget
}
AttachmentBinaryTarget = draft{draftId:String}
  | thread{threadId:String,attachmentId:String}
AttachmentBinaryChunk {offset:int,bytes:Uint8List,nextOffset:int?}
```

port／read为drafts data/ports运行时能力，不导入UI/FRB；identity/target为Freezed纯值。
chunk是调用方独占的临时二进制结果，不Freezed、不进canonical/ViewState，也不交共享
可变buffer。target在打开前冻结，incarnation取原native读取资源的真实分配身份，不从
数字常量、业务revision或attachmentId散列伪造。scopeId是原共用registry真实scope ID；
沿现read scope关闭报告约定作为FeedCloseReport.feedId核验，不制造事件流或ACK。
factory未来只注入这个窄只读port；不为尚未定的admission添加stub方法或万能resolver。

SDK原公开readDraftAttachment/readThreadAttachment仍返回调用方独占Uint8List，但必须
沿同一次真实native scope按块组装。所有opening/query/close归Repo原工作集合，首await
前登记预算与责任；未完成scope的清理错误保原owner/issues，不能为了返回bytes丢弃
关闭责任。UI退役仅阻止旧发布，不取消业务提交或关闭整个Session。完整factory未齐前
可独立实现真实私有读取owner，不能因此给缺mutation能力的Repository注入Noop。

### 权限、文件与预算

- Draft在原entries核验与文件open之间和remove线性化；删除先赢则新open真实失败。
  不扩展原权限为任意路径，也不声称现draft record原本含Project/Thread归属字段。
- 普通Thread先沿原owned Thread、其catalog成员、原session-relative路径校验；工具
  resource沿原snapshot/pending effects/history中完整typed delivery授权，保同ID异引用
  或模态冲突拒绝。SQL substring、资源digest或ID前缀不能授予读取权限。
- 持同一file handle与handle.metadata长度，核原记录要求。工具resource复用原streaming
  长度／SHA完整性校验并在同一handle继续读取，不能验证一个路径后重新打开另一个对象。
  不把普通附件未有的额外摘要校验说成既有要求。文件按原不可变存储合同消费；外部
  原地修改／truncate不能由pin排除，意外EOF／长度或完整性冲突必须真实失败。
- 读块不共享无保护的seek cursor；现有worker/短同步锁只登记与取稳定owner，长hash/IO
  不在共用registry同步锁内。底层blocking工作开始后必须真join，不能靠取消wrapper释放。
- 明确新binary payload上限为256KiB、默认64KiB，maxBytes合法1..262144；不是借用JSON
  编码预算或内部hash buffer来推断。offset非负且不超过原长度；等于长度合法返回空块、
  nextOffset=null，大于长度InvalidArgument。中间块按实际字节数前进；到原长度才null，
  意外提前EOF为Storage，不能零长度假EOF。整数／加法受检，不钳制或回绕。
- Thread binary计入同Thread原scope8；Draft在共用ReadScopeBudgetKey增加真实的
  AttachmentDraftRuntime绑定，同runtime所有draft共8，跨read/ref/incarnation不分池。
  两者opening/hash/read均合用原ReadCalls64，scope只借任务不重复计费。SDK使用原
  readModel/pendingOperation许可，不把attachment metadata许可当读取许可。
- close/requestClose/retryClose复用原read scope/bridge registry与唯一runtime shutdown。
  requestClose同步封口；lateopen、hash、seek/read、producer-less query全部实际结束后
  才释放handle。普通read错误且worker已join不自动成为永久cleanup错误；一次性取消
  失败仍按§13 terminal保留。Linux unlink与Windows delete-pending都不等于已开句柄
  结束；不承诺跨平台删除必成功，也不以路径已删假Clean。

### FRB与HTTP

FRB只映射真实binary opaque、identity、原Vec<u8>与typed错误；不通过whole-buffer旧API
在Dart切片。HTTP提供两个具名POST open：`/api/v1/attachment-reads/draft`请求draftId，
`/api/v1/attachment-reads/thread`请求threadId/attachmentId，响应identity与byteLength。
`GET /api/v1/attachment-reads/{scope_id}/bytes?offset=...&maxBytes=...`只返回原始
`application/octet-stream`；`Anywork-Offset`为本块offset，`Anywork-Next-Offset`仅未到
末尾时存在。合法终点为200空body且无next，不伪造HTTP Range语义。错误沿现typed JSON
错误映射。POST同scope的`/close`与`/retry-close`返回原关闭报告，控制走原专用64许可；
open/read走原普通请求池，不能代替native64。原已登记scope与运输任务需真实join，
断HTTP请求不丢底层owner；OpenAPI从同router及真实DTO声明，不复制第二schema。

旧whole-read消费者在新链可用后全部迁移并删除旧入口，不留兼容转发；生成仍root统一。
原Server multipart200MiB/每文件50MiB/16文件与native模型max_bytes/max_count/总量／
source/mix等准入保持各自原语义，不把Server16项或50MiB外推为全native固定上限。
R对实际共享scope改动给新身份复审，D0只在真实声明后补ports出口，A等真实入口再映射，
C保现有读图／权限／lateopen／关闭用例并补原文件删除竞争与合法EOF/错误边界源码。

## 38. Interaction编辑重建与显式关闭的原会话保护（U2 / C）

fresh审查确认当前InteractionViewModel.build重建空state会丢dirty raw，且关闭确认只核
editRevision，不能区分同Notifier的后一编辑生命周期。本节落实既有编辑保全合同，不
扩大为native respond/cancel/route能力，也不改interaction请求准入或敏感信息规则。

同完整editor key的观察重建只替换其读取责任与canonical基线，不以空state重置原answers、
fallback、reason、feedback及dirty事实；原pending/Unknown/失败归原操作，不清成idle。
不同完整key／实际业务绑定不自动移植raw或用新目标结算旧操作；原输入仍按既有显式结束
规则保留和处置，不用永久全局缓存补救重建。VM仍是唯一编辑writer，不新增编辑器框架。

每次实际build／替换读取会话有可校验的编辑生命周期身份。Smart在打开确认前冻结原VM、
完整key、具体生命周期、editRevision与latestIntent；确认返回及清原raw前核身份仍有效，
任一失效只拒绝此次关闭，不discard新内容、不重弹或代替用户再次确认。同Notifier对象、
相同数值editRevision或仍mounted都不能单独证明原会话。显式endEditing必须接收并验证
同一组冻结条件，不能让另一调用路径绕过；同步发布产生重入后，面板关闭回调仍只作用于
原target／原callback，不能调用已换目标widget的新onClosed而关闭新的编辑器。

确认取消、provider／widget卸载和导航均不等于回答／取消native interaction。真实已受理
动作及其原query/cleanup继续原owner真join；只读观察代次守卫不替代编辑关闭守卫。
U2仅修改本dirty-close七文件中必要实现并给新身份，display2、图片媒体四文件与U0文案
保持已批内容。C随后在真实VM/Smart组件层覆盖dirty重建、确认期间重建／新编辑／新目标、
同步重入与原pending保全，不复制VM算法；所有运行仍在统一阶段进行。
