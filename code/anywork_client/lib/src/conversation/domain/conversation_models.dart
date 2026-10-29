import 'dart:convert';

import 'page_coverage.dart';

import '../../../models.dart';

/// 条目的执行终态事实（后端 `BridgeTimelineLifecycle`），与保存水位
/// [ConversationItem.saved] 严格独立。
enum ConversationLifecycle { streaming, terminal }

/// 后端只读来源语义；与逐条保存及 GUI 展示身份分别表达。
sealed class ConversationItemSource {
  const ConversationItemSource();
}

final class ConversationContentSource extends ConversationItemSource {
  const ConversationContentSource();
}

enum ConversationRecoveryNotice { retry, result }

final class ConversationRecoverySource extends ConversationItemSource {
  const ConversationRecoverySource({
    required this.attemptId,
    required this.notice,
  });
  final String attemptId;
  final ConversationRecoveryNotice notice;
}

/// 一个内容字段的详情引用：完整正文按 `(item, field, revision)` 读取。
///
/// `totalBytes` 是该字段完整正文的 UTF-8 字节数，`previewBytes` 是本次预览实际携带的
/// 字节数。两者都不等于 Dart 字符串长度：消费者不得据此切分字符串。
class ConversationDetailRef {
  const ConversationDetailRef({
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
      other is ConversationDetailRef &&
          field == other.field &&
          revision == other.revision &&
          totalBytes == other.totalBytes &&
          previewBytes == other.previewBytes;

  @override
  int get hashCode => Object.hash(field, revision, totalBytes, previewBytes);
}

/// 唯一读取条目：结构描述和字段正文分离，不持有持久化 ThreadItem 副本。
class ConversationItemHeader {
  const ConversationItemHeader({
    required this.id,
    required this.threadId,
    required this.turnId,
    required this.ordinal,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String threadId;
  final String turnId;
  final int ordinal;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ConversationFieldPreview {
  const ConversationFieldPreview({
    required this.field,
    required this.text,
    required this.totalBytes,
  });
  final ThreadContentFieldView field;
  final String text;
  final int totalBytes;
  int get previewBytes => utf8.encode(text).length;
  int get omittedBytes => totalBytes - previewBytes;
}

class ConversationItem {
  const ConversationItem({
    required this.header,
    required this.revision,
    required this.descriptor,
    this.source = const ConversationContentSource(),
    required this.saved,
    required this.lifecycle,
    required this.fields,
  });
  final ConversationItemHeader header;
  final int revision;
  final ConversationDescriptor descriptor;
  final ConversationItemSource source;
  final bool saved;
  final ConversationLifecycle lifecycle;
  final List<ConversationFieldPreview> fields;
  String get id => header.id;
  bool get terminal => lifecycle == ConversationLifecycle.terminal;
  int get omittedBytes => fields.fold(0, (sum, f) => sum + f.omittedBytes);
  Iterable<ConversationDetailRef> get details => fields.map(
    (f) => ConversationDetailRef(
      field: f.field,
      revision: revision,
      totalBytes: f.totalBytes,
      previewBytes: f.previewBytes,
    ),
  );
  ConversationFieldPreview? fieldFor(ThreadContentFieldView field) {
    for (final value in fields) {
      if (value.field == field) return value;
    }
    return null;
  }

  ConversationDetailRef? detailFor(ThreadContentFieldView field) {
    final value = fieldFor(field);
    return value == null
        ? null
        : ConversationDetailRef(
            field: field,
            revision: revision,
            totalBytes: value.totalBytes,
            previewBytes: value.previewBytes,
          );
  }
}

/// 一条尾部连接的基线：与接收者登记一致的最新小页。
class ConversationBaseline {
  const ConversationBaseline({
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
  final List<ConversationItem> items;

  /// 直接继续翻更旧一页的不透明边界 token；只有 [hasOlder] 为真时给出。
  final String? before;

  /// 是否真的还有更旧内容（真实存在性证明，不凭条数猜 EOF）。
  final bool hasOlder;
}

/// 一页升序预览条目、下一更旧边界与是否真的还有更旧内容。
class ConversationPage {
  const ConversationPage({
    required this.items,
    required this.before,
    required this.hasOlder,
  });

  final List<ConversationItem> items;
  final String? before;
  final bool hasOlder;
}

/// 同一 item 的一个字段变化，携带该字段一次提交的完整/预览字节数。
class ConversationFieldUpdate {
  const ConversationFieldUpdate({
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
sealed class ConversationChange {
  const ConversationChange();
}

/// 订阅尚未交付过的一条权威条目。
final class ConversationAdd extends ConversationChange {
  const ConversationAdd(this.item);
  final ConversationItem item;
}

/// 同一身份的全部内容与状态字段，在**一次** expectedRevision/revision 提交里原子应用。
final class ConversationUpdateItem extends ConversationChange {
  const ConversationUpdateItem({
    required this.itemId,
    required this.expectedRevision,
    required this.revision,
    required this.saved,
    required this.lifecycle,
    required this.fields,
    this.header,
    this.descriptor,
  });

  final String itemId;
  final int expectedRevision;
  final int revision;
  final bool saved;
  final ConversationLifecycle lifecycle;
  final ConversationItemHeader? header;
  final ConversationDescriptor? descriptor;
  final List<ConversationFieldUpdate> fields;
}

/// 真实删除：该身份不再存在。预览缓存退出不是删除。
final class ConversationRemove extends ConversationChange {
  const ConversationRemove(this.itemId);
  final String itemId;
}

/// 一帧是否需要立即应用，还是普通文本已经合帧。
enum ConversationPriority { immediate, coalesced }

/// 订阅无法继续用连续补丁表达时的原因。
enum ConversationResyncReason { lagging, unavailable }

/// transport 交付的一帧尾部更新。
sealed class ConversationUpdate {
  const ConversationUpdate();
}

/// 连续补丁：`from` 必须等于本地已交付版本。
final class ConversationPatch extends ConversationUpdate {
  const ConversationPatch({
    required this.subscriptionId,
    required this.from,
    required this.to,
    required this.changes,
    required this.priority,
  });

  final String subscriptionId;
  final int from;
  final int to;
  final List<ConversationChange> changes;
  final ConversationPriority priority;
}

/// 无法连续表达：给出原因与新的最新小页基线，同连接沿用本订阅身份。
final class ConversationResync extends ConversationUpdate {
  const ConversationResync({
    required this.subscriptionId,
    required this.reason,
    required this.baseline,
  });

  final String subscriptionId;
  final ConversationResyncReason reason;
  final ConversationBaseline baseline;
}

/// 唯一内容泵交付给展示消费者的帧。
///
/// 只有两种形状：**建立/重建整份展示**的基线帧，与**按身份增量**的补丁帧。消费方先应用
/// 基线，再逐条应用补丁；无法证明连续时显式按重同步处理，不逐帧比较全部已加载历史。
sealed class ConversationContentFrame {
  const ConversationContentFrame();
}

/// 基线帧：新一代展示或同连接显式重同步。
final class ConversationBaselineFrame extends ConversationContentFrame {
  const ConversationBaselineFrame(
    this.baseline, {
    required this.pageCoverage,
    this.resyncReason,
  });

  final ConversationBaseline baseline;
  final ConversationPageCoverage pageCoverage;

  /// 非空表示这是同连接的重同步基线，而不是一次新订阅的首帧。
  final ConversationResyncReason? resyncReason;

  bool get isResync => resyncReason != null;
}

/// 补丁帧：按身份增量，`patch.from` 必须等于消费者自己已应用的版本。
final class ConversationPatchFrame extends ConversationContentFrame {
  const ConversationPatchFrame(this.patch);
  final ConversationPatch patch;
}

/// 详情读取请求：item 由调用参数给出，其余绑定在同一份 typed 请求里。
class ConversationDetailQuery {
  const ConversationDetailQuery({
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
class ConversationDetailChunk {
  const ConversationDetailChunk({
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
