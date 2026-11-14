import 'package:anywork_client/models.dart';

import '../../interactions/state/interaction_payload.dart';
import 'live_status_state.dart';

/// 规范尾部和独立业务状态的纯展示投影；不保存事件账本、不执行 I/O。
abstract final class LiveStatusProjection {
  /// 当前轮次正文或压缩记录已承担展示时，接管并抑制对应的普通同类状态提示。
  static bool hasCurrentOutputRenderer({
    required TailSnapshot? live,
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

  /// 规范最新窗口是当前尾组身份的唯一来源；旧页和来源仅描述内容。
  static LiveDisplayBlock? currentWork(TailSnapshot? live) {
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
      WorkDisplayBlock() => block.hasUnfinishedMembers,
      SingleDisplayBlock(:final record) =>
        record.atom.lifecycle is ActiveChatAtom ||
            (record.contentSource is FrozenObservation &&
                !(record.contentSource as FrozenObservation).available),
    };
  }

  /// 普通活动沿原 State 合并到明确的当前尾组；不把来源或成员状态当活动。
  /// 审批、存储故障等关键提示仍保持独立呈现。
  static ({String blockId, ExecutionLiveNotice notice})? mergeableWorkNotice({
    required TailSnapshot? live,
    required List<LiveStatusNotice> notices,
  }) {
    if (live == null || !live.executionPresent) {
      return null;
    }
    final latest = currentWork(live);
    if (latest == null) return null;
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

  /// 在有效窗口上计算上方时间线实时工作块与底部状态栏主表面（纯函数，无副作用）。
  static ({
    LiveStatusPrimarySurface? surface,
    List<LiveDisplayBlock> timelineWorkBlocks,
  })
  projectSurfaceAndTimelineWork({
    required TailSnapshot? effectiveOutputWindow,
    required TailSnapshot? effectiveTimelineWindow,
    required TailSnapshot? latestWindow,
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
      ?tail,
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

  static LiveStatusView project({
    required String threadId,
    required LiveStatusInputs observation,
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
        threadId: threadId,
        cut: observation.cut,
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
        threadId: threadId,
        cut: observation.cut,
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
        threadId: threadId,
        cut: observation.cut,
        barState: barState,
        timelineWork: timelineSlice,
        outputPaging: outputPaging,
        timelineWorkPaging: timelineWorkPaging,
        primaryActivity: primaryActivity,
      );
    }

    return _finalize(
      threadId: threadId,
      cut: observation.cut,
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

  static LiveStatusView _finalize({
    required String threadId,
    required LiveWindowCut cut,
    required LiveStatusMachineState barState,
    required LiveStatusTimelineWorkSlice timelineWork,
    required LiveWindowPagingState outputPaging,
    required LiveWindowPagingState timelineWorkPaging,
    required ConversationActivityView? primaryActivity,
  }) => LiveStatusView(
    threadId: threadId,
    cut: cut,
    barState: barState,
    timelineWork: timelineWork,
    primaryActivity: primaryActivity,
  );
}
