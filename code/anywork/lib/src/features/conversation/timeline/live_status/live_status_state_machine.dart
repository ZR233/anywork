import 'package:anywork_client/models.dart';

import '../../interactions/state/interaction_payload.dart';
import 'live_status_state.dart';

/// 实时状态栏纯领域状态机（`design/05-conventions.md` §5.3）：
/// 不执行任何异步 I/O、不读取 Provider、不依赖 Widget 上下文。
/// 所有窗口切换、遮蔽门控、阶段合并与外部副作用统一在此完成确定性转换。
abstract final class LiveStatusStateMachine {
  /// 是否已有当前轮次真实流式正文渲染器承担输出展示（避免重复叠加普通“正在输出”提示行）。
  static bool hasCurrentOutputRenderer({
    required LiveDisplayWindow? live,
    required String? activeTurnId,
    required LiveStatusNotice notice,
  }) {
    if (notice is! ExecutionLiveNotice ||
        notice.view.kind != ConversationActivityKind.responding ||
        notice.view.errorMessage != null ||
        notice.view.turnId != activeTurnId ||
        activeTurnId == null ||
        live?.executionPresent != true) {
      return false;
    }
    return live!.blocks.any((block) {
      if (block.state != DisplayBlockState.open) return false;
      if (block.body case SingleDisplayBlock(
        record: DisplayRecord(contentSource: CurrentAtom(), atom: final atom),
      )) {
        return atom.kind == ChatAtomKind.text &&
            atom.lifecycle is ActiveChatAtom &&
            atom.source is ForegroundTurnChatSource &&
            (atom.source as ForegroundTurnChatSource).turnId == activeTurnId;
      }
      return false;
    });
  }

  /// 规范最新窗口是当前尾组身份的唯一来源；旧页和来源仅描述内容。
  static LiveDisplayBlock? currentWork(LiveDisplayWindow? live) {
    final id = live?.currentWorkId;
    if (id == null) return null;
    for (final block in live!.blocks) {
      if (block.id == id &&
          block.state == DisplayBlockState.open &&
          block.body is WorkDisplayBlock) {
        return block;
      }
    }
    return null;
  }

  static bool _needsRestoration(LiveDisplayBlock block) {
    if (block.state != DisplayBlockState.open) return false;
    return switch (block.body) {
      WorkDisplayBlock(:final summary) =>
        summary.hasUnfinishedOrUnavailableMembers,
      SingleDisplayBlock(:final record) =>
        record.atom.lifecycle is ActiveChatAtom ||
            (record.contentSource is FrozenObservation &&
                !(record.contentSource as FrozenObservation).available),
    };
  }

  /// 普通活动沿原 State 合并到明确的当前尾组；不把来源或成员状态当活动。
  /// 审批、存储故障等关键提示以及 unavailable 组仍保持独立呈现。
  static ({String blockId, ExecutionLiveNotice notice})? mergeableWorkNotice({
    required LiveDisplayWindow? live,
    required List<LiveStatusNotice> notices,
  }) {
    if (live == null || !live.executionPresent) {
      return null;
    }
    final latest = currentWork(live);
    if (latest == null) return null;
    final summary = (latest.body as WorkDisplayBlock).summary;
    if (summary.unavailable != 0) {
      return null;
    }
    for (final notice in notices) {
      if (notice is! ExecutionLiveNotice) continue;
      final view = notice.view;
      if (view.errorMessage != null) continue;
      if (view.kind == ConversationActivityKind.preparing ||
          view.kind == ConversationActivityKind.thinking ||
          view.kind == ConversationActivityKind.runningTool ||
          view.kind == ConversationActivityKind.planning) {
        return (blockId: latest.id, notice: notice);
      }
    }
    return null;
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
  );

  /// 封闭状态转换主入口：输入前一聚合根与领域事件，输出新聚合根与待执行副作用。
  static LiveStatusTransition transition(
    LiveStatusAggregate previous,
    LiveStatusEvent event,
  ) {
    return switch (event) {
      LiveStatusObserved(:final observation) => _recompute(
        previous: previous,
        observation: observation,
        outputPaging: previous.outputPaging.reconcile(observation.cut),
        timelineWorkPaging: previous.timelineWorkPaging.reconcile(
          observation.cut,
        ),
      ),
      LiveStatusLoadOlderRequested(:final target, :final before) =>
        _handleLoadOlderRequested(
          previous: previous,
          target: target,
          before: before,
        ),
      LiveStatusOlderLoaded(
        :final target,
        :final before,
        :final window,
        :final cut,
      ) =>
        _handleOlderLoaded(
          previous: previous,
          target: target,
          before: before,
          window: window,
          cut: cut,
        ),
      LiveStatusOlderFailed(
        :final target,
        :final before,
        :final error,
        :final cut,
      ) =>
        _handleOlderFailed(
          previous: previous,
          target: target,
          before: before,
          error: error,
          cut: cut,
        ),
      LiveStatusReturnToLatestRequested(:final target) => _recompute(
        previous: previous,
        observation: previous.observation,
        outputPaging: target == LiveStatusSectionTarget.outputBar
            ? const LatestLiveWindow()
            : previous.outputPaging,
        timelineWorkPaging: target == LiveStatusSectionTarget.timelineWork
            ? const LatestLiveWindow()
            : previous.timelineWorkPaging,
      ),
    };
  }

  static LiveStatusTransition _handleLoadOlderRequested({
    required LiveStatusAggregate previous,
    required LiveStatusSectionTarget target,
    required String before,
  }) {
    final cut = previous.observation.cut;
    if (!cut.hasWindow) {
      return LiveStatusTransition(state: previous);
    }
    final currentPaging = target == LiveStatusSectionTarget.outputBar
        ? previous.outputPaging
        : previous.timelineWorkPaging;
    if (currentPaging.isLoading) {
      return LiveStatusTransition(state: previous);
    }
    final nextPaging = LoadingOlderLiveWindow(
      before: before,
      cut: cut,
      previousOlder: currentPaging.olderWindow,
    );
    final recomputed = _recompute(
      previous: previous,
      observation: previous.observation,
      outputPaging: target == LiveStatusSectionTarget.outputBar
          ? nextPaging
          : previous.outputPaging,
      timelineWorkPaging: target == LiveStatusSectionTarget.timelineWork
          ? nextPaging
          : previous.timelineWorkPaging,
    );
    return LiveStatusTransition(
      state: recomputed.state,
      effects: [
        ...recomputed.effects,
        ReadOlderLiveWindowEffect(target: target, before: before, cut: cut),
      ],
    );
  }

  static LiveStatusTransition _handleOlderLoaded({
    required LiveStatusAggregate previous,
    required LiveStatusSectionTarget target,
    required String before,
    required LiveDisplayWindow window,
    required LiveWindowCut cut,
  }) {
    final activeCut = previous.observation.cut;
    if (!activeCut.hasWindow ||
        activeCut != cut ||
        !activeCut.matchesWindow(window)) {
      return LiveStatusTransition(state: previous);
    }
    final nextPaging = ViewingOlderLiveWindow(
      before: before,
      window: window,
      cut: activeCut,
    );
    return _recompute(
      previous: previous,
      observation: previous.observation,
      outputPaging: target == LiveStatusSectionTarget.outputBar
          ? nextPaging
          : previous.outputPaging,
      timelineWorkPaging: target == LiveStatusSectionTarget.timelineWork
          ? nextPaging
          : previous.timelineWorkPaging,
    );
  }

  static LiveStatusTransition _handleOlderFailed({
    required LiveStatusAggregate previous,
    required LiveStatusSectionTarget target,
    required String before,
    required Object error,
    required LiveWindowCut cut,
  }) {
    final activeCut = previous.observation.cut;
    if (!activeCut.hasWindow || activeCut != cut) {
      return LiveStatusTransition(state: previous);
    }
    final currentPaging = target == LiveStatusSectionTarget.outputBar
        ? previous.outputPaging
        : previous.timelineWorkPaging;
    final nextPaging = OlderLiveWindowFailed(
      before: before,
      error: error,
      cut: activeCut,
      previousOlder: currentPaging.olderWindow,
    );
    return _recompute(
      previous: previous,
      observation: previous.observation,
      outputPaging: target == LiveStatusSectionTarget.outputBar
          ? nextPaging
          : previous.outputPaging,
      timelineWorkPaging: target == LiveStatusSectionTarget.timelineWork
          ? nextPaging
          : previous.timelineWorkPaging,
    );
  }

  /// 在有效窗口上计算上方时间线实时工作块与底部状态栏主表面（纯函数，无副作用）。
  static ({
    LiveStatusPrimarySurface? surface,
    List<LiveDisplayBlock> timelineWorkBlocks,
  })
  projectSurfaceAndTimelineWork({
    required LiveDisplayWindow? effectiveOutputWindow,
    required LiveDisplayWindow? effectiveTimelineWindow,
    required LiveDisplayWindow? latestWindow,
    required String? activeTurnId,
    required LiveWindowPagingState outputPaging,
    required List<LiveStatusNotice> rawNotices,
  }) {
    final tail = currentWork(latestWindow);
    final timelineWorkBlocks = <LiveDisplayBlock>[
      for (final block
          in effectiveTimelineWindow?.blocks ?? const <LiveDisplayBlock>[])
        if (block.body is WorkDisplayBlock && block.id != tail?.id) block,
    ];

    final merged = mergeableWorkNotice(live: latestWindow, notices: rawNotices);
    final unrestoredInWorkHeader =
        tail != null &&
        latestWindow?.executionPresent == false &&
        latestWindow!.blocks.every((block) => block.body is WorkDisplayBlock);
    final standaloneNotices = <LiveStatusNotice>[
      for (final notice in rawNotices)
        if (!identical(notice, merged?.notice) &&
            !hasCurrentOutputRenderer(
              live: effectiveOutputWindow,
              activeTurnId: activeTurnId,
              notice: notice,
            ) &&
            !(unrestoredInWorkHeader && notice is UnrestoredLiveNotice))
          notice,
    ];

    final outputBlocks = <LiveDisplayBlock>[
      for (final block
          in effectiveOutputWindow?.blocks ?? const <LiveDisplayBlock>[])
        if (block.body is SingleDisplayBlock) block,
      if (tail != null) tail,
    ];

    final hasPagingControls =
        outputPaging.isLoading ||
        outputPaging.isViewingOlder ||
        outputPaging.error != null;
    if (outputBlocks.isEmpty &&
        standaloneNotices.isEmpty &&
        !hasPagingControls) {
      return (surface: null, timelineWorkBlocks: timelineWorkBlocks);
    }

    final LiveStatusPrimarySurface surface;
    if (tail != null) {
      final mergedView = merged?.blockId == tail.id
          ? merged?.notice.view
          : null;
      surface = LiveStatusWorkSurface(
        workBlock: tail,
        precedingSingles: outputBlocks.sublist(0, outputBlocks.length - 1),
        mergedActivity: mergedView,
        headerIndicatorStyle: resolveLiveHeaderIndicatorStyle(mergedView),
        standaloneNotices: standaloneNotices,
      );
    } else if (outputBlocks.isNotEmpty) {
      surface = LiveStatusStreamingSurface(
        singleBlocks: outputBlocks,
        standaloneNotices: standaloneNotices,
      );
    } else {
      surface = LiveStatusNoticeOnlySurface(notices: standaloneNotices);
    }
    return (surface: surface, timelineWorkBlocks: timelineWorkBlocks);
  }

  static LiveStatusTransition _recompute({
    required LiveStatusAggregate previous,
    required LiveStatusObservation observation,
    required LiveWindowPagingState outputPaging,
    required LiveWindowPagingState timelineWorkPaging,
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

    final latestLive = observation.cut.isDisplayActive
        ? observation.latestLive
        : null;
    final effectiveOutputWindow = outputPaging.olderWindow ?? latestLive;
    final effectiveTimelineWindow =
        timelineWorkPaging.olderWindow ?? latestLive;

    // 1. 派生候选阶段通知与故障通知（基于最新权威活动与存储事实）。
    final rawActivity = latestLive?.executionPresent == false
        ? null
        : observation.activity;
    final executionView = rawActivity == null
        ? null
        : mapThreadActivity(rawActivity);
    final approvalView = interaction?.kind == InteractionKind.toolApproval
        ? projectConversationActivity(
            activity: null,
            snapshot: null,
            interaction: interaction,
          )
        : null;
    final storageView = observation.storage?.blocksContinuation == true
        ? projectConversationActivity(
            activity: null,
            snapshot: null,
            storage: observation.storage,
          )
        : null;

    final rawNotices = <LiveStatusNotice>[
      if (latestLive?.executionPresent == false &&
          latestLive!.blocks.any(_needsRestoration))
        const UnrestoredLiveNotice(),
      if (executionView != null &&
          !(confirmingPlan &&
              executionView.kind == ConversationActivityKind.awaitingInput &&
              interaction?.turnId != null &&
              executionView.turnId == interaction?.turnId))
        ExecutionLiveNotice(executionView),
      if (approvalView != null) ExecutionLiveNotice(approvalView),
      if (storageView != null) ExecutionLiveNotice(storageView),
    ];

    final projected = projectSurfaceAndTimelineWork(
      effectiveOutputWindow: effectiveOutputWindow,
      effectiveTimelineWindow: effectiveTimelineWindow,
      latestWindow: latestLive,
      activeTurnId: observation.activeTurnId,
      outputPaging: outputPaging,
      rawNotices: rawNotices,
    );
    final timelineSlice = LiveStatusTimelineWorkSlice(
      workBlocks: projected.timelineWorkBlocks,
      effectiveWindow: effectiveTimelineWindow,
      paging: timelineWorkPaging,
    );
    final obscured = projected.surface == null
        ? null
        : LiveStatusPresenting(
            surface: projected.surface!,
            effectiveWindow: effectiveOutputWindow,
            paging: outputPaging,
            showInteractionDetails: false,
          );

    // 2. 若普通待决提问占据底部交互停靠区，则遮蔽底部活动条（不影响独立时间线工作区）。
    if (questionMasked) {
      return _finalize(
        previous: previous,
        observation: observation,
        barState: LiveStatusDockMasked(
          interactionId: interaction!.id,
          showInteractionDetails: showInteractionDetails,
          obscured: obscured,
        ),
        timelineWork: timelineSlice,
        outputPaging: outputPaging,
        timelineWorkPaging: timelineWorkPaging,
        primaryActivity: null,
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
        previous: previous,
        observation: observation,
        barState: LiveStatusDockMasked(
          interactionId: interaction.id,
          showInteractionDetails: false,
          obscured: obscured,
        ),
        timelineWork: timelineSlice,
        outputPaging: outputPaging,
        timelineWorkPaging: timelineWorkPaging,
        primaryActivity: primaryActivity,
      );
    }

    final surface = projected.surface;
    if (surface == null) {
      final barState = showInteractionDetails
          ? LiveStatusDockMasked(
              interactionId: interaction?.id ?? 'details',
              showInteractionDetails: true,
            )
          : const LiveStatusHidden();
      return _finalize(
        previous: previous,
        observation: observation,
        barState: barState,
        timelineWork: timelineSlice,
        outputPaging: outputPaging,
        timelineWorkPaging: timelineWorkPaging,
        primaryActivity: primaryActivity,
      );
    }

    return _finalize(
      previous: previous,
      observation: observation,
      barState: LiveStatusPresenting(
        surface: surface,
        effectiveWindow: effectiveOutputWindow,
        paging: outputPaging,
        showInteractionDetails: showInteractionDetails,
      ),
      timelineWork: timelineSlice,
      outputPaging: outputPaging,
      timelineWorkPaging: timelineWorkPaging,
      primaryActivity: primaryActivity,
    );
  }

  static LiveStatusTransition _finalize({
    required LiveStatusAggregate previous,
    required LiveStatusObservation observation,
    required LiveStatusMachineState barState,
    required LiveStatusTimelineWorkSlice timelineWork,
    required LiveWindowPagingState outputPaging,
    required LiveWindowPagingState timelineWorkPaging,
    required ConversationActivityView? primaryActivity,
  }) {
    final driverChanged =
        !previous.hasPublishedDriver ||
        primaryActivity != previous.publishedDriverActivity;
    final nextState = LiveStatusAggregate(
      threadId: previous.threadId,
      observation: observation,
      barState: barState,
      timelineWork: timelineWork,
      outputPaging: outputPaging,
      timelineWorkPaging: timelineWorkPaging,
      primaryActivity: primaryActivity,
      publishedDriverActivity: primaryActivity,
      hasPublishedDriver: true,
    );
    return LiveStatusTransition(
      state: nextState,
      effects: [
        if (driverChanged) SyncStudioDriverActivityEffect(primaryActivity),
      ],
    );
  }
}
