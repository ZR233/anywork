# v4 领域公共能力与装配port

本文件固定Dart共享能力和D2/D3公共方法；[产品wire](./v4-product-wire-contract.md)负责载荷，
[生命周期](./v4-lifecycle-contract.md)负责真实取消/join。未列齐的D1/启动/更新及跨transport
签名在末尾明确保留为准入缺口，不授权执行者自创接口。所有声明为Dart形状；Rust对应
snake_case，异步trait按项目RPITIT + Send约定，不用async_trait。

## 1. 调用约定

- Repository action同步返回`OperationTicket<T>`，它在首await前冻结身份/输入并登记操作。
  admission关闭、无效同步输入或资源不足可同步抛StudioFailure；此时没有native写入，
  不能当UnknownOutcome。取得ticket后的结果全部经CommandResult<T>，不丢后台错误。
- 无原生receipt的真实成功走acknowledged；有receipt走committed/syncFailed，不能为统一
  T伪造原生receipt。read/validate/search/page返回Future<T>，失败抛StudioFailure，不产生
  OperationId，也不触发业务refresh、扫描、联网或activation。
- 可写能力只存在领域内部/装配ports。Widget/VM不能拿recorders、budget permit、stream
  producer或native handle。每个Repository只有自己的只读state公开，不导出reducer。
- `seal()`同步拒绝新意图，`close({DateTime? deadline})`与`retryCleanup({DateTime? deadline})`
  返回`Future<CloseReport>`；query/已接受意图仍由原owner收束，deadline不撤销工作。
- 相同目标写串行；stop、只读页/详情和不同account usage identity不进入无关写队列。
- 下文`Observed<T>`是迁到resources的原八态ObservedResource<T> Freezed值，不是新的异步
  状态机；外层VM仍使用Riverpod AsyncValue，不再创建通用页面状态总线。

## 2. D0共享装配能力

领域公开resources.dart只导出只读观察、不可变identity/错误/关闭/计量值。下列mutable能力
只从resources_ports.dart给Repository/组合根使用，复用原实现，不另建状态库：

```text
LatestValue<T>(T initial)
  value:T; observerCount:int
  watch(listener,{fireImmediately=false})->Observation
  watchLatest(listener)->LatestWatch<T>
  waitFor(predicate)->Future<T>
  publish(T value)->void
  close()->void

ResourceBudget({Map<ResourceKind,int> capacities=原六项默认})
  capacities:Map<ResourceKind,int>
  acquire(ResourceKind kind,{required String owner,ResourcePhase phase=active})->ResourcePermit
  used(ResourceKind kind)->int
  usage:List<ResourceUsage>
  watchAvailability(ResourceKind kind,void Function() listener)->Observation
ResourcePermit
  kind:ResourceKind;owner:String;phase:ResourcePhase;isReleased:bool
  mark(ResourcePhase next)->void
  release()->void
```

业务返回只读view，不直接返回上面的LatestValue实例作为可写类型；mutable构造与writer不在
领域公共barrel导出。release幂等但不得提前调用；对released permit改变phase是明确错误。
LatestValue关闭后拒绝watch/publish并使waiter结束，已有listener错误不能阻断其余订阅的
实际通知/清理；原cause/stack留owner诊断，不放Freezed或凭message分类。

Operations公共只读形状沿共享合同§5。装配面固定：

```dart
abstract interface class OperationRecorder {
  Operations get observations;
  OperationWriter<T> begin<T>({required String target, DraftStamp? draft});
  void observe(ObservationStamp stamp);
  void seal();
}
abstract interface class OperationWriter<T> {
  OperationTicket<T> get ticket;
  void accepted(T value, CommitReceipt receipt);
  void acknowledged(T value);
  void identityObserved();
  void effective();
  void durable();
  void rejected(StudioFailure error);
  void unknownOutcome(StudioFailure error);
  void synchronizationFailed(StudioFailure error, {T? value, CommitReceipt? receipt});
  void acknowledgedSynchronizationFailed(StudioFailure error, {T? value});
}
```

这只是原MutationBoard/handle的能力隔离，不是第二operation registry。accepted只登记同id
的receipt/value；普通targets由observe覆盖，requiresIdentityObservation则必须有领域的
预登记predicate调用identityObserved，不能因任意资源revision增长调用。acknowledged与
receipt互斥，不自动赋予observed/effective/durable。synchronizationFailed必须已有真实
receipt，或参数给出同operation的真实receipt；value可在尚未取得完整T时为None。
没有receipt的失败不能用此方法冒充已知受理。
没有可用Dart receipt但native成功已可靠确认时，调用acknowledgedSynchronizationFailed；
它产生共享合同的acknowledgedSyncFailed，保留已知成功，不生成receipt、不自动重发。
所有mutation port的typed CommandDispatchFailure与native outcome按[失败合同](./v4-failure-contract.md)
处理，不能把任意Future异常当作已知拒绝。writer在完成必要处理后才结算ticket，不先完成
成功Future再试图将其改成失败。

同步writer方法不得接受另一个OperationId或当前选择；旧完成只影响它自己的ticket。
重复相同证据幂等，矛盾证据明确失败并保原记录；closed/失败不能吞成成功。ticket.result
只完成一次，后续真实证据仅更新该operation的只读state，不回溯改写已经交付的结果。
UnknownOutcome不因VM销毁淘汰，也不自动重新dispatch；其领域冻结payload/附件归属继续保留。
record保留策略维持原maxRetained=128/maxObservedResources=1024，未解决或有观察者记录受保护。
acknowledged操作同样可以在取得真实领域证据后调用identityObserved/effective/durable；
不能要求D1伪造CommitReceipt才能记录这些事实。证据与原writer目标绑定且不自动赋真，
输入提交的具体证明/延后语义见[Conversation合同](./v4-conversation-contract.md)§5。

## 3. ConfigurationRepository与ConfigurationPort

```text
ConfigurationRepository
  state:ReadonlyLatestValue<ConfigurationState>
  profiles:ReadonlyLatestValue<ProfilesState>
  loadAccount(String accountId)->Future<AccountConfiguration>
  loadInstructions()->Future<StudioInstructionsSettings>
  loadSkillsSettings()->Future<StudioSkillsSettings>
  loadGeneralSettings()->Future<StudioGeneralSettings>
  loadWebSearchSettings()->Future<WebSearchConfiguration>
  loadDeepSeekSettings()->Future<DeepSeekSearchConfiguration>
  loadProfile(String profileId)->Future<AgentProfileSnapshot>
  saveAccount(AccountEdit intent)->OperationTicket<Unit>
  setDefaultAccount(String accountId)->OperationTicket<Unit>
  removeAccount(String accountId,{String? replacementAccountId})->OperationTicket<Unit>
  removeAccountModel(String accountId,String modelId)->OperationTicket<Unit>
  applyField(SettingsFieldUpdate update)->OperationTicket<Unit>
  applyFields(List<SettingsFieldUpdate> updates)->SettingsWriteBatch
  setPermissionMode(PermissionMode mode)->OperationTicket<Unit>
  saveProfile(AgentProfileEdit profile)->OperationTicket<Unit>
  setSystemProfileEnabled(String profileId,bool enabled)->OperationTicket<Unit>
  reload()->OperationTicket<Unit>
  seal()/close()/retryCleanup()
```

applyFields是有序的一组原字段命令，不宣称跨字段原子事务；完整batch返回值在§3.3定义，
不创造父operation/receipt，也不抛错丢已成功步骤。普通观察/read不调用reload；
reload是原显式磁盘导入写入，Profiles外部文件修改也通过它采用，不伪造独立profiles reload。

load*只打开本域当前canonical版本的typed读取scope，Repository登记/组装并发布加载结果。
有旧值时保其原stamp；源推进后迟到旧read不标为新值。调用方拿完整值，不看到无依据默认字段。
ModelCatalog、AccountTemplates、effective search policy不归本Repository writer。

ConfigurationPort（adapter专用）：

```text
openConfiguration()->Future<FeedConnection<ConfigurationFrame>>
openAgentProfiles()->Future<FeedConnection<AgentProfilesFrame>>
openConfigurationRead(ConfigurationReadRef ref)->Future<ConfigurationReadConnection>
openProfilesRead(AgentProfilesReadRef ref)->Future<AgentProfilesReadConnection>
saveAccount(UpdateAccountRequest request)->Future<ConfigurationCommandReply>
setDefaultAccount(SetDefaultAccountRequest request)->Future<ConfigurationCommandReply>
removeAccount(RemoveAccountRequest request)->Future<ConfigurationCommandReply>
removeAccountModel(RemoveAccountModelRequest request)->Future<ConfigurationCommandReply>
applyField(UpdateSettingsFieldRequest request)->Future<ConfigurationCommandReply>
setPermission(UpdatePermissionSettingsRequest request)->Future<ConfigurationCommandReply>
saveProfile(SaveProfileRequest request)->Future<ConfigurationCommandReply>
setSystemProfileEnabled(SetSystemProfileEnabledRequest request)->Future<ConfigurationCommandReply>
reload({required int expectedRevision})->Future<ConfigurationReloadResult>
```

`ConfigurationCommandReply {receipt:CommitReceipt,configuration:ConfigurationReadRef,
models:ModelCatalogReadRef}`；这是两个各自版本的canonical读取引用，不再携带旧聚合
SettingsStateSnapshot，也不由adapter拆旧Dart聚合快照。Mutation成功对应的推送与reply
来源进入各自Repository归并，旧reply不覆盖新事实。native必须在返回前建立这些读取定位。
`ConfigurationReloadResult`同样含两个ref但**无伪造receipt**；原reload没有operation receipt。

### 3.1 编辑intent与命令字段

`AccountEdit`保原accountId、create/edit与原模板身份，明确逐字段用户意图。完整字段：

```text
AccountEdit {
 accountId:String,create:bool,
 templateId:FieldEdit<String?>,protocol:FieldEdit<String>,name:FieldEdit<String>,
 baseUrl:FieldEdit<String>,secret:AccountSecretUpdate,pricingEnabled:FieldEdit<bool>,
 customModels:List<CustomModelChange>,connections:List<ModelConnectionChange>,
 autoCompactLimits:List<ModelLimitChange>
}
FieldEdit<T> = keep | set{value:T}
CustomModelChange = upsert{originalModelId:String?,value:AccountModelUpdate} | remove{modelId:String}
ModelConnectionChange {modelId:String,connectionMode:String}
ModelLimitChange {modelId:String,overrideLimit:int?}
```

FieldEdit只是typed immutable命令值，不是万能reducer。原AccountModelUpdate完整字段为
model_id/display_name/wire_api:String、context_window/max_output_tokens:Option<u64>；
AccountSecretUpdate三态沿产品合同。limit=null表示移除该覆盖，非空必须正整数tokens。
未知模板不替换成默认模板；create初始必需字段必须明确set，协议不从URL/名称推断。

同account lane内，从**最新完整canonical AccountConfiguration**应用这些意图构造原
AccountSettingsUpdate。保留未改变的custom model/connection/limit成员，包括当前在线目录
未显示的成员。已知StaleRevision最多两次恢复后重新构造，不重发UnknownOutcome。
account identity创建后不能重命名；custom model改ID是明确移除original并添加新ID，不按
displayName认领。创建和编辑UI的dirty字段必须映成相应intent，不能把旧整页snapshot回写。

`AgentProfileEdit`完整字段：profileId/displayName/description/whenToUse/systemInstructions/
accountId/modelId:String、effort:String?、enabled:bool、workspaceMode:AgentWorkspaceMode。
SaveProfileRequest另含operationId/expectedSettingsRevision；系统启停请求含operationId/
expectedSettingsRevision/profileId/enabled。沿原ID 1..64字节ASCII小写/数字/-/_及系统ID保护，
不将当前unresolved route静默换默认route；后端校验错误如实返回。

其余Request字段/SettingsFieldUpdate所有变体保持`studio/settings_update.rs`当前完整定义。
唯一明确变更是RemoveAccountModelRequest增加`operation_id:String`，由Dart原操作owner提供，
替代Rust自行构造固定`remove-account-model:<account>:<model>`。仓库内Rust/FRB/server/demo/
fake/tests全部一起迁移，禁止兼容重载；不会因此宣称后端已新增外部ID持久去重机制。

### 3.2 Settings字段全集与边界

InstructionBaseOverride/Developer/User、ProjectDocMaxBytes/FallbackFilenames；SkillsEnabled/
AutoLearn/SystemEnabled/ProjectDir/UserDir/ExternalDirs/Disabled/AutoLearnMinToolCalls；
McpServerEnabled/Transport/Endpoint；GeneralFollowActiveTurn/CompactTimeline/SidebarWidth/
PinnedThreadIds/PinnedProjectIds；WebSearchMode/ContextSize/AllowedDomains/Country/Region/City/
Timezone；DeepSeekWebSearchEnabled/DeepSeekWebFetchEnabled；ModeModel/ModeReasoningEffort/
RoleModel/RoleReasoningEffort全部保留原typed payload，不增加任意字符串key的patch入口。

sidebar width仍None或300..440，pins各最多64，原列表trim/空项归一化仅在原定义字段发生；
mode/role/effort保原解析与权限约束。Profile保存及reload同样受Config closing封准入，
不能绕过它。UI不把后端未知标签默认为local/允许/健康；协议不能解码时typed Protocol。

### 3.3 多字段保存：只编排真实子操作

```text
SettingsWriteBatch                  // runtime owner借用，不是Freezed
  operations:List<OperationObservation>
  result:Future<SettingsBatchResult>
SettingsBatchResult {steps:List<SettingsFieldResult>}
SettingsFieldResult =
  finished {index:int,operationId:OperationId,result:CommandResult<Unit>}
  | notStarted {index:int,operationId:OperationId,error:StudioFailure}
```

Repository首await前复制全部typed意图、分配每一步自己的OperationId并取得所需permits；
无法完整准入时回收尚未dispatch的预留并同步拒绝，不部分发命令。batch在同一Settings写
lane内按原顺序执行，每步从最新canonical构造/CAS；任一步rejected/unknown/syncFailed后
停止后续步骤，未dispatch项明确notStarted并结算自己的本地登记，不伪装native取消成功。
每步有真实独立ticket和receipt；没有父operation、原子回滚或fake aggregate receipt。
result包含所有步骤的最终结果/未开始原因，正常业务失败不从该Future丢弃已有成功信息。
batch与已排队步骤的实际工作归ConfigurationRepository，VM只借观察；seal后未dispatch
步骤明确未受理，原在途结果/未知payload继续收束，不能靠Widget/Provider寿命维持。
空updates合法返回空batch，无native调用/新operation，不把它当有保存动作完成。

## 4. Models / Modes

ModelsRepository公开只读state与templates；`loadAccount(String)->Future<AccountCatalogEntry>`、
`loadTemplates()->Future<AccountCatalogSnapshot>`、`loadModel(String accountId,String modelId)
->Future<ModelDescriptor>`。不能重算context/effort/input能力，不提供保存配置的别名方法。
其ModelsPort只含openModelCatalog/openAccountTemplates及各自openRead；具体返回都是本域
FeedConnection<具体Frame>/ReadConnection。online model refresh若原产品没有独立公开命令，
不凭本次分域新增“刷新所有模型”的隐含网络操作。

ModesRepository：

```text
state:ReadonlyLatestValue<ModesState>
readDefinition(String modeId)->Future<ModeDefinitionSnapshot>
validate(String rawJson)->Future<ModeValidationResult>
schema()->Future<String>
preview(WorkflowPreviewRequest request)->Future<WorkflowPreviewSnapshot>
save(ModeDocument document,{required int expectedRevision})->OperationTicket<ModeDefinitionResult>
delete(String modeId,{required int expectedRevision})->OperationTicket<ModeDefinitionResult>
reload({required int expectedRevision})->OperationTicket<ModeDefinitionResult>
seal()/close()/retryCleanup()
```

ModesPort对应openModeCatalog/openModeRead、readDefinition/validate/schema/preview，以及
save/delete/reload增加required OperationId。`ModeDefinitionResult {catalog:ModeCatalogReadRef,
definition:ModeDefinitionSnapshot?}`，native命令reply再含真实CommitReceipt，保留原definition
可空语义。不在SDK保ModeEditorOwner/undo/dirty/rawJSON；它们唯一归U1真VM。

ModeDocument、Definition、EditorLayout、WorkflowDefinition/State/Transition、validation issue
和preview完整字段沿原typed定义，不用旧宽容fromJson作为业务验证。raw JSON是明确authoring
输入；Rust validator拒绝所有层未知字段、原文及canonical256KiB、图约束和坐标约束不放宽。

## 5. AccountUsage与Statistics

```text
AccountUsageRepository
  state:ReadonlyLatestValue<AccountUsageState>
  load(String accountId)->Future<AccountUsageRecord>
  check(String accountId)->OperationTicket<AccountUsageRecord>
  setVisibleAccounts(Set<String> accountIds)->void
  seal()/close()/retryCleanup()
AccountUsagePort
  openAccountUsage()->Future<FeedConnection<AccountUsageFrame>>
  openUsageRead(AccountUsageReadRef ref)->Future<AccountUsageReadConnection>
  check(String accountId,{required int expectedUsageQueryRevision})->Future<AccountUsageCheckResult>
AccountUsageCheckResult {reference:AccountUsageReadRef,accountId:String,usageQueryRevision:int}
```

check没有原生receipt，Repository在dispatch前冻结该账号真实usageQueryRevision，native
在联网准入前校验相同revision；不匹配StaleRevision，不使用同ID新账号/新凭据替换原目标。
必要身份尚未加载时先由显式read需求取得，不把缺值按0发命令。真实返回后读取/归并同账号同query revision的canonical记录才结束
acknowledged；旧账号删除后同ID新建不能接收旧结果。可见集合只产生一次明确检查需求，
本轮失败也算已尝试；隐藏停止新需求但不取消已受理查询，不因rebuild/default/catalog无关
变化重查全体。不同(accountId,usageQueryRevision)不等彼此网络；同identity复用真实在途。
Native已确认check成功但其返回引用读取失败时是acknowledgedSyncFailed，不能作为再次
调用供应商查询的理由；纯观察恢复不重复网络检查。

StatisticsRepository提供三类独立只读观察及typed页：summaries、history、costs(rootThreadId)；
open/read能力只由StatisticsPort三个具体feed/scope提供。过滤、展开、页需求归Statistics VM，
原聚合指标仍由Rust算，不能为方便筛选在Dart重算另一套费用或性能事实。
全部状态、页方法及筛选key的精确字段待产品类型册/VM表补齐，不用dynamic泛型查询逃过合同。

## 6. D3资源动作（无native receipt者不伪造）

下列Repository都有独立只读state、本域typed open/read port及seal/close/retryCleanup；
所有列出的动作返回OperationTicket<具体T>，T如下。port返回真实Future<同T或本域ReadRef>，
无native receipt；异步响应是已知成功后再归并，否则区分known rejection/unknown/sync失败。

| Repository | 动作 | T与语义 |
| --- | --- | --- |
| RecoveryRepository | retry() | RecoveryReadRef；原审计重试，不是普通read |
| RecoveryRepository | cleanupWorktree(ownerKind,ownerThreadId,expectedLeaseRevision) | Unit；原lease CAS/受控清理，不扩大删用户数据授权 |
| PersistenceRepository | retry() | PersistenceReadRef |
| PersistenceRepository | retryThreadHistory(threadId,faultGeneration) / resumeThreadHistory(threadId,faultGeneration) | PersistenceQueueSnapshot；原raw响应无发布revision，不写进versioned queue mirror |
| McpRepository | resetServer(serverId) / resetAll() | McpReadRef；配置修改仍走ConfigurationRepository字段命令 |
| LspRepository | probe(projectId) / repair(projectId,serverId) / resetServer(projectId,serverId) / resetWorkspace(projectId) | LspReadRef；仍归并全局真实LSP来源 |
| SkillsRepository | discover(projectId) | SkillsReadRef；显式发现，不在watch/build扫描 |
| SkillsRepository | search(projectId,query,{limit=50}) | **只读Future<SkillSearchResult>**，不是OperationTicket；保project/catalog revision/matches/truncated |
| RemoteRepository | save(SshServerProfile,SshPasswordUpdate) | SshServerRuntimeEntry |
| RemoteRepository | delete(alias) | Unit |
| RemoteRepository | authenticate(alias,password,{required rememberPassword}) | SshConnectionSnapshot |
| RemoteRepository | test(alias) / reconnect(alias) | SshConnectionSnapshot |
| RemoteRepository | openDirectory(alias,{String? path}) | **只读Future<RemoteDirectoryQuery>**，见下方有界读取，不生成receipt |

Remote list原实现会reload SSH配置/hydrate lease，因此新方法名为`reloadServers()`显式action
（T=List<SshServerRuntimeEntry>），不能伪称无副作用read/getter；只读当前已加载state不调用它。
SSH profile字段alias/hostName/port/username/identityFile；password Preserve/Replace/Clear及
rememberPassword保持原秘密语义，return不含秘密。RemoteDirectoryEntry保name/path/
isDirectory/isSymlink四字段，不能沿旧Dart只两字段的遗漏。远程打开项目归Workspace能力，
不让Remote再写一份当前selection。
managed=true才是原anywork管理条目，允许原有编辑/删除；managed=false保持只读。
不从name/host推断managed，不把这个布尔值反向解释成“托管所以只读”。

`RemoteDirectoryQuery`为Repository监督的runtime查询owner，公开只读
`state:ReadonlyLatestValue<RemoteDirectoryState>`、`loadMore()->Future<void>`、
`requestClose()->void`、`close()/retryCleanup()->Future<CloseReport>`。
`RemoteDirectoryState {alias:String,path:String,parent:String?,entries:List<RemoteDirectoryEntry>,
total:int,nextOffset:int?,loading:bool,error:StudioFailure?}`；entry完整四字段如上。
初始取得完整header后返回query；默认首32项，后续显式loadMore有界前进。旧目录query
只结算原alias/path/attempt，不写新导航目标，关闭真join，不能只取消UI等待。

RemotePort对应`openDirectory(alias,{path})->Future<RemoteDirectoryReadConnection>`，其
typed scope提供header/path/parent/total、entries(offset,limit)、text及close/retryClose，
String仍按ReadText、页/块仍256KiB；内部使用原helper的typed目录结果，不修改SSH codec或
为本任务新增远端数据库。scope是这次查询取得的不可变结果，不伪造全局目录业务revision。
也不把一次性目录读取冒充服务端推送。它与其它详情共用全局64在途调用及readModel预算。

## 7. 仍未闭合

- [x] D0错误详情、dispatch证据、无receipt成功后同步失败及batch结果，见失败合同/§3.3。
- [ ] D1完整接缝；Session/草稿/冻结与真实durable证据已见[Conversation合同](./v4-conversation-contract.md)，其末尾未闭合项仍待定稿。
- [ ] D3全部接口；显式启动/退出与组合根顺序见[应用生命周期](./v4-application-lifecycle-contract.md)，Workspace/Updates动作全集仍待补。
- [ ] 所有State及产品Read DTO逐字段类型册、公共新文件/导出表、HTTP/FRB名字。
- [ ] 全VM对动作的具体消费/dirty/unknown/retry与最终验证矩阵。

本文件已确定的接口可供后续合同引用，但有未闭合条目时仍不派编码。
