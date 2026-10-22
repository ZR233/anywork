# v4 产品集合、配置分域与有界读取合同

本文件是root的产品观察接口决定，补充[共享合同](./v4-shared-contract.md)与
[Thread协议](./v4-thread-wire-contract.md)。基线、当前源身份由
[逐文件清单](./v4-source-ownership.json)绑定。不是旧ProductTopicFrame再包一层Repository。
领域命令/全部port的独立签名册仍需补齐；本文件本身不释放整包编码。

## 1. 产品资源与唯一writer

| 具体产品观察 | scope参数 | Rust权威 | Dart唯一归并者 |
| --- | --- | --- | --- |
| ProjectDirectory | 无 | 原项目目录owner | WorkspaceRepository |
| ThreadDirectory | DirectoryQuery | 原目录/查询owner | WorkspaceRepository的对应query window |
| AgentDirectory | 无 | 原Agent directory | WorkspaceRepository |
| Configuration | 无 | ConfigRuntime desired配置与配置事实 | ConfigurationRepository |
| ModelCatalog | 无 | ConfigRuntime catalog/模型策略来源 | ModelsRepository |
| AccountTemplates | 无 | 原内置AccountCatalog | ModelsRepository；只读版本化目录 |
| AgentProfiles | 无 | 原ProfilesResource | ConfigurationRepository的profiles能力 |
| ModeCatalog | 无 | 原ThreadModeManager | ModesRepository |
| AccountUsage | 无 | 原AccountUsageRuntime | AccountUsageRepository |
| PerformanceSummaries | 无 | 原ModelPerformanceOwner | StatisticsRepository |
| PerformanceHistory | 无；读取请求可带既有UI过滤条件 | 同一ModelPerformanceOwner | StatisticsRepository的history能力 |
| SessionCosts | rootThreadId:String | 同一计费owner的root scope | StatisticsRepository的cost能力 |
| Recovery | 无 | 原RecoveryRegistry | RecoveryRepository |
| Mcp | 无 | 原MCP运行态owner | McpRepository |
| Lsp | 无 | 原LSP运行态owner | LspRepository |
| Skills | projectId:String | 原SkillCatalog owner | SkillsRepository的对应project scope |
| Persistence | 无 | 原保存协调器 | PersistenceRepository |
| PersistenceQueue | 无 | 原队列统计owner | PersistenceRepository的queue能力 |
| Updates | 无 | 原更新状态机 | UpdatesRepository |

StatisticsRepository属于account_usage域；产品资源各Repository位于resources相应子目录。
这些是小能力实例，不要求一个对象实现本表全部接口。共享ProductEventBus仍只通知原owner
已发布事实，不新建第二消息总线；原巨大公开baseline/state union与Dart RuntimeTransport删除。
Rust内部保留typed topic用于分发不等于保留外部全业务payload桶。

Skills和SessionCosts的scope非空校验沿用原行为（trim仅用于判空，实际ID不归一化）；不得
把scoped观察提升为global。LSP操作可以带projectId，LSP观察仍是原真实全局来源，不伪造
per-project health。目录过滤是查询语义，不过滤掉owner的真实终态/错误。

## 2. 完整身份、版本与frame

每个具体资源都有自己的typed Frame/Event/Baseline/Change类，Rust serde camelCase、FRB
typed mirror、Dart Freezed。以下是相同形状的说明，不是一个dynamic payload接口：

```text
ProductFeedIdentity {
  feed_id:String,owner_epoch:String,incarnation:u64,resource:ProductResource
}
ProductProjectionStamp {owner_epoch:String,incarnation:u64,revision:u64}
ProductReadScopeIdentity {
  scope_id:String,owner_epoch:String,incarnation:u64,version:ProductReadVersion
}
ProductReadVersion = Value{entry:u64,revision:u64} | SourceStatus{entry:u64,revision:u64}
ProductSourceStatusRef {entry:u64,revision:u64}
ProductEntityRef {entry:u64,revision:u64}
ProductCollectionRef {entry:u64,revision:u64,total:u64}
<Resource>ReadRef {entry:u64,revision:u64}

<Resource>Frame =
  Data{delivery_sequence:u64,event:<Resource>Event}
  | ResyncRequired{identity:ProductFeedIdentity,reason:SourceLagged|ReliableQueueFull|RevisionGap}
  | Failure{identity:ProductFeedIdentity,error:StudioFailure}
  | Closed{identity:ProductFeedIdentity,reason:Requested|OwnerReplaced|RuntimeStopped}
<Resource>Event =
  Baseline{identity:ProductFeedIdentity,stamp:ProductProjectionStamp,value:<Resource>Baseline}
  | Change{stamp:ProductProjectionStamp,base_revision:u64,value:<Resource>Change}
```

ProductResource枚举恰为§1的19个观察名；每个open port已经固定资源及scope，不能在同一
连接换resource。feed_id/scope_id分别由原registry用new_id("product-feed")/
new_id("product-read")创建，owner_epoch复用runtime；三者小于64 ASCII字节。不把无界
canonical scope ID、实体ID、路径或查询文本重复内嵌到每个有界Data中；它们在原open/
query binding冻结，真实业务身份在typed读取中完整返回，不能缩小已有ID合法范围。

incarnation绑定实际资源投影实例，不是订阅次数。projection revision只在该观察的数据实际
变化时推进；source的canonical revision另外完整保留在下面header中。receipt只能比较其
指定的canonical资源水位，不能用projection revision、delivery序号或本地加载完成度代替。
变更有base_revision；只有同owner/incarnation接上前一已处理水位才归并，否则局部resync。

ProductEntityRef/CollectionRef只用于原scope内typed源索引，不是业务ID，不可拿entry给
删除/保存命令。相同成员更新保entry、改revision，移除后同业务ID重建用新entry。登记/
opening/immutable pin/结束释放原则与Thread §11一致；引用不可取得原版为Superseded。
不能让进程内entry成为新的持久化ID或跨重启协议。

### 2.1 状态版本与业务值版本分离

`ObservedBrief.revision`始终是原来源状态机revision；`ProductProjectionStamp.revision`是本次
产品观察交付水位；`<Resource>ReadRef.revision`仅版本化它实际指向的业务字段，三者不能
互相代替。`ProductReadScopeIdentity.version`明确本scope pin的是业务值还是来源metadata，
不再使用含混的source_revision。原有receipt仍只比较它声明的来源水位。

每个Observed资源header的`source`类型固定为
`ObservedHeader {brief:ObservedBrief,status:ProductSourceStatusRef}`。status仅指原八态的完整
metadata（无业务value），由`openSourceStatus(ProductSourceStatusRef)`返回
`ProductSourceStatusReadConnection`；它具有header/text/requestClose/close/retryClose，使用
相同scope/call预算。header是原八态的具体metadata union，字符串按ReadText，错误仍为原
code/message/retryable三字段。此能力在该资源port上提供，不建立可观察全业务的通用总线。
原业务ReadConnection不再承载source_status()，防止为读取新错误而废弃稳定正文scope。

`ProductSourceStatusReadHeader`完整八态为下列封闭union，保原字段与可空性：

```text
Uninitialized{revision:u64,updated_at:i64}
Loading{revision:u64,operation:StateOperation,operation_id:ReadText,started_at:i64}
Ready{revision:u64,updated_at:i64,last_checked_at:Option<i64>}
Refreshing{revision:u64,operation:StateOperation,operation_id:ReadText,
           started_at:i64,last_checked_at:Option<i64>}
Stale{revision:u64,stale_at:i64,last_checked_at:Option<i64>}
Degraded{revision:u64,failed_at:i64,last_checked_at:Option<i64>,
         operation:StateOperation,error:SourceStateErrorRead}
Failed{revision:u64,failed_at:i64,operation:StateOperation,error:SourceStateErrorRead}
Stopped{revision:u64,stopped_at:i64}
StateOperation = Initialize|Activate|Reload|Reconcile|Discover|Check|Probe|Repair|Reset|Shutdown
SourceStateErrorRead {code:ReadText,message:ReadText,retryable:bool}
```

operation是原enum而不是需要任意文本解码的名称；仅operation_id及错误字符串走ReadText。
Degraded/Failed原来没有operation_id，不擅自补一个。Data brief中retryable从同一error派生，
不是另一可写事实；读取完整header不得出现与已发布brief矛盾的同revision结果。

业务header的`reference:Option<<Resource>ReadRef>`与collection按来源实际value存在性赋值；
Ready/Refreshing/Stale/Degraded均有原value，仍可读取，但质量由原brief明确标识。
Uninitialized/Loading/Failed/Stopped无value，reference/collection为None；不在wire发明
第二个last-known值。Repository可以保留此前确实读到的value/ref供显示，不当当前已知值。
始终具有canonical值而没有Observed外壳的资源，其reference保持非空。

metadata-only更新仅改变status ref/brief和投影水位；业务字段相同则业务ref、集合ref、
实体ref保持原身份。同理，业务对象更新不让未改变的嵌套实体/文本引用失效。首次生成ref
在原owner发布边界登记，使用既有typed值比较/来源修订，不哈希动态JSON或维护另一正文库。
已经成功打开的scope始终pin其原版本，后续source推进不取消它；未打开且原版已不可得才
Superseded。现有唯一registry管理这些定位和生命周期，不新增永久历史ref表。

## 3. baseline、upsert/remove与分页

### 3.1 集合事件

```text
CollectionBaseline<H> {header:H,collection:Option<ProductCollectionRef>}
CollectionChange<H> {
  header:H,base_collection_revision:Option<u64>,collection:Option<ProductCollectionRef>,
  upserted:Vec<ProductEntityRef>,removed_entries:Vec<u64>
}
```

H在各具体DTO中展开为自己的header，不生成跨业务dynamic H。scalar资源用自己的完整
typed小header Replace，无集合时不造空collection；其Event为Baseline/Replace而非Change。
实体正文不塞进上述ref数组。一次变更的upsert+remove合计最多100；超限明确ResyncRequired，
新的完整索引可分页读取，不截断合法集合/误报空值，也不增加实体数量准入限制。

原ObservedResource没有value时collection=None，不伪造total=0的已知空集合；首次有值的
Change以base_collection_revision=None表达。已有集合消失为collection=None，upsert/remove
为空，canonical当前value明确不可用，last-known另保原stamp用于显示；不是逐条删除事实。
各header中依赖value的内层revision/时间/count字段因此为Option，None不是0。没有Observed
外壳、始终具有canonical值的资源（例如Mode catalog）的这些字段保持非空。

除§3.2的ThreadDirectory外，scope.header与scope.entries(offset,limit)来自同一不可变
collection revision和固定顺序。普通页完整形状为
`<Resource>EntryPage {collection:ProductCollectionRef,offset:u64,
items:Vec<ProductEntityRef>,next_offset:Option<u64>}`；total唯一来自collection.total。
默认32、允许1..100，offset==total为空末页、offset>total拒绝。每次响应完整serde JSON
最多256KiB，限额是最大返回量，可以提前停止，但next_offset必须按实际元素前进。实体
索引页返回typed Ref和必要固定标量排序键；实体的canonical ID/名字/路径通过typed实体读
完整可达。不要用截断ID做Map key或靠当前显示名字找实体。

Repository是索引、已加载实体及页水位的唯一归并者。它可持last-known实体，但必须同时
保留其value revision，不把旧值标为当前ref已经加载。分页期间到达的新delta照常归并；
旧页只能补原scope材料，不能覆盖同entry新水位或复活remove成员。仅为本次页查询保留的
新水位/tombstone最多64帧、8MiB；超限放弃旧scope并重读该collection，不缓存无限delta。
页的完整collection身份必须等于发起时冻结的scope collection。若页返回时已有新delta，
以页的base collection为起点连续重放本次查询保留的typed delta；每个entry采用最新ref，
remove优先于旧页材料。缺任一base链/越过保留预算则废弃该页合并，不部分发布成当前值。
complete仅在该scope所有页取得、连续delta已覆盖到当前collection且排序/窗口覆盖可证明时
成立，首32项不能冒充全量。物化旧实体只证明相应旧ref已加载，不证明新ref已完整加载。

scope销毁不清理Repository canonical镜像，不关闭其他scope的feed；关闭原资源才统一封
准入/取消/真实join。body索引和已加载值不同时在一个旧facade与新Repository各保存一份。

### 3.2 Thread目录专门规则

DirectoryQuery保留项目、搜索、all/running/attention、归档及原父子/根关系查询语义；其
确切字段以workspace port合同为准，不能先用无scope全量Thread数组再在Widget过滤。
排序继续用原`(last_user_message_at ?? created_at,id)`降序，不回退到updated_at。

目录仍使用原keyset cursor，cursor绑定完整查询与原读取身份；跨query混用明确拒绝。
其专用签名为`entries(cursor:Option<String>,limit:u32)->ThreadDirectoryEntryPage`，不提供
offset重载；`ThreadDirectoryEntryPage {collection:ProductCollectionRef,
items:Vec<ProductEntityRef>,next_cursor:Option<ReadText>,has_more:bool}`。cursor是原opaque
keyset token，不从ID/显示名在Dart重新构造；ReadText解开后原样交回同query scope。
读取query与scope已冻结，不将原无界查询文本重复塞回每页。页collection校验及连续delta
合并与§3.1相同，total表示当前query window成员，不冒充库中所有匹配项总数。
root/project/child关系由原目录owner筛选，归档后的列表边界与后继选择保留。公开页的
Thread字段是原完整Thread元数据的typed按需表示，不因新的字段预算丢workspacePath、
lastUserMessageAt、archived或父子身份。

query window内的upsert/remove由Rust按该查询的相同谓词/排序规则计算，不让Dart再造另一
套目录事实。排序变化导致成员跨窗口时同时更新该window的成员和cursor/hasMore事实，
不能只把被移走项删除后假称窗口完整。无法保持原游标覆盖时局部ResyncRequired，而非
静默跳过成员；用户切查询后旧页/旧事件只结算自己的window。

## 4. 源状态、header与完整字段预算

### 4.1 原ObservedResource八态保留

源八态不压成loading/success/error布尔值。具体header包含以下typed小状态；所有operation
ID、operation名称、错误code/message原文另从§2.1的status ref完整读，非静默丢失：

```text
ObservedBrief =
 Uninitialized{revision:u64,updated_at:i64}
 | Loading{revision:u64,started_at:i64}
 | Ready{revision:u64,updated_at:i64,last_checked_at:Option<i64>}
 | Refreshing{revision:u64,started_at:i64,last_checked_at:Option<i64>}
 | Stale{revision:u64,stale_at:i64,last_checked_at:Option<i64>}
 | Degraded{revision:u64,failed_at:i64,last_checked_at:Option<i64>,retryable:bool}
 | Failed{revision:u64,failed_at:i64,retryable:bool}
 | Stopped{revision:u64,stopped_at:i64}
```

source status header返回原ObservedResource所有metadata字段，String→ReadText、数字/nullable不变；
原ObservedResourceError恰含code/message/retryable，不伪造不存在的correlationId。真实
StudioFailure则保留自己的完整code/retryable/correlation，不能与上述来源错误混同。
无value状态不伪造健康空集合；VM可显示last-known，但以明确stale/error区分当前事实。

### 4.2 各域header

下列每个header均另含具体typed详情ref；ref用于取得原metadata/实体字段，不承载正文。
Observed表示上节八态的ObservedHeader；u64计数、时间i64秒、age/response/TTFT均毫秒，
Option不补零。下表不重复顶层collection.total；嵌套计数只来自其对应typed list ref.total。

| header | 除详情ref以外的全部字段 |
| --- | --- |
| Project/Thread/Agent目录 | source:ObservedHeader；Thread window另带has_more:Option<bool>与原opaque cursor的typed文本读取引用 |
| Configuration | source:ObservedHeader,configuration_revision:Option<u64>,updated_at:Option<i64> |
| ModelCatalog | source:ObservedHeader,catalog_revision:Option<u64>,updated_at:Option<i64> |
| AccountTemplates | schema_version:u32；原revision:String通过typed读取，不当u64计数 |
| AgentProfiles | source:ObservedHeader |
| ModeCatalog | revision:u64 |
| AccountUsage | source:ObservedHeader |
| PerformanceSummaries | revision:u64,updated_at:i64,statistics_pending:bool,statistics_gap:bool,read_failed:bool |
| PerformanceHistory | revision:u64,updated_at:i64,statistics_pending:bool,statistics_gap:bool,read_failed:bool |
| SessionCosts | revision:u64,updated_at:i64,statistics_pending:bool,statistics_gap:bool,read_failed:bool,has_cost:bool,has_unpriced_usage:Option<bool> |
| Recovery | source:ObservedHeader |
| Mcp/Lsp | source:ObservedHeader |
| Skills | source:ObservedHeader,catalog_revision:Option<u64>,complete:Option<bool> |
| Persistence | 原Ready/Flushing/Degraded/Recovering/Blocked五态、revision、pending_commits/oldest_pending_revision/first_failed_at全部原标量；error另经typed详情 |
| PersistenceQueue | revision:u64,updated_at:i64,statistics_gap:bool,pending_operations:u64,pending_bytes:u64,in_flight_bytes:u64,oldest_pending_age_millis:Option<u64>,pressure_paused:bool,has_last_error:bool |
| Updates | §4.4的完整typed标量状态，原summary/operation/error文本经详情读取 |

collection.total是该顶层集合唯一长度事实；其他嵌套集合用下面typed方法分页。
Source不可读时不得靠counts=0宣称没有项目/模型/保存问题。它们表示原状态可知的集合
长度，不代替ObservedBrief/read_failed/gap。SessionCosts.has_cost=false是原cost=None的
明确清除，不等于零金额；has_unpriced_usage因此是None，不默认false。

### 4.3 typed读取形状（固定规则，不是运行期codec）

产品scope沿用ReadText Inline/Deferred与text(field_id,offset,max_bytes)的UTF-8/完整JSON
预算、immutable pin和真实close/retry_close。原每个结构字段必须按原名逐个声明typed DTO：

1. 原String→ReadText，Option<String>→Option<ReadText>。enum/bool/u32/u64/i64/f64及
   nullable不改；不将数字/枚举转文本绕过结构。
2. 原固定结构仍是同名具体Read结构；原Vec<T>改为`TypedListRef{list_id:u64,total:u64}`，
   对应下表固定的返回TReadPage方法。Map使用具体KeyValueReadItem，不用任意Value/Map。
3. list_id只是scope内的已知字段/索引定位，resolver用封闭typed字段种类核对，不能请求
   任意JSON路径。wrong list type/越界索引为InvalidArgument；每个list保持原有顺序，Map
   则按原key稳定排序。字段的None与空列表区别保留。
4. Read DTO是此领域的运输/按需能力；Repository组装完整领域值时逐字段读取，保留来源
   stamp。它不能把未加载字段填默认值当canonical。VM可以驱动可见需求，不重复归并wire。
5. 各scope的text/header/固定typed页方法与独立source status读取是公开领域查询，不新增动态doc树、
   反射字段API、通用codec或另一持久化缓存。原不透明诊断扩展仅保其原opaque语义。

各方法均为`(list_id:u64,offset:u64,limit:u32)->对应具体Page`；无list的header/detail方法
不接list_id。下表枚举每域所有列表元素族，包含嵌套列表，避免“顶层分页但单元素仍无界”：

| scope | 固定typed列表方法及元素 |
| --- | --- |
| ConfigurationReadScope | accounts→AccountConfigurationRead；custom_models→CustomModelConfigurationRead；model_connections→ModelConnectionRead；auto_compact_overrides→ModelAutoCompactRead；mode_routes→ModeModelRouteRead；role_routes→RoleModelRouteRead；mcp_configs→McpConfigurationRead；strings→TextReadItem；input_capabilities→InputCapabilityRead；input_sources→ModelInputSourceReadItem |
| ModelCatalogReadScope | accounts→AccountCatalogEntryRead；models→ModelDescriptorRead；type_support→ModelTypeSupportRead；type_exclusions→ModelTypeExclusionReadItem；connection_modes→ConnectionModeRead；input_capabilities→InputCapabilityRead；input_sources→ModelInputSourceReadItem；modalities→ModelModalityReadItem；price_tiers→ModelPriceTierRead；strings→TextReadItem |
| AccountTemplatesReadScope | templates→AccountTemplateRead；catalogs→NamedModelCatalogRead；与ModelCatalog相同的models/type_support/type_exclusions/connection_modes/input_capabilities/input_sources/modalities/price_tiers/strings |
| AgentProfilesReadScope | profiles→AgentProfileRead；diagnostics→ProfileDiagnosticRead |
| ModeCatalogReadScope | modes→ThreadModeDescriptorRead；单定义读/校验/预演走modes独立typed命令，不将文档塞catalog |
| AccountUsageReadScope | usages→AccountUsageRead；balances→BalanceRead；quota_limits→QuotaLimitRead；quota_details→QuotaDetailRead |
| PerformanceSummariesReadScope | summaries→PerformanceSummaryRead；effort_breakdowns→PerformanceEffortRead |
| PerformanceHistoryReadScope | samples→PerformanceSampleRead |
| SessionCostsReadScope | purposes→PurposeCostRead；amounts→RuntimeCostRead |
| RecoveryReadScope | issues→RecoveryIssueRead；actions→RecoveryActionReadItem；changed_files→TextReadItem |
| McpReadScope | servers→McpServerRead；active_servers→TextReadItem |
| LspReadScope | servers→LspServerRead；strings→TextReadItem（active/extensions/language_ids各自list_id） |
| SkillsReadScope | skills→SkillSummaryRead；strings→TextReadItem（warnings/platforms等各自list_id） |
| PersistenceReadScope | 无列表；原错误经ReadText |
| PersistenceQueueReadScope | threads→ThreadPersistenceRead |
| UpdatesReadScope | 无列表；只读该版本summary及来源错误 |
| Project/Thread/AgentDirectoryReadScope | 对应projects/threads/agents具体完整元数据；嵌套workspace赋值的writable_paths用strings，其他固定typed结构原样 |

所有Read元素的原字段来源由§5和既有协议定义唯一指定；改变字段名/单位/可空性需root
同步此合同。禁止执行者为了简化reader删除某个Vec或把它改成String JSON。

### 4.4 Updates完整状态

```text
UpdatesBrief =
 Disabled{revision:u64,updated_at:i64}
 | Idle{revision:u64,updated_at:i64}
 | Checking{revision:u64,started_at:i64}
 | UpToDate{revision:u64,checked_at:i64}
 | Available{revision:u64,checked_at:i64}
 | Downloading{revision:u64,updated_at:i64,downloaded:u64,total:u64}
 | Verifying{revision:u64,updated_at:i64,downloaded:u64,total:u64}
 | Ready{revision:u64,ready_at:i64}
 | InstallerLaunched{revision:u64,launched_at:i64}
 | CheckFailed{revision:u64,failed_at:i64,retryable:bool}
 | InstallFailed{revision:u64,failed_at:i64,retryable:bool}
```

恰11种，不是12种。每个Updates Data另含UpdatesReadRef；其header返回同variant完整
原状态，其中Checking.operation_id:ReadText；有update的六种状态保
`UpdateSummaryRead{version:ReadText,published_at:i64,notes_url:ReadText}`（三字段非空），
两个失败状态error为`{code:ReadText,message:ReadText,retryable:bool}`。没有update的状态
不能填默认版本或URL。下载计数是字节、不代表安装成功；typed日期保持Unix秒，不在SDK
canonical值中改成依赖本地时区的显示DateTime。UI按原本地化格式转换。

为避免下载进度使稳定文本反复失效，Data除brief与reference外固定带
`summary:Option<UpdateSummaryReadRef>,operation:Option<UpdateOperationReadRef>,
error:Option<UpdateErrorReadRef>`，三种ref仍为entry/revision。分别以
openSummary/openOperation/openError打开同预算的typed scope；各header完整字段为
UpdateSummaryRead、`{operation_id:ReadText}`、`{code:ReadText,message:ReadText,retryable:bool}`。
只有对应文本/值真的改变才推进该ref；Downloading计数增加不改summary ref。
UpdatesReadScope的完整状态可供显式详情使用，但Repository归并进度只需Data已有标量，
不能每个字节进度都重开完整scope。业务全状态和窄引用都指原updater同一canonical值。

## 5. Config与Catalog真正拆域

### 5.1 Configuration canonical值

新的ConfigurationValue不含effective model列表、model catalog status或模板catalog。完整字段：

```text
ConfigurationValue {
 default_account_id:Option<String>,accounts:Vec<AccountConfiguration>,
 mode_model_routes:Vec<StudioModeModelSettings>,roles:Vec<StudioRoleSettings>,
 permission_mode:String,instructions:StudioInstructionsSettings,skills:StudioSkillsSettings,
 mcp_servers:Vec<StudioMcpServerSettings>,general:StudioGeneralSettings,
 web_search:WebSearchConfiguration,deepseek_web_search:DeepSeekSearchConfiguration
}
AccountConfiguration {
 pricing_enabled:bool,account_id:String,template_id:Option<String>,protocol:String,name:String,
 base_url:String,has_bearer_token:bool,usage_query_revision:u64,
 custom_models:Vec<StudioCustomModelSettings>,model_connection_modes:Vec<StudioModelConnectionSettings>,
 model_auto_compact_limits:Vec<StudioModelAutoCompactSettings>,catalog_id:Option<String>
}
WebSearchConfiguration {
 configured_mode:String,context_size:Option<String>,allowed_domains:Vec<String>,
 country:Option<String>,region:Option<String>,city:Option<String>,timezone:Option<String>
}
DeepSeekSearchConfiguration {configured_enabled:bool,configured_fetch_enabled:bool}
```

上述Studio*嵌套类型字段严格取`pl-protocol/src/studio/settings.rs`当前对应定义；读取所有字段，
不以命令可写字段的子集冒充完整配置值。has_bearer_token是无秘密的凭据存在事实，
usage_query_revision是account查询输入身份，均只读；不能回写成desired TOML字段。
只在相同账号的新canonical版本仍有效时合并；删除再新建同ID的query revision不能复用。

### 5.2 Models canonical值

```text
ModelsValue {
 accounts:Vec<AccountCatalogEntry>,web_search:EffectiveWebSearch,
 deepseek_web_search:EffectiveDeepSeekSearch
}
AccountCatalogEntry {
 account_id:String,credential_required:bool,capability_source:String,
 hosted_web_search:bool,hosted_web_search_dialect:String,standalone_web_search:Option<String>,
 prompt_cache_dialect:String,responses_programmatic_tool_calling:bool,default_model_id:String,
 effective_models:Vec<ModelDescriptor>,model_catalog:StudioModelCatalogStatus
}
EffectiveWebSearch {effective_mode:String,availability:String,account_id:Option<String>,model_id:Option<String>}
EffectiveDeepSeekSearch {
 effective_enabled:bool,effective_fetch_enabled:bool,availability:String,account_id:Option<String>
}
```

ModelDescriptor、全部capability/context/transport/reasoning/pricing子结构取
`pl-protocol/src/account_catalog.rs`；CatalogStatus及其error/cacheWarning全部typed变体取
`studio/settings.rs`。price的per-million-token单位、currency字符串、verified_at秒和nullable
窗口/费用不变；Dart不计算政策或从显示名/URL猜厂商/能力。AccountTemplates是原
AccountCatalogSnapshot的schema_version/revision/templates/model_catalogs完整值，独立读。

上述移动来自原StudioAccountSettings/WebSearch/DeepSeek中的**derived字段**，不是新计算
来源。Rust在原ConfigRuntime的canonical发布边界重用原模型解析能力，相关配置/目录真实
变化使Models观察采用最新值；仅实际产品字段变化推进对应产品投影revision。不把Settings
revision改名为catalog revision，也不在Dart将两个旧SettingsStateSnapshot合成一整页再分发。

Config与Models各自的唯一writer只写本域。跨域页面可以只读组合两者，但保留各自stamp及
加载/失败状态，不用一个全局revision覆盖另一域。不匹配/未加载的目录选择保留原account/
model/effort和unavailable显示，不偷偷换第一个可用项。Thread当前策略的相容Settings/catalog
读取仍在原Rust owner的同锁观察边界，不能靠两个Dart通知拼出来源屏障。

### 5.3 写入保全

AccountSecretUpdate保留Preserve/Replace(value)/Clear；生产快照从不包含明文token。空编辑
且has_bearer_token=true默认Preserve，Replace空值明确拒绝，不能因空表单清凭据。
保存账号与随后setDefault是两个独立CAS/结果；第二步失败或unknown不能抹掉第一步成功。
custom_models、connection_modes、auto_compact覆盖的完整集合必须在最新canonical上构造，
CAS恢复后重构，不能因为在线catalog暂时撤下某项就删除其desired覆盖。

## 6. Statistics独立交付

PerformanceSummaries只含完整按account/model分组的汇总及effort breakdown可读引用；
PerformanceHistory只含原最近历史窗口的索引/状态。任何一次sample变化不把整个history
和所有summary正文重复塞入同一个feed。现有有界最近样本窗口继续使用原
`PERFORMANCE_SAMPLE_LIMIT`，不擅自扩大为全历史数据库浏览；UI分页遍历该固定scope窗口。

两者仍由同一个ModelPerformanceOwner读取/发布，没有第二套聚合器、周期查询或前端重算
指标。summary完整字段取`protocol/event.rs::StudioModelPerformanceSummary/EffortSummary`；
history完整字段取`StudioModelPerformanceSample`，包括model_id/sent_model/reported_model/
model_match_state/effort、decode_millis诊断值、总响应耗时及nullable指标。保留decode诊断
不意味着用它作吞吐分母：吞吐仍completion_tokens/total_response_millis，TTFT仍使用独立
ttft_sample_count。零样本/未知模型不能塞进已知分组或显示成测得零性能。

SessionCosts按root独立观察，其purpose_costs/estimated_costs/has_unpriced_usage全部保留，
purpose可空；不同币种不合并。成本来源、statistics_pending/gap/read_failed均保真。
用户未打开统计页时不因实时Thread指标建立全局历史订阅；当前会话费用不接收无关root。

原ModelPerformanceOwner一次内部发布可同时通知两个观察，但新产品projection/collection
版本分别判断实际承载字段：summary变化不能更改不变sample的entity ref；只改pending/gap/
read_failed不更改业务collection/entity ref。新样本使最近窗口成员变化，但旧样本身份与
正文保持原ref。各summary/effort的计量标量与稳定account/model/effort文本须在最终类型册
分别声明typed引用；不能以同一个不断变化的整页ReadRef要求重读所有长文本。SessionCosts
同理按root只推进实际变化的金额/用途，保独立来源质量标记，不按总owner revision强制改正文。

## 7. 流控与退出

所有具体产品feed最多2个未ACK Data（含baseline）；集合delta用FIFO64/8MiB，单Data
256KiB；纯最新标量/下载进度使用latest1/64KiB。来源的真实状态终结不能被进度latest覆盖，
Updates的Available/Ready/失败等状态迁移走可靠数据，只有同一阶段的下载计数可合并。
不在原大队列外再叠另一个无界队列；生产者/交付责任只有一个明确owner。

ACK只确认同具体连接连续处理前缀，旧ACK幂等、超sent Protocol；来源读取/转换/归并失败
不ACK。Failure/Closed/ResyncRequired至多选一个控制终结、不被满data窗口阻塞；业务状态
终态仍是有序Data。requestClose同步封准入，close/retryClose等待实际producer/subscription/
query/consumer，成功后才dispose/释permit，完整issues沿生命周期合同，不以取消Future假join。

产品详情scope计入现有readModel预算；每个具体资源scope最多8个详情scope，runtime合计
64个在途详情call，与Thread详情**共用**64上限，不各建一个64池来扩大总量。对已受理操作
与关闭查询保留归属；不足typed Overloaded，不能回收在途scope或清未知操作换容量。

## 8. 仍需合同闭合

- [ ] 全19具体scope header/Read DTO按本schema逐字段展开的正式类型册（尤其Updater/Agent目录）。
- [ ] 所有Repository/port/动作具体签名与T、receipt目标及read-only/显式mutation区别。
- [ ] HTTP/SSE/open/ACK/close/查询与OpenAPI完整替换路径；删除旧聚合入口，不留alias。
- [ ] 与所有VM可见需求、完整加载/dirty/保存CAS、统计与目录分页的端到端验收对应。

未完成条目不交executor自由设计；本合同尚不是全局编码放行。
