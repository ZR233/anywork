# v4 产品领域类型册：业务值与typed Read闭包

本类型册补充[产品wire合同](./v4-product-wire-contract.md)的19个资源，绑定
[源码输入manifest](./v4-source-ownership.json)。它定义字段，不是运行期反射schema或JSON
codec；Rust实现用具体struct/enum，Dart领域值用Freezed，adapter不重新计算业务策略。
根文档中的`ConfigurationValue`及`ModelsValue`按真实分域，不允许照搬旧聚合StudioSettings。

## 1. 类型记法与封闭转换

下面使用Rust字段名/数值宽度；Dart生成输入使用camelCase，整数精确转换为int，f64为double。
`a/b:T`表示两个分别具名的字段均为T，不是路径或Map。没有写出的字段不暗加默认值。
Dart标识符例外明确为ModelReasoningDescriptor.default→defaultValue（Read形式相同）；
wire字段仍default，不能因语言关键字删除该字段或改公开JSON字段名。
Unix时间为i64秒；名称包含millis的耗时/年龄为毫秒；bytes为字节，tokens为token数量。

每个业务结构T对应具体TRead，字段一一变换：String→ReadText，Option递归保持None，
Vec<T>→TypedListRef，固定结构递归为具名Read结构。原无payload enum不变；含文本的enum
有具体Read形式，例如QuotaWindowRead.other(ReadText)，不能把整个enum转成JSON。原enum
中的具体数字/布尔/可空性保留。Dart物化值与Read值是不同职责，物化前不能给未加载字段填默认。

`ThreadModeId`保原经验证newtype（mode.及最多64 ASCII字节），Read中可直接保其typed值，
不增加新输入范围；其它任意业务ID、路径和SkillProviderId文本都用ReadText。PathBuf在已有
公开序列化边界转换为字符串，不能从displayName/当前工作目录推导原路径。

```text
TypedListRef {list_id:u64,total:u64}
TextReadItem {value:ReadText}
<Resource><Element>ReadPage {
 list_id:u64,offset:u64,total:u64,items:Vec<<Element>Read>,next_offset:Option<u64>
}
```

list_id是原scope内封闭typed字段/索引定位，不是任意JSON路径。页默认32、1..100，完整
serde JSON≤256KiB；按实际返回项前进。无界字符串可Deferred，Inline只规定最大4096 UTF-8
字节，并不强制每个短字符串都Inline；为满足完整header/page预算可以更早Deferred。
所有header/page/文本共享原typed读取与immutable pin/close规则，不新增字节codec。

具体Scope的所有结构Read方法为`header()`；结构内列表通过产品合同§4.3列出的固定typed
页方法读取。下面每个Vec都必须可由该列表族到达，不建立只有顶层列表可读的伪完整接口。
SourceStatus独立header及八态字段只在产品合同§2.1定义一次，不复制进业务值。
为匹配既定具名页族，以下Read命名是明确的唯一名称（不是alias）：
AgentProfileSnapshot→AgentProfileRead、AccountUsageRecord→AccountUsageRead、
ThreadPersistenceSnapshot→ThreadPersistenceRead。其余按TRead；Map目录页例外用本册的
NamedModelCatalogReadItem以保key。所有公共导出只导出这一条名称。

## 2. Configuration

顶层ConfigurationValue、AccountConfiguration、WebSearchConfiguration和
DeepSeekSearchConfiguration逐字段采用产品合同§5.1（同一类型定义），其完整嵌套闭包如下。
原权威：`code/pl-protocol/src/studio/settings.rs`；仅下述已明确投影字段进入本域。

```text
CustomModelConfiguration {
 input_capabilities:Vec<ModelInputCapability>,context_window:Option<u64>,
 max_output_tokens:Option<u64>,model_id:String,display_name:String,
 reasoning_efforts:Vec<String>,base_instructions:String,wire_api:String,
 supported_connection_modes:Vec<String>,default_connection_mode:String
}
ModelConnection {model_id:String,connection_mode:String}
ModelAutoCompact {model_id:String,override_limit:Option<u64>}
ModeModelRoute {mode_id:String,account_id:String,model_id:String,effort:String}
RoleModelRoute {key:String,account_id:String,model_id:String,effort:String}
InstructionsSettings {
 base_override:String,developer:String,user:String,project_doc_max_bytes:u64,
 project_doc_fallback_filenames:Vec<String>
}
SkillsSettings {
 enabled:bool,auto_learn:bool,system_enabled:bool,project_dir:String,user_dir:String,
 external_dirs:Vec<String>,disabled:Vec<String>,auto_learn_min_tool_calls:u32
}
McpConfiguration {
 id:String,transport:String,endpoint:String,configuration:McpConfigurationState,
 source_kind:String,mutation_policy:String
}
McpConfigurationState = Enabled | Disabled | MissingCredential
GeneralSettings {
 follow_active_turn:bool,compact_timeline:bool,sidebar_width:Option<u16>,
 pinned_thread_ids:Vec<String>,pinned_project_ids:Vec<String>
}
```

新ConfigurationValue嵌套字段类型采用上述具名类型，分别取代旧Studio*Settings公共名；
旧名不保别名。AccountConfiguration.custom_models/model_connection_modes/
model_auto_compact_limits分别是本节三种元素；mode_model_routes/roles/mcp_servers同表。
ModelInputCapability由models域唯一定义（下节），本域只引用。catalog_id仍在配置账号，
不因探索报告中旧字段分类错误将其再次迁走；derived能力依产品合同§5.2归Models。
原custom model只读能力、instructions、连接字段都必须完整保留，保存intent仅写原允许部分。

## 3. ModelCatalog与AccountTemplates共用的模型闭包

ModelsValue/AccountCatalogEntry/EffectiveWebSearch/EffectiveDeepSeekSearch逐字段采用
产品合同§5.2。权威模型定义来自`code/pl-protocol/src/account_catalog.rs`；状态来自
`code/pl-protocol/src/studio/settings.rs`。以下是新公共命名，不建旧Dto后缀转发别名。

```text
ModelDescriptor {
 model_id:String,type_support:Vec<ModelTypeSupport>,origin:ModelOrigin,
 display_name:String,description:Option<String>,context_window:Option<u64>,
 max_context_window:Option<u64>,context:ModelContextResolution,
 max_output_tokens:Option<u64>,transport:ModelTransportDescriptor,
 capabilities:ModelCapabilities,reasoning:Option<ModelReasoningDescriptor>,
 pricing:Option<ModelPricing>
}
ModelTypeSupport {model_type:ModelType,exclusions:Vec<ModelTypeExclusion>}
ModelType = Text
ModelTypeExclusion = TextInputUnsupported | TextOutputUnsupported | ContextWindowUnknown |
 ContextParametersInvalid | InputBudgetExhausted
ModelOrigin = Bundled | Online | Manual
ModelContextResolution {
 unavailable:Option<ModelContextUnavailable>,context_window:Option<u64>,
 input_token_limit:Option<u64>,auto_compact_limit:Option<u64>,
 adjustment:Option<ModelContextAdjustment>
}
ModelContextUnavailable = WindowUnknown | InvalidParameters | InputBudgetExhausted
ModelContextAdjustment = SafetyLimit
ModelTransportDescriptor {
 protocol:String,connection_modes:Vec<ConnectionMode>,default_connection_mode:String
}
ConnectionMode {id:String,display_name:String}
ModelCapabilities {
 input:Vec<ModelInputCapability>,output:Vec<ModelModality>,streaming:bool,temperature:bool,
 reasoning:bool,web_search:bool,function_calling:bool,parallel_tool_calls:bool,
 custom_tools:bool,freeform_tools:bool,instruction_snapshot_overrides:bool,
 native_context_family:Option<String>
}
ModelModality = Text | Image | Audio | Video | File
ModelInputSource = Local | RemoteUrl
ModelInputCapability {
 modality:ModelModality,sources:Vec<ModelInputSource>,max_count:Option<u32>,
 max_bytes:Option<u64>,max_total_bytes:Option<u64>,max_width:Option<u32>,
 max_height:Option<u32>,media_types:Vec<String>
}
ModelReasoningDescriptor {parameter:String,label:String,default:Option<String>,candidates:Vec<String>}
ModelPricing {currency:String,tiers:Vec<ModelPriceTier>,source:String,verified_at:i64}
ModelPriceTier {
 label:String,input_per_mtok:f64,output_per_mtok:f64,
 cache_read_per_mtok:Option<f64>,cache_write_per_mtok:Option<f64>
}
ModelCatalogStatus {
 supported:bool,source:ModelCatalogSource,probing:bool,last_success_at:Option<i64>,
 checked_at:Option<i64>,error:Option<ModelCatalogError>,cache_warning:Option<ModelCatalogCacheWarning>
}
ModelCatalogSource = Default | Cached | Online
ModelCatalogError = Unsupported | Configuration | Timeout | Transport{http_status:Option<u16>} |
 Http{status:u16} | TooLarge | Protocol | CacheIdentity | UnexpectedNotModified | CacheWrite | Closing
ModelCatalogCacheWarning = Read | Schema | Identity | Declaration
```

价格单位为每百万tokens，币种不合并；context/effort/input策略由Rust给出，Dart不重新解算。
固定enum列表各自有具名ReadItem{value:原enum}，例如ModelTypeExclusionReadItem、
ModelInputSourceReadItem、ModelModalityReadItem；不将enum文本化。

AccountTemplates的完整值（`AccountCatalogSnapshot`来源，同一个独立模型模板资源）：

```text
AccountTemplatesValue {
 schema_version:u32,revision:String,templates:Vec<AccountTemplate>,
 model_catalogs:Map<String,NamedModelCatalog>
}
AccountTemplate {
 pricing_enabled:bool,id:String,display_name:String,description:Option<String>,base_url:String,
 credential:CredentialDescriptor,model_catalog_id:String,protocol:String,suggested_model_id:String,
 icon_key:Option<String>,service_capabilities:AccountServiceCapabilities
}
CredentialDescriptor {label:String,env_var:Option<String>}
AccountServiceCapabilities {
 web_search:WebSearchServiceCapabilities,prompt_cache_dialect:String,
 responses_programmatic_tool_calling:bool
}
WebSearchServiceCapabilities {hosted_responses:bool,hosted_dialect:String,standalone:Option<String>}
NamedModelCatalog {id:String,models:Vec<ModelDescriptor>}
NamedModelCatalogReadItem {key:ReadText,value:NamedModelCatalogRead}
```

`catalogs`页返回NamedModelCatalogReadItem，不能丢原Map key或只按内部id认领。原BTreeMap
按key顺序读取。模板revision仍为String；不能拿它作为u64产品投影版本或固定为当前schema值。

## 4. AgentProfiles与ModeCatalog

权威：`pl_protocol::AgentProfileSnapshot`、runtime `protocol/event.rs::StudioAgentProfilesData`
及`pl_protocol::thread::mode`。Profile和运行期AgentDirectory不是同一资源。

```text
ProfilesValue {profiles:Vec<AgentProfileSnapshot>,diagnostics:Vec<ProfileDiagnostic>}
AgentProfileSnapshot {
 profile_id:String,display_name:String,description:String,when_to_use:String,
 system_instructions:String,account_id:String,model_id:String,effort:Option<String>,
 source:String,revision:String,content_hash:String,system:bool,enabled:bool,
 workspace_mode:AgentWorkspaceMode
}
AgentWorkspaceMode = Unrestricted | Directory | Worktree | Review
ProfileDiagnostic {path:String,message:String}
ModesValue {revision:u64,modes:Vec<ThreadModeDescriptor>}
ThreadModeDescriptor {
 id:ThreadModeId,display_name:String,description:String,order:u32,
 has_workflow:bool,read_only:bool
}
```

Profile的revision/content_hash保持源字符串，不因当前生成方式猜历史限制；诊断path采用
发布DTO的String，不直接暴露扫描器私有PathBuf。ModeDefinition/authoring不塞catalog，
原严格validator与文档/preview类型在Mode编辑合同中单独定义。

## 5. AccountUsage

权威是runtime `studio/runtime/account_usage.rs`的资源payload与`account_usage.rs`及其state
模块，不能声称已存在pl-protocol同构DTO。R在本次typed产品协议中明确投影，保原数值与状态。

```text
AccountUsageValue {config_fingerprint:String,usages:Vec<AccountUsageRecord>}
AccountUsageRecord {
 account_id:String,revision:u64,updated_at:i64,last_operation_id:String,state:AccountUsageResult
}
AccountUsageResult = Unsupported | MissingCredential{message:String} |
 Ready{data:AccountUsageData} | Failed{error:SourceStateError}
AccountUsageData = DeepSeekBalance{is_available:bool,balances:Vec<Balance>} |
 ZhipuCodingPlan{level:Option<String>,limits:Vec<QuotaLimit>}
Balance {currency:String,total_balance:String,granted_balance:String,topped_up_balance:String}
QuotaLimit {
 window:QuotaWindow,percentage:f64,current_value:Option<f64>,total:Option<f64>,
 remaining:Option<f64>,next_reset_at:Option<i64>,usage_details:Vec<QuotaDetail>
}
QuotaWindow = FiveHour | Weekly | McpMonthly | Other(String)
QuotaDetail {name:String,current_value:Option<f64>,total:Option<f64>,percentage:Option<f64>}
```

余额是原供应商十进制文本，不转double；QuotaWindow.Other的原未知标签完整可读，不默认为
某个已知窗口。query identity仍来自Configuration账号usage_query_revision，不能用用量
记录自身revision替代。check原native准入校验身份及后续同步失败语义沿domain ports。

## 6. Performance与SessionCosts：稳定身份和标量分别读取

源为runtime `protocol/event.rs`的StudioModelPerformanceSummary/EffortSummary/Sample与
SessionCosts，原ModelPerformanceOwner计算；历史窗口仍PERFORMANCE_SAMPLE_LIMIT=3000。
以下Counters结构是明确的新分组，字段只从对应原DTO提取，不在Dart求均值/吞吐。

```text
PerformanceCounters {
 sample_count:u64,completion_tokens:u64,total_ttft_millis:u64,ttft_sample_count:u64,
 total_response_millis:u64,tokens_per_second:f64,average_ttft_millis:Option<f64>,
 average_response_millis:f64
}
PerformanceSummaryIdentity {account_id:String,account_display_name:String,model_id:String}
PerformanceEffortIdentity {effort:Option<String>}
PerformanceSampleIdentity {
 account_id:String,account_display_name:String,model_id:Option<String>,sent_model:Option<String>,
 reported_model:Option<String>,model_match_state:ModelMatchState,effort:Option<String>
}
ModelMatchState = Matched | Mismatched | Unreported | LegacyUnknown
PerformanceSampleCounters {
 completed_at:i64,completion_tokens:u64,ttft_millis:Option<u64>,decode_millis:Option<u64>,
 total_response_millis:Option<u64>,tokens_per_second:Option<f64>
}
PerformanceSummary {
 identity:PerformanceSummaryIdentity,counters:PerformanceCounters,
 effort_breakdowns:Vec<PerformanceEffort>
}
PerformanceEffort {identity:PerformanceEffortIdentity,counters:PerformanceCounters}
PerformanceSample {identity:PerformanceSampleIdentity,counters:PerformanceSampleCounters}
SessionCost {
 root_thread_id:String,purpose_costs:Vec<PurposeCost>,estimated_costs:Vec<RuntimeCost>,
 has_unpriced_usage:bool
}
PurposeCost {purpose:Option<String>,estimated_costs:Vec<RuntimeCost>,has_unpriced_usage:bool}
RuntimeCost {currency:String,amount:f64}
```

source revision/updated_at/statistics_pending/gap/read_failed由产品header完整保留，业务实体不
重复它们。SessionCosts业务value为Option<SessionCost>；None是明确清除，不是零金额。

高频窄Read布局固定覆盖默认转换规则：

```text
PerformanceSummaryIdentityRef {entry:u64,revision:u64}
PerformanceEffortIdentityRef {entry:u64,revision:u64}
PerformanceSampleIdentityRef {entry:u64,revision:u64}
PerformanceSummaryRead {
 identity:PerformanceSummaryIdentityRef,counters:PerformanceCounters,effort_breakdowns:TypedListRef
}
PerformanceEffortRead {identity:PerformanceEffortIdentityRef,counters:PerformanceCounters}
PerformanceSampleRead {identity:PerformanceSampleIdentityRef,counters:PerformanceSampleCounters}
```

三个identity scope分别以openSummaryIdentity/openEffortIdentity/openSampleIdentity打开，
完整签名均含`reference,{required ProductReadOrigin origin}`，见产品read ports§4；
header返回对应IdentityRead（String→ReadText），有text/close/retryClose，同readModel/
runtime64预算。不另造永久身份缓存。数值变化只更新受影响entity ref；稳定身份不变则其
identity ref不变。样本进入/离开窗口改collection，不能改其它sample的ref。账号改显示名
只更新该身份，不能重分组；summary group唯一key仍account_id+model_id。effort=None不
改成空字符串。吞吐用总response_millis，TTFT均值分母ttft_sample_count，decode仅诊断。

当前样本源公开DTO没有稳定sample ID；R须沿原CallLogRecord的`(thread_id,call_id)`建立
投影entry，不能用completed_at/account/model的非唯一组合合并两次调用。准确接缝为
`studio/storage/calls.rs::PerformanceSampleRow`增加crate内thread_id/call_id字段，
recent_performance_samples解码原record后原样携带，ModelPerformanceOwner在转成公开值
之前登记source identity。原索引/日志已经有这对键，无新表或数据库迁移，不把私有source
key误添加到原统计展示业务字段。顺序保recorded_at/thread_id/call_id降序，仍受原日志
保留期与history_limit约束；不能误改为直接遍历performance_samples表的另一历史来源。

## 7. Workspace目录

公开Thread采用`pl_protocol::Thread`，不是多出visibility/thread_kind/summary/error的私有
ThreadRecord。项目来自runtime ProjectRecord，Agent来自protocol/runtime.rs目录entry。

```text
ProjectRecord {id:String,name:String,path:String,ssh_alias:Option<String>,updated_at:i64}
WorkspaceThreadRecord {
 id:String,project_id:String,title:String,mode:ThreadModeId,workspace_mode:ThreadWorkspaceMode,
 workspace_path:String,root_thread_id:String,parent_thread_id:Option<String>,role:String,
 agent_path:String,status:ThreadStatus,created_at:i64,updated_at:i64,
 last_user_message_at:Option<i64>,archived:bool
}
ThreadWorkspaceMode = Local | Worktree
ThreadStatus = Idle | Queued | Running | WaitingTool | WaitingInteraction | Cancelling |
 Closing | Closed | Faulted
AgentDirectoryEntry {
 id:String,thread_id:String,root_thread_id:String,path:String,parent_path:Option<String>,
 role:String,task:String,summary:Option<String>,depth:u32,state:AgentState,updated_at:i64
}
AgentState = Idle{budget_pause:Option<AgentBudgetPause>} |
 Queued{turn_id:String} | Running{turn_id:String} | WaitingTool{turn_id:String} |
 WaitingInteraction{turn_id:String,interaction_id:String} | Cancelling{turn_id:String} |
 Closing{workspace_disposition:AgentWorkspaceDisposition,turn_id:Option<String>,error:Option<SourceStateError>} |
 Closed | Faulted{error:SourceStateError,turn_id:Option<String>,classification:AgentFaultClassification}
AgentBudgetPause {turn_id:String,limit:BudgetLimitSnapshot,paused_at:i64}
AgentWorkspaceDisposition = Preserve | Cleanup
AgentFaultClassification = RecoverableRuntime | RecoverableProtocol | AggregateCorruption | LegacyUnknown
DirectoryQuery {project_id:Option<String>,search:Option<String>,archived:bool,filter:DirectoryFilter}
DirectoryFilter = All | Running | Attention
```

ThreadDirectoryScope的query/thread两分支精确形状由Workspace合同定义；DirectoryQuery
仍只表示原root过滤，不扩大它去混装child查询。单Thread元数据分支承接旧详情能力。

目录集合顶层分别projects/threads/agents，不嵌入workspace assignment。Assignment是另一
独立冻结快照，只有原来确实提供该字段的详情消费者可读取，不能凭类型存在给AgentDirectory
凭空加字段。AgentState保原kind/data tagged union；TurnId原底层字符串在Read中完整ReadText，
不把状态payload压成摘要。BudgetLimitSnapshot/Kind/Usage复用Thread合同§9.2同一完整类型，
改由D0 resources唯一导出供D1/D3共同引用，不在Agent和Turn各复制一份。

Thread目录按真实Thread::directory_sort_time()即last_user_message_at??created_at，再以id
降序破平；旧分页注释的updatedAt不构成改排序授权。DirectoryQuery只选root，原search
匹配项目或title、大小写及trim行为由原Rust谓词保留；Running为Queued/Running/WaitingTool/
Cancelling，Attention为WaitingInteraction/Faulted。不能把WaitingInteraction加入Running。

## 8. Recovery、MCP、LSP

```text
RecoveryIssue {
 id:String,scope:RecoveryScope,category:RecoveryCategory,action:RecoveryAction,
 project_id:Option<String>,thread_id:Option<String>,message:String,
 worktree:Option<WorktreeRecoveryPreview>
}
RecoveryScope = Application | Project | Thread
RecoveryCategory = ProcessLease | ToolCatalog | Repository | Storage
RecoveryAction = None | Retry | CleanupThread | RemoveProject | CleanupWorktree
WorktreeOwner = Session | Child
WorktreeRecoveryPreview {
 owner_kind:WorktreeOwner,owner_thread_id:String,lease_revision:u64,state:String,
 repository_root:String,path:String,branch:String,base_commit:String,head_commit:Option<String>,
 dirty:bool,changed_files:Vec<String>
}
McpValue {desired_config_fingerprint:String,applied_config_fingerprint:String,health:McpHealth}
McpHealth {mcp_servers:Vec<McpServer>,active_mcp_servers:Vec<String>}
McpServer {id:String,transport:String,endpoint:String,source_kind:String,mutation_policy:String,state:McpServerState}
McpServerState = Disabled{message:String} | MissingCredential{message:String} |
 Checking{message:String} | Available{checked_at:i64,tool_count:u64} |
 Unavailable{checked_at:i64,error:SourceStateError}
LspHealth {lsp_servers:Vec<LspServer>,active_lsp_servers:Vec<String>}
LspServer {id:String,display_name:String,extensions:Vec<String>,language_ids:Vec<String>,state:LspServerState}
LspServerState = Checking{message:String} | Disabled{message:String} |
 Unavailable{checked_at:i64,error:SourceStateError} |
 Available{checked_at:i64,diagnostic_count:u64,activity:LspActivity}
LspActivity = Idle | Busy{title:Option<String>,message:Option<String>,percentage:Option<u32>} |
 Indexing{title:Option<String>,message:Option<String>,percentage:Option<u32>}
```

Recovery业务顶层是Vec<RecoveryIssue>，action为单enum非Vec，删除旧合同虚构的actions页。
blocksAccess等资格从原已定义scope/category/action语义派生，不添加假native字段。
MCP/LSP的SourceStateError复用D0三字段类型，Checking不等于健康，未知百分比不补零。
LSP只观察全局来源，probe/repair命令可带project不意味增加per-project健康事实。

## 9. Skills

```text
SkillsValue {project_id:String,config_fingerprint:String,catalog_revision:u64,catalog:SkillCatalogValue}
SkillCatalogValue {project_dir:String,skills:Vec<SkillSummary>,warnings:Vec<String>,complete:bool}
SkillSummary {
 name:String,description:String,category:Option<String>,platforms:Vec<String>,
 source:SkillSource,provider_id:String,invocation:SkillInvocationPolicy,
 resource_base:SkillResourceBase
}
SkillSource = Project | User | System | External
SkillInvocationPolicy {model_invocable:bool,user_invocable:bool}
SkillResourceBase = Directory{path:String} | Url{url:String} | Opaque{description:String}
```

上述按现有公开SkillSummary序列化投影列字段。SkillMetadata.path原有serde(skip)，HTTP/
SSE不序列化，FRB也不投影；本次不新增该内部path字段。SkillProviderId原为transparent
String，构造只用trim判空且保原文，不能新加字符集/长度cap。complete和warnings是
真实产品事实，不能遗漏或以列表非空替代complete。ResourceBase.Opaque只保原opaque描述，
不授权本次把其它已知schema转JSON。scoped projectId冻结在open中，header里通过ReadText
可达，不重复放每个Data帧。

## 10. Persistence与PersistenceQueue

权威为runtime `studio/persistence.rs`、protocol `studio/persistence.rs`与产品event wrapper。

```text
PersistenceValue {revision:u64,state:PersistenceStatus}
PersistenceStatus = Ready{pending_commits:u64} |
 Flushing{pending_commits:u64,oldest_pending_revision:Option<u64>} |
 Degraded{pending_commits:u64,oldest_pending_revision:Option<u64>,first_failed_at:i64,error:SourceStateError} |
 Recovering{pending_commits:u64,oldest_pending_revision:Option<u64>,first_failed_at:i64} |
 Blocked{pending_commits:u64,oldest_pending_revision:Option<u64>,first_failed_at:i64,error:SourceStateError}
PersistenceQueueValue {revision:u64,updated_at:i64,queue:PersistenceQueueSnapshot}
PersistenceQueueSnapshot {
 statistics_gap:bool,pending_operations:u64,pending_bytes:u64,in_flight_bytes:u64,
 oldest_pending_age_millis:Option<u64>,last_error:Option<String>,pressure_paused:bool,
 threads:Vec<ThreadPersistenceSnapshot>
}
ThreadPersistenceSnapshot {
 thread_id:String,fault_generation:u64,fault:Option<HistoryFault>,state_dirty_revision:Option<u64>,
 state_saving_revision:Option<u64>,state_durable_revision:Option<u64>,
 history_admitted_sequence:Option<u64>,history_durable_sequence:Option<u64>,
 calls_admitted_sequence:Option<u64>,calls_durable_sequence:Option<u64>,
 pending_operations:u64,pending_bytes:u64,oldest_pending_age_millis:Option<u64>,
 in_flight_bytes:u64,last_error:Option<String>,pressure_paused:bool
}
HistoryFault = QueueFull | WriteFailed | WriterUnavailable | NoProgress | CheckpointFailed | BlobFailed
```

外层revision/updated_at只来自产品发布wrapper；retryThreadHistory/resume原raw响应没有
这些值，不伪造一个versioned状态盖掉push。所有nullable水位保None，calls水位不代history。
last_error是原文本，Read中完整可达，不因header只has_last_error就删正文。

## 11. Updates

完整11状态的数字/时间/错误与产品合同§4.4一致。唯一顶层业务值UpdatesValue的variants：

```text
Disabled{revision:u64,updated_at:i64} | Idle{revision:u64,updated_at:i64} |
Checking{revision:u64,operation_id:String,started_at:i64} |
UpToDate{revision:u64,checked_at:i64} |
Available{revision:u64,checked_at:i64,update:UpdateSummary} |
Downloading{revision:u64,updated_at:i64,update:UpdateSummary,downloaded:u64,total:u64} |
Verifying{revision:u64,updated_at:i64,update:UpdateSummary,downloaded:u64,total:u64} |
Ready{revision:u64,ready_at:i64,update:UpdateSummary} |
InstallerLaunched{revision:u64,launched_at:i64,update:UpdateSummary} |
CheckFailed{revision:u64,failed_at:i64,error:SourceStateError} |
InstallFailed{revision:u64,failed_at:i64,update:UpdateSummary,error:SourceStateError}
UpdateSummary {version:String,published_at:i64,notes_url:String}
UpdateAsset {url:String,size:u64,sha256:String,signature:String}
UpdateDetails {summary:UpdateSummary,installer:UpdateAsset}
```

UI materialized UpdatesValue沿原FRB摘要三字段，source完整StudioUpdate另有installer；
不得因GUI没有显示就擅自删除server原公开字段。Updates Data新增
`details:Option<UpdateDetailsReadRef>`（entry/revision）；所有有update的六个variant均有值。
UpdatesPort.openDetails(ref,{required ProductReadOrigin origin})返回UpdateDetailsReadConnection，header为UpdateDetailsRead
（本节summary/installer全部字段按Read转换），带text/requestClose/close/retryClose，同
scope/call预算。details ref只在完整StudioUpdate真实改变时变化，不随下载计数改变。
完整UpdatesReadScope.header的update字段使用UpdateDetailsRead，保server全部公开值；
SDK UI UpdatesValue仍只借摘要，不将installer塞回原FRB摘要或随进度物化。高频summary/operation/error窄引用沿产品合同，不每次
字节进度重读完整状态。error只有一份retryable事实，brief的同字段是同revision派生值。

## 12. 来源定位与剩余闭合

- Configuration/Models/Templates：pl-protocol `studio/settings.rs`、`account_catalog.rs`；
  Profiles：`agent_profile.rs`与runtime `protocol/event.rs`；Mode：`thread/mode/mod.rs`。
- Usage：runtime `account_usage.rs`与`account_usage/state`；Performance/Costs：runtime
  `protocol/event.rs`、`studio/storage/calls/performance.rs`，计费枚举来自protocol `billing.rs`。
- Directory：protocol `thread/mod.rs`、`studio/query.rs`，runtime `studio/records.rs`与
  `protocol/{event,runtime}.rs`；Recovery：runtime `studio/runtime_state/mod.rs`。
- MCP/LSP：runtime `protocol/{mcp_server_state,lsp_server_state}`；Skills：pl-tool `skill`
  的真实serde来源与server `skills_schema.rs`公开schema。
- Persistence：runtime `studio/persistence.rs`与protocol `studio/persistence.rs`；Updates：
  runtime `studio/runtime/updater/state`、`updater/types.rs`及手写FRB convert/runtime/updater。

本册字段闭包已覆盖19域主体，仍有明确待核项，不能视为整包已准入：

- [x] AgentState全部variants、Skills内部path与实际wire差异、Updates server installer可达。
- [x] Performance sample entry的真实稳定source key；新IdentityScope按本节具名方法与共同读取能力实现。
- [ ] 各域materialized只读Repository state的加载/旧版本身份，以及所有typed页/实体读取
      统一方法签名与公共文件表；HTTP/SSE/OpenAPI端到端映射在单独接缝册闭合。

不把以上缺口留给executor设计；root继续核定，不运行中间编译/测试/生成。
