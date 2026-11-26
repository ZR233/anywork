import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../state/timeline_display_models.dart';

/// 实时工作组在状态机中的运行子形态。
enum LiveWorkGroupMode { active, waiting, stopping }

/// 存储阻塞的 typed 严重度分类；由后端 `ThreadStorageStateView` 直接派生，绝不解析错误文本。
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

/// 实时流同步连接状态。
enum LiveConnectionStatus { connected, reconnecting, disconnected }

/// 实时状态栏的互斥主阶段。
@immutable
sealed class LiveStatusPrimaryPhase {
  const LiveStatusPrimaryPhase();
}

final class LiveReconnectingPhase extends LiveStatusPrimaryPhase {
  const LiveReconnectingPhase({
    this.detail,
    this.attempt,
    this.maxAttempts,
    this.retryAt,
  });

  final String? detail;
  final int? attempt;
  final int? maxAttempts;
  final DateTime? retryAt;

  @override
  bool operator ==(Object other) =>
      other is LiveReconnectingPhase &&
      detail == other.detail &&
      attempt == other.attempt &&
      maxAttempts == other.maxAttempts &&
      retryAt == other.retryAt;

  @override
  int get hashCode => Object.hash(detail, attempt, maxAttempts, retryAt);
}

/// 正在输出的一条正文及其计时起点。
final class LiveResponsePhase extends LiveStatusPrimaryPhase {
  const LiveResponsePhase({
    required this.itemId,
    required this.previewText,
    this.startedAt,
  });
  final String itemId;
  final String previewText;
  final int? startedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveResponsePhase &&
          itemId == other.itemId &&
          previewText == other.previewText &&
          startedAt == other.startedAt;

  @override
  int get hashCode => Object.hash(itemId, previewText, startedAt);
}

/// 开放工作组正在实时状态栏主区运行、等待或停止。
final class LiveWorkPhase extends LiveStatusPrimaryPhase {
  const LiveWorkPhase({
    required this.id,
    required this.block,
    required this.mode,
    required this.timing,
    this.activity,
    this.thinkingSummary,
    this.items = const [],
    required this.executionPresent,
  });

  final String id;
  final DisplayBlock block;
  final LiveWorkGroupMode mode;
  final WorkTiming timing;
  final ConversationActivityView? activity;
  final String? thinkingSummary;
  final List<LiveWorkItem> items;
  final bool executionPresent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveWorkPhase &&
          id == other.id &&
          sameDisplayBlock(block, other.block) &&
          mode == other.mode &&
          timing == other.timing &&
          activity == other.activity &&
          thinkingSummary == other.thinkingSummary &&
          executionPresent == other.executionPresent &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(
    id,
    block.id,
    block.blockOrder,
    mode,
    timing,
    activity,
    thinkingSummary,
    executionPresent,
    Object.hashAll(items),
  );
}

/// 上下文压缩阶段。
final class LiveCompactingPhase extends LiveStatusPrimaryPhase {
  const LiveCompactingPhase({required this.activity, this.startedAt});

  final ConversationActivityView activity;
  final int? startedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveCompactingPhase &&
          activity == other.activity &&
          startedAt == other.startedAt;

  @override
  int get hashCode => Object.hash(activity, startedAt);
}

/// 独立活动状态（无正文/无开放工作组时的准备、思考、规划、等待或单行执行态）。
final class LiveActivityPhase extends LiveStatusPrimaryPhase {
  const LiveActivityPhase({required this.activity, this.startedAt});

  final ConversationActivityView activity;
  final int? startedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveActivityPhase &&
          activity == other.activity &&
          startedAt == other.startedAt;

  @override
  int get hashCode => Object.hash(activity, startedAt);
}

/// 与主阶段正交并存的控制态、审批态或故障关注条；同帧去重。
@immutable
sealed class LiveStatusAttention {
  const LiveStatusAttention();
}

final class LiveStoppingAttention extends LiveStatusAttention {
  const LiveStoppingAttention(this.activity);

  final ConversationActivityView activity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStoppingAttention && activity == other.activity;

  @override
  int get hashCode => activity.hashCode;
}

final class LiveApprovalAttention extends LiveStatusAttention {
  const LiveApprovalAttention(this.activity);

  final ConversationActivityView activity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveApprovalAttention && activity == other.activity;

  @override
  int get hashCode => activity.hashCode;
}

final class LiveStorageAttention extends LiveStatusAttention {
  const LiveStorageAttention({
    required this.activity,
    required this.storage,
    required this.severity,
  });

  final ConversationActivityView activity;
  final ThreadStorageStateView storage;
  final LiveStorageSeverity severity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStorageAttention &&
          activity == other.activity &&
          storage == other.storage &&
          severity == other.severity;

  @override
  int get hashCode => Object.hash(activity, storage, severity);
}

final class LiveDisconnectedAttention extends LiveStatusAttention {
  const LiveDisconnectedAttention({this.detail});

  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is LiveDisconnectedAttention && detail == other.detail;

  @override
  int get hashCode => detail.hashCode;
}

final class LiveErrorAttention extends LiveStatusAttention {
  const LiveErrorAttention({required this.message, this.retryable = false});

  final String message;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveErrorAttention &&
          message == other.message &&
          retryable == other.retryable;

  @override
  int get hashCode => Object.hash(message, retryable);
}

/// 单帧实时状态栏的完整纯展示模型。
@immutable
final class LiveStatusPresentation {
  LiveStatusPresentation({
    this.primary,
    List<LiveStatusAttention> attentions = const [],
    this.showInteractionDetails = false,
  }) : attentions = List.unmodifiable(attentions);

  final LiveStatusPrimaryPhase? primary;
  final List<LiveStatusAttention> attentions;
  final bool showInteractionDetails;

  bool get isEmpty =>
      primary == null && attentions.isEmpty && !showInteractionDetails;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusPresentation &&
          primary == other.primary &&
          listEquals(attentions, other.attentions) &&
          showInteractionDetails == other.showInteractionDetails;

  @override
  int get hashCode =>
      Object.hash(primary, Object.hashAll(attentions), showInteractionDetails);
}

/// 顶层门控状态机：空闲、被底部交互停靠区遮蔽，或正在呈现实时状态。
@immutable
sealed class LiveStatusGateState {
  const LiveStatusGateState();

  bool get showInteractionDetails => switch (this) {
    LiveStatusIdle() => false,
    LiveStatusSuppressed(:final showInteractionDetails) =>
      showInteractionDetails,
    LiveStatusPresenting(:final presentation) =>
      presentation.showInteractionDetails,
  };
}

final class LiveStatusIdle extends LiveStatusGateState {
  const LiveStatusIdle();

  @override
  bool operator ==(Object other) => other is LiveStatusIdle;

  @override
  int get hashCode => (LiveStatusIdle).hashCode;
}

final class LiveStatusSuppressed extends LiveStatusGateState {
  const LiveStatusSuppressed({
    required this.interactionId,
    required this.showInteractionDetails,
    this.obscured,
  });

  final String interactionId;
  @override
  final bool showInteractionDetails;
  final LiveStatusPresentation? obscured;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusSuppressed &&
          interactionId == other.interactionId &&
          showInteractionDetails == other.showInteractionDetails &&
          obscured == other.obscured;

  @override
  int get hashCode =>
      Object.hash(interactionId, showInteractionDetails, obscured);
}

final class LiveStatusPresenting extends LiveStatusGateState {
  const LiveStatusPresenting({required this.presentation});

  final LiveStatusPresentation presentation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusPresenting && presentation == other.presentation;

  @override
  int get hashCode => presentation.hashCode;
}

final class LiveStatusView {
  const LiveStatusView({
    required this.threadId,
    required this.gate,
    this.primaryActivity,
  });

  final String threadId;
  final LiveStatusGateState gate;
  final ConversationActivityView? primaryActivity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusView &&
          threadId == other.threadId &&
          gate == other.gate &&
          primaryActivity == other.primaryActivity;

  @override
  int get hashCode => Object.hash(threadId, gate, primaryActivity);
}
