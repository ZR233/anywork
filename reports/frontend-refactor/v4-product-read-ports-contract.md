# v4 产品读取port与Repository只读状态

本册将[产品wire](./v4-product-wire-contract.md)与[字段册](./v4-product-type-catalog.md)
落实为D0/D2/D3/A/R之间的固定读取能力。下面的泛型仅是不可变值容器，不是通用业务
payload、消息总线或第二可写store；实际每个资源都有具体header/ReadConnection/Repository。
Flutter VM不接触这些ports或native句柄，只借领域state并发本域可见读取需求。

## 1. 物化身份与未知值

D0 resources定义一次：

```text
ResourceSyncPhase = idle | connecting | ready | reconnecting | failed | closed
ResourceSyncState {phase:ResourceSyncPhase,error:StudioFailure?,retryExhausted:bool}
ProductProjection<H> {stamp:ProductProjectionStamp?,header:H?,sync:ResourceSyncState}
Materialized<T,R> {origin:ProductReadOrigin,reference:R,value:T}
ReadValue<T,R> = unloaded{origin:ProductReadOrigin,reference:R}
 | loading{origin:ProductReadOrigin,reference:R,previous:Materialized<T,R>?}
 | ready{current:Materialized<T,R>}
 | failed{origin:ProductReadOrigin,reference:R,error:StudioFailure,previous:Materialized<T,R>?}
CollectionContinuation = unknown | offset{value:int} | cursor{value:String} | end
CollectionWindow<T> {
 origin:ProductReadOrigin,reference:ProductCollectionRef,entries:List<ProductEntityRef>,
 rows:Map<int,ReadValue<T,ProductEntityRef>>,continuation:CollectionContinuation,
 complete:bool,loading:bool,error:StudioFailure?
}
CollectionMirror<T> = unavailable{lastKnown:CollectionWindow<T>?}
 | current{window:CollectionWindow<T>}
```

全部是Freezed值；rows的int是entry不是截断业务ID。entries按原scope顺序，rows只记本次
实际物化/在读的成员，未加载成员不能拿默认T填充。ref变更后previous明确带旧ref，不能
把旧值标成新ref ready。已知空集合是current(window.reference.total=0,window.complete=true)，不是unavailable。
无来源value时可以显示lastKnown，但不能用它作新的CAS/动作准入。已知删除/已知空不会
继续把被删成员留在当前entries。历史显示所需旧immutable对象共享引用，不再复制一份正文库。

header/source metadata/读取错误/transport sync是不同维度：ResourceSyncState.ready只说明
本feed基线已正确归并，不把来源Failed变健康。sourceStatus字段采用
`ReadValue<ProductSourceStatus,ProductSourceStatusRef>?`；ProductSourceStatus为产品合同
完整八态metadata的物化值（ReadText还原String），没有业务value字段。header已公布的
retryable/时间等保持原revision，读取错误原typed诊断另列，不从文案推状态。

rows的key必须等于对应entry及ReadValue current/previous的reference.entry；当前window的
row origin必须等于window.origin。owner替换时不能把旧window的同数字entry拷进新window，
原窗口只能作为带原origin的lastKnown。same ref不同origin不是同一可用值，旧query不得
通过读取port“当前owner”补origin。所有异步发布都先核origin再核ref及本次query generation。
ReadValue的跨origin previous只能作last-known展示，不能满足新origin读取/动作准入，
也不能仅因ref数字相同就提升为新origin的ready/current。

字段外层`?`表示尚无可读来源ref；ReadValue内的T可再nullable（例如String?或SessionCost?），
两层含义不能合并。初始化不制造空revision、空账号、零成本或无故健康状态。

## 2. 每个Repository的完整只读state字段

表中P(H)表示`projection:ProductProjection<H>`；S表示上节完整sourceStatus字段。
V(T,R)表示`ReadValue<T,R>?`。这是有限类型展开记法，生成输入为各具名Freezed State，
不使用dynamic Map替代。每个field独立服务本域读取，不重新聚合旧SettingsStateSnapshot。

| State | 除P之外的全部字段 |
| --- | --- |
| ConfigurationState；P(ConfigurationHeader) | S；accounts:CollectionMirror<AccountConfiguration>；defaultAccountId:V(String?,ConfigurationReadRef)；modeRoutes:V(List<ModeModelRoute>,ConfigurationReadRef)；roles:V(List<RoleModelRoute>,ConfigurationReadRef)；permissionMode:V(String,ConfigurationReadRef)；instructions:V(InstructionsSettings,ConfigurationReadRef)；skillsSettings:V(SkillsSettings,ConfigurationReadRef)；mcpConfigurations:V(List<McpConfiguration>,ConfigurationReadRef)；general:V(GeneralSettings,ConfigurationReadRef)；webSearch:V(WebSearchConfiguration,ConfigurationReadRef)；deepSeekSearch:V(DeepSeekSearchConfiguration,ConfigurationReadRef) |
| ProfilesState；P(AgentProfilesHeader) | S；profiles:CollectionMirror<AgentProfileSnapshot>；diagnostics:V(List<ProfileDiagnostic>,AgentProfilesReadRef) |
| ModelsState；P(ModelCatalogHeader) | S；accounts:CollectionMirror<AccountCatalogEntry>；webSearch:V(EffectiveWebSearch,ModelCatalogReadRef)；deepSeekSearch:V(EffectiveDeepSeekSearch,ModelCatalogReadRef) |
| TemplatesState；P(AccountTemplatesHeader) | templates:CollectionMirror<AccountTemplate>；catalogs:V(Map<String,NamedModelCatalog>,AccountTemplatesReadRef)；catalogRevision:V(String,AccountTemplatesReadRef) |
| ModesState；P(ModeCatalogHeader) | modes:CollectionMirror<ThreadModeDescriptor> |
| AccountUsageState；P(AccountUsageHeader) | S；usages:CollectionMirror<AccountUsageRecord>；configFingerprint:V(String,AccountUsageReadRef) |
| PerformanceSummariesState；P(PerformanceSummariesHeader) | summaries:CollectionMirror<PerformanceSummary> |
| PerformanceHistoryState；P(PerformanceHistoryHeader) | samples:CollectionMirror<PerformanceSample> |
| SessionCostsState；P(SessionCostsHeader) | rootThreadId:String；cost:V(SessionCost?,SessionCostsReadRef) |
| ProjectDirectoryState；P(ProjectDirectoryHeader) | S；projects:CollectionMirror<ProjectRecord> |
| ThreadDirectoryState；P(ThreadDirectoryHeader) | scope:ThreadDirectoryScope；S；threads:CollectionMirror<WorkspaceThreadRecord> |
| AgentDirectoryState；P(AgentDirectoryHeader) | S；agents:CollectionMirror<AgentDirectoryEntry> |
| RecoveryState；P(RecoveryHeader) | S；issues:CollectionMirror<RecoveryIssue> |
| McpState；P(McpHeader) | S；servers:CollectionMirror<McpServer>；activeServerIds:V(List<String>,McpReadRef)；desiredConfigFingerprint:V(String,McpReadRef)；appliedConfigFingerprint:V(String,McpReadRef) |
| LspState；P(LspHeader) | S；servers:CollectionMirror<LspServer>；activeServerIds:V(List<String>,LspReadRef) |
| SkillsState；P(SkillsHeader) | projectId:String；S；skills:CollectionMirror<SkillSummary>；warnings:V(List<String>,SkillsReadRef)；projectDirectory:V(String,SkillsReadRef)；configFingerprint:V(String,SkillsReadRef) |
| PersistenceState；P(PersistenceHeader) | value:V(PersistenceValue,PersistenceReadRef) |
| PersistenceQueueState；P(PersistenceQueueHeader) | threads:CollectionMirror<ThreadPersistenceSnapshot>；lastError:V(String?,PersistenceQueueReadRef) |
| UpdatesState；P(UpdatesHeader) | value:V(UpdatesValue,UpdatesReadRef) |

Product header中已有catalog revision、complete、下载计数及queue标量不再在state另持第二份
可写字段；固定状态中的加载结果只由对应Repository写。低频配置有多个可见field需求时
复用同一个已pin scope，逐字段读取；未显示字段不因无关header更新而自动读大正文。
高频统计和Updates必须复用字段册稳定identity/summary refs，只刷新受影响的数值，不用
整页read替代真正分频。

需要来源身份但尚未物化的动作显式等待对应本域读取，再按原冻结意图构造；不能从空值
猜默认。当前选择/编辑dirty/operation呈现不放这些canonical State，分别归Workspace/
VM/operations。例如Settings提交失败不清ConfigurationState的last-known内容。

## 3. 具体产品feed与read打开方法

每个表项固定三个名字：`open<Resource>()`返回`Future<FeedConnection<<Resource>Frame>>`；
`open<Resource>Read(<Resource>ReadRef reference,{required ProductReadOrigin origin})`返回
`Future<<Resource>ReadConnection>`；有ObservedHeader者另实现
`openSourceStatus(ProductSourceStatusRef,{required ProductReadOrigin origin})->Future<ProductSourceStatusReadConnection>`。
scope参数只在openFeed携带；read ref已绑定原resource/scope/owner，不能借同ID新owner。
独立command reply读取目标是`<Resource>ReadTarget {origin,reference}`；调用方不得靠最新
feed stamp补齐迟到reply的origin。所有稳定identity/Updates子scope的open也必带同origin。
具体展开清单如下：

| Port | Resource | open参数 |
| --- | --- | --- |
| WorkspacePort | ProjectDirectory | 无 |
| WorkspacePort | ThreadDirectory | ThreadDirectoryScope scope |
| WorkspacePort | AgentDirectory | 无 |
| ConfigurationPort | Configuration | 无 |
| ConfigurationPort | AgentProfiles | 无 |
| ModelsPort | ModelCatalog | 无 |
| ModelsPort | AccountTemplates | 无 |
| ModesPort | ModeCatalog | 无 |
| AccountUsagePort | AccountUsage | 无 |
| StatisticsPort | PerformanceSummaries | 无 |
| StatisticsPort | PerformanceHistory | 无 |
| StatisticsPort | SessionCosts | String rootThreadId |
| RecoveryPort | Recovery | 无 |
| McpPort | Mcp | 无 |
| LspPort | Lsp | 无 |
| SkillsPort | Skills | String projectId |
| PersistencePort | Persistence | 无 |
| PersistencePort | PersistenceQueue | 无 |
| UpdatesPort | Updates | 无 |

上述是具体接口名的有限展开，不生成`open(ProductResource,dynamic scope)`公共方法。
原domain ports中的openProfilesRead/openUsageRead等简写统一替换为本表名字，不保双出口。
每个read连接提供以下完整共同能力（对应native snake_case），只查询，不创建OperationId：

```text
header()->Future<<Resource>ReadHeader>
text(int fieldId,{int offset=0,int maxBytes=65536})->Future<TextChunk>
requestClose()->void
close()->Future<FeedCloseReport>
retryClose()->Future<FeedCloseReport>
```

所有有顶层collection的连接提供：
`entries({int offset=0,int limit=32})->Future<<Resource>EntryPage>`；
`entity(ProductEntityRef reference)->Future<<Resource>EntityRead>`。
ThreadDirectory的entries**唯一例外**是`entries({String? cursor,int limit=32})`专用keyset页。
EntityRead是`{reference:ProductEntityRef,value:<PrimaryElement>Read}`，PrimaryElement按下表。
scalar资源无entries/entity，不能返回假空集合代替未支持。

| Resource | PrimaryElement／顶层collection |
| --- | --- |
| ProjectDirectory / ThreadDirectory / AgentDirectory | ProjectRecord / WorkspaceThreadRecord / AgentDirectoryEntry |
| Configuration / ModelCatalog / AccountTemplates | AccountConfiguration / AccountCatalogEntry / AccountTemplate |
| AgentProfiles / ModeCatalog / AccountUsage | AgentProfileSnapshot / ThreadModeDescriptor / AccountUsageRecord |
| PerformanceSummaries / PerformanceHistory | PerformanceSummary / PerformanceSample |
| Recovery / Mcp / Lsp / Skills / PersistenceQueue | RecoveryIssue / McpServer / LspServer / SkillSummary / ThreadPersistenceSnapshot |
| SessionCosts / Persistence / Updates | 无顶层collection，使用typed scalar header及具名嵌套列表 |

每个<Resource>ReadHeader是字段册中该资源完整根Read结构，不是feed小header；Observed
metadata不在其中。Collection根结构的列表字段仍有TypedListRef，它与entries索引指向
同一个原根字段，不是第二份列表源；Nested pages返回对应具名类型，不能从JSON动态解析。
Recovery的ReadHeader仅`{issues:TypedListRef}`；Directory分别`{projects/threads/agents:TypedListRef}`；
ThreadDirectory另含`next_cursor:Option<ReadText>,has_more:bool`；Performance分别
`{summaries:TypedListRef}`、`{samples:TypedListRef}`。SessionCosts根为`{cost:Option<SessionCostRead>}`。
Persistence/Updates/Configuration等其余根Read严格按字段册固定结构，不省略未在feed中的字段。

同root scope的entity只接受该版本collection中登记的ref（entry+revision都相同）；不是按entry
查当前值。不存在成员NotFound、期望旧版不可得Superseded、跨scope/类型引用InvalidArgument，
关闭Cancelled优先。页返回的scope与collection身份核验先于canonical归并。

## 4. 嵌套页、定位与稳定身份

嵌套列表方法全量采用产品wire§4.3的表，并统一为
`method(int listId,{int offset=0,int limit=32})->Future<<Element>ReadPage>`。
元素与页面类型是具体静态类型，不以Object/dynamic、任意字符串method或runtime JSON-path
resolver实现该规则。重复元素族可共用同一具名页方法，例如strings，但list_id必须在当前
scope的封闭字段表中登记为该族；wrong type/越界明确失败。

为按明确业务ID加载而不扫描/物化无关全页，下列资源连接额外提供固定typed lookup，返回
`Future<ProductEntityRef?>`，只查询本scope成员，不跨当前query/window扩大读取范围：

- Configuration / ModelCatalog / AccountUsage：lookupAccount(String accountId)。
- AccountTemplates：lookupTemplate(String templateId)。
- AgentProfiles：lookupProfile(String profileId)；ModeCatalog：lookupMode(ThreadModeId mode)。
- ProjectDirectory：lookupProject(String projectId)；ThreadDirectory：lookupThread(String threadId)。
- AgentDirectory：lookupAgent(String agentId)；Recovery：lookupIssue(String issueId)。
- Mcp / Lsp：lookupServer(String serverId)；Skills：lookupSkill(String name)。
- PersistenceQueue：lookupThread(String threadId)。
- PerformanceSummaries：lookupSummary(String accountId,String modelId)。

lookup不到为None且不伪造entity；当前scope已closing仍Cancelled优先。Skills只按原Catalog
解析后的有效name定位，不新建第二套来源优先级：原local catalog与provider registry都
以ASCII lowercase name选唯一winner，lookup复用原eq_ignore_ascii_case，保原name文本，
不新增trim/Unicode归一化或大小写敏感规则。PerformanceHistory不公开假复合ID查找，
其内部entry来自真实thread_id/call_id；UI用已取得的ProductEntityRef即可。

稳定identity scope（Summary/Effort/Sample）与Updates Summary/Operation/Error/Details的
open方法、header字段采用产品类型册/产品wire已列的唯一具名方法，放对应StatisticsPort/
UpdatesPort；具有本册共同text/close/retry能力，不挂通用`read(kind:String)`。这些scope
计入同一每资源8scope、全runtime64call/readModel预算，不能每个子类型各建一个8/64池。

具体子scope签名（origin来自原父feed或真实command ReadTarget，不从最新feed回填）：

```text
StatisticsPort
 openSummaryIdentity(PerformanceSummaryIdentityRef reference,{required ProductReadOrigin origin})
   ->Future<PerformanceSummaryIdentityReadConnection>
 openEffortIdentity(PerformanceEffortIdentityRef reference,{required ProductReadOrigin origin})
   ->Future<PerformanceEffortIdentityReadConnection>
 openSampleIdentity(PerformanceSampleIdentityRef reference,{required ProductReadOrigin origin})
   ->Future<PerformanceSampleIdentityReadConnection>
UpdatesPort
 openSummary(UpdateSummaryReadRef reference,{required ProductReadOrigin origin})->Future<UpdateSummaryReadConnection>
 openOperation(UpdateOperationReadRef reference,{required ProductReadOrigin origin})->Future<UpdateOperationReadConnection>
 openError(UpdateErrorReadRef reference,{required ProductReadOrigin origin})->Future<UpdateErrorReadConnection>
 openDetails(UpdateDetailsReadRef reference,{required ProductReadOrigin origin})->Future<UpdateDetailsReadConnection>
```

## 5. 读取取消与晚到结果

Repository登记原scopeRef/selection或query generation/实际Future后才await；异步读完核
完整目标和目标ref。源推进不破坏已pin读取，但旧read只能供原version/last-known，不
覆盖新current值。没有证据说明scope已经取消/join时不能从容器删除以回收容量。

同scope的独立字段读取可以并行到全局call预算，不让大文本阻塞ACK/close。关闭Repository
先封读取需求，再requestClose所有已open与待返回open，等真实调用/stream/producer结束，
失败沿CleanupRecovery保全部诊断。deadline仅结束本次等待，不伪造原任务已结束。

## 6. 仍需闭合

- [ ] 全Repository业务/本地选择动作与对应VM使用方法；本册只固定canonical state及read ports。
- [x] Workspace按ID读取使用ThreadDirectoryScope.thread单实体scope，见Workspace合同，不把当前window缺失当实体不存在。
- [x] Skills有效name唯一性与查询规则，已核pl-tool skill/catalog.rs及provider/mod.rs。
- [ ] 所有页/ReadHeader跨源字段核对及最终公共新文件表。
- [ ] HTTP/SSE/ACK/read/close映射，完整Turn历史不能被active/recent Execution覆盖。

原SourceStatus与字段册未覆盖的具体接口不得由executor自行补设计。全手写完成前不编译、
测试、生成或GUI；当前仍不构成全局编码放行。
