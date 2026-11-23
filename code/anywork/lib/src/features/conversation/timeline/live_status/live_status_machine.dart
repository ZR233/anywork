import 'package:anywork_client/models.dart';

import '../../interactions/state/interaction_payload.dart';
import '../state/timeline_display_models.dart';
import 'live_status_state.dart';

/// Current 活动、Atoms、开放工作组、连接/存储异常与交互门控的纯状态机。
///
/// 零 Flutter、Riverpod、FRB 或 Client I/O 依赖；直接复用
/// [projectConversationActivity] 完成服务端活动映射。
abstract final class LiveStatusMachine {
  static LiveStatusView project({
    required String threadId,
    required LiveStatusInputs inputs,
    Object? currentAtomsError,
    LiveActivityToolsWindow? activityTools,
  }) {
    final interaction = activePendingInteraction(inputs.interactions);
    final confirmingPlan = interaction?.planConfirmation != null;
    final questionMasked =
        interaction?.kind == InteractionKind.userInput && !confirmingPlan;
    final showInteractionDetails =
        !confirmingPlan &&
        inputs.hasContentOwner &&
        inputs.businessRefs?.interactions != null &&
        inputs.interactions.isNotEmpty;

    final executionView = inputs.activity == null
        ? null
        : projectConversationActivity(
            activity: inputs.activity,
            businessRefs: inputs.businessRefs,
          );
    final ignorePlanInputDuplicate =
        confirmingPlan &&
        executionView?.kind == ConversationActivityKind.awaitingInput &&
        interaction?.turnId != null &&
        executionView?.turnId == interaction?.turnId;
    final activeExecution = ignorePlanInputDuplicate ? null : executionView;

    final approvalView = interaction?.kind == InteractionKind.toolApproval
        ? projectConversationActivity(activity: null, interaction: interaction)
        : null;
    final storage = inputs.storage;
    final storageView = storage?.blocksContinuation == true
        ? projectConversationActivity(activity: null, storage: storage)
        : null;

    final current = inputs.current;
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

    final liveWork = _projectLiveWork(
      threadId: threadId,
      openWork: inputs.liveOpenWork,
      liveWorkAtoms: liveWorkAtoms,
      activity: activeExecution,
      executionPresent: executionPresent,
    );

    final hasPreviewResponse =
        inputs.previewResponseText != null &&
        inputs.previewResponseText!.isNotEmpty;
    final responseSuppressed =
        activeExecution != null &&
        activeExecution.kind == ConversationActivityKind.responding &&
        ((hasPreviewResponse &&
                liveResponseAtoms.isEmpty &&
                activeExecution.errorMessage == null) ||
            _hasCurrentOutputRenderer(
              current: current,
              renderedCurrentAtomIds: inputs.renderedCurrentAtomIds,
              activeTurnId: inputs.activeTurnId,
              activity: activeExecution,
            ));
    final compactingSuppressed =
        activeExecution != null &&
        activeExecution.kind == ConversationActivityKind.compacting &&
        _hasCurrentOutputRenderer(
          current: current,
          renderedCurrentAtomIds: inputs.renderedCurrentAtomIds,
          activeTurnId: inputs.activeTurnId,
          activity: activeExecution,
        );

    final primary = _selectPrimaryPhase(
      execution: activeExecution,
      liveWork: liveWork,
      liveResponseAtoms: liveResponseAtoms,
      previewResponseText: inputs.previewResponseText,
      previewResponseStartedAt: inputs.previewResponseStartedAt,
      responseSuppressed: responseSuppressed,
      compactingSuppressed: compactingSuppressed,
    );

    final effectiveError = currentAtomsError ?? inputs.currentAtomsError;
    final attentions = _collectAttentions(
      execution: activeExecution,
      approvalView: approvalView,
      storage: storage,
      storageView: storageView,
      connectionStatus: inputs.connectionStatus,
      connectionDetail: inputs.connectionDetail,
      currentAtomsError: effectiveError,
      primary: primary,
    );

    final presentation = LiveStatusPresentation(
      primary: primary,
      attentions: attentions,
      activityTools: questionMasked || confirmingPlan ? null : activityTools,
      showInteractionDetails: showInteractionDetails,
    );
    final visiblePresentation = presentation.isEmpty ? null : presentation;

    final primaryActivity = questionMasked
        ? null
        : activeExecution ?? approvalView ?? storageView;

    if (questionMasked) {
      return LiveStatusView(
        threadId: threadId,
        gate: LiveStatusSuppressed(
          interactionId: interaction!.id,
          showInteractionDetails: showInteractionDetails,
          obscured: visiblePresentation,
        ),
        primaryActivity: null,
        activityTools: activityTools,
      );
    }

    if (confirmingPlan && interaction != null) {
      return LiveStatusView(
        threadId: threadId,
        gate: LiveStatusSuppressed(
          interactionId: interaction.id,
          showInteractionDetails: false,
          obscured: visiblePresentation,
        ),
        primaryActivity: primaryActivity,
        activityTools: activityTools,
      );
    }

    if (presentation.primary == null &&
        presentation.attentions.isEmpty &&
        presentation.activityTools == null) {
      return LiveStatusView(
        threadId: threadId,
        gate: showInteractionDetails
            ? LiveStatusSuppressed(
                interactionId: interaction?.id ?? 'details',
                showInteractionDetails: true,
              )
            : const LiveStatusIdle(),
        primaryActivity: primaryActivity,
        activityTools: activityTools,
      );
    }

    return LiveStatusView(
      threadId: threadId,
      gate: LiveStatusPresenting(presentation: presentation),
      primaryActivity: primaryActivity,
      activityTools: activityTools,
    );
  }

  static bool _isLiveWorkKind(ChatAtomKind kind) => switch (kind) {
    ChatAtomKind.reasoning ||
    ChatAtomKind.toolCall ||
    ChatAtomKind.fileChange ||
    ChatAtomKind.skill ||
    ChatAtomKind.agent => true,
    _ => false,
  };

  /// 当本轮次已由正文或压缩记录渲染且完成首次布局测量后，接管并抑制同类简单提示。
  static bool _hasCurrentOutputRenderer({
    required CurrentAtomSnapshot? current,
    required Set<String> renderedCurrentAtomIds,
    required String? activeTurnId,
    required ConversationActivityView activity,
  }) {
    if ((activity.kind != ConversationActivityKind.responding &&
            activity.kind != ConversationActivityKind.compacting) ||
        activity.errorMessage != null) {
      return false;
    }
    if (activity.kind == ConversationActivityKind.responding &&
        (activeTurnId == null || activity.turnId != activeTurnId)) {
      return false;
    }
    final expectedAtomKind = switch (activity.kind) {
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

  static LiveWorkPhase? _projectLiveWork({
    required String threadId,
    required DisplayBlock? openWork,
    required List<CurrentAtom> liveWorkAtoms,
    required ConversationActivityView? activity,
    required bool executionPresent,
  }) {
    if (openWork == null && liveWorkAtoms.isEmpty) return null;

    final WorkDisplayBlock? openBody = openWork?.body is WorkDisplayBlock
        ? openWork!.body as WorkDisplayBlock
        : null;
    if (openWork != null && openBody == null) return null;

    final effectiveExecutionPresent =
        openBody?.executionPresent ?? executionPresent;
    if (!effectiveExecutionPresent) return null;

    final timing = openBody?.timing ?? _timingFromAtoms(liveWorkAtoms);
    final headerActivity = _filterWorkHeaderActivity(activity);
    final thinkingSummary = _allowsThinkingSummaryOnHeader(headerActivity?.kind)
        ? (_nonEmpty(headerActivity?.thinkingSummary) ??
              _nonEmpty(openBody?.summary))
        : null;

    final id = openWork?.id ?? 'live-work:$threadId';
    final effectiveBlock =
        openWork ??
        DisplayBlock(
          id: id,
          blockOrder: 0,
          body: WorkDisplayBlock(
            timing: timing,
            summary: thinkingSummary,
            members: DisplayBlockRef(
              blockId: id,
              cut: const HistoryCut(''),
              anchorSeq: 0,
              headSeq: 0,
              afterSeq: 0,
            ),
            executionPresent: true,
            memberCount: liveWorkAtoms.length,
            unfinishedCount: liveWorkAtoms.length,
            groupClosed: false,
          ),
        );

    final mode = switch (headerActivity?.kind) {
      ConversationActivityKind.stopping => LiveWorkGroupMode.stopping,
      ConversationActivityKind.awaitingApproval => LiveWorkGroupMode.waiting,
      _ when headerActivity?.wait != null => LiveWorkGroupMode.waiting,
      _ => LiveWorkGroupMode.active,
    };

    return LiveWorkPhase(
      id: id,
      block: effectiveBlock,
      liveWorkAtoms: liveWorkAtoms,
      mode: mode,
      timing: timing,
      activity: headerActivity,
      thinkingSummary: thinkingSummary,
      executionPresent: true,
    );
  }

  static bool _allowsThinkingSummaryOnHeader(ConversationActivityKind? kind) =>
      switch (kind) {
        ConversationActivityKind.preparing ||
        ConversationActivityKind.thinking ||
        ConversationActivityKind.planning ||
        ConversationActivityKind.runningTool => true,
        _ => false,
      };

  static ConversationActivityView? _filterWorkHeaderActivity(
    ConversationActivityView? activity,
  ) {
    if (activity == null || activity.errorMessage != null) return null;
    return switch (activity.kind) {
      ConversationActivityKind.responding ||
      ConversationActivityKind.compacting ||
      ConversationActivityKind.awaitingInput ||
      ConversationActivityKind.storageBlocked => null,
      ConversationActivityKind.preparing ||
      ConversationActivityKind.thinking ||
      ConversationActivityKind.planning ||
      ConversationActivityKind.runningTool ||
      ConversationActivityKind.awaitingApproval ||
      ConversationActivityKind.stopping => activity,
    };
  }

  static LiveStatusPrimaryPhase? _selectPrimaryPhase({
    required ConversationActivityView? execution,
    required LiveWorkPhase? liveWork,
    required List<CurrentAtom> liveResponseAtoms,
    required String? previewResponseText,
    required int? previewResponseStartedAt,
    required bool responseSuppressed,
    required bool compactingSuppressed,
  }) {
    final hasResponse =
        liveResponseAtoms.isNotEmpty ||
        (previewResponseText != null && previewResponseText.isNotEmpty);
    if (hasResponse) {
      final showCompanionActivity =
          execution != null &&
          !responseSuppressed &&
          !_isAttentionOnlyActivity(execution.kind);
      return LiveResponsePhase(
        responseAtoms: liveResponseAtoms,
        previewText: previewResponseText,
        startedAt:
            previewResponseStartedAt ??
            liveResponseAtoms.firstOrNull?.startedAt,
        activity: showCompanionActivity ? execution : null,
      );
    }

    if (execution != null &&
        execution.kind == ConversationActivityKind.responding) {
      return LiveActivityPhase(activity: execution);
    }

    if (execution != null &&
        execution.kind == ConversationActivityKind.compacting &&
        !compactingSuppressed) {
      return LiveCompactingPhase(activity: execution);
    }

    if (liveWork != null) {
      return liveWork;
    }

    if (execution != null &&
        !_isAttentionOnlyActivity(execution.kind) &&
        !(execution.kind == ConversationActivityKind.compacting &&
            compactingSuppressed)) {
      return LiveActivityPhase(activity: execution);
    }

    return null;
  }

  static List<LiveStatusAttention> _collectAttentions({
    required ConversationActivityView? execution,
    required ConversationActivityView? approvalView,
    required ThreadStorageStateView? storage,
    required ConversationActivityView? storageView,
    required LiveConnectionStatus connectionStatus,
    required String? connectionDetail,
    required Object? currentAtomsError,
    required LiveStatusPrimaryPhase? primary,
  }) {
    final attentions = <LiveStatusAttention>[];
    final workAbsorbedKind = primary is LiveWorkPhase
        ? primary.activity?.kind
        : null;

    if (execution != null &&
        execution.kind == ConversationActivityKind.stopping &&
        workAbsorbedKind != ConversationActivityKind.stopping) {
      attentions.add(LiveStoppingAttention(execution));
    }

    final approvalActivity =
        execution?.kind == ConversationActivityKind.awaitingApproval
        ? execution
        : approvalView;
    if (approvalActivity != null &&
        workAbsorbedKind != ConversationActivityKind.awaitingApproval) {
      attentions.add(LiveApprovalAttention(approvalActivity));
    }

    if (storage != null && storageView != null) {
      attentions.add(
        LiveStorageAttention(
          activity: storageView,
          storage: storage,
          severity: _classifyStorage(storage),
        ),
      );
    }

    if (connectionStatus != LiveConnectionStatus.connected) {
      attentions.add(
        LiveConnectionAttention(
          status: connectionStatus,
          detail: _nonEmpty(connectionDetail),
        ),
      );
    }

    final primaryActivityError = switch (primary) {
      LiveActivityPhase(:final activity) => _nonEmpty(activity.errorMessage),
      LiveCompactingPhase(:final activity) => _nonEmpty(activity.errorMessage),
      LiveResponsePhase(:final activity) => _nonEmpty(activity?.errorMessage),
      _ => null,
    };
    if (currentAtomsError != null) {
      attentions.add(
        LiveErrorAttention(
          message: currentAtomsError.toString(),
          retryable: true,
        ),
      );
    } else if (execution != null &&
        execution.kind != ConversationActivityKind.storageBlocked &&
        _nonEmpty(execution.errorMessage) != null &&
        _nonEmpty(execution.errorMessage) != primaryActivityError) {
      attentions.add(
        LiveErrorAttention(message: _nonEmpty(execution.errorMessage)!),
      );
    }

    return attentions;
  }

  static LiveStorageSeverity _classifyStorage(ThreadStorageStateView storage) {
    if (storage.resumeRequired && storage.canResume) {
      return LiveStorageSeverity.resumeReady;
    }
    if (storage.hasFault) {
      return LiveStorageSeverity.fault;
    }
    if (storage.pressurePaused) {
      return LiveStorageSeverity.pressure;
    }
    if (storage.resumeRequired) {
      return LiveStorageSeverity.resumeRequired;
    }
    return LiveStorageSeverity.paused;
  }

  static bool _isAttentionOnlyActivity(ConversationActivityKind kind) =>
      switch (kind) {
        ConversationActivityKind.stopping ||
        ConversationActivityKind.awaitingApproval ||
        ConversationActivityKind.storageBlocked => true,
        _ => false,
      };

  static WorkTiming _timingFromAtoms(List<CurrentAtom> atoms) {
    int? earliestMillis;
    for (final atom in atoms) {
      final startedAt = atom.startedAt;
      if (startedAt == null) continue;
      final millis = startedAt * Duration.millisecondsPerSecond;
      if (earliestMillis == null || millis < earliestMillis) {
        earliestMillis = millis;
      }
    }
    return WorkTiming(startedAtMillis: earliestMillis, finishedAtMillis: null);
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed != null && trimmed.isNotEmpty ? trimmed : null;
  }
}
