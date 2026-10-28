# 最新主线合流：目录分工与固定实施合同

本文件只记录实施步骤与验收责任，不替代 `design/25-frontend-state.md` 的权威设计。首轮基线为 HEAD `420c4fe8`、MERGE_HEAD `7aa6ee04`，已保存为 `e3e33b77`；本轮继续合流 `a9e4e807`，原批准计划持续有效。当前手写阶段不运行工具链，全部汇合后由 root 串行生成、格式检查、分析、测试与 GUI 验收。

## 1. 所有权与依赖

| 任务 | 唯一写入范围 | 输入与依赖 | 完成边界 |
| --- | --- | --- | --- |
| N | protocol / runtime / Rust FRB / Server | main + PR120，401候选已冻结 | 分调用链审查，问题原执行者定向修复 |
| S | SDK Conversation / Drafts / Workspace / Recovery | 固定 native 类型；403正在收尾 | 公共接口、owner、回归源码及旧入口清理 |
| A1 | App `infrastructure/frb/conversation/**`、`infrastructure/frb/shared/**`；SDK仅 `resources/domain/failures.dart` 的控制错误值 | 下述固定 native 与 SDK ports | 执行流、命令、交互与错误适配，原资源生命周期不退回 |
| A2 | App `infrastructure/frb/products/recovery/**`、`products/workspace/**`、`drafts/**` | N/S，动作列表合同已定 | Recovery/目录轻状态/附件路由适配 |
| U1 | App `features/conversation/**` | S 的公开 Session/Repository；现视觉合同 | 主按钮、只读 child、hosted 卡片与 raw origin |
| U2 | App `features/workspace/**`、`features/settings/agents/**` | S 的目录动作和 Recovery值 | 目录行停止、归档不被工作树故障挡住、恢复界面 |
| C | App `test/client/**`、`test_driver/**`、`diagnostics/**` | A/U交付的固定 API | 迁移唯一测试与 Driver 证明，不删独特断言 |
| root | Git、design/report、`app/**`、`l10n/**`、共享导出、旧 orphan 清理与跨目录接线 | 各任务交付 | 统一生成、全量验证、集成与 PR |

A1/A2/U1/U2 不写测试目录、生成物、彼此目录或根装配。发现跨界调用点报告具体旧/新签名，由对应 owner 处理；不为绕过权限在自身目录造平行实现。SDK failure-reason 投影 helper 暂由 root 在 S 交付后做单点适配，A1 不并写 Conversation SDK。

```text
N + S 固定接口
 ├─ A1：执行/命令/交互 adapter ─┐
 ├─ A2：Recovery/目录/Drafts ──┤
 ├─ U1：Conversation UI ───────┼─ C 测试与 Driver → root统一生成/验证
 └─ U2：Workspace/Recovery UI ┘
```

## 2. 固定类型，不留两种选择

- native `ExecutionBaseline.execution: Option<AgentExecution>`、`continuation: Option<ContinuationView>`；增量各为 `Unchanged | Replace { value: Option<_> }`。
- SDK值位于 `conversation/domain/execution_values.dart` 及 `continuation_values.dart`；以当前声明的名称与字段为准，不另造 UI 或 adapter 身份类型。
- Recovery 的读取值和领域值都使用 `availableActions: List<RecoveryAction>`，替代单值 `action`。`canRetry = contains(retry)`；清理资格只来自对应显式动作，不从 `worktree != null` 推断。
- Recovery `inspection` 四态；`headCommit`、`dirty`、`changedFiles` 都可空。read层 `changedFiles: TypedListRef?`，null是未知，不是空列表。
- `NewThreadAttachmentAdmissionContext` 必填现有 `ModelSelection route`；native为 `NewThreadModelRoute`，不再传mode或重读默认路由。
- 控制错误：SDK `StudioFailureDetails.control(reason: String, facts: ControlFailureFacts)`；facts一一对应native `BridgeControlFailureFacts`的21种封闭变体与字段，字段名转camelCase，u64用现有精确数值转换。不要raw map、`detailsJson`或消息解析。普通reason旧变体保原合法用途，不作为control的丢字段替身。

## 3. A1 执行与命令步骤

```text
convert execution frame:
  保原 identity/stamp/baseRevision/deliverySequence
  baseline分别映射execution与continuation（包括null）
  change: Unchanged原样；Replace(null)明确清除；Replace(value)完整映射
  转换失败抛真实typed failure；现有owner决定是否ACK，adapter不提前ACK
```

SDK `ConversationCommandPort`：
- `stopExecution(String threadId, String executionId, {required OperationId operationId}) -> Future<StopExecutionReply>`。
- `continueThread(String threadId, {required OperationId operationId, required String expectedContinuationId, required int expectedModelRouteRevision}) -> Future<ContinueThreadReply>`。
- `readContinuationOperation(String threadId, OperationId operationId) -> Future<ContinuationOperationView?>`。
- `respondInteraction(String hostThreadId, String interactionId, {required OperationId operationId, required int expectedInteractionRevision, required InteractionResolutionCommand resolution})`。

native stop/continue/read入口在 `handlers/prompt.rs`；回应顺序固定为 `(operation_id, host_thread_id, expected_revision, interaction_id, resolution)`。

```text
continue call:
  同步转换并冻结thread/op/continuation/routeRevision
  转换在调用前失败 -> 明确未派发拒绝
  调用native；成功 -> 严格转换完整reply/receipt
  native错误Control.ContinuationAccepted且accepted=true且thread/op匹配:
      有合法receipt按现有confirmed路径处理
      无合法receipt -> confirmedWithoutUsableReceipt，绝不伪造receipt
  其它错误沿既有真实派发证据分类；普通异常不能凭Busy/retryable判未受理
  后续回查由SDK原operation owner承担，adapter不重发
```

hosted详情的ref仍属host原来源，详情threadId是真实target；不要在adapter重写target成host。读scope、取消、late handle、预算继续由现有资源owner接管。#177订阅失败顺序只修真实互等：创建决定先完成，再等待依赖该决定的取消；不能跳过cancel/join。

## 4. A2 产品与附件步骤

```text
recovery read:
  inspection逐值映射
  nullable数值/文本/列表引用保null
  availableActions逐值完整映射，顺序不成为权限
  list非null才分页；读取失败保原scope与owner，不返回空列表假成功
agent directory read:
  增量与baseline都映射execution/canStop/awaitingScheduling，保原ref/source
attachment admission:
  captured ModelSelection -> native route(accountId/modelId/effort)
  不读取当前选择，不fallback mode，不改变已排队请求
```

## 5. U1 主按钮矩阵和交互能力

按以下优先级唯一推导，不用上次点击或最后消息猜状态：

1. child详情：只读，无输入/发送/继续/停止/答题/审批。
2. 停止已受理或execution.phase=stopping：禁用“正在停止”。
3. 有execution：有文本/附件为“发送并继续”；无内容为停止。保存/模型/工作区阻塞可挡发送，不能挡仍存在的停止目标。
4. 无execution，continue已受理或point.claimed：禁用“正在继续”。
5. 未认领point：有内容为发送并继续，无内容为显式继续。
6. 无point：普通发送，空内容禁用。

请求在途防重复但不伪造受理。Enter只发有内容草稿；无内容继续必须点按钮。保持已有主题、布局、快捷键作用域与key。

公开能力：Session `stopExecution(origin,executionId)`、`continueThread(origin,operationId?,continuationId,expectedModelRouteRevision)`。hosted卡片通过原有有界交互索引/详情，`openHostedInteraction(origin,reference,targetThreadId)` 与 `respondHostedInteraction(origin,reference,targetThreadId,operationId?,interactionId,expectedInteractionRevision,resolution)`；child Plan不可决议。旧普通root交互走原同Session能力。所有按钮冻结原能力与来源，异步结果仅结算原操作。

Session 和 Repository 的两个停止准入统一返回普通 sealed 能力结果 `StopExecutionResult`：
`StopNoExecution(threadId)` 或 `StopExecutionOperation(ticket: OperationTicket<Unit>)`。
该结果含借用票据能力，不放进 Freezed ViewState。前者只在原来源有效、没有同目标未释放票据且当前执行确为空时
返回，不登记操作或发命令；UI 不报失败也不显示“已停止”，等权威投影即可。后者仅表示
已有原操作可观察，不等于 native 已受理。来源失效或存在其它执行仍拒绝。CommandPort
的 `Future<StopExecutionReply>` 保持不变；native 派发后竞争用 typed noExecution 原因判别。

停止准入顺序固定为：校验原来源及当前完整成员 → 拒绝空执行编号或不同的当前执行 →
复用同目标未释放票据 → 无执行时返回无操作结果 → 登记新操作。同一来源的较新修订允许
核验，但不跨来源或重建成员借用身份；新操作冻结此次真正核验的当前来源和成员引用，
不能在后续派发时又用旧引用精确相等检查拒绝自己。

## 6. U2 目录与恢复步骤

```text
row stop:
  从本行Ready agentDirectory冻结origin/member ref/executionId
  ConversationRepository.stopDirectoryExecution(origin, member, executionId)
  不select，不session()，不建draft，不改父/兄弟
```

目录成员计数仅未关闭，关闭成员仍能查看。归档入口仅去掉工作树故障阻塞，不放宽源身份/归属/存储失败/真实busy规则；取消归档只恢复可见性。恢复卡显示inspection、未知head/dirty/changedFiles与原路径；Retry和Cleanup按动作集合分别出现，可并存。清理保分支的文案已在ARB，不能继续显示会删分支。

## 7. 交付与统一验证

每任务交付：实际修改文件/hash、已实现调用链、尚需其它owner接线的精确签名、静态检查、未执行项。小块交付不等于整体完成。root收到后安排对应局部独立审查，审查按具体调用链，不让一个reviewer重复通读所有目录。

各任务全部闭合后再统一生成与全量验证；不能以接口暂不编译为由手改生成物、造兼容alias或弱化断言。发现集成失败由root给出真实错误、固定预期和定向步骤，再交责任目录修复。

## 8. Native 关闭接续与恢复收尾合同

N3 仍使用现有 `ThreadCloseRun`、`CleanupGate`、Entry 和工厂关闭所有者，不新增登记表。
物理身份固定为原 incarnation、ThreadHandle 与 cleanup gate；workspace 策略不是替换物理
所有者的理由。策略首次可见仍须在 Studio 的显式关闭意图提交成功之后。

```text
explicit close under original per-id operation gate:
  校验原目录授权，封新准入
  若 core 已 Closed 且需仅存储所有者:
    先接续旧 run 到真实退役；原失败不获准恢复则原样返回
    旧登记移除后才新建 storage-only Entry + 新 cleanup gate/run
  提交并确认显式封口意图；失败不发布 workspace 策略
  在原 operation/cleanup 边界发布或认领唯一显式策略
  接续原 runtime 阶段与原 wait；不重做已成功阶段，不清失败
  PublishedResources 尚未开始时捕获当前已授权策略
  若旧 Retain 已跳过资源阶段但尚未移除 Entry，补结算未完成的显式责任
  资源阶段在途复用原 wait，失败沿原 typed factory owner 显式恢复
  仅当 runtime 与适用资源责任都真实完成才 RemoveEntry
```

`valid_identity` 与 `resume_source` 使用同一物理身份定义；不能仅删除策略等值校验却
继续使用旧 `published=false` 跳过资源阶段。只允许补结算此前确实跳过且尚无副作用的
资源责任，不覆盖未知或失败的阶段 Future；`Done` 的 run 不承担后继所有者。
普通 `Retain` 不凭策略标记派发新的物理工作或重试；已在执行的清理仍由原所有者负责
等待，未完成责任保持可观察。显式策略一旦开始不能从 preserve 改为 cleanup 或相反。
独立装配器仍在原显式关闭入口授予内存策略，不能要求不存在的 Studio 存储。

锁顺序沿原 operation → cleanup permit → 短暂 Registry state；进度锁与 Registry 锁
不跨等待，取消只结束本次等待，不丢原 wait、任务或原因。回归增强现有 owner 契约，
覆盖 Retain 失败后显式接续、原失败保全、未提交意图不触发清理、成功只执行一次，以及
Closed core 的旧责任未结算时不得替换实例。

其余 N3 固定事项：恢复诊断在发布前统一使用有界脱敏的类型化原因和阶段，不把原路径、
无界 stderr 或 `{error:#}` 直接送入 message；根工作树创建使用现有 creation guard
覆盖整个创建/发布/失败路径；移除旧公开整表 Recovery DTO/事件输出，当前 typed
read/feed 为唯一界面入口。主代理已确认并删除无主库的旧 `studio_api.dart` parts，
它们不是需要保留的生产消费者；其余真实 Rust/HTTP 消费者仍须按具体契约迁移。

## 9. Driver 共享采集接线

### 9.1 原有采集合同

C2 继续拥有 `test_driver/**` 与 `diagnostics/**`；C3 仅拥有 `shared/**` 内
`driver_projection.dart`、`driver_snapshot.dart`、`driver_snapshot_json.dart` 及必要私有
诊断拆分。C1 继续唯一拥有 `test/client/**`，不并写。

固定输入为 `DriverViewFacts.interactionEditors: List<InteractionViewState>?`，默认 null。
C2 从已存在的 Conversation VM 当前键集合借用已存在的 interaction provider 值，绝不
实例化 provider、打开 scope 或读取正文。C3 原样收为请求局部不可变列表，并按当前 host
Session/incarnation、currentEditors 成员、target、revision、scope 与 sourceCurrent 核验；
未知、未物化、过期或读取失败均保持不可用，不以 id 或当前 Plan 拼装正文。

共享序列化使用现有 `availableActions`、worktree inspection 与 nullable facts，以及
目录行的 execution/canStop/awaitingScheduling。workspace.isBusy 只由当前就绪执行域的
execution 有无决定。活跃交互的类型、身份、目标和已物化问题／审批内容来自上述已挂载
所有者；保原 Driver 旅程真实观察字段，但不输出草稿答案、审批理由或秘密输入。

每个问题的 JSON 保原 `optionsCount`，补 `options` 和 `optionsComplete`：count 为 null
时后二者为 null；否则只按原索引排序输出已读 `OptionReadItem` 的 index/label/description。
文本只用现 `textOf`，不补读；完整性须核无 optionsLoading/optionsError、无后继页、数量及
连续索引匹配且标签/说明均已物化。count=0 的已知空列表可以完整，count>0 的未读空数组
必须不完整。C1 在真实 Driver capture 流中补非空选项、部分与延迟文本，并断言采集前后
options/text 查询次数不变；不只写共享序列化器的复制品测试。

统计请求只输出现公开快照的真实配对身份，移除三个无来源的旧单流占位键；不新增 SDK
诊断仓储或为 Driver 扩大 Freezed 值。请求 release 归还需求，真正 feed/read join 仍由
原 statistics owner 监督，最终应用关闭统一证明，不新增请求级强关共享仓储能力。

## 10. 冷显式关闭的受管结果与集中收尾

冷 checkpoint 已 Closed 且带显式 marker 的分支也统一进入现有 Entry／CleanupGate／
ThreadCloseRun，不再直接调用一次性 factory 然后丢结果。旧 resident 的责任未结束时先接续，
真正退役后才建立新的 storage-only owner；已有 marker 的 commit 幂等，不启模型或工具。
显式关闭的目录确认纳入原 run 的具名阶段，位于原资源处置成功之后、RemoveEntry 之前。
阶段仅持原 factory、record 与身份，使用原 Thread 的已保存封口事实；不得新建全局结果表。

```text
冷/热显式关闭共用：登记原owner → 附接存储 → 确认封口意图 → 冻结显式策略
原run：存储/工具/内核/观察收束 → PublishedResources → DirectoryProjection → RemoveEntry
PublishedResources失败：保原FactoryCloseFailure，只显式恢复原责任
DirectoryProjection失败：保原阶段与错误，Entry不移除，物理成功不回退
显式重试投影：同factory/record/原owner，以现幂等目录写重做此阶段，不重跑物理处置
standalone或普通Retain：没有Studio投影责任，不产生上述目录写和新物理授权
```

不要在 run 外先保存投影错误，再做物理处置，最后抛出已无所有者持有的错误；也不要先替换
旧 incarnation 或用 Done 的旧 run 充当新 owner。新阶段仅扩现关闭责任，不扩恢复权限到
其它失败阶段。集中收尾同时保产品库 19–21 的 `StorageMigrationRequired` 分类；这些旧
格式在任何 ledger 写入前交回启动所有者，不误报为更高版本，也不直接迁移或重置数据。

## 11. 无项目预选接线

Interaction 目录独立收尾：复用现有 `SessionOptionsViewModel`，允许其呈现键为可空
projectId；仅无项目实例观察现有 `DraftsRepository.startRoutes`，dispose 只取消自己的
观察。现有项目草稿动作先检查非空 projectId；模型／effort 预选调用仓储既有
`setStartModel`／`setStartEffort`，不创建假项目草稿，不引入第二份选择状态。
`StartInputConnector(projectId:null)` 借该实例和已有 selector catalog 装配选择器，
输入仍禁用，mode 为原默认 simple 但不可编辑，点击 mode 通过现有菜单的 onBlockedTap
说明 needsProject；model/effort 根据实际目录与已选偏好可用，未知不猜默认。
`ModeSelector` 只补纯回调／提示参数并转交现 `QuietSelectorMenu`，不另造菜单。
纯 `InputModelControlsView` 区分 mode-only 原因与全行阻塞，不能用 needsProject 同时
禁掉模型和强度。C1 保留并增强现 session_selector_sync 真实行为回归，执行者不并写测试。

## 12. 恢复领域外部出口收尾

架构与公开接口见 design/25 §25.16.1，实施分为互斥范围：Server 负责 HTTP 传输，
Native 负责 runtime／FRB 旧出口退役。后者须等当前 Native 关闭与诊断候选冻结后再实施，
不得并写 `recovery_task`、`tool_refresh` 等当前范围。

- Server 复用现有 Templates／Configuration 的传输生命周期模式，新增域专属 Recovery
  路由与传输所有者，不创建业务缓存或通用框架。读接口沿现有 `StudioRecoveryRead` 与
  来源状态读取能力；问题、变更文件和文本保持有界，未知保持空值。
- 事件流、确认、关闭与读取路由按 design/25 的域前缀注册；精确路由分类保独立控制额度。
  `AppState` 与退出链登记同一传输所有者，首次期限不延长，未决句柄不丢弃。
- Server 删除旧恢复整表 GET、旧产品主题解析及 SSE 标签；重试命令仍返回原命令签发的
  `RecoveryReadTarget`，清理命令不扩大授权。其他诊断域不删除。
- Native 保原 `StudioRecoveryRegistry` 到 `RecoverySource` 的发布边界，移除不再需要的
  整表事件、旧主题/基线变体、旧快照恢复字段及 FRB 对应 DTO/转换。全应用旧 FRB 查询
  若无消费者则删除入口；有消费者的服务端聚合仅退役恢复字段，不以空列表占位。
- 原生 typed feed/read、动作集合、nullable 工作树事实、命令发布寿命和安全诊断保持。
  生成物由 root 最后统一更新，不能手工修 FRB 输出。

## 13. ACP 取消身份与继承回归

Settings Accounts 的生产执行者只修安装取消的原操作身份隔离，C1 继续独占应用测试。
固定合同见 design/25 §25.19：A 的取消在途不能挡 B 的取消，A 的迟到结果不结算 B。
旧主线三份 ACP 测试中的认证呈现、命令通知归属、草稿认领与取消生命周期独特断言须逐项
迁入真实当前 VM／Repository／View，不恢复旧 facade、不把安装事实写入表单草稿。
只读面板与失败消息测试按原主线呈现纠正，不把新增 effort chip 或错误背景卡片当作保真要求。
