# v4 资源关闭与展示候选合同

本文件是 root 在 [共享接缝](./v4-shared-contract.md) 下冻结的生命周期决定；完整计划仍为
[全链路 v4](./implementation-plan.md)。它替代历史 A2 合同中“正常 Unresolved 永久复用而没有
恢复能力区分”的部分；**整包其他接口未齐，不单凭本文件派发编码**。
适用任务：R（native owner）、D0（共享值与 port）、D1（会话／查询 owner）、A（适配及 fake）、
U2（展示候选与消费者）、U3（应用退出汇总）、C（测试／Driver消费者）。

## 1. 已核组件事实与决策

- Dart `StreamSubscription.cancel()` 的 Future 表示 cleanup 结果，错误完成不保证 cleanup
  成功。锁定 SDK 的 buffering subscription 只首次调用 onCancel，后续返回同一 cancel
  Future；不能通过再次 cancel 发明可恢复能力。
- 现有 native owned completion 对真实 task join 留存结果。panic／Failed 是已终止但失败，
  不是尚有可重新启动 producer 的工作；重新执行 producer 会改变业务，禁止作为清理重试。
- 现有 query scope 能继续等待同一批已登记 Future；deadline 不是原工作的终止事实。
- 当前 native `producerTaskFailed` issue 的 retryable=false；adapter 则可能保留原取消异常的
  retryable=true。二者不能只凭一个布尔值决定“清理是否能重试”。

因此保留原始 typed diagnostic，并增加**清理恢复能力**的正交字段。该字段是领域协议，
不是新的状态管理器或错误总线；不改原始错误的 code／retryable／correlation。

## 2. 共享不可变值（D0／R 精确对齐）

Rust 枚举／结构派生 serde camelCase；Dart 全部用 Freezed。Rust 字段 snake_case，Dart camelCase。
`StudioShutdownIssue` 的现有五字段原样保留：`stage:String, code:String, message:String,
retryable:bool, correlationId:String`，不从 message 推断恢复动作。

```dart
enum CleanupRecovery { awaitCompletion, retryClose, terminal }

// 每项含原始完整诊断，不改写 diagnostic.retryable 来代替恢复能力。
// 运行时异常的原始 cause/stack 由 owner 私有保留，不放入 Freezed 值。
// Rust 对应 FeedCloseIssue { diagnostic: ShutdownIssue, recovery: CleanupRecovery }。
FeedCloseIssue(
  StudioShutdownIssue diagnostic,
  CleanupRecovery recovery,
)

// 与既有 report 一样只允许两种 outcome；issues 非空。
FeedCloseOutcome.clean()
FeedCloseOutcome.unresolved(List<FeedCloseIssue> issues)
FeedCloseReport(String feedId, FeedCloseOutcome outcome)

// App／领域级汇总；attemptId 是本次实际工作的身份。
UnresolvedResource(String owner, AttemptId attemptId, List<FeedCloseIssue> issues)
CloseReport(List<UnresolvedResource> unresolved)
```

以上为字段签名，不是另一个包装实现建议。`FeedCloseReport.feedId` 必须非空，收到 baseline
后必须与该 feed 的身份相同。issues 全量保留、不可变且不重复拼入同一次工作相同诊断。
`CloseReport.complete` 当且仅当 unresolved 为空；不能把 terminal 问题从数组移走而变成 Clean。
旧 `StudioFeedCloseReport`／Outcome／Failure 等公共名称一并迁移，不保留别名。

恢复能力只取三种值：

| recovery | 必须存在的事实／权限 | 禁止行为 |
| --- | --- | --- |
| awaitCompletion | 原工作已登记且仍有可等待的 completion；例如 query/controller/consumer/native join 尚未结束 | 只凭 timeout 猜它已结束；开替身句柄 |
| retryClose | 原句柄和清理能力仍有效，某次调用未获得可确认结果；允许显式重新调用同一个 owner 的清理入口 | 重发业务操作、重新打开 feed、自动循环重试 |
| terminal | 已观察的不可恢复故障，或组件没有可证明的再次清理能力；保留全部原因 | 重新启动失败 producer、仅改 retryable 或吞诊断假 Clean |

第三方 cancel Future 错误完成且没有独立恢复能力时，diagnostic 保留 source 的 retryable，
recovery 为 terminal。它不是假装成功或释放 permit 的许可；该问题继续影响退出结果。
native join 的永久失败同理。真正仍 pending 的工作必须保留 awaitCompletion 对应 completion；
不能发一个无法再次等待的 pending 报告。

## 3. Feed port 与 native 方法

所有 typed push 连接共享下面的**能力形状**，不通过动态 payload 统一各域 DTO：

```dart
abstract interface class FeedConnection<TFrame> {
  Stream<TFrame> get events;
  Future<void> ackThrough(int deliverySequence);
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
```

各具体连接以自己的 sealed typed frame 实现该能力；Timeline 另外保留 typed page/readDetail，
不把业务查询塞进公共泛型 feed。native 每个对应 opaque 具有 stream、ack_through、
request_close、close、retry_close；其中 close／retry_close 都返回对应 BridgeFeedCloseReport，
并映射本节全部 fields。FRB dispose 仍是生成的句柄释放能力，不用其模拟 join。

- events getter 不建立或认领流；首次实际 listen 同步认领。第二次实际 listen 为 typed
  Conflict。requestClose 后 getter／listen／ACK／query 以 Cancelled 优先，不因参数错误变更
  关闭优先级。fake/demo 与真实适配相同，复用同一 Stream 再 listen 也不能漏成框架 StateError。
- requestClose 同步封准入并广播取消，不等待自己的 onCancel／consumer 回调。
- close 首次建立关闭责任，进行中 close 共用同一次真实工作；成功后的 Clean 幂等。
  close 不自动重启已完成的失败尝试，不刷新 app 首次绝对期限。
- retryClose 是显式恢复入口：pending 继续等待同一个 completion；retryClose 项对原 owner
  发起一次新的清理调用；terminal 仍保留，不重新开始。并发 retryClose 共享一个恢复尝试，
  不能并发消费同一个 JoinHandle。返回新的当前报告，不永久返回旧的可恢复失败结果。
- retryClose 不要求 caller 改 OperationId／重发提交，也不改变 feed identity／owner epoch。
  普通 close 与 retryClose 的实现可复用私有状态，不新增第二个正文队列或全局关闭服务。

## 4. native R 的登记与真实完成

Opening guard、active call、唯一 producer/delivery、reader/tail/baseline 与查询均在首次 await
前登记。producer 由 NotStarted 转 Pending 时，其 completion 安装与关闭方读取受同一明确
登记屏障保护；不能把“已设 Pending 但还没有 join 句柄”的中间态当正常终态返回。

关闭步骤：封准入／取消 → 等 open 与 active calls → join producer 与 sink → 释放 reader、
tail、baseline → 判定报告。失败持有原 owner 及必要资源。若 task 已真正失败终止，可以释放
已不被使用的内容资源，但保留失败诊断和 registry 的未解决身份；这不使 Clean 谓词成立。
如 completion 注册缺失，明确协议／owner invariant 失败并保留资源，不虚构一个可等待句柄。

关闭 observer 与 producer 各自的 JoinHandle 由唯一 owner 消费；取消一个调用 future 不能
drop 掉清理责任。复用已存在的 owned-completion 机制；Shared 完成结果不证明资源已释放，
也不能因有 Shared 就复制或重启 producer。错误报告的恢复能力由实际状态与存留能力决定。

## 5. adapter A 的共同关闭

每个连接私有拥有 native handle、一次实际原生 stream subscription、其取消 completion、
native join completion、当前报告及原始错误 cause。close 同步登记两条错误/完成路径，
并行等待 native join 与 stream cancellation，不先 await 一条再迟挂另一条错误处理。

- native Clean 且 Dart 原生取消已真实成功，且没有其他已登记本地工作，才 dispose 一次。
- native Unresolved 的每项 diagnostic/recovery 原样保留；本地失败追加自己的 issue，不盖掉
  native issues。取消错误保留原source元数据，但其恢复能力根据实际组件契约判断。
- retryClose 只重试仍有效的 native清理调用，或等待已有 completion；已经失败且没有独立
  恢复能力的 StreamSubscription.cancel 不再次调用来假装重试。terminal issue 一直存在。
- native report 解码／身份校验失败时不能先 dispose；保留原 handle 与失败，允许明确的同句柄
  清理恢复。没有可确认的本地释放事实时，不能仅因 native Clean 就丢本地 issue。
- close 的 Future 缓存区分进行中责任、Clean、带恢复能力的当前失败；retryClose 不被普通
  close 的旧结果短路。返回值只体现当前实际完成与尚未解决事项，不伪造清理成功。

## 6. D1 会话与 query scope

Channel 每个 attempt 私有持有 openFuture/openSettled、原connection、streamCancel、consumer
回调、query scopes、清理Future及permit。所有异步结束只结算原attempt，不反向选择新目标。

首次 retire 先对 connection.requestClose 封闭准入，同时停止 consumer 新回调并取消原迭代器，
再等待这些独立路径；不能等消费者结束才发native取消。scope退出登记、producer退出、
stream取消和consumer完成均参与最终Clean。

领域公共 `retryCleanup()` 不再只是重读一个已完成 Unresolved future：

1. 正在清理的 attempt：继续等待已有责任，不再创建并发 close。
2. 已有当前报告：按 issue.recovery 在原connection调用 retryClose 或继续等待现存 scopes。
3. terminal保留；更新后的问题仍完整返回，旧诊断仅在其对应清理真的成功时变为已解决。
4. 只有所有实际工作结束且无unresolved issue时释放原permit与attempt。不能以移除map恢复容量。

query scope 首 await 前登记每个Future与permit，retire拒绝新query／迟到发布；close可对同一
登记集反复等待。deadline只控制本次观察，未完成查询以awaitCompletion记录，完成后真实
解除归属。scope 不关闭执行 Session 或writer，也不因页面dispose就放弃在途清理。

## 7. U2 展示身份与收束

展示 coordinator 的内部身份固定分开：

- selection binding：具体 Session 对象＋绑定代次；Thread ID 只作业务目标，不足以证明身份。
- consumer binding：这次 attach 返回的唯一 consumer lease，不能由同 ID 新Session替代。
- candidate epoch：每个新候选在首await前递增并登记；新候选开始即撤销旧候选发布资格。
- display generation：已发布 UI 控制器的代次，不替代 candidate 或 selection 身份。

回调捕获其具体 Session、selection/consumer binding，不再只捕获threadId。候选在首await前
登记到 coordinator 的未发布候选集合，openQueries闭包捕获原Session的timeline能力。
写入成功后核对 coordinator未关闭、具体Session/binding仍当前、candidate为最新、原pending
意图仍匹配；全部成立才交换当前展示，否则只收束该候选。A→B→A和同IDSession替换不能复活旧候选。

每次 detach 无条件对取出的lease执行requestClose/close并登记自己的Future；禁止用一个
`??=`同时决定“是否调用后续close”。旧consumer在途回调、未发布候选写入及退役display lease
均保留唯一归属。close同步封准入、解除展示绑定并广播各自取消，再等待上述所有登记；期限
报告覆盖每一个未完成consumer/candidate/display，不用“当前没有展示”推导完成。

真实join完成Future可共用，但deadline观察报告不能永久缓存为最终结果。再次明确清理检查
同一批未完工作当前状态；不会重新挂载widget或等待不存在的挂载回调。controller只有已受理
写入完成、实际子树解除绑定、queryscope结束后才能dispose并等待operations stream done。
不为修复交错增加第二份Message列表或跨帧正文队列。

## 8. U3 退出与最终验证矩阵

应用首次退出仍固定意图与绝对deadline。D0/D1/A/U2的当前未决报告须在Rust finalizer前并入
external issues；超过期限不续期、不延迟到宣告Clean后追加诊断。永久失败导致非Clean，
安装器交接仍是独立结果；不以进程退出或GC证明前面的逻辑清理成功。

以下源码测试与Driver场景在各任务编写，**此阶段不执行**，全部手写完成后统一取得证据：

| 范围 | 必须区分的反例／后置条件 |
| --- | --- |
| typed报告 | 全部native issues和本地source诊断/recovery保真，空feedId／空Unresolved issues拒绝；错误不dispose |
| pending | query/consumer/controller/native join gate未完成时报告awaitCompletion且permit保留；gate完成后同owner真实释放 |
| 可重试调用 | 第一次同handle close调用失败，显式retryClose成功；并发重试只有一次调用，无新open、无业务重放 |
| 永久失败 | nativepanic或没有恢复能力的Dartcancel失败保持terminal，不重新producer、不清原诊断、不伪Clean |
| 流认领 | getter读取两次不claim；实际listen后再从相同或新getter listen都是typedConflict；closingCancelled优先 |
| 候选 | A→B→A、同IDSession更换、旧候选先完成而新候选尚未发布、关闭期间未发布candidate，均不发布旧内容/不借新query |
| 解绑 | 连续两次以上detach每次close实际执行；全部consumer和candidate可等待，期限报告不漏项 |
| 退出 | Router实际卸载、并行join、firstdeadline不延长、externalIssues先于finalizer、安装失败独立，原生进程证据最终取得 |

该矩阵不是已有通过证据。局部审查看目标逻辑与准确接口，不要求尚未迁完的调用方或生成物
在中间可编译；整合后最终必须无遗留问题。
