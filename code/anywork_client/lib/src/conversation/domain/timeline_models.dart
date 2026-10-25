import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'thread_content.dart';

part 'timeline_models.freezed.dart';

/// 条目的执行终态事实（后端 `BridgeTimelineLifecycle`），与保存水位
/// [StudioTimelineItem.saved] 严格独立。
enum StudioTimelineLifecycle { streaming, terminal }

/// 后端只读来源语义；与逐条保存及 GUI 展示身份分别表达。
@Freezed(toStringOverride: false)
sealed class StudioTimelineItemSource with _$StudioTimelineItemSource {
  const StudioTimelineItemSource._();

  const factory StudioTimelineItemSource.content() =
      StudioTimelineContentSource;

  const factory StudioTimelineItemSource.modelRecovery({
    required String attemptId,
    required StudioTimelineRecoveryNotice notice,
  }) = StudioTimelineRecoverySource;
}

enum StudioTimelineRecoveryNotice { retry, result }

/// 一个内容字段的详情引用：完整正文按 `(item, field, revision)` 读取。
///
/// [StudioTimelineDetailRef.totalBytes] 是该字段完整正文的 UTF-8 字节数，
/// [StudioTimelineDetailRef.previewBytes] 是本次预览实际携带的字节数。两者都不等于
/// Dart 字符串长度：消费者不得据此切分字符串。
@Freezed(toStringOverride: false)
abstract class StudioTimelineDetailRef with _$StudioTimelineDetailRef {
  const StudioTimelineDetailRef._();

  const factory StudioTimelineDetailRef({
    required ThreadContentFieldView field,
    required int revision,
    required int totalBytes,
    required int previewBytes,
  }) = _StudioTimelineDetailRef;

  /// 该字段的预览被省略：完整正文仍然是可用事实，只是需要显式详情读取。
  bool get truncated => previewBytes < totalBytes;
}

/// 一条时间线条目的预览值。
///
/// [StudioTimelineItem.item] 是 canonical typed 条目的**预览**投影；完整工具参数、结果、
/// 原始记录与产物正文只能通过 [StudioTimelineItem.details] 指向的详情读取获得，不在这里
/// 常驻。
@Freezed(toStringOverride: false)
final class StudioTimelineItem with _$StudioTimelineItem {
  StudioTimelineItem({
    required this.item,
    this.source = const StudioTimelineContentSource(),
    required this.saved,
    required this.lifecycle,
    required this.omittedBytes,
    required List<StudioTimelineDetailRef> details,
  }) : details = List.unmodifiable(details);
  final ThreadItemView item;
  final StudioTimelineItemSource source;
  final bool saved;
  final StudioTimelineLifecycle lifecycle;
  final int omittedBytes;
  final List<StudioTimelineDetailRef> details;

  String get id => item.id;
  int get revision => item.revision;
  bool get terminal => lifecycle == StudioTimelineLifecycle.terminal;

  /// 该字段的详情引用；从未交付过该字段时返回 null（与“空字段”不同）。
  StudioTimelineDetailRef? detailFor(ThreadContentFieldView field) {
    for (final detail in details) {
      if (detail.field == field) return detail;
    }
    return null;
  }
}

/// 一条尾部连接的基线：与接收者登记一致的最新小页。
@Freezed(toStringOverride: false)
final class StudioTimelineBaseline with _$StudioTimelineBaseline {
  StudioTimelineBaseline({
    required this.subscriptionId,
    required this.version,
    required List<StudioTimelineItem> items,
    this.before,
    required this.hasOlder,
  }) : items = List.unmodifiable(items);
  final String subscriptionId;
  final int version;
  final List<StudioTimelineItem> items;
  final String? before;
  final bool hasOlder;
}

/// 一页升序预览条目、下一更旧边界与是否真的还有更旧内容。
@Freezed(toStringOverride: false)
final class StudioTimelinePage with _$StudioTimelinePage {
  StudioTimelinePage({
    required List<StudioTimelineItem> items,
    this.before,
    required this.hasOlder,
  }) : items = List.unmodifiable(items);
  final List<StudioTimelineItem> items;
  final String? before;
  final bool hasOlder;
}

/// 同一 item 的一个字段变化，携带该字段一次提交的完整/预览字节数。
@Freezed(toStringOverride: false)
abstract class StudioFieldUpdateView with _$StudioFieldUpdateView {
  const StudioFieldUpdateView._();

  const factory StudioFieldUpdateView({
    required ThreadContentFieldView field,
    required ThreadFieldChangeView change,
    required int totalBytes,
    required int previewBytes,
  }) = _StudioFieldUpdateView;
}

/// 一帧尾部变化里按身份表达的单条事实。
@Freezed(toStringOverride: false)
sealed class StudioTimelineChange with _$StudioTimelineChange {
  const StudioTimelineChange._();

  /// 订阅尚未交付过的一条权威条目。
  const factory StudioTimelineChange.add(StudioTimelineItem item) =
      StudioTimelineAdd;

  /// 同一身份的全部内容与状态字段，在**一次** expectedRevision/revision 提交里原子应用。
  factory StudioTimelineChange.updateItem({
    required String itemId,
    required int expectedRevision,
    required int revision,
    required int omittedBytes,
    required bool saved,
    required StudioTimelineLifecycle lifecycle,
    ThreadItemView? itemShell,
    required List<StudioFieldUpdateView> fields,
  }) = StudioTimelineUpdateItem;

  /// 真实删除：该身份不再存在。预览缓存退出不是删除。
  const factory StudioTimelineChange.remove(String itemId) =
      StudioTimelineRemove;
}

@Freezed(toStringOverride: false)
final class StudioTimelineUpdateItem extends StudioTimelineChange
    with _$StudioTimelineUpdateItem {
  StudioTimelineUpdateItem({
    required this.itemId,
    required this.expectedRevision,
    required this.revision,
    required this.omittedBytes,
    required this.saved,
    required this.lifecycle,
    this.itemShell,
    required List<StudioFieldUpdateView> fields,
  }) : fields = List.unmodifiable(fields),
       super._();
  final String itemId;
  final int expectedRevision;
  final int revision;
  final int omittedBytes;
  final bool saved;
  final StudioTimelineLifecycle lifecycle;
  final ThreadItemView? itemShell;
  final List<StudioFieldUpdateView> fields;
}

/// 一帧是否需要立即应用，还是普通文本已经合帧。
enum StudioTimelinePriority { immediate, coalesced }

/// 订阅无法继续用连续补丁表达时重新建立基线的原因。
enum StudioTimelineResyncReason { lagging, unavailable }

/// transport 交付的一帧尾部更新。
@Freezed(toStringOverride: false)
sealed class StudioTimelineUpdate with _$StudioTimelineUpdate {
  const StudioTimelineUpdate._();

  /// 连续补丁：`from` 必须等于本地已交付版本。
  factory StudioTimelineUpdate.patch({
    required String subscriptionId,
    required int from,
    required int to,
    required List<StudioTimelineChange> changes,
    required StudioTimelinePriority priority,
  }) = StudioTimelinePatch;

  /// 无法连续表达：给出原因与新的最新小页基线，同连接沿用本订阅身份。
  const factory StudioTimelineUpdate.resync({
    required String subscriptionId,
    required StudioTimelineResyncReason reason,
    required StudioTimelineBaseline baseline,
  }) = StudioTimelineResync;
}

@Freezed(toStringOverride: false)
final class StudioTimelinePatch extends StudioTimelineUpdate
    with _$StudioTimelinePatch {
  StudioTimelinePatch({
    required this.subscriptionId,
    required this.from,
    required this.to,
    required List<StudioTimelineChange> changes,
    required this.priority,
  }) : changes = List.unmodifiable(changes),
       super._();
  final String subscriptionId;
  final int from;
  final int to;
  final List<StudioTimelineChange> changes;
  final StudioTimelinePriority priority;
}

/// 唯一内容消费路径交付给展示消费者的帧。
///
/// 只有两种形状：**建立/重建整份展示**的基线帧，与**按身份增量**的补丁帧。消费方先应用
/// 基线，再逐条应用补丁；无法证明连续时显式按重同步处理，不逐帧比较全部已加载历史。
@Freezed(toStringOverride: false)
sealed class StudioTimelineFrame with _$StudioTimelineFrame {
  const StudioTimelineFrame._();

  /// 基线帧：新一代展示或同连接显式重同步。
  const factory StudioTimelineFrame.baseline(
    StudioTimelineBaseline baseline, {
    StudioTimelineResyncReason? resyncReason,
  }) = StudioTimelineBaselineFrame;

  /// 补丁帧：按身份增量，`patch.from` 必须等于消费者自己已应用的版本。
  const factory StudioTimelineFrame.patch(StudioTimelinePatch patch) =
      StudioTimelinePatchFrame;
}

/// 基线帧的只读属性；同模型库内 public extension 表达。
extension StudioTimelineBaselineFrameProperties on StudioTimelineBaselineFrame {
  /// 非空表示这是同连接的重同步基线，而不是一次新订阅的首帧。
  bool get isResync => resyncReason != null;
}

/// 详情读取请求：item 由调用参数给出，其余绑定在同一份 typed 请求里。
@Freezed(toStringOverride: false)
abstract class StudioTimelineDetailQuery with _$StudioTimelineDetailQuery {
  const StudioTimelineDetailQuery._();

  const factory StudioTimelineDetailQuery({
    required ThreadContentFieldView field,
    required int revision,
    String? continuation,
    int? maxBytes,
  }) = _StudioTimelineDetailQuery;
}

/// 一段完整正文块。
@Freezed(toStringOverride: false)
abstract class StudioTimelineDetailChunk with _$StudioTimelineDetailChunk {
  const StudioTimelineDetailChunk._();

  const factory StudioTimelineDetailChunk({
    required String itemId,
    required ThreadContentFieldView field,
    required int revision,
    required String text,
    required int totalBytes,
    String? continuation,
  }) = _StudioTimelineDetailChunk;

  /// continuation 为 null 表示本字段已读完。
  bool get isLast => continuation == null;
}

/// transport 推送的一帧投送事实。
///
/// `data` 携带单调递增的 `deliverySequence`（从 1 开始，基线也占额度）；`failure` 是
/// 至多一次的 typed 传输失败；`closed` 是传输结束，**不是** saved／Turn terminal。
@Freezed(toStringOverride: false)
sealed class StudioTimelineFeedFrame with _$StudioTimelineFeedFrame {
  const StudioTimelineFeedFrame._();

  const factory StudioTimelineFeedFrame.data({
    required int deliverySequence,
    required StudioTimelineFeedEvent event,
  }) = StudioTimelineFeedData;

  const factory StudioTimelineFeedFrame.failure({
    required StudioFailure error,
  }) = StudioTimelineFeedFailure;

  const factory StudioTimelineFeedFrame.closed() = StudioTimelineFeedClosed;
}

/// data 帧的业务事件：首个 data 只能是 baseline，同连接后续 baseline 只能经
/// `Update::Resync` 表达。
@Freezed(toStringOverride: false)
sealed class StudioTimelineFeedEvent with _$StudioTimelineFeedEvent {
  const StudioTimelineFeedEvent._();

  const factory StudioTimelineFeedEvent.baseline({
    required StudioTimelineBaseline baseline,
  }) = StudioTimelineFeedBaseline;

  const factory StudioTimelineFeedEvent.update({
    required StudioTimelineUpdate update,
  }) = StudioTimelineFeedUpdate;
}
