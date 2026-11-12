import 'package:anywork_client/models.dart';

import '../../interactions/state/interaction_payload.dart';
import 'live_status_state.dart';

/// 实时状态栏纯领域状态机（`design/05-conventions.md` §5.3）：
/// 不执行任何异步 I/O、不读取 Provider、不依赖 Widget 上下文。
/// 所有窗口切换、遮蔽门控、阶段合并与外部副作用统一在此完成确定性转换。
abstract final class LiveStatusStateMachine {
  /// 当前轮次正文或压缩记录已承担展示时，接管并抑制对应的普通同类状态提示。
  static bool hasCurrentOutputRenderer({
    required LiveDisplayWindow? live,
    required String? activeTurnId,
    required LiveStatusNotice notice,
  }) {
    if (notice is! ExecutionLiveNotice ||
        (notice.view.kind != ConversationActivityKind.responding &&
            notice.view.kind != ConversationActivityKind.compacting) ||
        notice.view.errorMessage != null ||
        notice.view.turnId != activeTurnId ||
        activeTurnId == null ||
        live?.executionPresent != true) {
      return false;
    }
    final expectedAtomKind = switch (notice.view.kind) {
      ConversationActivityKind.responding => ChatAtomKind.text,
      ConversationActivityKind.compacting => ChatAtomKind.compaction,
      _ => null,
    };
    return live!.blocks.any((block) {
      if (block.state != DisplayBlockState.open) return false;
      if (block.body case SingleDisplayBlock(
        record: DisplayRecord(contentSource: CurrentAtom(), atom: final atom),
      )) {
        return atom.kind == expectedAtomKind &&
            atom.lifecycle is ActiveChatAtom &&
            atom.source is ForegroundTurnChatSource &&
            (atom.source as ForegroundTurnChatSource).turnId == activeTurnId;
      }
      return false;
    });
  }

  /// 当前活跃前台轮次的最新开放 `Work` 归入底部实时状态栏；
  /// 已封存、冷读未恢复、跨轮次及计划遮蔽期工作组留在上方时间线工作区。
  static bool isLiveBarWorkBlock({
    required bool confirmingPlan,
    required bool dockMasked,
    required LiveDisplayWindow? live,
    required String? activeTurnId,
    required LiveDisplayBlock block,
  }) {
    if (dockMasked ||
        confirmingPlan ||
        live == null ||
        !live.executionPresent ||
        activeTurnId == null ||
        !identical(live.blocks.lastOrNull, block) ||
        block.state != DisplayBlockState.open ||
        block.body is! WorkDisplayBlock) {
      return false;
    }
    final source = block.source;
    return source is ForegroundTurnChatSource && source.turnId == activeTurnId;
  }

  /// 判断上方时间线工作区应忽略的“属于当前轮次底部栏”的开放 `Work`：
  /// 普通问答遮蔽期间该开放组归前台交互轮次持有，不转入独立时间线工作记录。
  static bool _isOwnedByActiveForegroundTurn({
    required bool confirmingPlan,
    required LiveDisplayWindow? live,
    required String? activeTurnId,
    required LiveDisplayBlock block,
  }) {
    if (confirmingPlan ||
        live == null ||
        !live.executionPresent ||
        activeTurnId == null ||
        !identical(live.blocks.lastOrNull, block) ||
        block.state != DisplayBlockState.open ||
        block.body is! WorkDisplayBlock) {
      return false;
    }
    final source = block.source;
    return source is ForegroundTurnChatSource && source.turnId == activeTurnId;
  }

  /// 常规轮次活动提示合并进当前活跃轮次最新且开放的 `Work` 卡片头部；
  /// 成员失败、取消或交接不代表当前轮次结束，不阻止当前活动合并。
  /// 更早实时窗口以及审批/存储故障等关键提示仍保持独立呈现。
  static ({String blockId, ExecutionLiveNotice notice})? mergeableWorkNotice({
    required LiveDisplayWindow? live,
    required String? activeTurnId,
    required List<LiveStatusNotice> notices,
  }) {
    if (live == null || !live.executionPresent || activeTurnId == null) {
      return null;
    }
    final latest = live.blocks.lastOrNull;
    if (latest == null ||
        latest.state != DisplayBlockState.open ||
        latest.body is! WorkDisplayBlock) {
      return null;
    }
    final summary = (latest.body as WorkDisplayBlock).summary;
    if (summary.unavailable != 0) {
      return null;
    }
    final source = latest.source;
    if (source is! ForegroundTurnChatSource || source.turnId != activeTurnId) {
      return null;
    }
    for (final notice in notices) {
      if (notice is! ExecutionLiveNotice) continue;
      final view = notice.view;
      if (view.turnId != activeTurnId || view.errorMessage != null) continue;
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
    required String? activeTurnId,
    required bool confirmingPlan,
    required LiveWindowPagingState outputPaging,
    required List<LiveStatusNotice> rawNotices,
  }) {
    final timelineWorkBlocks = <LiveDisplayBlock>[
      for (final block
          in effectiveTimelineWindow?.blocks ?? const <LiveDisplayBlock>[])
        if (block.body is WorkDisplayBlock &&
            !_isOwnedByActiveForegroundTurn(
              confirmingPlan: confirmingPlan,
              live: effectiveTimelineWindow,
              activeTurnId: activeTurnId,
              block: block,
            ))
          block,
    ];

    final merged = !outputPaging.isViewingOlder
        ? mergeableWorkNotice(
            live: effectiveOutputWindow,
            activeTurnId: activeTurnId,
            notices: rawNotices,
          )
        : null;
    final coldWorkOnly =
        effectiveOutputWindow != null &&
        !effectiveOutputWindow.executionPresent &&
        effectiveOutputWindow.blocks.isNotEmpty &&
        effectiveOutputWindow.blocks.every(
          (block) => block.body is WorkDisplayBlock,
        );
    final standaloneNotices = <LiveStatusNotice>[
      for (final notice in rawNotices)
        if (!identical(notice, merged?.notice) &&
            !hasCurrentOutputRenderer(
              live: effectiveOutputWindow,
              activeTurnId: activeTurnId,
              notice: notice,
            ) &&
            !(coldWorkOnly && notice is UnrestoredLiveNotice))
          notice,
    ];

    final outputBlocks = <LiveDisplayBlock>[
      for (final block
          in effectiveOutputWindow?.blocks ?? const <LiveDisplayBlock>[])
        if (block.body is SingleDisplayBlock ||
            (block.body is WorkDisplayBlock &&
                isLiveBarWorkBlock(
                  confirmingPlan: confirmingPlan,
                  dockMasked: false,
                  live: effectiveOutputWindow,
                  activeTurnId: activeTurnId,
                  block: block,
                )))
          block,
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
    final trailingWork = outputBlocks.lastOrNull;
    if (trailingWork != null && trailingWork.body is WorkDisplayBlock) {
      final mergedView = merged?.blockId == trailingWork.id
          ? merged?.notice.view
          : null;
      surface = LiveStatusWorkSurface(
        workBlock: trailingWork,
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
          latestLive!.blocks.any(
            (block) => block.state == DisplayBlockState.open,
          ))
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
      activeTurnId: observation.activeTurnId,
      confirmingPlan: confirmingPlan,
      outputPaging: outputPaging,
      rawNotices: rawNotices,
    );
    final timelineSlice = LiveStatusTimelineWorkSlice(
      workBlocks: projected.timelineWorkBlocks,
      effectiveWindow: effectiveTimelineWindow,
      paging: timelineWorkPaging,
    );

    // 2. 若普通待决提问占据底部交互停靠区，则遮蔽底部活动条（不影响独立时间线工作区）。
    if (questionMasked) {
      return _finalize(
        previous: previous,
        observation: observation,
        barState: LiveStatusDockMasked(
          interactionId: interaction!.id,
          showInteractionDetails: showInteractionDetails,
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
