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
  }) : notices = List.unmodifiable(notices);
  final LiveDisplayWindow? live;
  final List<RealtimeNotice> notices;
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

/// A normal notice may annotate only the latest open Work of the active Turn.
/// Older windows, closing Work and critical notices keep independent surfaces.
({String blockId, ExecutionRealtimeNotice notice})? currentWorkNotice({
  required LiveDisplayWindow? live,
  required String? activeTurnId,
  required List<RealtimeNotice> notices,
}) {
  if (live == null || !live.executionPresent || activeTurnId == null) {
    return null;
  }
  final latest = live.blocks.lastOrNull;
  if (latest == null || latest.closing || latest.body is! WorkDisplayBlock) {
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
    if (view.kind == ConversationActivityKind.thinking ||
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
  if (interaction?.kind == InteractionKind.userInput) {
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
    if (live?.executionPresent == false && live!.blocks.isNotEmpty)
      const UnrestoredRealtimeNotice(),
    if (view != null) ExecutionRealtimeNotice(view),
    if (approval != null) ExecutionRealtimeNotice(approval),
    if (storageNotice != null) ExecutionRealtimeNotice(storageNotice),
  ];
  return live?.blocks.isNotEmpty == true || notices.isNotEmpty
      ? ContentRealtimeRegion(live: live, notices: notices)
      : const HiddenRealtimeRegion();
}
