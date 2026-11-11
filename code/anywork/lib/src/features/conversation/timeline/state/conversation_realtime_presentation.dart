import 'package:anywork_client/models.dart';

sealed class ConversationRealtimeRegion {
  const ConversationRealtimeRegion();
}

final class HiddenRealtimeRegion extends ConversationRealtimeRegion {
  const HiddenRealtimeRegion();
}

final class DockRealtimeRegion extends ConversationRealtimeRegion {
  const DockRealtimeRegion({required this.interactionId});
  final String interactionId;
}

final class ContentRealtimeRegion extends ConversationRealtimeRegion {
  ContentRealtimeRegion({
    required this.live,
    required List<RealtimeNotice> notices,
    this.confirmingPlan = false,
  }) : notices = List.unmodifiable(notices);
  final LiveDisplayWindow? live;
  final List<RealtimeNotice> notices;
  final bool confirmingPlan;
}

sealed class RealtimeNotice {
  const RealtimeNotice();
}

final class ExecutionRealtimeNotice extends RealtimeNotice {
  const ExecutionRealtimeNotice(this.view);
  final ConversationActivityView view;
}

final class UnrestoredRealtimeNotice extends RealtimeNotice {
  const UnrestoredRealtimeNotice();
}

bool hasCurrentOutputRenderer({
  required LiveDisplayWindow? live,
  required String? activeTurnId,
  required RealtimeNotice notice,
}) {
  if (notice is! ExecutionRealtimeNotice ||
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

/// 当前活跃前台轮次的最新开放 Work 归入底部实时状态栏；
/// 已封存、冷读未恢复、跨轮次及提问／计划遮蔽期工作组留在时间线工作区。
bool isLiveBarWorkBlock({
  required ConversationRealtimeRegion region,
  required LiveDisplayWindow? live,
  required String? activeTurnId,
  required LiveDisplayBlock block,
}) {
  if (region is! ContentRealtimeRegion ||
      region.confirmingPlan ||
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

/// A normal notice may annotate only the latest open Work of the active Turn.
/// Older windows, closing Work, abnormal terminal outcomes and critical notices
/// keep independent surfaces.
({String blockId, ExecutionRealtimeNotice notice})? currentWorkNotice({
  required LiveDisplayWindow? live,
  required String? activeTurnId,
  required List<RealtimeNotice> notices,
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
  final working = summary.running > 0 || summary.waiting > 0;
  final cleanIdle =
      !working &&
      summary.failed == 0 &&
      summary.cancelled == 0 &&
      summary.transferred == 0;
  if (summary.unavailable != 0 || (!working && !cleanIdle)) {
    return null;
  }
  final source = latest.source;
  if (source is! ForegroundTurnChatSource || source.turnId != activeTurnId) {
    return null;
  }
  for (final notice in notices) {
    if (notice is! ExecutionRealtimeNotice) continue;
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

ConversationRealtimeRegion projectConversationRealtime({
  required ThreadStorageStateView? storage,
  required PendingInteraction? interaction,
  required LiveDisplayWindow? live,
  required ThreadActivityView? status,
}) {
  final confirmingPlan = interaction?.planConfirmation != null;
  if (interaction?.kind == InteractionKind.userInput && !confirmingPlan) {
    return DockRealtimeRegion(interactionId: interaction!.id);
  }
  final activity = live?.executionPresent == false ? null : status;
  final view = activity == null
      ? null
      : ConversationActivityView(
          identity: activity.identity,
          kind: switch (activity.kind) {
            ThreadActivityKind.preparing => ConversationActivityKind.preparing,
            ThreadActivityKind.compacting =>
              ConversationActivityKind.compacting,
            ThreadActivityKind.waitingApi ||
            ThreadActivityKind.thinking => ConversationActivityKind.thinking,
            ThreadActivityKind.responding =>
              ConversationActivityKind.responding,
            ThreadActivityKind.planning => ConversationActivityKind.planning,
            ThreadActivityKind.runningTool =>
              ConversationActivityKind.runningTool,
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
        );
  final approval = interaction?.kind == InteractionKind.toolApproval
      ? projectConversationActivity(
          activity: null,
          snapshot: null,
          interaction: interaction,
        )
      : null;
  final storageNotice = storage?.blocksContinuation == true
      ? projectConversationActivity(
          activity: null,
          snapshot: null,
          storage: storage,
        )
      : null;
  final notices = <RealtimeNotice>[
    if (live?.executionPresent == false &&
        live!.blocks.any((block) => block.state == DisplayBlockState.open))
      const UnrestoredRealtimeNotice(),
    // The plan dock already explains its own input wait. It does not replace
    // actual output, other execution phases, storage faults or cold-read facts.
    if (view != null &&
        !(confirmingPlan &&
            view.kind == ConversationActivityKind.awaitingInput &&
            interaction?.turnId != null &&
            view.turnId == interaction?.turnId))
      ExecutionRealtimeNotice(view),
    if (approval != null) ExecutionRealtimeNotice(approval),
    if (storageNotice != null) ExecutionRealtimeNotice(storageNotice),
  ];
  return live?.blocks.isNotEmpty == true || notices.isNotEmpty
      ? ContentRealtimeRegion(
          live: live,
          notices: notices,
          confirmingPlan: confirmingPlan,
        )
      : const HiddenRealtimeRegion();
}
