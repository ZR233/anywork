import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../shared/studio_driver_state.dart';
import '../../interactions/state/interaction_payload.dart';
import '../view_models/conversation_activity_view_model.dart';
import '../view_models/timeline_view_model.dart';
import '../state/conversation_activity_state.dart';
import '../widgets/conversation_activity_viewport.dart';
import '../widgets/conversation_activity_bar.dart';
import 'conversation_current_connector.dart';
import 'interaction_details_connector.dart';

/// Activity operations and read-only interaction details borrow their original
/// owners. Actionable questions remain in the State-owned composer dock.
class ConversationActivityConnector extends ConsumerWidget {
  const ConversationActivityConnector({required this.threadId, super.key});
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationActivityViewModelProvider(threadId));
    final sessionState = ref.watch(threadSessionStoreProvider(threadId));
    final conversations = ref.read(anyworkClientProvider).conversations;
    final session = conversations.existingSession(threadId);
    final content = session?.content;
    StudioDriverState.publishConversationActivity(state?.view);
    // Only the selected plan's duplicate details are replaced by its reader and
    // dock. Work belongs to Timeline; actual output and critical notices retain
    // their original display qualification here.
    final interaction = activePendingInteraction(sessionState.interactions);
    final confirmingPlan = interaction?.planConfirmation != null;
    final children = <Widget>[];
    switch (state?.region) {
      case ContentRealtimeRegion region when content != null:
        ref.watch(timelineViewModelProvider(threadId));
        final timeline = ref.read(timelineSessionOwnerProvider);
        final lease = timeline.lease(threadId);
        if (lease != null && identical(lease.content, content)) {
          // This renderer owns any explicitly loaded older window. Only it can
          // decide whether its actual sources produce content or zero layout.
          children.add(
            ConversationCurrentConnector(
              section: ConversationLiveSection.output,
              key: ValueKey((threadId, content, lease.generation)),
              session: sessionState,
              content: content,
              region: region,
              live: lease.live,
              liveUnit: lease.liveUnit,
              loadLiveOlder: (before) => lease.loadLiveOlder(before: before),
              onExpandedChanged: StudioDriverState.publishActivityExpanded,
              registerDisplay: lease.registerCurrentDisplay,
              images: lease.imageResources,
              readAttachment: (id) => ref
                  .read(anyworkClientProvider)
                  .readAttachmentBytes(threadId, id),
              isDisplayActive: () =>
                  !lease.retirement.value &&
                  identical(timeline.lease(threadId), lease) &&
                  identical(lease.content, content),
            ),
          );
        } else {
          children.add(
            ConversationActivityBar(
              children: [ConversationRealtimeNotices(notices: region.notices)],
            ),
          );
        }
      case HiddenRealtimeRegion() || DockRealtimeRegion() || null:
        break;
      case ContentRealtimeRegion():
        break;
    }
    final reference = sessionState.businessRefs?.interactions;
    // Ordinary questions/approvals keep their independent details reader.
    // The selected plan already has a dedicated reader; unmounting this one
    // retires only its local demand, not the underlying interaction or tools.
    if (!confirmingPlan &&
        content != null &&
        reference != null &&
        sessionState.interactions.isNotEmpty) {
      children.add(
        InteractionDetailsConnector(
          key: ValueKey((
            'interaction-details',
            content,
            content.currentAttemptId,
          )),
          content: content,
          reference: reference,
          isCurrent: () =>
              identical(conversations.existingSession(threadId), session) &&
              conversations.visibleThreadId.value == threadId &&
              session?.state.businessRefs?.interactions == reference,
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return ConversationActivityViewport(
      key: ValueKey(threadId),
      children: children,
    );
  }
}
