import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../shared/studio_driver_state.dart';
import '../view_models/conversation_activity_view_model.dart';
import '../view_models/timeline_view_model.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_activity_viewport.dart';
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
    final children = <Widget>[];
    if (content != null && state?.activity != null) {
      ref.watch(timelineViewModelProvider(threadId));
      final timeline = ref.read(timelineSessionOwnerProvider);
      final lease = timeline.lease(threadId);
      if (lease != null && identical(lease.content, content)) {
        children.add(
          ConversationCurrentConnector(
            key: ValueKey((threadId, content, lease.generation)),
            session: sessionState,
            content: content,
            view: state?.view,
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
      }
    } else if (state?.view case final view?) {
      children.add(
        ConversationActivityBar(
          children: [ConversationActivityStatus(view: view)],
        ),
      );
    }
    final reference = sessionState.businessRefs?.interactions;
    if (content != null &&
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
    return ConversationActivityViewport(
      key: ValueKey(threadId),
      children: children,
    );
  }
}
