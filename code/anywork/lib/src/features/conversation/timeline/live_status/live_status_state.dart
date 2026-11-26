import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

/// 存储阻塞的 typed 严重度分类；由后端 [ThreadStorageStateView] 直接派生，绝不解析错误文本。
enum LiveStorageSeverity {
  fault,
  pressure,
  paused,
  resumeRequired,
  resumeReady;

  static LiveStorageSeverity fromStorage(ThreadStorageStateView? storage) {
    if (storage == null) return fault;
    if (storage.resumeRequired && storage.canResume) return resumeReady;
    if (storage.hasFault) return fault;
    if (storage.pressurePaused) return pressure;
    if (storage.resumeRequired) return resumeRequired;
    return paused;
  }
}

/// 告警单态分类（与存储／连接／审批／错误一一对应）。
enum LiveAlertKind {
  approval,
  storageReady,
  storageWarning,
  storageFault,
  disconnected,
  error,
}

/// 实时工作容器内折叠的单个思考或工具条目的前端投影模型。
@immutable
final class LiveWorkMember {
  const LiveWorkMember({
    required this.id,
    this.callId,
    required this.kind,
    required this.toolName,
    required this.status,
    required this.summary,
    this.startedAtMs,
    this.finishedAtMs,
  });

  final String id;
  final String? callId;
  final String kind;
  final String toolName;
  final String status;
  final String summary;
  final int? startedAtMs;
  final int? finishedAtMs;

  bool get isActive =>
      status == 'running' ||
      status == 'cancelling' ||
      status == 'awaitingApproval';

  bool get isFailed => status == 'failed' || status == 'denied';

  bool get isCancelled => status == 'cancelled';

  bool get isCompleted => status == 'completed' || status == 'backgrounded';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveWorkMember &&
          id == other.id &&
          callId == other.callId &&
          kind == other.kind &&
          toolName == other.toolName &&
          status == other.status &&
          summary == other.summary &&
          startedAtMs == other.startedAtMs &&
          finishedAtMs == other.finishedAtMs;

  @override
  int get hashCode => Object.hash(
    id,
    callId,
    kind,
    toolName,
    status,
    summary,
    startedAtMs,
    finishedAtMs,
  );
}

/// 实时状态栏前端展示层的单一扁平状态机（8 个互斥态）。
@immutable
sealed class LiveStatusState {
  const LiveStatusState();
}

/// 隐藏状态（空闲或被根线程交互覆盖）。
final class LiveStatusHidden extends LiveStatusState {
  const LiveStatusHidden({required this.suppressed});

  final bool suppressed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusHidden && suppressed == other.suppressed;

  @override
  int get hashCode => Object.hash(LiveStatusHidden, suppressed);
}

/// 思考中或执行工具容器状态（包含可折叠的单行工作条目列表与单行思考摘要）。
final class LiveStatusWorkingState extends LiveStatusState {
  LiveStatusWorkingState({
    required this.threadId,
    required List<LiveWorkMember> items,
    this.reasoningPreview,
    this.startedAtMs,
  }) : items = List.unmodifiable(items);

  final String threadId;
  final List<LiveWorkMember> items;
  final String? reasoningPreview;
  final int? startedAtMs;

  bool get hasRunningCommand =>
      items.any((item) => item.kind == 'command' && item.isActive);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusWorkingState &&
          threadId == other.threadId &&
          listEquals(items, other.items) &&
          reasoningPreview == other.reasoningPreview &&
          startedAtMs == other.startedAtMs;

  @override
  int get hashCode => Object.hash(
    LiveStatusWorkingState,
    threadId,
    Object.hashAll(items),
    reasoningPreview,
    startedAtMs,
  );
}

/// 文本流持续输出状态。
final class LiveStatusStreamingState extends LiveStatusState {
  const LiveStatusStreamingState({
    required this.attemptId,
    required this.itemId,
    required this.text,
    this.startedAtMs,
  });

  final String attemptId;
  final String itemId;
  final String text;
  final int? startedAtMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusStreamingState &&
          attemptId == other.attemptId &&
          itemId == other.itemId &&
          text == other.text &&
          startedAtMs == other.startedAtMs;

  @override
  int get hashCode => Object.hash(
    LiveStatusStreamingState,
    attemptId,
    itemId,
    text,
    startedAtMs,
  );
}

/// 上下文压缩状态。
final class LiveStatusCompactingState extends LiveStatusState {
  const LiveStatusCompactingState({required this.manual, this.startedAtMs});

  final bool manual;
  final int? startedAtMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusCompactingState &&
          manual == other.manual &&
          startedAtMs == other.startedAtMs;

  @override
  int get hashCode =>
      Object.hash(LiveStatusCompactingState, manual, startedAtMs);
}

/// 模型连接中断重连状态。
final class LiveStatusReconnectingState extends LiveStatusState {
  const LiveStatusReconnectingState({
    required this.attemptId,
    required this.message,
    this.retryAfterMs,
    required this.attempt,
    required this.maxAttempts,
  });

  final String attemptId;
  final String message;
  final int? retryAfterMs;
  final int attempt;
  final int maxAttempts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusReconnectingState &&
          attemptId == other.attemptId &&
          message == other.message &&
          retryAfterMs == other.retryAfterMs &&
          attempt == other.attempt &&
          maxAttempts == other.maxAttempts;

  @override
  int get hashCode => Object.hash(
    LiveStatusReconnectingState,
    attemptId,
    message,
    retryAfterMs,
    attempt,
    maxAttempts,
  );
}

/// 用户中断后的停止中终态锁存展示。
final class LiveStatusStoppingState extends LiveStatusState {
  const LiveStatusStoppingState({this.startedAtMs});

  final int? startedAtMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusStoppingState && startedAtMs == other.startedAtMs;

  @override
  int get hashCode => Object.hash(LiveStatusStoppingState, startedAtMs);
}

/// 最高优先级单行告警状态（审批、存储、断连或错误）。
final class LiveStatusAlertState extends LiveStatusState {
  const LiveStatusAlertState({required this.kind, this.detail, this.storage});

  final LiveAlertKind kind;
  final String? detail;
  final ThreadStorageStateView? storage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusAlertState &&
          kind == other.kind &&
          detail == other.detail &&
          storage == other.storage;

  @override
  int get hashCode => Object.hash(LiveStatusAlertState, kind, detail, storage);
}

/// 子线程只读交互详情状态（仅子线程使用）。
final class LiveStatusChildInteractionState extends LiveStatusState {
  const LiveStatusChildInteractionState({
    required this.interactionId,
    required this.payload,
  });

  final String interactionId;
  final InteractionPayload payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusChildInteractionState &&
          interactionId == other.interactionId &&
          payload == other.payload;

  @override
  int get hashCode =>
      Object.hash(LiveStatusChildInteractionState, interactionId, payload);
}

/// 实时状态栏对外发布的只读投影视图。
@immutable
final class LiveStatusView {
  const LiveStatusView({
    required this.threadId,
    required this.state,
    this.primaryActivity,
    this.revision = 0,
  });

  final String threadId;
  final LiveStatusState state;
  final ConversationActivityView? primaryActivity;
  final int revision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusView &&
          threadId == other.threadId &&
          state == other.state &&
          primaryActivity == other.primaryActivity &&
          revision == other.revision;

  @override
  int get hashCode => Object.hash(threadId, state, primaryActivity, revision);
}
