import '../../models.dart';

/// 条目的执行终态事实（后端 `BridgeTimelineLifecycle`），与保存水位
/// [StudioTimelineItem.saved] 严格独立。
enum StudioTimelineLifecycle { streaming, terminal }

/// 后端只读来源语义；与逐条保存及 GUI 展示身份分别表达。
sealed class StudioTimelineItemSource {
  const StudioTimelineItemSource();
}

final class StudioTimelineContentSource extends StudioTimelineItemSource {
  const StudioTimelineContentSource();
}

enum StudioTimelineRecoveryNotice { retry, result }

final class StudioTimelineRecoverySource extends StudioTimelineItemSource {
  const StudioTimelineRecoverySource({
    required this.attemptId,
    required this.notice,
  });
  final String attemptId;
  final StudioTimelineRecoveryNotice notice;
}

/// 一个内容字段的详情引用：完整正文按 `(item, field, revision)` 读取。
///
/// `totalBytes` 是该字段完整正文的 UTF-8 字节数，`previewBytes` 是本次预览实际携带的
/// 字节数。两者都不等于 Dart 字符串长度：消费者不得据此切分字符串。
class StudioTimelineDetailRef {
  const StudioTimelineDetailRef({
    required this.field,
    required this.revision,
    required this.totalBytes,
    required this.previewBytes,
  });

  final ThreadContentFieldView field;
  final int revision;
  final int totalBytes;
  final int previewBytes;

  /// 该字段的预览被省略：完整正文仍然是可用事实，只是需要显式详情读取。
  bool get truncated => previewBytes < totalBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioTimelineDetailRef &&
          field == other.field &&
          revision == other.revision &&
          totalBytes == other.totalBytes &&
          previewBytes == other.previewBytes;

  @override
  int get hashCode => Object.hash(field, revision, totalBytes, previewBytes);
}

/// 一条时间线条目的预览值。
///
/// [item] 是 canonical typed 条目的**预览**投影；完整工具参数、结果、原始记录与产物正文
/// 只能通过 [details] 指向的详情读取获得，不在这里常驻。
class StudioTimelineItem {
  const StudioTimelineItem({
    required this.item,
    this.source = const StudioTimelineContentSource(),
    required this.saved,
    required this.lifecycle,
    required this.omittedBytes,
    required this.details,
  });

  final ThreadItemView item;
  final StudioTimelineItemSource source;
  final bool saved;
  final StudioTimelineLifecycle lifecycle;

  /// 预览省略的正文总字节数；零表示所有字段都是完整正文。
  final int omittedBytes;

  /// 本条目所有按字段绑定的详情引用。
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
class StudioTimelineBaseline {
  const StudioTimelineBaseline({
    required this.subscriptionId,
    required this.version,
    required this.items,
    required this.before,
    required this.hasOlder,
  });

  /// 本连接的订阅身份；重连换新，同连接重同步保持不变。
  final String subscriptionId;

  /// 订阅自己的内容版本；与条目 revision、持久化水位无关。
  final int version;
  final List<StudioTimelineItem> items;

  /// 直接继续翻更旧一页的不透明边界 token；只有 [hasOlder] 为真时给出。
  final String? before;

  /// 是否真的还有更旧内容（真实存在性证明，不凭条数猜 EOF）。
  final bool hasOlder;
}

/// 一页升序预览条目、下一更旧边界与是否真的还有更旧内容。
class StudioTimelinePage {
  const StudioTimelinePage({
    required this.items,
    required this.before,
    required this.hasOlder,
  });

  final List<StudioTimelineItem> items;
  final String? before;
  final bool hasOlder;
}

/// 同一 item 的一个字段变化，携带该字段一次提交的完整/预览字节数。
class StudioFieldUpdateView {
  const StudioFieldUpdateView({
    required this.field,
    required this.change,
    required this.totalBytes,
    required this.previewBytes,
  });

  final ThreadContentFieldView field;
  final ThreadFieldChangeView change;

  /// 该字段完整正文的 UTF-8 字节数；预览被截断时仍是原文长度。
  final int totalBytes;

  /// 本次交付的预览字节数。
  final int previewBytes;
}

/// 一帧尾部变化里按身份表达的单条事实。
sealed class StudioTimelineChange {
  const StudioTimelineChange();
}

/// 订阅尚未交付过的一条权威条目。
final class StudioTimelineAdd extends StudioTimelineChange {
  const StudioTimelineAdd(this.item);
  final StudioTimelineItem item;
}

/// 同一身份的全部内容与状态字段，在**一次** expectedRevision/revision 提交里原子应用。
final class StudioTimelineUpdateItem extends StudioTimelineChange {
  const StudioTimelineUpdateItem({
    required this.itemId,
    required this.expectedRevision,
    required this.revision,
    required this.omittedBytes,
    required this.saved,
    required this.lifecycle,
    required this.fields,
    this.itemShell,
  });

  final String itemId;
  final int expectedRevision;
  final int revision;
  final int omittedBytes;
  final bool saved;
  final StudioTimelineLifecycle lifecycle;
  final ThreadItemView? itemShell;
  final List<StudioFieldUpdateView> fields;
}

/// 真实删除：该身份不再存在。预览缓存退出不是删除。
final class StudioTimelineRemove extends StudioTimelineChange {
  const StudioTimelineRemove(this.itemId);
  final String itemId;
}

/// 一帧是否需要立即应用，还是普通文本已经合帧。
enum StudioTimelinePriority { immediate, coalesced }

/// 订阅无法继续用连续补丁表达时的原因。
enum StudioTimelineResyncReason { lagging, unavailable }

/// transport 交付的一帧尾部更新。
sealed class StudioTimelineUpdate {
  const StudioTimelineUpdate();
}

/// 连续补丁：`from` 必须等于本地已交付版本。
final class StudioTimelinePatch extends StudioTimelineUpdate {
  const StudioTimelinePatch({
    required this.subscriptionId,
    required this.from,
    required this.to,
    required this.changes,
    required this.priority,
  });

  final String subscriptionId;
  final int from;
  final int to;
  final List<StudioTimelineChange> changes;
  final StudioTimelinePriority priority;
}

/// 无法连续表达：给出原因与新的最新小页基线，同连接沿用本订阅身份。
final class StudioTimelineResync extends StudioTimelineUpdate {
  const StudioTimelineResync({
    required this.subscriptionId,
    required this.reason,
    required this.baseline,
  });

  final String subscriptionId;
  final StudioTimelineResyncReason reason;
  final StudioTimelineBaseline baseline;
}

/// 唯一内容泵交付给展示消费者的帧。
///
/// 只有两种形状：**建立/重建整份展示**的基线帧，与**按身份增量**的补丁帧。消费方先应用
/// 基线，再逐条应用补丁；无法证明连续时显式按重同步处理，不逐帧比较全部已加载历史。
sealed class StudioTimelineFrame {
  const StudioTimelineFrame();
}

/// 基线帧：新一代展示或同连接显式重同步。
final class StudioTimelineBaselineFrame extends StudioTimelineFrame {
  const StudioTimelineBaselineFrame(this.baseline, {this.resyncReason});

  final StudioTimelineBaseline baseline;

  /// 非空表示这是同连接的重同步基线，而不是一次新订阅的首帧。
  final StudioTimelineResyncReason? resyncReason;

  bool get isResync => resyncReason != null;
}

/// 补丁帧：按身份增量，`patch.from` 必须等于消费者自己已应用的版本。
final class StudioTimelinePatchFrame extends StudioTimelineFrame {
  const StudioTimelinePatchFrame(this.patch);
  final StudioTimelinePatch patch;
}

/// 详情读取请求：item 由调用参数给出，其余绑定在同一份 typed 请求里。
class StudioTimelineDetailQuery {
  const StudioTimelineDetailQuery({
    required this.field,
    required this.revision,
    this.continuation,
    this.maxBytes,
  });

  final ThreadContentFieldView field;

  /// 该字段读取绑定的内容版本；版本变化必须显式重读，不能拼接跨 revision 正文。
  final int revision;

  /// 上一块返回的不透明 continuation；首块为 null。
  final String? continuation;

  /// 单块最大 UTF-8 字节数：默认 64 KiB，允许 4 字节到 256 KiB。
  final int? maxBytes;
}

/// 一段完整正文块。
class StudioTimelineDetailChunk {
  const StudioTimelineDetailChunk({
    required this.itemId,
    required this.field,
    required this.revision,
    required this.text,
    required this.totalBytes,
    required this.continuation,
  });

  final String itemId;
  final ThreadContentFieldView field;
  final int revision;
  final String text;

  /// 该字段完整正文的 UTF-8 字节数。
  final int totalBytes;

  /// 下一块的不透明 continuation；null 表示本字段已读完。
  final String? continuation;

  bool get isLast => continuation == null;
}

/// 一个有界、自包含的内容连接：一致基线、连续补丁、无状态页与按身份详情。
///
/// transport 实现只做 DTO 机械转换；它不保存第二份基线，也不应用差量——那是唯一内容泵与
/// 展示 lease 的职责（design/26 §26.6、§26.8）。
abstract interface class StudioTimelineConnection {
  Future<StudioTimelineBaseline> initial();
  Future<StudioTimelineUpdate?> next();
  Future<StudioTimelinePage> page({String? before, int? limit});
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  });
  void requestClose();
  Future<void> close();
}
