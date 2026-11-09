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
  ContentRealtimeRegion({required this.live, required List<RealtimeNotice> notices})
    : notices = List.unmodifiable(notices);
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
  final view = activity == null ? null : ConversationActivityView(
    identity: activity.identity,
    kind: switch (activity.kind) {
      ThreadActivityKind.preparing => ConversationActivityKind.preparing,
      ThreadActivityKind.compacting => ConversationActivityKind.compacting,
      ThreadActivityKind.waitingApi || ThreadActivityKind.thinking => ConversationActivityKind.thinking,
      ThreadActivityKind.responding => ConversationActivityKind.responding,
      ThreadActivityKind.planning => ConversationActivityKind.planning,
      ThreadActivityKind.runningTool => ConversationActivityKind.runningTool,
      ThreadActivityKind.awaitingApproval => ConversationActivityKind.awaitingApproval,
      ThreadActivityKind.awaitingInput => ConversationActivityKind.awaitingInput,
      ThreadActivityKind.stopping => ConversationActivityKind.stopping,
    },
    turnId: activity.turnId,
    executionId: activity.executionId,
    summary: activity.summary,
  );
  final approval = interaction?.kind == InteractionKind.toolApproval
    ? projectConversationActivity(activity: null, snapshot: null, interaction: interaction)
    : null;
  final storageNotice = storage?.blocksContinuation == true
    ? projectConversationActivity(activity: null, snapshot: null, storage: storage)
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
