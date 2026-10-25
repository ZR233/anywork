# v4 Conversation／草稿／输入持久化接缝

本文件固定D1的领域借用、草稿动作和提交证据，补充[领域port](./v4-domain-ports-contract.md)、
[Thread wire](./v4-thread-wire-contract.md)、[生命周期](./v4-lifecycle-contract.md)。
基线/批准计划/所有权沿[共享合同](./v4-shared-contract.md)。这不是旧Client的代理表；D1
唯一拥有Conversation canonical归并、提交和附件ledger，U2是真VM与展示owner。
末尾未闭合项仍阻止整包编码，不把本文件存在当作已实现或放行。

## 1. Session借用与五域观察

Session是运行时owner，不用Freezed。Workspace唯一选择owner通过装配能力发布需求，读取
Session、观察当前选择或VM rebuild本身不admit native资源。公共能力与装配能力分开：

```text
ConversationRepository
  active:ReadonlyLatestValue<ConversationSession?>
  activationFailure:ReadonlyLatestValue<ConversationActivationFailure?>
  retryActivation({required String threadId,required int selectionGeneration})->void
  existingSession(String threadId)->ConversationSession?
  session(String threadId)->ConversationSession
  seal()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>

ConversationDemand                         // 仅conversation_ports与组合根可见
  select({required String? threadId,required bool needsOpen,
          required int selectionGeneration})->void
  retire(String threadId,{DateTime? deadline})->Future<CloseReport>
  retrySelected(String threadId)->void

ConversationSession                       // 公共借用能力，消费者不能close整个Session
  threadId:String
  execution:ReadonlyLatestValue<ThreadExecutionState>
  metrics:ReadonlyLatestValue<ThreadMetricsState>
  context:ReadonlyLatestValue<ThreadContextState>
  configuration:ReadonlyLatestValue<ThreadConfigurationState>
  authoring:ReadonlyLatestValue<ThreadAuthoringState>
  timeline:ConversationTimeline
  retry(ThreadFacet facet)->Future<void>
ThreadFacet = execution | metrics | context | configuration | authoring
```

`session`仅创建/取得Dart镜像，取得readModel permit，不启动源；`existingSession`不创建。
`active`指具体Session实例，而非threadId别名。需求首次同步登记selection generation，
needsOpen=true不启动；更换需求先撤回active，再退役原attempt，新Session就绪前不可借旧
同ID句柄充数。五域有独立连接/ready/错误/重同步，retry某域不刷新Timeline或重放命令。
retired planner child按Thread合同cold规则，不把所有child当retired。资源不足如实发布错误，
不回收尚在途owner；同Thread的live域共享原native assembler/incarnation，不重建五个执行者。

`ConversationActivationFailure {threadId:String,selectionGeneration:int,error:StudioFailure}`
是Freezed失败值，不含Session、Future或permit。它仅记录已选需求尚未得到Session时的准入
失败，唯一writer仍为该ConversationRepository；active仍借具体Session，不改成值对象。
选择替换、needsOpen或seal使旧失败失效；同步通知重入后必须重新核原选择才能发布后续结果。
创建失败保原typed诊断和私有cause，不留下未登记的局部资源；已创建的Session内部连接/上下文
失败仍由原五域/Timeline状态表达，不复制到activationFailure。

`retryActivation`只重试当前同threadId/generation、needsOpen=false且尚无Session的失败准入；
封闭时Cancelled，目标或代次已过时为Superseded，同目标已激活则幂等无操作。重试不制造
新的selectionGeneration，不触发Workspace.open/ensure，不重连已有Session的五域。
直接`session(threadId)`的非选择借用失败仍返回原typed错误，不改变当前选择的失败槽。
装配只转交Workspace唯一选择需求；Workspace VM同步观察这个只读失败值，并按当前选择身份
呈现/重试，不自建错误owner或通过页面重建掩盖准入失败。

每个`Thread<Facet>State`是Freezed值，共同字段为`stamp:ThreadFacetStamp?`、
`sync:FacetSyncState`与本域`value`；初始stamp/value均null。具体value类型固定为：

| State | value |
| --- | --- |
| ThreadExecutionState | ThreadExecutionBaseline? |
| ThreadMetricsState | ThreadMetricsValue? |
| ThreadContextState | ThreadContextValue? |
| ThreadConfigurationState | ThreadConfigurationValue? |
| ThreadAuthoringState | ThreadAuthoringBaseline? |

`FacetSyncState {phase:FacetSyncPhase,error:StudioFailure?,retryExhausted:bool}`；
`FacetSyncPhase=idle|connecting|ready|reconnecting|failed|closed`。它只描述源连接，不替代
canonical业务状态，重连/失败保last-known value及其原stamp，不将其标为新owner ready。
ThreadExecutionBaseline里的interaction index是引用，不是已加载完整问题；领域查询服务
唯一组装所需实体，VM不写其索引。ViewState可以借不可变领域值，不复制另一canonical reducer。
上述类型是纯Dart领域值，不是FRB生成类型；各facet header/Read DTO沿Thread合同字段全集。
选中需求与operation证据需求在同一D1 owner内分别登记。切走选择可以退役Timeline/UI demand，
但不能关闭尚被受理操作借用的execution/storage观察；active仍只表示选中的Session，不
因为后台保存观察把旧Thread重新选中。退出封所有新需求后统一join两类借用。

## 2. Timeline保持唯一正文路径

以下能力沿已有typed Timeline实现迁移，不恢复公开initial/next pull泵、不新增正文缓存：

```text
ConversationTimeline
  state:ReadonlyLatestValue<TimelineConnectionState>
  ready:Future<StudioTimelineBaselineFrame>
  attachConsumer(TimelineFrameConsumer consume)->TimelineConsumerLease
  openScope({required int generation})->StudioTimelineQueryScope?
  refresh()->void
TimelineFrameConsumer = FutureOr<void> Function(StudioTimelineFrame frame)
TimelineConsumerLease
  isClosed:bool
  requestClose()->void
  close()->Future<void>
StudioTimelineQueryScope
  generation:int
  attemptId:AttemptId
  threadId:String
  pendingQueries:int
  isActive:bool
  page({String? before,int? limit})->Future<StudioTimelinePage>
  readDetail({required String itemId,required StudioTimelineDetailQuery query})
    ->Future<StudioTimelineDetailChunk>
  retire()->void
  close({DateTime? deadline})->Future<CloseReport>
TimelineConnectionState {
  threadId:String,phase:TimelineConnectionPhase,attemptId:AttemptId?,
  lastStamp:ViewStamp?,error:StudioFailure?,retryExhausted:bool
}
TimelineConnectionPhase = idle | opening | ready | reconnecting | failed | closed
```

TimelineConnectionState是新Freezed连接值，只承载连接水位/诊断，不继续把可靠正文放latest snapshot供第二消费者
遍历。consumer是唯一有序正文交接，完成转换、归并及必要UI交接后ACK；第二个实际认领
同步typed Conflict，closing优先Cancelled。getter不认领。ready只证明源baseline，不证明
UI已经应用，更不证明durable。page默认32、1..100；详情UTF-8块4B..256KiB，默认64KiB。

U2首await前捕获具体Session、selection binding、consumer binding和最新candidate；不仅
按threadId比对。所有未发布候选、旧consumer、scope与canvas mounts均被实际owner登记。
关闭query/consumer只结束其借用，不清草稿、不关闭Session。查询仍在途时close等待原工作；
错误不得永久缓存成可恢复失败的假终态。整个Session close/retryCleanup由D1收束未解决
owner，细节依生命周期合同，不能用Stream.cancel或timeout当join。

## 3. 草稿公共值和动作

草稿只由DraftsRepository写。VM管理校验、呈现及平台交互，可以借完整不可变草稿引用；
不能保留另一份canonical文本、附件集合或冻结操作。UI Controller只管理selection/composing。
草稿句柄与Repository持有Future/ledger/permit，均不是Freezed。

```text
DraftsRepository
  composer(String threadId)->ComposerDraft
  start(String projectId)->StartDraft
  startRoutes:ReadonlyLatestValue<StartRoutePreferences>
  setStartModel(ThreadModeId mode,String accountId,String modelId)->void
  setStartEffort(ThreadModeId mode,String effort)->void
  seal()->void
  close({DateTime? deadline})->Future<CloseReport>
  retryCleanup({DateTime? deadline})->Future<CloseReport>

ComposerDraft
  threadId:String
  state:ReadonlyLatestValue<ComposerDraftState>
  setText(String text)->void
  addLocalFiles(List<String> paths)->OperationTicket<Unit>
  addRemoteUrl(String url)->OperationTicket<Unit>
  addClipboardImage(Uint8List pngBytes)->OperationTicket<Unit>
  removeAttachment(String attachmentDraftId)->OperationTicket<Unit>
  discard()->OperationTicket<Unit>
  submit({Future<void> Function()? preparePresentation})->OperationTicket<SubmitPromptReceipt>

StartDraft
  projectId:String
  state:ReadonlyLatestValue<StartDraftState>
  setText(String text)->void
  setMode(ThreadModeId mode)->void
  setWorkspaceMode(ThreadWorkspaceMode mode)->void
  addLocalFiles(List<String> paths)->OperationTicket<Unit>
  addRemoteUrl(String url)->OperationTicket<Unit>
  addClipboardImage(Uint8List pngBytes)->OperationTicket<Unit>
  removeAttachment(String attachmentDraftId)->OperationTicket<Unit>
  discard()->OperationTicket<Unit>
  submit()->OperationTicket<StartNewThreadResult>
```

只读借用不授予关闭整个draft owner的能力；显式discard仅放弃当前draft所有权，不删除
仍被冻结提交持有的附件。编辑方法是本地同步意图；不能为了统一ticket而伪造native保存。
异步附件动作无native CommitReceipt，实际完成用acknowledged，未知admission仍保预算与
归属。原未决submission禁止原stamp重发，但允许编辑形成新stamp；未知旧操作及其冻结
引用仍保留，不能因新输入而自动释放或断言旧请求未受理。

完整Freezed草稿值：

```text
ComposerDraftState {
 stamp:DraftStamp,text:String,attachments:List<AttachmentMetadata>,
 attachmentGeneration:int,submissionRevision:int,submission:DraftSubmissionState,
 cleanupIssues:List<AttachmentCleanupIssue>
}
StartDraftState {
 stamp:DraftStamp,text:String,attachments:List<AttachmentMetadata>,
 attachmentGeneration:int,submissionRevision:int,submission:DraftSubmissionState,
 cleanupIssues:List<AttachmentCleanupIssue>,mode:ThreadModeId,
 workspaceMode:ThreadWorkspaceMode,preparation:NewThreadPreparation?
}
DraftSubmissionState = idle
 | submitting{operationId:OperationId,inputId:String}
 | failed{operationId:OperationId?,inputId:String?,error:StudioFailure}
 | unknownOutcome{operationId:OperationId,inputId:String,error:StudioFailure}
AttachmentCleanupIssue {attachmentDraftId:String,error:StudioFailure}
AttachmentMetadata {
 id:String,modality:AttachmentModality,mediaType:String,filename:String,
 byteSize:int,width:int?,height:int?
}
AttachmentModality = image | video | file
StartRoutePreferences {
 models:Map<String,StartModelIntent>,efforts:Map<String,String>
}
StartModelIntent {accountId:String,modelId:String}
NewThreadPreparation {
 projectId:String,inputId:String,workspaceMode:ThreadWorkspaceMode,
 progress:ThreadPreparationProgress?,phase:NewThreadPreparationPhase,failure:StudioFailure?
}
NewThreadPreparationPhase = preparing | failed | unknownOutcome
ThreadPreparationProgress {
 projectId:String,inputId:String,stage:ThreadPreparationStage,workspacePath:String?,branch:String?
}
ThreadPreparationStage = checkingProject | preparingWorkspace | resolvingRepository |
 creatingWorktree | initializingSession | submittingPrompt
```

StartRoutePreferences的key是原mode.id，保留按mode而非按project的意图寿命，不用displayName。
新草稿默认mode.simple/workspace local仅为原本本地初始编辑值，不冒充后端resolved策略。
StartDraftState将原两个project文本/附件draft合到单一owner，单stamp同时版本化这两种编辑，
不保原StartSessionDraft与AttachmentDraftBoard的双份文本。全局新建单提交准入仍保留：
不同project编辑可以并存，一次创建未结算时不并行发起第二次创建。代次变化不清其它project。

没有previewBytes放在上述Freezed值中。原`final Uint8List`不是不可变；原图/预览按需读后
给UI构造ImageProvider，图像buffer/Provider不是canonical状态。D1提供
`readDraftAttachment(String draftId)->Future<Uint8List>`与
`readThreadAttachment(String threadId,String attachmentId)->Future<Uint8List>`只读能力；
每次返回由调用方独占的bytes，不暴露adapter共享可变buffer。任务归D1登记并参与close，
UI请求失效只阻止旧展示，不能丢真实query归属或将另一Thread的图复用进来。

## 4. 冻结提交与附件时序

1. submit入口不是async：首await前校验owner/目标/源可用性/重复准入，复制text与附件ID，
   固定具体Session或project选择binding、DraftStamp、OperationId、inputId、mode/workspace
   mode、route及route revision；登记操作、预算、冻结附件引用后才返回ticket。
2. 传输输入为`StudioPromptInput {inputId:String,text:String,attachmentDraftIds:List<String>}`。
   text仅在原submit边界trim；不把编辑中的raw文本主动trim。inputId由该operation生成，
   未知结果不换ID重试。已有Thread按冻结route revision CAS；新建携完整冻结route，不先
   保存全局默认。能力校验在native按冻结Thread或mode上下文解析，不能信UI抄来的capability。
3. 已有Thread的preparePresentation在冻结后、dispatch前等待。真实准备失败是已知未受理，
   保留草稿与原History。纯选择变化只结束旧显示前置，不更换提交目标；app钩子不能以
   Widget dispose丢失原任务，也不能把当前新Thread准备结果当旧目标准备完成。
4. 成功后校验返回threadId/inputId；附件只转移该operation的冻结引用，且仅在当前stamp
   仍等于冻结stamp时清文本/对应附件。提交期间新的编辑不被旧finally覆盖。
5. 明确拒绝释放该operation引用但保草稿；未知结果保冻结输入、引用和预算；已成功确认后
   mirror/cleanup失败使用acknowledgedSyncFailed或真实receipt对应syncFailed，不改成
   rejected/unknown。typed dispatch证据沿失败合同，不通过异常文案猜“没执行”。
6. 新建进度只结算原project/input/operation；终态成功/明确失败只结算一次。没有终态的EOF
   或传输失败为UnknownOutcome，不自动创建替代Thread。新建成功是否自动选中由Workspace
   原selection generation裁决，Drafts不能成为第二selection writer。

附件ledger仍是原draft与operation双归属：最后一个owner释放时才native删除。clipboard
stager签名`Future<String?> Function(Uint8List)?`、cleanup签名`Future<void> Function(String)?`
仅在drafts_ports装配，进入异步前复制bytes；路径/回调/cleanup Future不进Freezed。staging
为空或dispatch前失败明确未受理；native已dispatch无结果保unresolved admission，不能只
按已返回附件ID清理。迟到成功先登记真实metadata/permit归属再决定采用或清理，禁止空隙丢owner。
已开始的staging/admission/preview/delete及失败清理均参与Repository close/retryCleanup。

## 5. SubmitPromptReceipt与真实输入持久化证据

```text
SubmitPromptReceipt {
 threadId:String,inputId:String,cursor:int,requestDigest:String
}
InputAcceptanceEvidence {
 acceptedSequence:int,requestDigest:String?,disposition:PersistedInputDisposition
}
PersistedInputDisposition = consumed | discarded

ConversationCommandPort
  submitPrompt(String threadId,StudioPromptInput input,
               {required int expectedModelRouteRevision})->Future<SubmitPromptReceipt>
  readInputAcceptance(String threadId,String inputId)->Future<InputAcceptanceEvidence?>
```

新增requestDigest由Rust原`prompt_request_digest(request,presentation)`在真实受理/幂等命中
路径计算并返回，格式严格`sha256:`+64小写hex；Dart不复刻序列化或摘要算法。cursor保留
原名与语义，它是accepted_sequence，不是history/chat保存水位。不新增外部operation去重
表，原驻留完整request/presentation比较和持久request_digest比较继续保留。
R同步扩充StudioSubmitPromptResponse及新建结果内的同一receipt，A机械转换，server
OpenAPI/demo/fake/tests全部迁移；不保只有三个旧字段的兼容构造或缺摘要默认值。

本提交原本没有通用native CommitReceipt，因此D1用真实SubmitPromptReceipt作为
`CommandResult.acknowledged`的value，**删除原Dart临时构造input ResourceStamp和伪造
CommitReceipt的路径**。输入确实被观察/effective/durable可由后续独立原事实推进同一
OperationState；result在受理确认和必要附件转移完成后结束，不等待所有未来Turn或durable。
已确认结果不因晚到证据重写Future；同步失败留同一operation记录。

`readInputAcceptance`是窄typed纯查询：直接读取现有HistoryStore.input_identity，
不ensure执行owner、不activation、不新建表/写入或迁移，不对外暴露整个持久InputRecord。
查询绑定原runtime、Thread存储目标与inputId；返回行在查询时已经持久，consumed/discarded
来自原InputState，若发现Pending持久索引行是Protocol/Storage错误，不冒充已消费。
原core digest不是requestDigest，不能替换。未知旧数据的request_digest=None保留None。
不在返回值重复无界业务ID；参数及查询owner已固定目标。该call使用共用runtime64在途
详情额度，D1登记真实query并join，不为每个操作建立额外feed/registry或正文缓存。

D1的独立证据观察：

- 同步登记原Thread storage durable来源并立即读一次，随后只在真实durable水位变化时
  触发读取；合并同input在途和dirty需求，无timer轮询。通知只表示“可以再查”，不是保存证明。
- query结果只有在冻结thread/input匹配、acceptedSequence等于receipt.cursor、非空
  requestDigest等于receipt.requestDigest时才允许标durable并标identity observed。
  consumed可同时证明输入已被消费/effective；discarded不伪造模型执行已生效。
- 原索引仅存非Pending输入，故该证明可能延后；等待排队时durable保持未证明。无行/无
  digest不等于未受理，不能重发。序号或摘要矛盾报typed Protocol/Conflict并保原证据，不
  以任意更大的数字满足。读取失败保typed诊断，不让失败query悬空或完成成false成功。
- 执行域已观察到匹配input的真实Turn可独立证明observed/effective；仅按原准入/执行状态
  判断，不用目录状态或任一saved为durable。每个Turn item saved只证明该item该revision，
  不聚合成input全部输出保存完成。
- observer permit与必要source demand归operation owner；切路由不丢，close统一收束。
  durable成立后可释放此只读保存观察；尚无effective的discarded操作不能继续无限等一个
  永不会出现的Turn，按已知discarded事实结束其观察，effective仍false。

UnknownOutcome没有可验证的完整receipt时保持未知及冻结引用；本接口不新增自动unknown
恢复，不从缺行推导拒绝，也不因重新读取创建另一条发送。所有源事实、失败和预算都计入
原operation，禁止旧Timeline snapshot遍历成为第二正文消费者。

原事实定位：`prompt_runner/submit.rs`驻留/持久幂等路径、`thread_projection/content.rs`
的host摘要、`storage/history.rs::input_identity/commit_checkpoint_effect`、
`storage/thread_writer.rs::terminal_input_identities`与提交成功后durable发布。无新DB迁移。

## 6. 本轮仍未闭合的接缝

- [x] Session借用/五域状态、Timeline唯一consumer、草稿值/动作/冻结与可靠输入身份语义。
- [ ] 所有Thread详情materialized DTO与Repository查询签名、respond/route/mode/stop完整回复。
- [ ] 新建进度连接的有界typed运输/终态/取消签名、跨Workspace创建后选择回调及归档清理。
- [ ] 附件大字节typed读取的native/FRB/HTTP方法与分块生命周期；不能只凭上述Future bytes
      就声称wire预算已满足。
- [ ] 共享公开新文件与barrel、server路由/OpenAPI、VM精确消费与最终验证矩阵。

以上未完成项由root继续定稿；执行者不能自行补公用类型或改变字段。按v4只编辑源码/文档，
中途不执行编译、测试、生成、格式化或GUI。

## 7. 最终验证增量（现在只迁测试源码，不运行）

优先改造已有完整行为用例，不为新DTO构造/字段回读另增用例。C拥有现有测试消费者迁移，
D1/R提供生产语义，root在全部手写完成后执行并取得同一真实回归的红绿证据。

| 风险/旧保护 | 最小充分层级与最终判定 |
| --- | --- |
| studio_drafts_test中“accepted input waits for Chat Turn saved”旧断言 | 重写该真实draft提交用例：receipt返回可先acknowledged；任一匹配Turn.saved/terminal仍不durable；无row、缺摘要或错误摘要/序号均不成功，只有匹配持久identity才durable；原ticket.result不被晚证据改写 |
| 同文件冻结route、较新编辑保留、UnknownOutcome/创建EOF保护 | 迁到新Drafts公共入口并保原断言；无Timeline正文观察依赖，不为每种mode复制用例；纯选择变化不改冻结请求，准备真失败使native submit次数为0 |
| client_query_lifecycle/timeline_query_scope的真实在途gate | 复用门闩交错保护identity query：storage多通知合并为在途+dirty，不轮询；退役选择仍保operation观察，close未join前permit不释放，迟到查询不写同ID替换owner |
| runtime既有history身份/迁移专项 | 在允许的存储专项中复用真实临时SQLite，检验同事务提交前查不到/提交后digest与cursor一致，Pending与缺摘要旧行不误证，失败事务不发布durable事实；不在其它crate新增私有接口测试 |
| 跨FRB requestDigest映射与原生保存 | 统一最终原生发送/冷恢复旅程核同一input；隔离本地供应商、真实bridge/history与进程回收。Dart fake只证明归并规则，不能替代此证据 |

没有将测试执行、原生验收或红绿证据记为已完成；当前仅有静态合同核对。
