# v4 共享接缝合同（root 编写中，整包未到实施准入）

批准计划见 [implementation-plan.md](./implementation-plan.md)，内容 SHA-256
`f8b26bdc7c55994ad3beb154fbcdffe57a81509f2ec2b5c515d3c9f1259727c8`。
基线为 main `b3f22b8f651816851852582a10a970fe25af3ae6`，任务 HEAD
`78a2762495772d7fe416faaf5f14876cf46597c4` 加已审旧成果；已知缺陷见
[main-sync-v4.md](./main-sync-v4.md)。本文件只冻结已经明确的共享形状，不授权执行者填空。
Thread 大载荷／五域、产品实体、所有领域动作与全部 VM／props 尚未齐全前，不释放全量编码。

## 1. 固定模块与公共路径

纯 Dart 包的领域根为 `lib/src/{configuration,models,account_usage,modes,workspace,
conversation,drafts,resources,updates,operations}`。每域只按真实职责使用 `domain/`、`data/`，
不建立只有一个转发文件的空目录。公共领域入口为同名 `lib/<domain>.dart`；装配／adapter
能力入口为 `lib/<domain>_ports.dart`。UI 只能导入领域入口，不导入 ports、src 或生成 FRB。

`operations` 只拥有命令身份／结果／观察证据，`resources` 只拥有资源预算、观察租约和关闭；
它们不是全业务 facade。其他领域的可写 reducer、发布源、命令 lane 和 native handle 均私有。
共同装配只持有各域实例，不代理每个领域的业务方法。旧 `AnyworkClient`、`StudioTransport`、
`models.dart`／`studio_client.dart` 巨桶及旧同构转发在消费者迁完后删除，不保留别名。

Flutter 的固定职责根为：

- `lib/src/app/`：composition、bootstrap、go_router、窗口／退出生命周期。
- `lib/src/features/{workspace,conversation,settings}/`：实际使用的 screens、connectors、
  view_models、state、views、widgets；不用机械创建所有六种空目录。
- `lib/src/ui/`：无业务 owner 的共享 props、视觉组件和格式化；主题仍由 app/theme 所有。
- `lib/src/infrastructure/frb/`：各小型 typed port 的机械适配，不含 VM、草稿或第二 reducer。
- `lib/src/diagnostics/`：Driver／诊断公共能力适配，不反向导入 feature 私有实现。
- `lib/src/platform/`、`l10n/`、`rust/`：既有平台、翻译和生成边界，不随本次分层另造一份。

全部新公共路径由 D0／U3 单一 owner 更新导出与装配；功能执行者不互改公共 barrel。
本表不意味着旧目录中的逻辑全删：迁移时保留实际能力，删除的是旧路径、重复 owner 和兼容层。

命名不能使全局配置与Thread配置发生同名歧义：Thread合同中的ExecutionBaseline/Change、
MetricsValue、ContextValue、ConfigurationValue、AuthoringBaseline/Change及各facet Frame/Event
在实际Rust/Dart/FRB公共类型中统一加`Thread`前缀；文档内短名仅为该域局部记法，不生成
兼容alias。全局ConfigurationValue仅指配置领域值。共用ReadText/TextChunk、ValidationIssue
由D0 resources定义一次；各域只引用，不能各自复制成同构类型。
原状态机错误统一采用`SourceStateError {code:String,message:String,retryable:bool}`及其
typed读取形式SourceStateErrorRead；它没有correlationId，不与StudioFailure混为一类。
新增应用启动/退出接缝见[应用生命周期](./v4-application-lifecycle-contract.md)，Conversation
草稿及输入保存证据见[Conversation合同](./v4-conversation-contract.md)。

## 2. 只读观察：复用现有同步能力

公共形状固定为以下现有能力，迁移到 resources；运行时对象不使用 Freezed：

```dart
abstract interface class ReadonlyLatestValue<T> {
  T get value;
  int get observerCount;
  Observation watch(void Function(T) listener, {bool fireImmediately = false});
  LatestWatch<T> watchLatest(void Function(T) listener);
  Future<T> waitFor(bool Function(T) predicate);
}

final class LatestWatch<T> {
  final T value;
  final Observation observation;
}

abstract interface class Observation {
  bool get isCancelled;
  bool get isPaused;
  void pause();
  void resume();
  void cancel();
}
```

`watchLatest` 在同一 isolate 同步登记并读取当前值；调用方立即消费返回的 value，不先 await，
不等待下一帧补首值。暂停只保留最新显示值，不适用于可靠正文／执行事件或命令结果队列。
发布者私有持有可写 `LatestValue<T>`，外部只看上述能力。`ReadModel.state=`、`source.publish`、
`CanonicalReadModel.replace/patch` 不作为领域公共 API 导出。

预算仍由领域所有者在实际登记观察之前取得 observer permit；取消观察释放自己的 permit，
不关闭 Session 或清草稿。watch／waitFor 在 source 关闭时明确失败，不能留下未完成 waiter；
错误分类在资源关闭合同中统一，不让页面从异常文本猜资源是否关闭。

## 3. 身份、计量与 Freezed 规则

以下值保持现有字段及精度，改为 Freezed 不可变值；不引入第二条兼容导出路径：

| 类型 | 完整字段及语义 |
| --- | --- |
| `ResourceStamp` | `resourceKey:String, ownerEpoch:String, revision:int`；仅相同 key/epoch 比较 revision，revision 非负 |
| `ViewStamp` | `threadId:String, viewId:String, viewEpoch:String, version:int`；相同三项身份才比较非负 version |
| `AttemptId` | `value:int`；进程内异步尝试身份，不替代资源 epoch |
| `OperationId` | `value:String`；首次 await 前由操作 owner 生成，未知结果不换 ID 重放 |
| `DraftStamp` | `draftId:String, revision:int`；revision 非负，区分逻辑草稿和每次编辑 |
| `ResourceUsage` | `kind:ResourceKind, owner:String, phase:ResourcePhase`；诊断值，不是可释放句柄 |

`ObservationStamp` 只允许 ResourceStamp／ViewStamp 两种现有版本域；covers 必须同时核对
完整身份，不以更大的数字覆盖另一 owner。Freezed deep equality 只处理值；Future、stream、
连接、Controller、取消 token、permit、操作 ticket、read lease 不放入 ViewState 或值模型。

Rust ID 仍用 String，时间戳仍为 Unix 秒 i64（字段 `*_at`），字节和计数保持原单位。
FRB u64 到 Dart int 精确验证，不 double 化、截断或钳制。metrics 的耗时是 response_millis，
含首字等待；不能重新使用旧 decode 分母。没有来源或未测量保留 unknown，不补零／空健康态。

## 4. 资源预算与准入

复用现有 `ResourceBudget`／permit 机制，不新建第二个计费 registry：

| ResourceKind | 默认容量 |
| --- | ---: |
| chatHandle | 2 |
| pendingOperation | 64 |
| draft | 64 |
| attachment | 256 |
| observer | 1024 |
| readModel | 256 |

`ResourcePhase={opening,active,retiring,unresolved}` 均计费。首次 await 前取得 permit 并登记
实际工作；只有真实完成才能 release。资源不足是 typed Overloaded／ResourceBudgetExceeded，
不能回收仍在途 owner、清草稿或返回空快照假装成功。等待容量使用现有释放观察，禁止轮询。
上述是运行中资源数量预算，不是载荷字节、完整源对象大小、FRB wire bytes 或 RSS 上界。

## 5. 操作 owner 与呈现 owner 的固定分工

`operations` 内部登记真实操作；各领域 action 在首 await 前冻结目标、payload、CAS revision、
OperationId、draft stamp 和附件归属。VM 只保留本页面 latestIntent／pending／error 呈现，
不能调用 operation 的 accept／markObserved／markDurable 或修改 canonical reducer。

命令公共返回只读 ticket／typed 结果，不暴露可写 `OperationHandle`。精确公共形状如下；
每个领域动作返回其中的具体T，T必须为不可变领域值。无payload的真实确认使用Unit，不伪造receipt。

```dart
abstract interface class OperationObservation {
  OperationId get id;
  ReadonlyLatestValue<OperationState> get state;
}

abstract interface class OperationTicket<T> implements OperationObservation {
  Future<CommandResult<T>> get result;
}

// 下述均为Freezed值；大括号内列出全部字段，不表示动态Map。
Unit()
CommandResult<T>.committed({T value, CommitReceipt receipt})
CommandResult<T>.acknowledged({T value})
CommandResult<T>.rejected({StudioFailure error})
CommandResult<T>.unknownOutcome({StudioFailure error})
CommandResult<T>.syncFailed({T? value, CommitReceipt receipt, StudioFailure error})
CommandResult<T>.acknowledgedSyncFailed({T? value, StudioFailure error})

OperationState({
  OperationId id,
  String target,
  DraftStamp? draft,
  CommitReceipt? receipt,
  bool acknowledged = false,
  bool observed = false,
  bool effective = false,
  bool durable = false,
  OperationFailurePhase? failurePhase,
  StudioFailure? error
})
enum OperationFailurePhase { rejected, unknownOutcome, syncFailed }
CommitReceipt({
  OperationId operationId,
  CommitDisposition disposition,
  List<ObservationStamp> targets,
  EffectPoint effect,
  bool effective = false,
  bool durable = false,
  bool requiresIdentityObservation = false
})
enum CommitDisposition { applied, noChange }
enum EffectPoint { immediate, nextTurn, futureSession }
```

普通`CommandResult.acknowledged`只用于没有原生receipt的真实成功确认，与receipt互斥；不能使observed/effective/
durable自动变true。普通receipt命令的result在必要canonical/identity观察完成或确定失败后
结束，不等待没有来源的durable；receipt和value已知但观察失败返回syncFailed而非unknown。
观察水位先到时登记当前值即满足，不等待下一帧。所有终态结果只结算同一id/target/draft。

无receipt接口已真实返回成功、随后读取/归并失败时用acknowledgedSyncFailed；已可靠识别
native成功但receipt无法无损映射的情况也使用该分支，原证据留adapter。acknowledged为true、
failurePhase为syncFailed，value仅在完整T已知时有值。不能构造假的receipt或把已知成功改成
unknown而鼓励重发。acknowledged只表示真实成功确认，不证明原接口没有native receipt；
它与syncFailed均不自动证明observed/effective/durable。完整typed错误/dispatch证据规则见
[失败合同](./v4-failure-contract.md)，不能从错误code或文案猜是否受理。

公开`Operations`只提供 `lookup(OperationId)->OperationObservation?`、
`latest(String target)->OperationObservation?` 和
`ReadonlyLatestValue<List<OperationState>> records`，不暴露异构dynamic结果。
具体动作返回的ticket始终保留具体T。
统一registry沿用MutationBoard真实逻辑；writer只通过装配专用operations_ports内部能力交给
Repository，不从领域公共入口导出begin/accept/markObserved/markDurable/publish。

固定行为如下：

1. Rust 已有 receipt 的命令保留 disposition、targets、effect、effective、durable 和 identity
   predicate；Accepted／Observed／Effective／Durable 不合并为一个成功布尔值。
2. 相同资源冲突写在该资源 lane 串行；分页、详情、停止和无关域查询不排在长写 FIFO 后。
3. Settings 已知 revision 冲突最多2次恢复后尝试，必须从新 canonical 重建完整 payload；
   它不是对 UnknownOutcome 的重发授权，也不能把非幂等数据写入吞成只读 refresh。
4. 手动压缩、SSH 等没有原生 receipt 的接口保留真实 Future 确认与未知结果，不能生成假的
   Rust receipt／durable 证据。后端已经成功而观察失败与不确定是否受理必须区分。
5. 已受理的 operation 不随 VM／Widget dispose 消失；UnknownOutcome 保留冻结目标和附件，
   只接受有来源的后续事实或明确人工决定，不自动重发。
6. terminal 操作可按既有保留策略淘汰；未解决或有观察者的记录不得为满足数量而静默移除。

## 6. 关闭的三类结果

具体值、feed方法、retryClose、各层责任和最终验证矩阵已固定在
[生命周期合同](./v4-lifecycle-contract.md)，本节保留分类依据。

后续 R／D1／A／U2 必须区分：

- **工作仍在途**：保留同一已登记 Future／native completion／consumer/query 记录；期限只结束
  本次等待，不结束原工作。再次清理等待同一工作，不能创建替身或假报 Clean。
- **调用失败但原 owner 仍可查询／join**：只在原 owner 的同一清理能力上显式重试；进行中尝试
  共享一个 future，已完成的可重试失败不得永久挡住下一次显式尝试。禁止自动重放业务命令。
- **已终止但不可恢复的故障**：例如真实任务 panic／join 失败，保留终态诊断，不重新启动 producer
  冒充清理。组件不承诺重复 cancel 可恢复时不能声称可恢复，也不能只改 retryable 标签伪装
  正确；必须给出实际组件契约与原始失败来源，退出结果保持非 Clean。

已确认事实：当前 native Timeline 的 `producerTaskFailed` issue 固定 retryable=false；
adapter 的取消 issue 却沿用原异常 retryable。前者不能被笼统写成“所有正常 Unresolved 都应
再启动 join”，后者也不能凭布尔值断言底层 StreamSubscription 存在可恢复能力。完整新关闭
合同须明确每种失败的可等待／可重试凭据，以及永久诊断如何被可靠退出报告保留。

## 7. 整包编码准入

- [x] 分层、公共路径、只读观察与现有预算的跨任务统一规则。
- [x] 现有版本域、精确计量、不可变值与运行时 owner 的边界。
- [ ] 全部领域 action／port／ticket 精确签名与 typed 错误矩阵。
- [ ] Thread 五域完整 DTO、可靠队列、typed 大载荷读取、回应 CAS、冷热 owner 和真实 join。
- [ ] Product 集合基线／delta／分页／统计与各实体完整字段迁移。
- [ ] 所有 VM 的 Freezed state、family key、保留规则和 Smart/Dumb props／callbacks。
- [ ] 唯一逐文件写入表、公共导出／manifest／生成输入 owner 和全消费者删除表。
- [ ] 最终统一测试／原生验收矩阵与五个已知逻辑／迁移问题的闭环归属。

未完成项由 root 定稿，不授权执行者自行选择。中间静态审查只按其负责逻辑和已冻结接口判断，
不因其他任务尚未迁完造成的阶段性编译／功能缺口阻塞；全部手写完成后统一验证仍不可省略。
