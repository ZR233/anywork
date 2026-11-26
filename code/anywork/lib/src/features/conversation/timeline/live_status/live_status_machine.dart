import 'package:anywork_client/models.dart' as feed;

import '../state/timeline_display_models.dart';
import 'live_status_state.dart';

abstract final class LiveStatusMachine {
  static LiveStatusView project(
    String threadId,
    feed.LiveStatusSnapshot snapshot, {
    required DateTime receivedAt,
    feed.PendingInteraction? interaction,
  }) {
    feed.ConversationActivityView activity(
      feed.ConversationActivityKind kind, {
      String? id,
      String? summary,
      String? reasoning,
      int count = 0,
    }) => feed.ConversationActivityView(
      identity: id ?? '$threadId:${kind.name}',
      kind: kind,
      summary: summary,
      thinkingSummary: reasoning,
      activeToolCount: count,
    );

    final primary = switch (snapshot.phase) {
      feed.LiveStatusIdle() => null,
      feed.LiveStatusWorking(
        :final items,
        :final reasoningPreview,
        :final startedAtMs,
      ) =>
        LiveWorkPhase(
          id: 'live-work:$threadId',
          block: DisplayBlock(
            id: 'live-work:$threadId',
            blockOrder: 0,
            body: WorkDisplayBlock(
              timing: WorkTiming(startedAtMillis: startedAtMs),
              executionPresent: true,
              memberCount: items.length,
              unfinishedCount: items.length,
              groupClosed: false,
              summary: reasoningPreview,
            ),
          ),
          mode: LiveWorkGroupMode.active,
          timing: WorkTiming(startedAtMillis: startedAtMs),
          activity: activity(
            items.isEmpty
                ? feed.ConversationActivityKind.thinking
                : feed.ConversationActivityKind.runningTool,
            reasoning: reasoningPreview,
            count: items.length,
          ),
          thinkingSummary: reasoningPreview,
          items: items,
          executionPresent: true,
        ),
      feed.LiveStatusStreamingText(
        :final itemId,
        :final text,
        :final startedAtMs,
      ) =>
        LiveResponsePhase(
          previewText: text,
          startedAt: startedAtMs == null ? null : startedAtMs ~/ 1000,
          activity: activity(
            feed.ConversationActivityKind.responding,
            id: itemId,
          ),
        ),
      feed.LiveStatusCompacting(:final startedAtMs) => LiveCompactingPhase(
        activity: activity(feed.ConversationActivityKind.compacting),
        startedAt: startedAtMs == null ? null : startedAtMs ~/ 1000,
      ),
      feed.LiveStatusReconnecting(
        :final message,
        :final attempt,
        :final retryAfterMs,
      ) =>
        LiveReconnectingPhase(
          detail: message,
          attempt: attempt,
          retryAt: retryAfterMs == null
              ? null
              : receivedAt.add(Duration(milliseconds: retryAfterMs)),
        ),
    };
    final attentions = [
      for (final item in snapshot.attentions)
        switch (item.kind) {
          'approval' => LiveApprovalAttention(
            activity(
              feed.ConversationActivityKind.awaitingApproval,
              id: item.id,
              summary: item.summary,
            ),
          ),
          'stopping' => LiveStoppingAttention(
            activity(
              feed.ConversationActivityKind.stopping,
              id: item.id,
              summary: item.summary,
            ),
          ),
          'disconnected' => LiveDisconnectedAttention(detail: item.summary),
          _ => LiveErrorAttention(message: item.summary),
        },
    ];
    final hide = snapshot.suppressedByInteraction;
    final details = interaction != null && !interaction.isPlanConfirmation;
    final presentation = LiveStatusPresentation(
      primary: primary,
      attentions: attentions,
      showInteractionDetails: details,
    );
    return LiveStatusView(
      threadId: threadId,
      primaryActivity: switch (primary) {
        LiveWorkPhase(:final activity) ||
        LiveResponsePhase(:final activity) => activity,
        LiveCompactingPhase(:final activity) => activity,
        _ => null,
      },
      gate: hide
          ? LiveStatusSuppressed(
              interactionId: interaction?.id ?? threadId,
              showInteractionDetails: details,
              obscured: presentation,
            )
          : presentation.isEmpty
          ? const LiveStatusIdle()
          : LiveStatusPresenting(presentation: presentation),
    );
  }
}
