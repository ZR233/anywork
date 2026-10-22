# v4 Interaction、Mode 与 Timeline 呈现接缝

本文件补齐 [Presentation 合同](./v4-presentation-contract.md) 中三个有独立生命周期的接缝。
这是 root 的接口决定，不是已完成实现／测试；其他 VM、产品 wire 和逐文件 manifest 未齐，
仍不释放整包编码。所有值均为 Freezed，所有计数/索引为非负 Dart int；下文运行时 binding
例外。`StudioFailure`、`OperationState` 来自共享领域，不能以 Object 或字符串猜错误分类。

## 1. Interaction：完整读取与允许空答案分开

### 1.1 保留的业务事实

现有 `user_input_dock.dart` 允许用户提交未作答的问题，提交数组中该题的 answers 为空；
不能因增加读取完整性检查而收紧为“每题必须作答”。只有原本空 questions 的 fallback
要求 trim 后非空，提交 `questionId="answer", answers=[trimmedText]`。

正常题目的 ID 使用 canonical 原字符串，不 trim、大小写转换或改成列表位置。现有
`pl-tool/src/ask_user.rs:89–103` 只校验 trim 非空及原 ID 唯一，并不归一化 ID；其 From
转换原样保存。因此旧 UI `_questionKey` 对非空 ID 的 trim 不能继续作为新 wire 身份规则。
对于其他来源／历史事实的空白 ID，保留旧 UI 的 `answer_<index>` fallback；该规则不扩大
正常工具写入的合法输入，也不回写或改造原问题。UI 行身份始终为 `(editorKey,index)`，
不能仅用可能相同的 label 或空 ID 合并两行。

选项仍按 label 值选择、去重，保留选择插入顺序；自由文本只在 `isOther` 或无选项时加入
答案，trim 后为空不追加。选项原 label 不 trim。None options 与 Some([]) 在数据状态仍不同，
两者在当前“无选项可自由输入”的 UI 准入相同。没有新增全题必填、固定选项数或正文长度上限。

Plan 决定仍是对应 canonical 问题的 typed user-input resolution：批准 `['Approve']`，
修改 `['Revise', feedback.trim()]`，修改反馈非空。识别依靠 typed purpose 和对应问题事实，
不扫描 raw JSON／仅凭特殊问题名猜 continuation；purpose 不是继续执行指令。
ToolApproval 保留 Approved/Denied 两种决定；reason.trim() 为空映 None，否则保留 trim 后值。

### 1.2 完整 ViewState 与局部值

`InteractionEditorKey` 沿用 threadId/incarnation/interactionId/revision 四字段。
读取 DTO 使用 [Thread wire §5.3](./v4-thread-wire-contract.md#53-interaction-完整读取面)；
以下名称 `QuestionReadItem`/`OptionReadItem` 分别指该节 Question/Option 的完整字段，而非旧
丢失 optional 信息的 `UserQuestionView`。D1 定义这些领域 DTO，U2 不另建同构 wire 模型。

```text
TextReadProgress {
  fieldId:int, totalUtf8Bytes:int, loadedUtf8Bytes:int, text:String,
  complete:bool, loading:bool, error:StudioFailure?
}
QuestionReadProgress {
  question:QuestionReadItem,
  options:List<OptionReadItem>, nextOptionOffset:int?, optionsLoading:bool,
  optionsError:StudioFailure?
}
QuestionAnswerDraft { selectedLabels:List<String>, text:String }
InteractionReadSection = header | questions | options | answerEntries | answerValues | text
InteractionReadIssue { section:InteractionReadSection, index:int?, fieldId:int?, error:StudioFailure }
InteractionSubmitBlock = readIncomplete | readFailed | sourceChanged |
  noLongerPending | operationPending | unknownOutcome | closing | disabled

InteractionViewState {
  key:InteractionEditorKey,
  scope:ReadScopeIdentity?, header:InteractionReadHeader?,
  questions:Map<int,QuestionReadProgress>, nextQuestionOffset:int?,
  answerEntries:List<AnswerEntryReadItem>, nextAnswerEntryOffset:int?, answerEntriesLoading:bool,
  answerValues:Map<int,List<AnswerValueReadItem>>, nextAnswerValueOffsets:Map<int,int?>,
  answerValueLoading:Set<int>,
  texts:Map<int,TextReadProgress>,
  currentQuestionIndex:int, questionPageLoading:bool,
  readIssues:List<InteractionReadIssue>, completingRead:bool,
  answers:Map<int,QuestionAnswerDraft>, fallbackText:String,
  approvalReason:String, planFeedback:String,
  enabled:bool, sourceCurrent:bool, closing:bool,
  latestIntent:int, submission:OperationState?,
  submitBlock:InteractionSubmitBlock?, submissionError:StudioFailure?
}
```

`Map<int,...>` 是固定类型的字段/索引查找，不是动态 JSON/Value DOM。相同 fieldId 必须属于
state.scope；新 scope 清掉旧读取进度而不是复用同数字的旧正文。Inline 文本直接取 DTO 值，
只有 Deferred 字段进入 texts；complete 当且仅当 UTF-8 连续前缀到原 total，无缺口/重叠。
None 与空字符串不合并。所有 header 字段、purpose、continuation 和 terminal payload 仍完整可读；
回答、理由和 secret 原文不进入 Driver／日志。`submission` 只读呈现原 operations 记录。

`questions`/`texts` 是此编辑器显式读取的呈现材料，不是新的全 Thread 缓存；只有一个编辑器
拥有这一组值。原生 scope/查询 Future、timer、Observation、取消/join 责任不进 ViewState。
typed read scope 的创建/登记/取消/join 属 D1，VM 私有借用并在结束编辑时同步封其准入，
真实完成由原 scope supervisor 收束，不能 ref.dispose 后遗弃查询或复用同 ID 新 Session。

### 1.3 VM 完整动作

同步返回 void：

```text
setEnabled(bool value)
setQuestionText(int questionIndex, String raw)
setOptionSelected(int questionIndex, String label, bool selected)
setFallbackText(String raw)
setApprovalReason(String raw)
setPlanFeedback(String raw)
```

返回 `Future<void>`，进度／错误只写本 key 的 state：

```text
showQuestion(int index)
loadNextQuestions()
loadNextOptions(int questionIndex)
loadNextAnswerEntries()
loadNextAnswerValues(int entryIndex)
loadText(int fieldId)          // 一个有界 chunk；续读使用已有实际 offset
completeRead()                // 用户明确需求，串行补齐提交所需的 typed 字段/页
retryRead()                   // 重试原 scope 读；Superseded 则重新取得当前身份，不发回应
submitAnswers()
approveTool()
denyTool()
approvePlan()
requestPlanRevision()
```

所有方法先核 closing/原 editor key；不存在／未加载的 questionIndex、option label、fieldId
不可凭 UI 参数创造 canonical 事实。错误落 typed state，不吞作空数据。`retryRead` 遇旧
revision 已失效时只结束旧 key 的读取并报告 sourceChanged，由 Smart 对新 canonical key
创建新编辑器；不在原 family 实例上篡改 key，不自动复制旧答案或重发 unknown 决定。

### 1.4 提交准入和时序

1. header 必须完整解码且对应当前 key；来源仍为相同 incarnation/revision 的 Pending。
2. 正常 UserInput：全部 question metadata、题干/header/ID、选项 label/description 和供 UI
   展示/决策的 purpose/continuation 文本必须完整可读；每题 isSecret 先于输入控件。选项页
   未完或 Deferred 必需字段未读完时显示读取进度和 completeRead，而不是把部分资料当全文。
   **读取完成不等于已作答**；空答案仍可提交。没有强制滚动到底或“已人工阅读”的虚假证明。
3. 空 questions：typed header 完成、fallback trim 非空即可，不能等待永远不存在的题目页。
4. ToolApproval：name、完整 arguments、workingDirectory 和实际展示的 parentAgentId 必须
   完整，不能凭摘要批准/拒绝。arguments 是唯一允许原有 opaque JSON 文本的字段；VM 不
   重新解释业务 payload。Plan 同样要求原确认问题/完整文档已读；旧文档不能回答新 revision。
5. terminal 历史阅读可以继续加载 answer entries/values，但不出现回应控件；不存在从终态
   重新打开模型/工具/continuation 的路径。详细历史读取由同一 typed scope 能力提供。
6. 第一条 await 前冻结具体 Session、四字段 key、答案/理由、OperationId 和 latestIntent。
   D1 接受后持有完整冻结 resolution 与 UnknownOutcome；VM 销毁不能删除已受理结果。
   每次 await 后核具体 binding/key/intent，旧 finally 不清新操作锁或新输入。
7. 成功仍等 canonical 身份观察；known-success + 观察失败为 syncFailed，unknown 不自动解锁
   再发。拒绝可保留输入供用户显式修正；真实 terminal 则结束该编辑器的可写资格。

### 1.5 Dumb 接口

`InteractionView(state:InteractionViewState, onShowQuestion:Future<void> Function(int),
onLoadQuestions/onLoadAnswerEntries/onCompleteRead/onRetryRead/onSubmitAnswers/onApproveTool/onDenyTool/
onApprovePlan/onRequestPlanRevision:Future<void> Function(),
onLoadOptions/onLoadAnswerValues:Future<void> Function(int), onLoadText:Future<void> Function(int),
onQuestionText:void Function(int,String), onOption:void Function(int,String,bool),
onFallback/onReason/onPlanFeedback:ValueChanged<String>, trailing:Widget?)`。

QuestionStep 的 UI-only TextEditingController/焦点可以留 View；唯一业务 raw/选项状态来自
VM props，controller 只同步当前文本、选区与 composing，不在 didUpdateWidget 重建/重置草稿。
键盘提交与按钮调用同一 VM 动作，不能在 Widget 再造另一套 canSubmit 或直接调用 Repository。

## 2. ModeEditor：唯一编辑会话

### 2.1 状态完整字段

下面 `ModeDocument`/workflow/validation/preview 均使用 modes 领域 Freezed 值；旧
`ModeEditorOwner` 删除。Mode JSON 原文是明确的用户 authoring 输入，不是实时 wire fallback。

```text
ModeEditorTab = graph | json | settings | preview
ModeEditorSelection = none | node {stateId:String} |
  edge {sourceStateId:String,targetStateId:String}
ModeEditorSnapshot { document:ModeDocument, jsonText:String, jsonApplied:bool }
ModeEditorNotice = draftCreated | imported | saved | deleted | copied
ModeLeaveChoice = save | discard | stay

ModeEditorViewState {
  catalog:ThreadModeCatalogView, selectedModeId:String?, catalogRevision:int,
  document:ModeDocument?, jsonText:String, jsonApplied:bool,
  orderText:String, orderError:ValidationIssue?,
  savedDocument:ModeDocument?, savedJson:String, savedRevision:int?,
  dirty:bool, readOnly:bool, busy:bool,
  undo:List<ModeEditorSnapshot>, redo:List<ModeEditorSnapshot>,
  tab:ModeEditorTab, selection:ModeEditorSelection, inspectorOpen:bool,
  query:String, validationRequested:bool, issues:List<ValidationIssue>,
  preview:WorkflowPreviewSnapshot?, previewReason:String,
  latestIntent:int, operation:OperationState?,
  error:StudioFailure?, notice:ModeEditorNotice?
}
```

undo/redo 各最多64项；UI 从列表推导 canUndo/canRedo，不维护第二份栈。不是每个键盘字符
都生成一次整文档 undo：沿用一次 JSON 编辑会话只登记入口快照，apply/选择/撤销结束该会话。
timer/keepAliveLink/command Future 不进值对象。catalog更新不覆盖 dirty document/raw JSON。
新增未保存文件的 savedDocument/savedRevision 为 None，不用默认文件假装已保存。

### 2.2 动作和编辑输入

同步动作：`setTab(ModeEditorTab)`、`setQuery(String)`、`select(ModeEditorSelection)`、
`setInspectorOpen(bool)`、`editJson(String)`、`setPreviewReason(String)`、`undo()`、`redo()`、
`discard()`、`edit(ModeEdit)`、`clearNotice()`。

`ModeEdit` 是 Freezed typed intent，不是 `ModeDocument Function(ModeDocument)`：

- `displayName(String)`、`description(String)`、`orderRaw(String)`、`prompt(String)`；
- `workflowTitle(String)`、`workflowGoal(String)`、`initialState(String)`；
- `addState(WorkflowState)`、`renameState(String oldId,String newId)`、`removeState(String id)`；
- `stateTitle(String id,String)`、`stateInstructions(String id,String)`、
  `stateCriteria(String id,List<String>)`、`stateKind(String id,WorkflowStateKind)`；
- `addTransition(WorkflowTransition)`、`removeTransition(String sourceId,String targetId)`、
  `transitionGuard(String sourceId,String targetId,String)`；
- `nodePositions(List<WorkflowNodePosition>)`、`enableWorkflow(WorkflowDefinition)`、`removeWorkflow()`。

`orderRaw` 的未通过 u32 校验原文留在 state.orderText/orderError，不能丢输入、转负数或
静默恢复原值。其它 typed 编辑
由 VM 检查目标存在/readonly/dirty JSON conflict，然后修改唯一 document 并登记 undo。
图形布局坐标计算可以留 UI-only canvas/controller；提交的 positions 是一次 typed intent，
图的语义增删、rename后的边/initial/position一致性仍归 VM，不让 canvas另持可写业务图。

异步动作：

```text
open(String modeId) -> Future<bool>
create(ModeDocument initial) -> void
importJson(String raw) -> Future<bool>
save() / delete() / reload() / applyJson() -> Future<bool>
validate() -> Future<void>
preview({String? targetStateId, bool reset=false}) -> Future<void>
readSchema() -> Future<String>
resolveLeave(ModeLeaveChoice choice) -> Future<bool>
```

Smart 只收集新增模板／复制／删除确认/leave choice及平台clipboard；预设模板是纯 immutable
输入（既有本地化初始文字），不得把 raw JSON 用宽容 Dart decoder吞未知字段再当合法文档。
`create(initial)` 不落盘。import/apply/validate 把原 JSON 交 Rust 严格 validator；未通过时保留
raw/旧有效document/typed issues。只接受 Rust 返回的成功 typed document。内置 readonly、
Mode ID `mode.`+1..59 ASCII小写字母/数字/`-`/`_`、256KiB文档、128用户Mode均不放宽。

save/delete/reload 在首 await 前冻结 modeId/catalogRevision/document/generation；冲突不
自动覆盖新文件，UnknownOutcome不重发。save成功只更新对应保存基线，不擅自清undo；
期间有新编辑时保留新raw及dirty。open/create遇dirty拒绝，必须先由resolveLeave得到许可；
stay不做事、discard恢复该编辑会话基线、save必须确认本次已知成功后才允许离开。
reload有真实磁盘导入副作用，不在build/普通观察中调用，也不覆盖dirty输入。

### 2.3 Dumb panels

- `ModeEditorView(state, onOpen:Future<bool> Function(String), onEdit:ValueChanged<ModeEdit>,
  onTab:ValueChanged<ModeEditorTab>, onQuery:ValueChanged<String>,
  onSelection:ValueChanged<ModeEditorSelection>, onInspector:ValueChanged<bool>,
  onUndo/onRedo/onCreateDialog/onImportDialog/onDeleteDialog/onCopy/onSchema:VoidCallback,
  onSave/onReload/onApplyJson:Future<bool> Function(), onValidate:Future<void> Function(),
  onJson/onPreviewReason:ValueChanged<String>, onPreview:Future<void> Function(String? target,bool reset))`。
- JSON panel保持 text/issues/error/readOnly/busy/validated 与 onChanged/onApply/onCopy/onValidate/
  onSchema；error由Smart从typed failure本地化，不由View捕捉业务异常。
- Settings/Inspector/Canvas共享document/readOnly/selection与 `onEdit(ModeEdit)`，不能分别
  产生完整document reducer。Canvas额外接UI-only本地化labels、onSelection与确认弹框callbacks；
  View只在已确认的callback之后发remove intent，不在画布内保存或刷新catalog。
- Preview panel保持 document/preview/reason/busy 与 onReason/onStart/onReset/onAdvance；
  preview只调用Rust预演，不改变真实Session Workflow或Mode保存水位。

## 3. Timeline：纯 UI binding 与 Smart 详情

运行时接口归 U2；不作 Freezed，不放 VM state：

```dart
abstract interface class TimelineCanvasBinding {
  String get threadId;
  int get displayGeneration;
  Key get chatKey;
  ChatController get chatController;
  ScrollController get scrollController;
  TimelineCanvasMount mount();
}

abstract interface class TimelineCanvasMount {
  void unmount();
}
```

mount 返回本次真实子树的唯一 token；unmount幂等、只解除该token，不退役Session、不关闭
query、不自行dispose Controller。多个/迟到实际挂载分别登记，不能一个bool遮掉另一个子树。
已释放binding明确拒绝mount；退役但未释放时仍登记迟到真实mount并等它unmount。
协调器真实等待写入、所有mount、query、consumer/candidate后才dispose，见生命周期合同。

ChatController只是给 stock Chat 组件的UI借用，View不得调用业务insert/replace/clear。
binding不暴露payload遍历、presentationFor、detailRef、openQueries、native handle或close。
行类型从同一controller的Message metadata读取；若需Smart详情行，由Connector传入
`messageBuilder: Widget Function(BuildContext, Message)`，Dumb只调用UI builder，不定位服务。

```text
TimelineViewState {
  threadId:String, generation:int, displayMode:live|history,
  connectionPhase:idle|opening|ready|reconnecting|failed|closed,
  connectionError:StudioFailure?, olderCursor:String?, hasOlder:bool,
  olderLoading:bool, olderError:StudioFailure?, hasNewOutput:bool,
  preparingLive:bool, ready:bool
}
```

`ready` 是当前已发布display可用事实，不由另一个Thread feed ready回填。没有Message数组。
Timeline VM公开 `enterHistory()->void`；`loadOlder()/retryOlder()/returnLive()/retryConnection()`
返回Future<void>。自动补齐页也走同一个loadOlder，在原generation内合并实际在途请求。
所有结果和finally绑定具体Session/binding/candidate/generation，不按当前threadId找查询owner。

详情与图片的具体读DTO沿Timeline领域合同；U2相应Smart持有自己的读取呈现状态和原
display key，Dumb只接完整值/进度/error与typed重试callback。原图文件/URL准入在领域/平台
边界，View不自己调用FRB或读native路径；网络ImageProvider factory由Smart装配后传入。
Flow/Plan/Todo不写Message数组；PlanPanelProps只代表Plan阅读与展开，回应/反馈唯一归
Interaction VM，不在Plan VM再复制一份答案或response operation。

## 4. 最终验证映射（当前不执行）

- Interaction：多页和多chunk、转义导致提前分页、None/Some(0)、isSecret先行、空answers允许、
  空questions fallback、原ID含首尾空白、重复label选择语义、旧revision和unknown不重发。
- Mode：unknown JSON字段/非法ID保留raw并拒绝；单栈64边界；graph/JSON切换同一document；
  save时新编辑不丢；保存和catalog刷新不抹dirty；delete/reload冲突及leave choice。
- Timeline：View不能触达query/FRB；同generation重复mount独立unmount；未发布candidate和
  多consumer join全覆盖；History内容冻结、回Live换controller/key；旧Session不借新query。
- 源码边界/测试迁移归C，局部实现归U1/U2；final门禁和原生旅程由root统一取得真实证据。
