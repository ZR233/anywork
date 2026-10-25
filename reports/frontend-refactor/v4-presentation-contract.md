# v4 Presentation 责任、family 与 UI 接缝

本文件由 root 冻结共享呈现责任；不是把 Widget 改名或包裹旧观察 Provider 当成真 VM。
批准计划见 [implementation-plan.md](./implementation-plan.md)。领域 port／DTO 和下方待完成
的具体状态表未齐之前，仍不释放全量编码。

## 1. 固定依赖与状态归属

`Screen/Connector → generated AsyncNotifier → domain public API`；Dumb View只接不可变state、
UI-only controller和typed callbacks。VM不得导入Widget/BuildContext/FRB/database/具体adapter；
build只登记观察或必要读取，不执行业务写入。首次无值用AsyncLoading/Error；有last-known时
局部保存/重连错误放Freezed ViewState，不抹空整页。同步状态和用户操作状态不能混成同一个布尔值。

VM拥有raw编辑、validation、dirty、debounce、latestIntent和交互编排。Repository拥有canonical
mirror、命令及已受理操作；长寿命Composer草稿/冻结提交/附件ledger不移进VM。模式JSON/graph/
undo统一进入ModeEditorViewModel，旧ModeEditorOwner删除，不留投影包装壳。

## 2. VM 清单、family 与保留

表中应用寿命使用生成式keepAlive；观察寿命使用生成式autoDispose。编辑期间的保留由页面
owner显式开关keepAlive，结束后释放并invalidate该key，不能永久累积family实例。

| VM | key／寿命 | 唯一职责 |
| --- | --- | --- |
| SettingsNavigationViewModel | 无；应用寿命 | 当前Settings tab、dirty离开协调；不保存Thread选择 |
| AccountsViewModel | 无；应用寿命 | query/filter、selectedAccountId、编辑身份、账号可见需求／结果 |
| AccountEditorViewModel | AccountEditorKey；编辑期 | 账号原始字段、密钥意图、模板/手工模型、校验、保存与部分成功 |
| AccountModelLimitsViewModel | accountId:String；详情期 | 每model阈值raw/校验/debounce/latestIntent；不从旧快照构造写入 |
| InstructionsViewModel | 无；应用寿命 | base/developer/user、文档限制raw、自动保存与局部错误 |
| GeneralSettingsViewModel | 无；应用寿命 | general开关、web search编辑/校验/逐字段保存、DeepSeek开关 |
| AgentProfilesViewModel | 无；应用寿命 | 搜索、系统profile启停、列表及diagnostics呈现 |
| AgentProfileEditorViewModel | ProfileEditorKey；编辑期 | profile字段/route/effort、校验与保存，不丢已有未解析选择 |
| ModeEditorViewModel | 无；应用寿命 | 单一document/rawJSON/jsonApplied、64步undo/redo、validate/preview/save/delete/reload |
| McpViewModel | 无；可见期 | 配置/运行态呈现、单server/全部reset、局部编辑与错误 |
| LspViewModel | projectId:String；可见期 | 项目probe/repair/reset意图；观察真实全局LSP，不伪造scoped feed |
| SkillsViewModel | projectId:String；可见期 | scoped目录/搜索/配置意图、warnings、active skills只读组合 |
| SshViewModel | 无；应用寿命 | 列表、按alias操作与错误、认证挑战／远程目录编排 |
| SshEditorViewModel | SshEditorKey；dialog期 | host/port等raw、password三态、managed限制、校验 |
| StatisticsViewModel | 无；可见期 | 筛选/展开/历史页/summary，TTFT按真实sample count |
| UpdatesViewModel | 无；应用寿命 | 更新可见进度与意图；下载/准备/句柄留领域owner |
| ComposerViewModel | ComposerKey；观察期 | draft投影、校验、send/stop/附件UI意图与latestIntent |
| InteractionViewModel | InteractionEditorKey；编辑期 | typed详情需求、答案/理由草稿、secret准入、respond CAS/unknown |
| PlanViewModel | threadId:String；展示期 | 文档身份/阅读需求/展开；反馈与决定唯一归对应Interaction VM，不从purpose猜continuation |
| TimelineViewModel | threadId:String；展示期 | Live/History、分页/重连/回实时/详情意图；不持Message数组 |
| ThreadMetricsViewModel | threadId:String；展示期 | 成对live/authoritative速度及unknown；不观察其他大域 |
| ThreadContextViewModel | threadId:String；展示期 | context、当前策略与冻结请求、压缩资格/意图/错误，无伪receipt |
| ThreadStatusViewModel | threadId:String；展示期 | 稳定execution/config/活动摘要；不订阅metrics |
| TodoViewModel | threadId:String；Conversation可见期，展开时读详情 | 只读Todo与面板可见意图，不发Todo修改命令 |
| WorkspaceViewModel | 无；应用寿命 | 目标意图、shell/persistence/recovery呈现；目标唯一writer仍是领域coordinator |
| SidebarViewModel | 无；应用寿命 | query/filter/archive/展开/分页/查询generation，目录仍由Repository归并 |
| StartupViewModel | 无；应用寿命 | 启动进度/错误/显式retry；bootstrap由app lifecycle发起 |
| ShutdownViewModel | 无；应用寿命 | 退出进度/问题/安装结果呈现；不拥有期限或关闭资源 |

keys完整字段：

- `AccountEditorKey {editorId:int, accountId:String?, initialTemplateId:String?}`；新建accountId=null，
  ID由Accounts VM同步分配，编辑不以displayName识别。
- `ProfileEditorKey {editorId:int, profileId:String?}`；编辑中不变更身份。
- `SshEditorKey {editorId:int, alias:String?}`；现有managed host按原约束锁定alias，不重命名凭据。
- `ComposerKey = start(projectId:String) | thread(threadId:String)`，不用两个nullable字段猜模式。
- `InteractionEditorKey {threadId:String, incarnation:int, interactionId:String, revision:int}`；
  新revision不自动发送旧答案，旧UnknownOutcome仍由原操作owner保留。

VM销毁只取消自身观察/timer，不能关闭跨路由Session、清草稿或清附件。处于已受理/unknown的
冻结提交不靠keepAlive维持，真实归属继续在领域层。

## 3. Freezed ViewState 的完整责任

每个VM有自己的state，不造所有页面共用的大可写State。source字段只保存所属Repository的
canonical只读值/stamp/typed同步状态；edit字段保留raw输入；validation按字段给typed问题；
operation呈现按OperationId/target/latestIntent隔离。Widget/Ref/handle/stream/Future不进state。

必须迁出StatefulWidget的编辑内容：

| 编辑面 | 必须保留的raw/edit内容 |
| --- | --- |
| Account | create/edit、冻结ID、template/name/protocol/baseURL、secret preserve/replace/clear与替换值、pricing、全部custom models/connection/autoCompact覆盖、validation/dirty、save和随后setDefault的独立结果 |
| Profile | ID编辑锁定、displayName/description/whenToUse/systemInstructions、account/model/nullable effort、enabled/workspaceMode、validation/dirty/save |
| SSH | alias/host/port原文/user/keyfile、password三态/rememberPassword、managed只读限制、test/auth/save不同错误；秘密不进入诊断快照 |
| General/Instructions | general两开关；web configured mode/context/domains/location；DeepSeek配置两开关；base/developer/user全文、文档byte限制raw和fallback filenames、有效待提交意图/debounce |
| Mode | document/rawJSON/jsonApplied/saved baseline/dirty/readOnly、选中node/edge/inspector/tab/query、issues、previewReason/preview、busy/error、undo/redo |
| Interaction | 原question ID对应的选项集合/自由文本、问题游标、fallback answer、approval reason、Plan feedback、完整读取状态、冻结CAS/operation、pending/error/unknown |
| Sidebar | query原文/normalized filter、all/running/attention、archive、expanded project IDs、query key/cursor/loading/error/generation，旧查询不盖新结果 |

Mode undo/redo每项是Freezed `{document:ModeDocument,jsonText:String,jsonApplied:bool}`，最多64项。
graph controller只投影坐标和交互，最终写回同一typed document。JSON/校验/保存失败留输入；
reload不覆盖dirty，保存成功不擅自清undo；内置readonly保留。

canonical变化只推进对应编辑基线，不能每帧invalidate重建输入。所有具体嵌套state/校验enum/
操作结果字段需在领域DTO与VM最终签名表中一致；本节责任清单不能代替尚未完成的字段定义。

## 4. Smart 公共入口

以下构造都可额外接Flutter Key；无Client/Repository/Ref/transport参数：

```text
WorkspaceScreen()
SettingsScreen(initialTab:SettingsTab?)
ConversationScreen(threadId:String)
ComposerConnector(target:ComposerKey, compact:bool=false)
InteractionConnector(target:InteractionEditorKey, enabled:bool, trailing:Widget?)
PlanConnector(threadId:String)
TimelineConnector(threadId:String)
ThreadStatusConnector(threadId:String)
ThreadMetricsConnector(threadId:String)
ThreadContextConnector(threadId:String)
TodoConnector(threadId:String, inDrawer:bool=false, onClose:VoidCallback?)
```

Widget/Key只出现在Smart/Dumb层，不是VM签名。Smart用ref.watch/select观察、ref.listen处理
导航/dialog/提示，业务意图调用VM。不得在build创建新editor key或开始写入。

## 5. Timeline 与 UI-only 借用

TimelineView不再接含query/业务能力的完整旧TimelineDisplayLease。Smart借出
`TimelineCanvasBinding`：只有当前chatController/scrollController/chatKey/displayGeneration及
真实mount/unmount登记能力，不开放openQueries/requestClose/native handle。它不是新正文owner，
controller仍归唯一展示coordinator；具体binding、挂载token和Smart行builder见
[编辑与展示接缝](./v4-editing-vm-contract.md) §3。

TimelineView固定props：`threadId:String, state:TimelineViewState, binding:TimelineCanvasBinding,
onLoadOlder/onRetryOlder/onReturnLive:Future<void> Function(), onEnterHistory:VoidCallback,
onRetryConnection:Future<void> Function(), plan:PlanPanelProps?=null, onPlanToggle:VoidCallback?,
messageBuilder:Widget Function(BuildContext,Message)`。
Plan展开只在PlanPanelProps表达，不保留第二个expanded状态。

TimelineViewState只含现有展示语义：threadId、generation、displayMode、connectionPhase、
connectionError、olderCursor、hasOlder、olderLoading、olderError、hasNewOutput、preparingLive、ready；
不含Message数组/lease/controller/Future/connection。具体字段与enum见编辑与展示接缝§3。
所有正文详情/图片读取由Smart或对应VM请求，Dumb内容组件只渲染typed值/加载/错误。

候选身份和退出遵循 [生命周期合同](./v4-lifecycle-contract.md)：捕获具体Session/binding，
新候选开始即使未发布也淘汰旧发布资格；详情query不动态借用同ID新Session。

## 6. U0 固定纯 UI 接缝

不视觉改版，不改theme/l10n/键盘/Driver key语义。通用组件不订阅provider，不解释业务结果。

- ModelRouteSelector：`options:List<ModelSelectionOption>, accountId:String, modelId:String,
  onSelected:FutureOr<void> Function(ModelSelectionOption), fieldLabel:String, selectorKey:Key,
  unresolvedLabel:String?, enabled:bool=true, tooltip:String?, onBlockedTap:VoidCallback?,
  labelMaxWidth:double=180, optionKeyBuilder:Key Function(ModelSelectionOption)?`。
- ModelSelectionOption：`accountId:String, accountName:String, accountIconKey:String?,
  descriptor:ModelDescriptor`；复合身份accountId+modelId，descriptor来自models领域最终策略，
  selector不重算资格/effort，不把未解析选择换第一项。
- ModeSelector：`modes:List<ThreadModeDescriptor>, selected:ThreadModeId,
  onSelected:ValueChanged<ThreadModeId>, enabled:bool=true, snapshotDisplayName:String?,
  usesSnapshot:bool=false`。原Consumer读取移到Connector。
- WorkspaceModeSelector：`mode:ThreadWorkspaceMode, onSelected:ValueChanged<ThreadWorkspaceMode>,
  enabled:bool=true`。
- EffortSelector：`efforts:List<String>, selected:String?, onSelected:ValueChanged<String?>,
  enabled:bool=true, pending:bool=false, blockedReason:String?, onExplain:ValueChanged<String>?`。
  null仍表示默认，effort保持开放字符串，不固定成四档。
- StatusBarItem：`label:String, icon:IconData?, trailingIcon:IconData?, tooltip:String?,
  semanticsLabel:String?, detailBuilder:WidgetBuilder?, detailWidth:double=300,maxWidth:double=180`；
  tooltip/detailBuilder互斥。
- StatusDetailPanel：`title:String, children:List<Widget>`；Divider无业务参数；Row为
  `label:String,value:String,valueMaxLines:int=2,valueKey:Key?`；IconRow为
  `icon:IconData,title:String,detail:String,tone:StudioTone=neutral`；IconList为
  `icon:IconData,title:String,items:List<String>,tone:StudioTone=neutral,itemKey:Key Function(String)?`。
- 共享确认View只接title/body/confirmLabel/cancelLabel/destructive与确认/取消callback；项目归档、
  账号/SSH删除、Mode dirty guard的警告及领域结果由各Smart决定。Plan确认仍属Interaction，
  不能当普通删除弹框处理。
- 附件元信息仅immutable ID/name/type/size/dimensions/preview状态及typed onOpen/onRemove；
  View不准入/删native文件，不建立新ledger，不为去重份数合并不同用途。

## 7. 操作与关闭

1. 禁止Dumb接任意reducer闭包（例如Account Function(Account)）并传至领域。使用明确字段/
   子模型intent，VM校验，Repository用最新canonical构造写入。
2. 额度隐藏停止新自动请求但不取消已受理查询；重现只补未尝试/身份变化，失败计入本轮，
   不因rebuild/default/catalog无关变化重查全体。
3. dialog仅在自己最新已知成功后关闭。Account保存和后续setDefault是独立操作，第二步失败/
   unknown不能假装第一步未保存或整体事务成功。
4. auto-save在退出封闭前交接已形成的有效意图，不在ref.dispose启动新写入；无效raw留错误，
   不恢复默认。手动保存表单不因应用close自动提交。
5. 发送由draft service首await前冻结target/payload/route/attachment；随后UI准备不能改目标。
   Settings往返和Provider dispose不取消已受理创建、不清草稿。
6. Interaction isSecret先于输入控件；source变化只改可操作资格，旧operation不清新输入；
   unknown保留原草稿和提交身份，不因等待/重建自动重发。
7. 模型切换按canonical Turn idle准入，active workflow本身不阻止；running/等待输入/closing/
   closed/faulted保持限制。路由对后续Turn生效，不自动续跑或清Plan。
8. 首次退出意图/deadline/Router卸载归app coordinator，Shutdown VM只呈现，不以Provider
   dispose替代join；所有交接写入参与领域关闭。

## 8. 尚待 root 补齐，不释放编码

- [ ] 所有具体Freezed ViewState嵌套字段、validation/operation结果及VM全部方法签名。
- [ ] Account/Profile/SSH/Mode各Dumb panel完整props/callback，消除任意reducer函数。
- [x] Interaction分页/完整读取进度/提交准入、正常问题可空答案及空questions fallback，见编辑接缝§1。
- [ ] status/context/metrics/Todo/workspace/sidebar完整state与动作，不是只读投影壳。
- [ ] TimelineCanvasBinding已定（编辑接缝§3）；detail/media connector完整props仍待补齐。
- [ ] U0/U1/U2/U3/C逐文件写入/迁移/删除清单及全部手写part解体。

未完成项由root定稿，不下放关键设计。中间只审负责逻辑，全部手写完成后再统一生成和验证。

## 9. 后续字段册必须遵守的root裁定

候选探索报告不是精确接口合同，以下事项已由root决定，不能沿候选中的占位类型直接编码：

- Accounts/Profile/SSH列表VM只持editor key与导航/行意图，不再持另一份编辑raw或保存owner；
  raw/dirty/validation唯一归相应Editor VM。不可用`Map<Field,Object>`或未定义的FieldValue
  代替完整typed编辑intent，也不把StudioFailure降成String丢code/correlation。
- 不新增无既有产品能力的Profile删除、Updates dismiss/download独立命令、任意null项目
  选择或MCP编辑动作。具体公共方法须依据原功能及已经冻结的领域port逐一确认。
- SSH **managed=true是anywork管理、允许原有编辑/删除的条目**；managed=false为用户
  手写只读条目。既有alias编辑时锁定。不能采纳“managed条目只读”的反向候选描述。
  typed passwordOffered=None保持未知，但保留用户显式尝试密码的原UI路径，见失败合同。
- Composer所有业务意图经过VM再调D1，不由Smart直接绕过VM操作草稿/附件。VM可持D1
  不可变draft值的引用用于显示，这不是接管draft owner；不能因“不造第二owner”而删掉
  输入/附件/模式/model/effort/发送/停止的实际VM动作。
- Timeline历史正文仍使用既有Timeline page/readDetail契约；新Thread五域scope只承载执行/
  authoring等事实详情，不替代历史正文接口或叠加第二套正文scope/cache。详情Query owner
  仍在D1原attempt，U2只管理可见读取/复制/错误。ImageProvider可作Dumb UI-only prop，
  不进Freezed state；图片bytes若作为不可变值必须有真实不可变所有权，不只将可写Uint8List
  字段标final就称不可变。
- Plan反馈和回应不放回Plan阅读VM；Plan展开唯一来自Plan VM，Timeline只消费其props。
  Todo只读内容与面板可见意图仍归Todo VM，不由Status再保存一份expanded；需要在面板
  隐藏时保留入口状态，可由同Conversation的Smart观察该VM，但未展开不发详情读取。
- 普通问题允许空答案、空questions fallback、模型idle准入、UnknownOutcome与原保存/
  取消/join边界继续按已定合同，不以候选的简化枚举或例子修改合法输入。

完整余下VM字段/动作/props仍待定稿；这组裁定不代表候选报告已被整体采用。
