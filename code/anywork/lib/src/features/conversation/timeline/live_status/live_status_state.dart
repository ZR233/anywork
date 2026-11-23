import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals, setEquals;

import '../state/timeline_display_models.dart';

/// 实时工作组在状态机中的运行子形态。
enum LiveWorkGroupMode { active, waiting, stopping }

/// 存储阻塞的 typed 严重度分类；由后端 `ThreadStorageStateView` 直接派生，绝不解析错误文本。
enum LiveStorageSeverity {
  fault,
  pressure,
  paused,
  resumeRequired,
  resumeReady,
}

/// 实时流同步连接状态。
enum LiveConnectionStatus { connected, reconnecting, disconnected }

/// 按需读取的活跃工具集合窗口（与后端 `tools.active` 字段绑定）。
@immutable
final class LiveActivityToolsWindow {
  LiveActivityToolsWindow({
    required this.reference,
    required this.totalCount,
    required List<ThreadActivityToolEntry> entries,
    required this.expanded,
    required this.loading,
    required this.hasPrevious,
    required this.hasNext,
    this.error,
  }) : entries = List.unmodifiable(entries);

  final CurrentCollectionRef reference;
  final int totalCount;
  final List<ThreadActivityToolEntry> entries;
  final bool expanded;
  final bool loading;
  final bool hasPrevious;
  final bool hasNext;
  final Object? error;

  int get loadedCount => entries.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveActivityToolsWindow &&
          reference == other.reference &&
          totalCount == other.totalCount &&
          listEquals(entries, other.entries) &&
          expanded == other.expanded &&
          loading == other.loading &&
          hasPrevious == other.hasPrevious &&
          hasNext == other.hasNext &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    reference,
    totalCount,
    Object.hashAll(entries),
    expanded,
    loading,
    hasPrevious,
    hasNext,
    error,
  );
}

/// 实时状态栏四选一主阶段。
@immutable
sealed class LiveStatusPrimaryPhase {
  const LiveStatusPrimaryPhase();
}

/// 主模型正在产出流式正文，可选附带未抑制的活动提示。
final class LiveResponsePhase extends LiveStatusPrimaryPhase {
  LiveResponsePhase({
    List<CurrentAtom> responseAtoms = const [],
    this.previewText,
    this.startedAt,
    this.finishedAt,
    this.activity,
  }) : responseAtoms = List.unmodifiable(responseAtoms);

  final List<CurrentAtom> responseAtoms;
  final String? previewText;
  final int? startedAt;
  final int? finishedAt;
  final ConversationActivityView? activity;

  bool get isActive => finishedAt == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveResponsePhase &&
          listEquals(responseAtoms, other.responseAtoms) &&
          previewText == other.previewText &&
          startedAt == other.startedAt &&
          finishedAt == other.finishedAt &&
          activity == other.activity;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(responseAtoms),
    previewText,
    startedAt,
    finishedAt,
    activity,
  );
}

/// 开放工作组正在实时状态栏主区运行、等待或停止。
final class LiveWorkPhase extends LiveStatusPrimaryPhase {
  LiveWorkPhase({
    required this.id,
    required this.block,
    List<CurrentAtom> liveWorkAtoms = const [],
    required this.mode,
    required this.timing,
    this.activity,
    this.thinkingSummary,
    required this.executionPresent,
  }) : liveWorkAtoms = List.unmodifiable(liveWorkAtoms);

  final String id;
  final DisplayBlock block;
  final List<CurrentAtom> liveWorkAtoms;
  final LiveWorkGroupMode mode;
  final WorkTiming timing;
  final ConversationActivityView? activity;
  final String? thinkingSummary;
  final bool executionPresent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveWorkPhase &&
          id == other.id &&
          sameDisplayBlock(block, other.block) &&
          listEquals(liveWorkAtoms, other.liveWorkAtoms) &&
          mode == other.mode &&
          timing == other.timing &&
          activity == other.activity &&
          thinkingSummary == other.thinkingSummary &&
          executionPresent == other.executionPresent;

  @override
  int get hashCode => Object.hash(
    id,
    block.id,
    block.blockOrder,
    Object.hashAll(liveWorkAtoms),
    mode,
    timing,
    activity,
    thinkingSummary,
    executionPresent,
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

final class LiveConnectionAttention extends LiveStatusAttention {
  const LiveConnectionAttention({required this.status, this.detail});

  final LiveConnectionStatus status;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveConnectionAttention &&
          status == other.status &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(status, detail);
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
    this.activityTools,
    this.showInteractionDetails = false,
  }) : attentions = List.unmodifiable(attentions);

  final LiveStatusPrimaryPhase? primary;
  final List<LiveStatusAttention> attentions;
  final LiveActivityToolsWindow? activityTools;
  final bool showInteractionDetails;

  bool get isEmpty =>
      primary == null &&
      attentions.isEmpty &&
      activityTools == null &&
      !showInteractionDetails;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusPresentation &&
          primary == other.primary &&
          listEquals(attentions, other.attentions) &&
          activityTools == other.activityTools &&
          showInteractionDetails == other.showInteractionDetails;

  @override
  int get hashCode => Object.hash(
    primary,
    Object.hashAll(attentions),
    activityTools,
    showInteractionDetails,
  );
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

/// 状态机投影所需全部不可变输入快照。
@immutable
final class LiveStatusInputs {
  LiveStatusInputs({
    this.storage,
    List<PendingInteraction> interactions = const [],
    this.businessRefs,
    this.activeTurnId,
    this.activity,
    this.current,
    this.liveOpenWork,
    Set<String> renderedCurrentAtomIds = const {},
    this.hasContentOwner = false,
    this.connectionStatus = LiveConnectionStatus.connected,
    this.connectionDetail,
    this.currentAtomsError,
    this.previewResponseText,
    this.previewResponseStartedAt,
  }) : interactions = List.unmodifiable(interactions),
       renderedCurrentAtomIds = Set.unmodifiable(renderedCurrentAtomIds);

  const LiveStatusInputs.empty()
    : storage = null,
      interactions = const [],
      businessRefs = null,
      activeTurnId = null,
      activity = null,
      current = null,
      liveOpenWork = null,
      renderedCurrentAtomIds = const {},
      hasContentOwner = false,
      connectionStatus = LiveConnectionStatus.connected,
      connectionDetail = null,
      currentAtomsError = null,
      previewResponseText = null,
      previewResponseStartedAt = null;

  final ThreadStorageStateView? storage;
  final List<PendingInteraction> interactions;
  final ThreadBusinessRefs? businessRefs;
  final String? activeTurnId;
  final ThreadActivityView? activity;
  final CurrentAtomSnapshot? current;
  final DisplayBlock? liveOpenWork;
  final Set<String> renderedCurrentAtomIds;
  final bool hasContentOwner;
  final LiveConnectionStatus connectionStatus;
  final String? connectionDetail;
  final Object? currentAtomsError;
  final String? previewResponseText;
  final int? previewResponseStartedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusInputs &&
          storage == other.storage &&
          listEquals(interactions, other.interactions) &&
          businessRefs == other.businessRefs &&
          activeTurnId == other.activeTurnId &&
          activity == other.activity &&
          current == other.current &&
          _sameOptionalBlock(liveOpenWork, other.liveOpenWork) &&
          setEquals(renderedCurrentAtomIds, other.renderedCurrentAtomIds) &&
          hasContentOwner == other.hasContentOwner &&
          connectionStatus == other.connectionStatus &&
          connectionDetail == other.connectionDetail &&
          currentAtomsError == other.currentAtomsError &&
          previewResponseText == other.previewResponseText &&
          previewResponseStartedAt == other.previewResponseStartedAt;

  @override
  int get hashCode => Object.hash(
    storage,
    Object.hashAll(interactions),
    businessRefs,
    activeTurnId,
    activity,
    current,
    liveOpenWork?.id,
    Object.hashAllUnordered(renderedCurrentAtomIds),
    hasContentOwner,
    connectionStatus,
    connectionDetail,
    currentAtomsError,
    previewResponseText,
    previewResponseStartedAt,
  );
}

bool _sameOptionalBlock(DisplayBlock? first, DisplayBlock? second) =>
    identical(first, second) ||
    (first != null && second != null && sameDisplayBlock(first, second));

/// 当前组件实际使用的只读展示结果；仅含派生表面，供 ViewModel、纯视图与驱动只读事实共用。
@immutable
final class LiveStatusView {
  const LiveStatusView({
    required this.threadId,
    required this.gate,
    this.primaryActivity,
    this.activityTools,
  });

  final String threadId;
  final LiveStatusGateState gate;
  final ConversationActivityView? primaryActivity;
  final LiveActivityToolsWindow? activityTools;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusView &&
          threadId == other.threadId &&
          gate == other.gate &&
          primaryActivity == other.primaryActivity &&
          activityTools == other.activityTools;

  @override
  int get hashCode =>
      Object.hash(threadId, gate, primaryActivity, activityTools);
}
