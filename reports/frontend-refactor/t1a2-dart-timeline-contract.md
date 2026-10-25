# T1.A2 — Dart Timeline 消费闭环合同（v4）

> 历史切片合同。下文的 Plan revision 6、旧基线与阶段测试／推送节奏记录当时输入，现已由
> [全链路计划 v4](./implementation-plan.md)（revision 9）替代，不构成当前实施授权。
> 同步审查确认的候选身份、consumer join、Unresolved 实际重试及 fake late-claim 缺口见
> [最新同步记录](./main-sync-v4.md)。这些行为必须在全重写合同中收口，不能用旧局部批准、
> 原重复 close 测试或本文标题中的 v4 冒充全链路 v4 已通过；中途不再测试、编译或生成。

状态：root 已冻结的接口／行为合同；**前置已完成，允许按本版本实施**。T1.A native R3 已获
第四轮独立局部批准，SDK 生成／依赖前置已取得[实际证据](./t1a2-generation-preflight.md)，
root 随后再次完成 canonical 检查。它们只释放本任务，不表示完整 T2、跨层阶段或整体重构完成。
v2 补齐实际消费者清单、原 Channel／QueryScope 完整公共面与唯一导出纪律，消除详情最小
字节单位的歧义，并明确 saved 观察必须消费同步登记时的当前值。v3 在首个手写稳定检查点后
由 root 明确尚未消费首基线的 opening 接入规则与关闭准入；不改变 native v2 合同。
v4 进一步明确 FRB adapter 的本地转发取消与 native join 属于同一关闭责任：两者真实
收束后才释放 opaque，本地取消失败保留 typed 诊断；不改变公共类型、方法、领域预算或
native v2 协议。这是既有“取消不是 join、失败不谎报 Clean”要求的关闭边界细化。

## 1. 目标、基线与阶段提交

批准计划为 [完整实施计划](./implementation-plan.md) 的 v3；canonical Plan revision 6，
内容身份 `sha256:8dbea7a50d90d0cd6b6de5502a997923734e0cbd37459aaf0efa204596f56dc3`。
派发／审查消息必须附完整计划，不只给链接。

最新代码比较基线为 `f6cb327ceb3416dca181790575711588571d3ec7`；当前已提交 docs 基线为
`b98432fa809446d57be87a8b96379455ec8a4828`。实际派发时 root 另附前置 native 成果及本任务输入
文件 hash；不能用此段代替最新内容身份。

用户要求提前建 PR、阶段性 commit/push，已有 Draft PR #120。本切片把 T1.A 的 typed push
贯通到 Dart port、唯一内容服务、展示 owner、demo 与测试，使阶段代码可以通过完整门禁后推送，
不推送删除 native API 却仍调用旧接口的破坏性中间版本。该顺序仅提前完成依赖已成立的
Timeline 消费接缝；广义 T2 的 Client 解体仍依赖完整 Thread／产品契约。

非目标：本切片不重做其它 Repository／ViewModel／Workspace，不保留 pull alias，不新造
通用事件总线、重放日志、UI 历史镜像或第二份业务状态。不改新会话 preparation、手动压缩
命令协议、上下文策略权威、Profile 迁移、持久化格式或用户数据。

## 2. 唯一职责与依赖

```text
BridgeTimeline typed push（T1.A-v2）
  → FrbTimelineConnection（机械 typed 转换、opaque 生命周期）
  → StudioTimelineChannel（attempt、连续性、唯一顺序消费、ACK、查询／关闭）
  → 唯一 TimelineFrameConsumer lease（可等待的展示交接）
  → TimelineSessionOwner／TimelineDisplayLease（唯一已加载 Message 集合）
```

- native/adapter 不做第二 reducer。纯 Dart 包不导入 Flutter、Riverpod、FRB 或 native handle。
- Timeline 领域值用 Freezed；运行时 Channel、consumer lease、permit、Controller 不是 value。
- 现有可靠 attempt、预算、query scope、关闭算法迁移复用，不因为改为 push 重写一套。
- `LatestValue` 仍仅用于状态／诊断 latest mirror，**不再作为 UI 正文的可靠交付通道**。
- UI 不通过 `ChatReady.snapshot` 应用正文；专用单消费者回调成功后才 ACK。暂停只读观察可以
  丢中间显示值，但不能把有序正文压成 latest-only。
- `StudioTimelineChannel` 的真实 owner 名称和其它非 Timeline 旧 Client 能力暂保留；这是已有
  生产实现的有序迁移，不新增兼容 façade。广义 T2 再收束其余领域与公共出口。

## 3. 文件与公共入口（固定）

### SDK

新增／迁移：

- `lib/conversation.dart`：Timeline 领域值及内容服务公共能力的唯一入口。
- `lib/conversation_ports.dart`：adapter／装配专用 port 入口，feature 禁止导入。
- `lib/resources.dart`：shared feed close 值的公共入口，供后续其它 feed 复用。
- `lib/src/conversation/domain/timeline_models.dart`：由旧 timeline_contract 的 value 类型迁入并
  Freezed 化，加本篇新 feed frame/event；part 为 `timeline_models.freezed.dart`。
- `lib/src/conversation/data/timeline_port.dart`：`StudioTimelineConnection`、`TimelineTransport`。
- `lib/src/conversation/data/timeline_channel.dart`：迁入原 Channel／QueryScope／attempt 实现。
- `lib/src/resources/domain/feed_close.dart`：本篇 shared close 值与 typed failure，part 为
  `feed_close.freezed.dart`。
- `lib/src/observation/latest_value.dart`：增加下述只读 capability，不新增镜像实例。

删除旧 `lib/src/studio/timeline_contract.dart`、`lib/src/chat/timeline_channel.dart`、
`lib/transport_ports.dart`，不留转发文件／alias。更新 `anywork_client.dart`、`studio_ports.dart`、
`src/studio/thread_session.dart` 的真实引用；旧巨桶不再重导出已迁移 Timeline 值／port／服务。
`models.dart` 本来没有这些 Timeline contract 值，不扩大它的出口。

`conversation.dart` 导出全部 Timeline value 和现有 Channel 公共能力（含 QueryScope、异常、
RetryPolicy、页／详情常量）及本篇 consumer 能力；不导出 transport。`conversation_ports.dart`
仅导出两个 port。`resources.dart` 导出 feed close 三种值，不复制已有 `StudioShutdownIssue`。
当前通用 `ChatUiState` 和资源预算值仍走已有公共入口，后续 T2 处理，不另建平行版本。

`studio_ports.dart` 为 `StudioTransport implements TimelineTransport` **只导入**
`conversation_ports.dart`；删除旧 Timeline export，不改成转发 export 新入口。
`studio_client.dart` 没有直接 Timeline export，其非 Timeline 导出保留；通过其它 barrel 的
间接导出随移除而消失，不能在任何旧 barrel 补回别名。`models.dart` 中既有
`src/models/timeline_models.dart` 是另一份文本／工具／todo 模型，不是本次待删除的内容契约。

### 应用

必须迁移现有真实消费者的 import、签名和逻辑：

- `infrastructure/frb/studio_api.dart`、`studio_timeline.dart`、`studio_demo_api.dart` 及其必要 part；
- `presentation/view_models/timeline_session_owner.dart`；
- `domain/models/timeline_presentation.dart`／`timeline_presentation_controller.dart` 的可等待
  controller 写入屏障；
- 当前所有使用搬迁 Timeline 类型的生产、Driver、测试引用；不得为省迁移恢复旧 re-export。

构造 props／Widget／VM family 本任务不新增、不改变。展示 binding 仍为原 UI-only lease，
不能让它携带 Repository／native handle 或第二份 Message 集合。

### 已核实的精确消费者／允许改动表

以下为 `b98432fa` 上未实施 A2 的手写输入；派发时另附各输入 hash。
`SDK` 表示 `code/anywork_client/`，`APP` 表示 `code/anywork/`。除新增目标文件及删除的旧
三路径外，实施写面限定于此表；其它实际编译依赖需要变更时先给 root 证据，不顺带重构。

| 分组 | 实际文件 | 固定职责与修改范围 |
| --- | --- | --- |
| SDK 生产 | `lib/anywork_client.dart`、`lib/studio_ports.dart` | 删除已迁 Timeline 值／服务／port 的旧出口；只导入新 port 装配 |
| SDK 生产 | `lib/src/studio/thread_session.dart` | 新 Channel 引用、既有 demand／refresh／join 生命周期接线，不改变 Session／草稿寿命 |
| SDK 生产 | `lib/src/studio/drafts/submission_observation.dart` | 新领域入口；保留按 input 的 saved／effective／durable 最小观察，并消费同步登记返回值 |
| SDK 生产 | `lib/src/observation/latest_value.dart` | 只读 capability，原实例／同步观察／暂停语义不变 |
| APP adapter 库 | `lib/src/infrastructure/frb/studio_api.dart`、`studio_api_contract.dart`、`studio_timeline.dart`、`studio_demo_api.dart` | 同一个 part 库的 import、open、typed stream／ACK／close 与 demo 实现；不改其它 transport 协议 |
| APP 展示 owner | `lib/src/presentation/view_models/timeline_session_owner.dart` | 状态与正文消费分离、候选 lease 与可等待交接、真实关闭 |
| APP 展示库 | `lib/src/domain/models/timeline_presentation.dart`、`timeline_presentation_controller.dart`、`timeline_messages.dart` | 新领域 import；当前帧／页写入屏障；原唯一 Message、分组与增量算法不重写 |
| APP View 库入口 | `lib/src/features/timeline/timeline_view.dart` | 追加新公共领域入口，保留其它非 Timeline import；其 11 个 part 自动共享 import，不借此改 Widget／业务行为 |
| APP Driver | `test_driver/page_switch_extension.dart` | 新领域 import，保留真实查询／快速往返的 `joinRetired`、attempt 计数及代次断言 |
| SDK 测试 | `test/support/timeline_transport.dart` | `TestTimelineTransport`／`TestTimelineConnection` 改脚本化 push／ACK／join gates，不复制被测 reducer |
| SDK 测试 | `test/timeline_tail_test.dart`、`timeline_query_scope_test.dart`、`chat_lifecycle_test.dart`、`thread_session_test.dart` | 迁移真实 Channel／QueryScope／资源生命周期行为断言 |
| SDK 测试 | `test/studio_drafts_test.dart`、`studio_command_receipts_test.dart` | `_DraftConnection`、`_RouteConflictConnection` 及可靠保存／回执场景迁移，不削弱 UnknownOutcome／身份断言 |
| SDK 测试 | `test/thread_item_convergence_test.dart` | TimelineDetailRef 等值的入口迁移，字段收敛断言不变 |
| APP 正式测试 | `test/client/frb_timeline_adapter_test.dart`、`timeline_demo_tail_test.dart`、`timeline_readiness_adapter_test.dart`、`studio_driver_query_test.dart` | 真实生产 adapter／demo 的 typed push、消费 ACK、close 与错误转换 |
| APP 正式测试 | `test/client/timeline_session_owner_test.dart`、`timeline_display_lease_test.dart`、`timeline_row_observation_test.dart` | 专用 consumer、候选发布／写入屏障及既有展示身份／分组断言 |
| APP 正式测试 | `test/client/app_graph_observation_test.dart`、`client_retirement_report_test.dart`、`thread_status_bar_test.dart` | 新入口与既有应用／关闭／状态观察接缝，非 Timeline 行为不改 |
| APP 正式测试支持 | `test/client/support/recording_demo_transport.dart` | `RecordingTimelineConnection` 的脚本帧与真实 delegate 改 push／ACK／typed close |
| APP 非门禁测试 | `test/features/timeline/timeline_view_binding_test.dart` | 入口／必要 fake 迁移，详情和 binding 断言保留；不将它冒称正式门禁 |

View 库 part 中的 detail、group、preview-host 等符号来自库入口的共享 import；adapter 的
`studio_demo_api.dart` 同样是 `part of studio_api.dart`，不是可独立加 import 的新库。
`lib/src/rust/**`、所有生成 part、manifest／lock、xtask／AST 专属 fixture、design、CI、工程
报告和 Git 均由 root 拥有，A2 执行者不写。

## 4. 精确 port 与消费 capability

```dart
abstract interface class TimelineTransport {
  Future<StudioTimelineConnection> openTimeline(String threadId);
}

abstract interface class StudioTimelineConnection {
  Stream<StudioTimelineFeedFrame> get events;
  Future<void> ackThrough(int deliverySequence);
  Future<StudioTimelinePage> page({String? before, int? limit});
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  });
  void requestClose();
  Future<StudioFeedCloseReport> close();
}

typedef TimelineFrameConsumer = FutureOr<void> Function(StudioTimelineFrame frame);

// 运行时 lease，构造函数不公开。
abstract interface class TimelineConsumerLease {
  bool get isClosed;
  void requestClose();
  Future<void> close();
}

// 增加到现有 StudioTimelineChannel，其余既有公共方法含义不变。
TimelineConsumerLease attachConsumer(TimelineFrameConsumer consume);
```

- events 只允许一个订阅；第二个订阅为 typed Conflict，不默默打开新 native handle。
- getter 本身不建立第二条流；首次实际订阅才认领原 handle 的 stream。取消该流必须在 finally
  显式 requestClose／close；仅 native `Clean` 才 dispose opaque，Unresolved／异常保留句柄。
- ACK 为 int，0／旧 ACK 幂等；负参数为 InvalidArgument，closing 时 Cancelled 优先。Data
  sequence 必须从 1 严格连续；重复／跳号是 Protocol，不把它当成可覆盖样本。
- 原 u64→int 精确往返检查继续适用，包括 deliverySequence。超平台表示范围是
  Overloaded(retryable=false)，不能截断、改零或用 double。其它版本／字节值沿用既有精确转换。
- page/detail 与 stream／ACK 独立，不消耗首基线、不推进订阅版本。输入范围不变：页默认32、
  显式1..100；详情默认64KiB，显式最小 **4 字节**、最大 **256KiB**；cursor/continuation
  原样传递，空串不作 null，不把最小值误读成4KiB。
- attachConsumer 同步认领唯一 active consumer 并返回 lease，不在返回前回调正文；第二个 active
  consumer 为 Conflict，不覆盖原回调。无 pause／replay API。
- attach 到已有 demand 且当前 attempt 已开始消费首个 baseline 时，显式刷新为新 attempt／
  新 baseline，再交付正文；不能给新消费者仅重放上一个 Patch。若当前 attempt 仍未开始
  消费任何首基线，可以承接该已登记 opening 的首基线，无需退役后为同一份未消费基线再开
  句柄。是否已经开始消费基线在归并／发布状态前同步记录，不能等 UI 回调或 ACK 才置位。
  没有当前 attempt 时继续既有 demand／容量／retry 准入，不因 attach 另造平行 open。
- Channel 已 closing／closed 时 attachConsumer 返回 typed Cancelled，优先于重复消费者
  Conflict，不分配新的 lease；不借本规则取消仍由原 owner 收束的在途回调。
  consumer requestClose 同步封闭自身回调准入；close 等其在途回调结束。
- consumer lease 关闭不改变业务 demand、不关闭 Session、不清 Message／草稿。没有展示消费者
  时，领域服务仍可归并 saved 等事实并 ACK；重新展示必须取得新基线，不缓存未显示的正文队列。
- 消费回调不得等待自己所属 session／lease 的 close join；可同步 requestClose，join 由外层
  owner 执行，避免自等待。生产展示回调只有本篇明确的 controller 写入屏障，不等待布局／动画。

### 只读状态 capability

```dart
abstract interface class ReadonlyLatestValue<T> {
  T get value;
  int get observerCount;
  Observation watch(void Function(T) listener, {bool fireImmediately = false});
  LatestWatch<T> watchLatest(void Function(T) listener);
  Future<T> waitFor(bool Function(T) predicate);
}
```

`LatestValue<T>` 实现该 interface，原同步登记／暂停 latest 行为不变，不增加 wrapper 或第二份
state。Channel 私有持有可写 LatestValue，公开 `state` 静态类型改为
`ReadonlyLatestValue<ChatUiState<StudioTimelineFrame>>`。consumer／Widget／测试不能 publish；
测试经真实 port 输入触发状态，不保留仅为旧测试调用的 setter。

### Channel／QueryScope 其余公共面（完整冻结）

这些是既有生产资源能力，不是允许自由缩减或增加的接口。值／状态类型改走新入口，方法
语义按本篇 push／ACK／consumer／关闭纪律迁移，不保旧 pull 方法。

```dart
final class RetryPolicy {
  const RetryPolicy({
    List<Duration> delays = const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 400),
      Duration(seconds: 1),
    ],
  });
  final List<Duration> delays;
}

final class StudioTimelineChannel {
  StudioTimelineChannel({
    required String threadId,
    required TimelineTransport transport,
    ResourceBudget? budget,
    RetryPolicy retryPolicy = const RetryPolicy(),
  });
  final String threadId;
  final ResourceBudget budget;
  final RetryPolicy retryPolicy;
  ReadonlyLatestValue<ChatUiState<StudioTimelineFrame>> get state;
  bool get hasDemand;
  bool get isClosed;
  AttemptId? get currentAttemptId;
  int get ownedAttemptCount;
  StudioTimelineFrame? get lastDeliveredFrame;
  Future<StudioTimelineBaselineFrame> get ready;
  void start();
  void setDemand(bool value);
  void refresh();
  StudioTimelineQueryScope? openScope({required int generation});
  TimelineConsumerLease attachConsumer(TimelineFrameConsumer consume);
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup();
  Future<CloseReport> joinRetired({DateTime? deadline});
  static const int continuityItems = 100;
}

final class StudioTimelineQueryScope {
  final int generation;
  AttemptId get attemptId;
  String get threadId;
  int get pendingQueries;
  bool get isActive;
  Future<StudioTimelinePage> page({String? before, int? limit});
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  });
  void retire();
  Future<CloseReport> close({DateTime? deadline});
}
```

四个原生命周期异常保留：`const StaleTimelineAttempt()`、`const TimelineStreamEnded()`、
`const TimelineContinuityError(String reason)`（只读 `reason`）、`const StaleTimelineScope()`。
保留常量 `timelinePageDefaultLimit=32`、`timelinePageMaxLimit=100`、
`timelineDetailMinBytes=4`、`timelineDetailMaxBytes=262144`；不改变合法输入或扩大重试策略。

`ready` 只表示当前 attempt 已得到可用领域 baseline，不是 UI 写入、ACK、saved 或 durable
凭据；`lastDeliveredFrame` 只作当前 latest 诊断，不向新消费者重放 Patch。
`prepareSend`／`returnToLive` 只由第7节候选展示写入与发布边界完成，不能直接等 `ready`
就宣布展示准备成功。`joinRetired` 不结束健康当前 attempt，`close` 首调用冻结 deadline，
`retryCleanup` 仅继续等待原清理，绝不重发命令或创建替身句柄。

### saved 领域观察（非 UI 正文消费）

`observeSubmittedInput` 保留原 input／Turn 身份、saved／effective／durable 归并，不改成 UI
consumer，也不以 delivery ACK／terminal 代替 durable。它使用只读 state 观察时，必须在同一
同步登记边界消费 `watchLatest` 返回的当前值：登记 state／content observation 并持有其 lease
后，分别归并返回的当前 state 与内容 frame，不能只注册 listener 等未来下一帧。相关 receipt
已经晚于带 saved 的当前 baseline 时，无需再来一帧也能推进正确事实；加定向红绿回归保护。
观察取消仍只释放自身与预算，不改变 Session demand。此处不新增正文缓存或第二个 reducer。

## 5. Freezed 模型（全字段／变体）

Dart int 的序号／revision／bytes 非负且精确；时间继续 Unix 秒／既有 millis 单位，不做单位
推断。不可变集合由发布者冻结，Freezed 不可修改视图不能被当成允许生产者继续改原 List。
不增加 JSON 编解码／开放 map 兼容入口。

### 5.1 原 Timeline value：字段与构造含义不变，改为生成值

| 类型 | 全字段／变体 |
| --- | --- |
| StudioTimelineLifecycle | streaming、terminal |
| StudioTimelinePriority | immediate、coalesced |
| StudioTimelineResyncReason | lagging、unavailable |
| StudioTimelineRecoveryNotice | retry、result |
| StudioTimelineItemSource | content()=StudioTimelineContentSource；modelRecovery({required String attemptId, required StudioTimelineRecoveryNotice notice})=StudioTimelineRecoverySource |
| StudioTimelineDetailRef | required field:ThreadContentFieldView、revision:int、totalBytes:int、previewBytes:int；truncated=previewBytes<totalBytes |
| StudioTimelineItem | required item:ThreadItemView、saved:bool、lifecycle:StudioTimelineLifecycle、omittedBytes:int、details:List<StudioTimelineDetailRef>；source默认const StudioTimelineContentSource()；保留id/revision/terminal/detailFor getter／方法语义 |
| StudioTimelineBaseline | required subscriptionId:String、version:int、items:List<StudioTimelineItem>、before:String?、hasOlder:bool |
| StudioTimelinePage | required items:List<StudioTimelineItem>、before:String?、hasOlder:bool |
| StudioFieldUpdateView | required field:ThreadContentFieldView、change:ThreadFieldChangeView、totalBytes:int、previewBytes:int |
| StudioTimelineChange | add(StudioTimelineItem item)=StudioTimelineAdd；updateItem({required String itemId,required int expectedRevision,required int revision,required int omittedBytes,required bool saved,required StudioTimelineLifecycle lifecycle,ThreadItemView? itemShell,required List<StudioFieldUpdateView> fields})=StudioTimelineUpdateItem；remove(String itemId)=StudioTimelineRemove |
| StudioTimelineUpdate | patch({required String subscriptionId,required int from,required int to,required List<StudioTimelineChange> changes,required StudioTimelinePriority priority})=StudioTimelinePatch；resync({required String subscriptionId,required StudioTimelineResyncReason reason,required StudioTimelineBaseline baseline})=StudioTimelineResync |
| StudioTimelineFrame | baseline(StudioTimelineBaseline baseline,{StudioTimelineResyncReason? resyncReason})=StudioTimelineBaselineFrame；patch(StudioTimelinePatch patch)=StudioTimelinePatchFrame |
| StudioTimelineDetailQuery | required field:ThreadContentFieldView、revision:int；continuation:String?、maxBytes:int? 默认null |
| StudioTimelineDetailChunk | required itemId:String、field:ThreadContentFieldView、revision:int、text:String、totalBytes:int、continuation:String?；isLast=continuation==null |

原 public redirect 类名与构造字段保留，调用点不必为 Freezed 改业务意义。union factory 名按表；
`StudioTimelineBaselineFrame.isResync` 仍为 resyncReason!=null，可用同模型库内 public extension
`StudioTimelineBaselineFrameProperties` 表达。不为 value 自己维护 ==/hash/copyWith。

嵌套 `ThreadItemView`／字段变化／错误等沿用已存在 typed 定义，本切片不重写 thread_models。
`itemShell==null` 是静态壳未变；空 items 是有效基线；hasOlder 不是条数判断；saved 与 terminal
和 revision 独立；同 revision 的 saved 更新合法。Resync 同连接保持 subscriptionId。

### 5.2 新传输值（Freezed）

```dart
sealed class StudioTimelineFeedFrame {
  const factory StudioTimelineFeedFrame.data({
    required int deliverySequence,
    required StudioTimelineFeedEvent event,
  }) = StudioTimelineFeedData;
  const factory StudioTimelineFeedFrame.failure({required StudioFailure error})
      = StudioTimelineFeedFailure;
  const factory StudioTimelineFeedFrame.closed() = StudioTimelineFeedClosed;
}

sealed class StudioTimelineFeedEvent {
  const factory StudioTimelineFeedEvent.baseline({
    required StudioTimelineBaseline baseline,
  }) = StudioTimelineFeedBaseline;
  const factory StudioTimelineFeedEvent.update({required StudioTimelineUpdate update})
      = StudioTimelineFeedUpdate;
}
```

首 data 只能是 baseline；同连接后续 baseline 只能通过 Update::Resync 表达。Failure 后无 data；
Closed 为传输结束，不是 saved／Turn terminal。展示帧没有 deliverySequence；传输确认身份不
混进 UI content revision，唯一 Channel 在原 attempt 上保留并确认它。

### 5.3 shared close 值（Freezed，resources 公共入口）

```dart
class StudioFeedCloseReport {
  const factory StudioFeedCloseReport({
    required String feedId,
    required StudioFeedCloseOutcome outcome,
  });
  bool get isClean; // outcome is StudioFeedCloseClean
}
sealed class StudioFeedCloseOutcome {
  const factory StudioFeedCloseOutcome.clean() = StudioFeedCloseClean;
  const factory StudioFeedCloseOutcome.unresolved({
    required List<StudioShutdownIssue> issues,
  }) = StudioFeedCloseUnresolved;
}
class StudioFeedCloseFailure implements Exception {
  const factory StudioFeedCloseFailure({required StudioFeedCloseReport report});
}
```

报告 feedId 必须非空，已收到 baseline 时须与该 attempt.subscriptionId 相同；Unresolved issues
必须非空，否则 Protocol，不能 dispose。`StudioShutdownIssue` 沿用现有完整字段
stage/code/message/correlationId:String、retryable:bool，不复制第二套同构类型。保留原脱敏
message/correlation，不从 message 推断分类，不把 issues 丢成单个泛化字符串。

adapter 的 close Future 幂等：返回 Clean 后才 dispose；Unresolved 返回 typed 报告并持有opaque，
重复 close 观察同一报告；真正 bridge 异常不 dispose，允许原 owner 后续 join 重试。Channel
将 Unresolved 报告作为 StudioFeedCloseFailure 留入现有 CloseReport／UnresolvedResource，
只有真实 Native Clean、query／consumer／stream 都结束才释放 permit。

FRB adapter 的关闭同时拥有 native join 与本地原生流转发订阅的取消。两条完成及错误归属
必须在等待前登记；即使一条先失败，也要收束另一条。只有 native Clean 且本地取消成功才
dispose。本地取消失败用现有 StudioShutdownIssue 并入 Unresolved，完整保留已有 native
issues 与 correlation；重复 close 观察同一 unresolved 报告，不因后续调用伪造 Clean。
Stream.cancel 等待同一个关闭责任，Unresolved 通过现有 StudioFeedCloseFailure 传播，
真正 native join 异常仍保留 typed StudioFailure 与原句柄。关闭不能等待自己的本地
controller done／onCancel 回调；Dart 业务 consumer 的等待仍由 Channel owner 负责。

## 6. 顺序、消费 ACK 与关闭状态机

原 attempt/DemandVersion/QueryScope 身份和首次 await 前冻结规则不变。传输 sequence、
subscription version、item revision、UI generation、业务保存各自独立。

```text
open attempt:
  在首次 await 前登记 attempt、chatHandle permit、原 open Future 和 openSettled 完成屏障
  await open；成功 handle 立即归原 attempt；成功或失败都完成 openSettled
  旧 attempt 晚到 handle 不能进新界面，必须由旧 cleanup 关闭

consume one push stream:
  只订阅一次（可用标准 StreamIterator；其 moveNext 是本地流消费，不是 FRB next RPC）
  first Data seq=1 + Baseline；后续 Data seq严格+1，随后只允许Update
  typed校验 → 原有有界身份/revision reducer → 发布领域状态镜像
  同步捕获唯一 consumer lease/generation；若存在，await consume(frame)
  await后核对原attempt、target、generation；旧回调只结算自身，不能写新状态或ACK新handle
  成功完成上述归并和展示交接才 ackThrough(原sequence)
  转换/归并/消费失败不ACK，进入typed失败及原attempt收束，不跳过
  没有展示consumer时只做领域归并与观察，不积累等待UI重放的正文

retire / close:
  先retired/封新query与consumer，再同步 requestClose native，取消原stream等待
  原 cleanup Future 幂等，等待 openSettled，处理晚到handle
  native close、stream cancel、query scope join 与当前consumer调用收束并行启动
  不等consumer结束才发native取消，也不等待attempt.task自己（避免finally→cleanup→task自环）
  真实join后检查NativeCloseReport；任何Unresolved/失败保留原owner与permit
  所有工作真实结束+NativeClean才释放预算与移除attempt；旧finally不改新pending
```

每个 attempt 最多一个在途 consumer 调用；不为每帧接 `.then` 链排后台队列。consumer lease
取消后不再准入新回调；其 close 等已开始的回调，不能假装同步返回就是回调 Future 已结束。
关闭顺序包含 stream cancel 的 adapter finally，不能形成 close→cancel→close 自等待；native
close 的共享 Future 不等待 Dart 业务回调。取消失败／超时仍由原 attempt 保留并可诊断。

应用 close 继续复用首 deadline；opening/active/retiring/unresolved 都占 chatHandle permit。
原 ResourceBudget 数值保持：chatHandle=2、pendingOperation=64、draft=64、attachment=256、
observer=1024、readModel=256；capacity 只在真实 permit 释放后唤醒，不轮询。原连续性身份副本
最多100，不存第二正文。原观察重试 delays 100ms/400ms/1s 不增加次数或期限。

### 传输与错误矩阵

| 事实 | typed 结果／动作 |
| --- | --- |
| 原 port 参数非法 | InvalidArgument，不夹紧；closing时Cancelled优先 |
| seq重复/跳号、首帧非baseline、第二baseline、身份/版本倒退 | Protocol，不ACK；关闭原feed，不自动重放命令 |
| 原内容连续性缺口 | TimelineContinuityError，重建本feed新基线，保留last-known／History |
| StudioFailure.retryable=true的观察故障、真实意外EOF | 复用原最多3次只读重订阅；非retryable不自动循环 |
| cancel/runtimeStopped/permissionDenied/invalidArgument/无法表示的数值 | 不自动重订阅；旧attempt取消不污染新目标 |
| consumer/controller应用错误 | 不ACK，保留typed cause/last-known；不自动循环同一呈现错误 |
| core Update::Resync | 普通有额度data，Live换展示代次，History保留冻结集合只更新提示 |
| CloseReport.Unresolved | 不dispose、不释放permit，保留typed issues与原owner |
| consumer重复登记 | Conflict，不换掉正在使用的consumer |

非幂等写入／新会话创建／手动压缩都不在此重订阅策略中，绝不自动重发。

## 7. 有界展示交接（root固定）

当前 `TimelineSessionOwner` 的状态观察继续更新 connection 状态，但删除其中对正文
`_applyFrame` 的调用。正文只走 attachConsumer 的可等待回调；Settings 往返不销毁该owner或
consumer，真正 Thread 切换／退出才显式解绑。

现有 `InMemoryChatController` 方法返回 Future；即使其当前实现先同步写列表，也不能忽略
Future 的异常后提前ACK。新增私有展示写入屏障，收集**当前 frame／当前页**产生的原生
controller Future 并 await 成功；不增加 Message 副本、逐帧全表diff或跨帧 future 链。
确认的是唯一 controller 的消息写入／错误收束，不等待布局、绘制或动画。

跨应用展示库的唯一新增共享方法固定为：

```dart
// 增加到既有 TimelinePresentationController；原构造、add/replace/remove/reset 等签名不变。
Future<void> flushWrites();
```

它在调用的同步阶段认领自上次 flush 以来已经启动的本批 stock controller 写入，返回的 Future
只在本批全部真实结束后结算，失败传播给调用方，不把第一项失败当作其它写入已结束。
不是等待未来所有帧的全局 flush，也不为下一帧排前一帧的 future 链。每批开始后立即登记
错误处理与归属，即使同步变换中途抛出，也要收束本批已经启动的写入，不能产生 Zone-only
异常。展示 owner 仅通过当前／候选 lease 的既有 presentation 实例等待它，不公开给 Widget。
组件测试可用官方 `InMemoryChatController` 的合法子类提供完成／失败 gate，调用真实
presentation 方法与 flush；不为测试新增 lease/controller factory 参数或另造 controller 框架。

- 当前 display lease 的 `applyPatch`／页插入可以保持同步 canonical 计算，但内容回调返回前必须
  await 本批 controller 写入屏障。错误必须传回 Channel，不能只 unawaited 后交 Zone 记录。
- 新 baseline 先构造未发布的候选 lease，await 其 controller 写入屏障，再核对目标／代次；成功后
  才交换当前 lease、发布 binding、完成 pending prepareSend／returnToLive，并退役旧lease。
  失败／过时代次只收束候选，保留已显示旧lease与错误，不提前宣告准备成功。
- History 的已显示结构／saved／正文仍冻结；回调可以仅记录提示并成功确认数据，不为未来回放
  另存正文。只有显式回Live／发送建立新代次。
- 当前/候选/退役的consumer与controller写入 Future 都由展示owner登记并参与其close。控制器
  仍在真实子树解绑且查询／写入完成后dispose，不破坏原mount/unbind/released握手。
- 页查询仍每展示代次最多一个在途分页，控制器屏障只持本批操作结果，不排跨帧正文队列。

## 8. Demo 与测试替身

- Demo 生产 port 也改为同样的 events/ACK/typed close；不保留公开 initial/next 或回调转发alias。
- 复用已有 demo typed 事实／有界尾部／页／详情算法，变化以事件通知触发；不得改成定时查询，
  不另造第二份历史。满两额度只持最多一个待发结果，恢复时由既有连续性机制Patch／Resync。
- Demo 与 native 各自既有预览计量保留；demo不是Rust canonical JSON或wire字节的证明，不能
  为相等数值复制canonical编码器。两额度与无隐藏待发队列的行为必须相同。
- fake仅脚本化环境输入和join gate，不重新实现Channel reducer／ACK决策后自测；测试helper
  可以用标准StreamIterator读push，不是保留产品RPC拉取接口。
- 已有frb_timeline_adapter、timeline_demo_tail、SDKtimeline_tail/chat_lifecycle/thread_session/
  drafts/receipts及UIlease测试迁移至新接口，保留原错误、Unicode、字段、分页、保存／终态断言。

## 9. root 前置：SDK Freezed 与统一生成

root 独占 manifest／lock／xtask，不由执行者自行添加依赖或跑生成器。

固定依赖选择（已有应用使用、纯Dart工具，非新组件路线）：

- SDK runtime：`freezed_annotation: 3.1.0`；禁止 Flutter／Riverpod／FRB；
- SDK dev：保留 `test: ^1.33.0`，加 `build_runner: 2.16.2`、`freezed: 4.0.2`；
- 不加 json_serializable、状态管理、消息bus或codec；版本刻意与现有应用lock一致，不顺便升级。

root 更新统一 generate-gui，使其在正确 SDK package 目录解析依赖、运行官方build_runner、
规范化／格式化生成文件，并把 SDK `.g.dart/.freezed.dart` 纳入 canonical snapshot／孤儿清理。
build/check生成使用已审lock，不在SDK安装目录执行命令，不直接运行孤立生成器。SDK runtime
manifest与AST import guard精确允许上述annotation公共入口，不解禁其它package／Flutter/FRB。
现有adapter测试集加入正反例，不能为了Freezed关闭整条层边界检查。

## 10. 所有权、步骤与验收

root 负责第9节和共享文档、生成、CI、全量／GUI／PR。一个执行者拥有第3节列出的SDK手写、
app adapter/demo/UI展示接缝及真实消费者／测试迁移；不写Rust/native、生成、manifest、lock、
xtask、边界检查器或其专属fixture、design、Git。派发时提供最窄目录和明确禁止文件。

步骤：

1. 核对最新 native 审查/生成身份及本合同，读既有算法／测试，不重新设计接口。
2. 迁移 Freezed value 与公共入口、typed port/close、只读state capability。
3. 迁移 Channel 唯一push消费／ACK／consumer lease／真实清理，保留100身份/预算/原attempt。
4. 迁移 FRB adapter、demo、UI交接与候选lease/写入屏障，删除旧pull出口和错误的latest正文入口。
5. 迁移全部真实caller与测试。输入稳定后暂停，请root统一generate-gui；不手改生成。
6. 生成后执行局部 SDK／adapter定向测试和静态检查；完成报告后冻结范围交fresh reviewer。

| 风险／要求 | 最小充分证据 | 不替代的证据 |
| --- | --- | --- |
| seq与消费ACK | 真实Channel+脚本port：baseline/patch归并、消费gate前无ACK、成功才ACK、错误不ACK、句柄隔离 | native窗口由T1.A与rootFFI证明 |
| 不用latest丢正文 | UI consumer专用通道；状态observer暂停不影响顺序；consumer仅一个；已消费基线后重绑换attempt；首基线未消费的opening接入不重复open；关闭拒新lease | native真实流式/Settings旅程 |
| close与lateopen | 控制open/query/consumer/close gate，fullwindow取消，旧finally不碰新attempt，permit未真结束不释放 | 操作系统/进程回收 |
| typed close报告 | FRB DTO→domain全部issues，Clean才dispose，Unresolved保handle/permit、重复结果一致 | Rustpanic真实join由T1.A |
| UI写入与准备 | controller Future gate／失败时不ACK；候选baseline成功前不发布/不完成prepareSend；旧lease不早dispose | 真实布局/滚动/动画/截图 |
| history/page/detail | 复用既有完整断言；冻结、显式换代、cursor、EOF/错误、Unicode/u64边界不弱化 | 原生大历史／数据库 |
| saved 观察登记 | 同步消费当前 state／内容值；receipt 晚到已保存 baseline 仍按 input 推进 durable；保留原身份／未 saved 终态不算 durable 断言 | 真实 native durable 保存与跨域最终验收 |
| Freezed与分层 | 实际生成/analyze；既有AST规则+annotation正反例；无旧文件/alias引用 | 整体VM/Smart-Dumb在T3/T4 |

局部命令由root的正确cwd统一入口支持；执行者只跑自身范围格式／analyze／定向测试，不全仓
门禁，不在SDK目录或直接flutter build/run。若当前入口无法定向，报告root而不自行扩大。
root代码阶段提交前执行完整适用Rust/Dart/GUI门禁与native验收，再commit/push PR120。

必须遵守本篇全部字段／方法／owner／时序／错误／预算；私有函数和容器可局部选择。若遇公共
契约／native结果／生成能力冲突，先停受影响范围报告root，不擅自加fallback/alias/新依赖。
