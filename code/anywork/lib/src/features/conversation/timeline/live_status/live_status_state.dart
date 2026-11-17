import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals, setEquals;

import '../widgets/timeline_activity_row.dart';
import '../state/timeline_display_models.dart';

/// 根据类型化活动阶段、前台活跃工具事实以及当前顶栏是否正在展示思考摘要解析指示器样式：
/// - `responding` -> 分层书写动态图标；
/// - `compacting` -> 经典拉链齿动态 ZIP 压缩图标；
/// - 当前顶栏正在展示思考摘要（`displayingThinkingSummary == true`）-> 趴卧摇尾猫图标；
/// - `runningTool` 且前台正在运行 `exec`（无思考摘要时）-> 圆形进度指示器；
/// - 其余等待/思考阶段 -> 趴卧摇尾猫图标。
TimelineActivityIndicatorStyle resolveLiveHeaderIndicatorStyle(
  ConversationActivityView? view, {
  bool displayingThinkingSummary = false,
}) {
  if (view == null) return TimelineActivityIndicatorStyle.restingCat;
  if (view.kind == ConversationActivityKind.responding) {
    return TimelineActivityIndicatorStyle.writing;
  }
  if (view.kind == ConversationActivityKind.compacting) {
    return TimelineActivityIndicatorStyle.compactingZip;
  }
  if (displayingThinkingSummary) {
    return TimelineActivityIndicatorStyle.restingCat;
  }
  if (view.isRunningExecTool) {
    return TimelineActivityIndicatorStyle.circularProgress;
  }
  return TimelineActivityIndicatorStyle.restingCat;
}

/// 实时状态栏顶层特殊通知封闭联合类型。
@immutable
sealed class LiveStatusNotice {
  const LiveStatusNotice();
}

final class ExecutionLiveNotice extends LiveStatusNotice {
  const ExecutionLiveNotice(this.view);
  final ConversationActivityView view;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExecutionLiveNotice && view == other.view;

  @override
  int get hashCode => view.hashCode;
}

/// 实时状态栏唯一主表面：权威活动/错误通知，不包含 Current Work 或历史行镜像。
@immutable
final class LiveStatusNoticeSurface {
  LiveStatusNoticeSurface({required List<LiveStatusNotice> notices})
    : notices = List.unmodifiable(notices);

  final List<LiveStatusNotice> notices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusNoticeSurface && listEquals(notices, other.notices);

  @override
  int get hashCode => Object.hashAll(notices);
}

/// Current activity-tool collection is exposed as one bounded page. The total
/// count comes from the Current collection head and is never inferred from the
/// loaded page.
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

/// 底部实时状态栏封闭生命周期状态机状态。
@immutable
sealed class LiveStatusMachineState {
  const LiveStatusMachineState();

  bool get showInteractionDetails => switch (this) {
    LiveStatusHidden() => false,
    LiveStatusDockMasked(:final showInteractionDetails) =>
      showInteractionDetails,
    LiveStatusPresenting(:final showInteractionDetails) =>
      showInteractionDetails,
  };
}

/// 状态 1：完全收起隐藏（无活动、无开放块、无待决交互详情）。
final class LiveStatusHidden extends LiveStatusMachineState {
  const LiveStatusHidden();

  @override
  bool operator ==(Object other) => other is LiveStatusHidden;

  @override
  int get hashCode => (LiveStatusHidden).hashCode;
}

/// 状态 2：待决问答或实施计划确认遮蔽底部活动条（普通问答保留只读交互详情入口，确认计划完全隐藏）。
final class LiveStatusDockMasked extends LiveStatusMachineState {
  const LiveStatusDockMasked({
    required this.interactionId,
    required this.showInteractionDetails,
    this.obscured,
  });

  final String interactionId;
  final LiveStatusPresenting? obscured;
  @override
  final bool showInteractionDetails;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusDockMasked &&
          interactionId == other.interactionId &&
          obscured == other.obscured &&
          showInteractionDetails == other.showInteractionDetails;

  @override
  int get hashCode =>
      Object.hash(interactionId, showInteractionDetails, obscured);
}

/// 状态 3：底部实时状态栏激活呈现中。
final class LiveStatusPresenting extends LiveStatusMachineState {
  const LiveStatusPresenting({
    required this.surface,
    required this.showInteractionDetails,
  });

  final LiveStatusNoticeSurface surface;
  @override
  final bool showInteractionDetails;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStatusPresenting &&
          surface == other.surface &&
          showInteractionDetails == other.showInteractionDetails;

  @override
  int get hashCode => Object.hash(surface, showInteractionDetails);
}

/// 状态机纯输入快照：仅保存客户端已归约的不可变领域值，不持有原生流或可变句柄。
@immutable
final class LiveStatusInputs {
  LiveStatusInputs({
    this.storage,
    List<PendingInteraction> interactions = const [],
    this.businessRefs,
    this.activeTurnId,
    this.activity,
    this.current,
    Set<String> renderedCurrentAtomIds = const {},
    this.hasContentOwner = false,
  }) : interactions = List.unmodifiable(interactions),
       renderedCurrentAtomIds = Set.unmodifiable(renderedCurrentAtomIds);

  const LiveStatusInputs.empty()
    : storage = null,
      interactions = const [],
      businessRefs = null,
      activeTurnId = null,
      activity = null,
      current = null,
      renderedCurrentAtomIds = const {},
      hasContentOwner = false;

  final ThreadStorageStateView? storage;
  final List<PendingInteraction> interactions;
  final ThreadBusinessRefs? businessRefs;
  final String? activeTurnId;
  final ThreadActivityView? activity;
  final CurrentAtomSnapshot? current;
  final Set<String> renderedCurrentAtomIds;
  final bool hasContentOwner;

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
          setEquals(renderedCurrentAtomIds, other.renderedCurrentAtomIds) &&
          hasContentOwner == other.hasContentOwner;

  @override
  int get hashCode => Object.hash(
    storage,
    Object.hashAll(interactions),
    businessRefs,
    activeTurnId,
    activity,
    current,
    Object.hashAllUnordered(renderedCurrentAtomIds),
    hasContentOwner,
  );
}

/// 当前组件实际使用的只读展示结果；只含派生表面，不保存业务输入镜像或诊断发布账本。
@immutable
final class LiveStatusView {
  const LiveStatusView({
    required this.threadId,
    required this.barState,
    this.primaryActivity,
    this.currentAtomsError,
    this.activityTools,
  });
  final String threadId;
  final LiveStatusMachineState barState;
  final ConversationActivityView? primaryActivity;
  final Object? currentAtomsError;
  final LiveActivityToolsWindow? activityTools;
}
