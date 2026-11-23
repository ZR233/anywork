import 'package:anywork_client/models.dart';

import '../../interactions/state/interaction_payload.dart';
import '../state/timeline_display_unit.dart';
import 'live_status_state.dart';

/// Current 活动、Atoms、开放工作组与独立业务状态的纯展示投影；不保存事件账本、不执行 I/O。
abstract final class LiveStatusProjection {
  static bool _isLiveWorkKind(ChatAtomKind kind) => switch (kind) {
    ChatAtomKind.reasoning ||
    ChatAtomKind.toolCall ||
    ChatAtomKind.fileChange ||
    ChatAtomKind.skill ||
    ChatAtomKind.agent => true,
    _ => false,
  };

  static bool _suppressedByLiveWork(
    LiveStatusNotice notice, {
    required bool hasLiveWork,
  }) {
    if (!hasLiveWork ||
        notice is! ExecutionLiveNotice ||
        notice.view.errorMessage != null) {
      return false;
    }
    return switch (notice.view.kind) {
      ConversationActivityKind.preparing ||
      ConversationActivityKind.thinking ||
      ConversationActivityKind.planning ||
      ConversationActivityKind.runningTool => true,
      _ => false,
    };
  }

  /// 当前轮次正文或压缩记录已承担展示时，接管并抑制对应的普通同类状态提示。
  static bool hasCurrentOutputRenderer({
    required CurrentAtomSnapshot? current,
    required Set<String> renderedCurrentAtomIds,
    required String? activeTurnId,
    required LiveStatusNotice notice,
  }) {
    if (notice is! ExecutionLiveNotice ||
        (notice.view.kind != ConversationActivityKind.responding &&
            notice.view.kind != ConversationActivityKind.compacting) ||
        notice.view.errorMessage != null) {
      return false;
    }
    if (notice.view.kind == ConversationActivityKind.responding &&
        (activeTurnId == null || notice.view.turnId != activeTurnId)) {
      return false;
    }
    final expectedAtomKind = switch (notice.view.kind) {
      ConversationActivityKind.responding => ChatAtomKind.text,
      ConversationActivityKind.compacting => ChatAtomKind.compaction,
      _ => null,
    };
    return current?.currentAtoms.any((atom) {
          if (!renderedCurrentAtomIds.contains(atom.id) ||
              atom.kind != expectedAtomKind ||
              atom.lifecycle is! ActiveChatAtom) {
            return false;
          }
          if (expectedAtomKind == ChatAtomKind.compaction) return true;
          return atom.source is ForegroundTurnChatSource &&
              (atom.source as ForegroundTurnChatSource).turnId == activeTurnId;
        }) ??
        false;
  }

  /// 将后端 `ThreadActivityView` 映射为前端类型化 `ConversationActivityView`（完整保留活跃工具列表）。
  static ConversationActivityView mapThreadActivity(
    ThreadActivityView activity,
  ) => ConversationActivityView(
    identity: activity.identity,
    kind: switch (activity.kind) {
      ThreadActivityKind.preparing => ConversationActivityKind.preparing,
      ThreadActivityKind.compacting => ConversationActivityKind.compacting,
      ThreadActivityKind.waitingApi ||
      ThreadActivityKind.thinking => ConversationActivityKind.thinking,
      ThreadActivityKind.responding => ConversationActivityKind.responding,
      ThreadActivityKind.planning => ConversationActivityKind.planning,
      ThreadActivityKind.runningTool => ConversationActivityKind.runningTool,
      ThreadActivityKind.awaitingApproval =>
        ConversationActivityKind.awaitingApproval,
      ThreadActivityKind.awaitingInput =>
        ConversationActivityKind.awaitingInput,
      ThreadActivityKind.stopping => ConversationActivityKind.stopping,
    },
    turnId: activity.turnId,
    executionId: activity.executionId,
    summary: activity.summary,
    thinkingSummary: activity.thinkingSummary,
    thinkingSeconds: activity.thinkingSeconds,
    activeTools: activity.tools.active,
    activeToolCount: activity.tools.count,
    backgroundToolCount: activity.tools.background,
    deferred: activity.deferred,
  );

  static LiveStatusNoticeSurface? projectSurface({
    required CurrentAtomSnapshot? current,
    required DisplayBlock? liveOpenWork,
    required Set<String> renderedCurrentAtomIds,
    required String? activeTurnId,
    required List<LiveStatusNotice> rawNotices,
  }) {
    final executionPresent = current?.executionPresent ?? false;
    final liveAtoms = executionPresent
        ? current?.currentAtoms ?? const <CurrentAtom>[]
        : const <CurrentAtom>[];
    final liveWorkAtoms = <CurrentAtom>[
      for (final atom in liveAtoms)
        if (atom.lifecycle is ActiveChatAtom && _isLiveWorkKind(atom.kind))
          atom,
    ];
    final liveResponseAtoms = <CurrentAtom>[
      for (final atom in liveAtoms)
        if (atom.lifecycle is ActiveChatAtom &&
            atom.kind == ChatAtomKind.text &&
            atom.contents.isNotEmpty)
          atom,
    ];
    final hasLiveWork = liveOpenWork != null || liveWorkAtoms.isNotEmpty;
    final notices = <LiveStatusNotice>[
      for (final notice in rawNotices)
        if (!hasCurrentOutputRenderer(
              current: current,
              renderedCurrentAtomIds: renderedCurrentAtomIds,
              activeTurnId: activeTurnId,
              notice: notice,
            ) &&
            !_suppressedByLiveWork(notice, hasLiveWork: hasLiveWork))
          notice,
    ];
    if (notices.isEmpty &&
        liveOpenWork == null &&
        liveWorkAtoms.isEmpty &&
        liveResponseAtoms.isEmpty) {
      return null;
    }
    return LiveStatusNoticeSurface(
      notices: notices,
      liveOpenWork: liveOpenWork,
      liveWorkAtoms: liveWorkAtoms,
      liveResponseAtoms: liveResponseAtoms,
    );
  }

  static LiveStatusView project({
    required String threadId,
    required LiveStatusInputs observation,
    Object? currentAtomsError,
    LiveActivityToolsWindow? activityTools,
  }) {
    final interaction = activePendingInteraction(observation.interactions);
    final confirmingPlan = interaction?.planConfirmation != null;
    final questionMasked =
        interaction?.kind == InteractionKind.userInput && !confirmingPlan;
    final showInteractionDetails =
        !confirmingPlan &&
        observation.hasContentOwner &&
        observation.businessRefs?.interactions != null &&
        observation.interactions.isNotEmpty;

    // 1. 派生候选阶段通知与故障通知（基于最新权威活动与存储事实）。
    final executionView = observation.activity == null
        ? null
        : mapThreadActivity(observation.activity!);
    final approvalView = interaction?.kind == InteractionKind.toolApproval
        ? projectConversationActivity(activity: null, interaction: interaction)
        : null;
    final storageView = observation.storage?.blocksContinuation == true
        ? projectConversationActivity(
            activity: null,
            storage: observation.storage,
          )
        : null;

    final rawNotices = <LiveStatusNotice>[
      if (executionView != null &&
          !(confirmingPlan &&
              executionView.kind == ConversationActivityKind.awaitingInput &&
              interaction?.turnId != null &&
              executionView.turnId == interaction?.turnId))
        ExecutionLiveNotice(executionView),
      if (approvalView != null) ExecutionLiveNotice(approvalView),
      if (storageView != null) ExecutionLiveNotice(storageView),
    ];

    final surface = projectSurface(
      current: observation.current,
      liveOpenWork: observation.liveOpenWork,
      renderedCurrentAtomIds: observation.renderedCurrentAtomIds,
      activeTurnId: observation.activeTurnId,
      rawNotices: rawNotices,
    );
    final obscured = surface == null
        ? null
        : LiveStatusPresenting(surface: surface, showInteractionDetails: false);

    // 2. 若普通待决提问占据底部交互停靠区，则遮蔽底部活动条（不影响独立时间线工作区）。
    if (questionMasked) {
      return _finalize(
        threadId: threadId,
        barState: LiveStatusDockMasked(
          interactionId: interaction!.id,
          showInteractionDetails: showInteractionDetails,
          obscured: obscured,
        ),
        primaryActivity: null,
        currentAtomsError: currentAtomsError,
        activityTools: activityTools,
      );
    }

    final primaryActivity = rawNotices
        .whereType<ExecutionLiveNotice>()
        .firstOrNull
        ?.view;

    // A pending plan decision owns the dock regardless of concurrent live content
    // or notifications. The observation and timeline work slice remain untouched.
    if (confirmingPlan && interaction != null) {
      return _finalize(
        threadId: threadId,
        barState: LiveStatusDockMasked(
          interactionId: interaction.id,
          showInteractionDetails: false,
          obscured: obscured,
        ),
        primaryActivity: primaryActivity,
        currentAtomsError: currentAtomsError,
        activityTools: activityTools,
      );
    }

    if (surface == null) {
      final barState = showInteractionDetails
          ? LiveStatusDockMasked(
              interactionId: interaction?.id ?? 'details',
              showInteractionDetails: true,
            )
          : const LiveStatusHidden();
      return _finalize(
        threadId: threadId,
        barState: barState,
        primaryActivity: primaryActivity,
        currentAtomsError: currentAtomsError,
        activityTools: activityTools,
      );
    }

    return _finalize(
      threadId: threadId,
      barState: LiveStatusPresenting(
        surface: surface,
        showInteractionDetails: showInteractionDetails,
      ),
      primaryActivity: primaryActivity,
      currentAtomsError: currentAtomsError,
      activityTools: activityTools,
    );
  }

  static LiveStatusView _finalize({
    required String threadId,
    required LiveStatusMachineState barState,
    required ConversationActivityView? primaryActivity,
    required Object? currentAtomsError,
    required LiveActivityToolsWindow? activityTools,
  }) => LiveStatusView(
    threadId: threadId,
    barState: barState,
    primaryActivity: primaryActivity,
    currentAtomsError: currentAtomsError,
    activityTools: activityTools,
  );
}
