import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../shared/studio_driver_state.dart';
import '../view_models/conversation_activity_view_model.dart';
import '../view_models/timeline_view_model.dart';
import '../widgets/conversation_activity_bar.dart';
import 'conversation_current_connector.dart';
import 'timeline_children_connector.dart';

/// Activity feature entry. The shell supplies identity, not display state,
/// content builders or recovery controls.
class ConversationActivityConnector extends ConsumerWidget {
  const ConversationActivityConnector({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationActivityViewModelProvider(threadId));
    StudioDriverState.publishConversationActivity(state?.view);
    if (state == null) return const SizedBox.shrink();
    final current = state.current;
    final conversations = ref.read(anyworkClientProvider).conversations;
    final content = conversations.existingSession(threadId)?.content;
    if (current == null || content == null) {
      // A genuine header-only state uses the same production component. It
      // cannot invent body content or expansion eligibility from other domains.
      return ConversationActivityBar(
        view: state.view,
        onExpandedChanged: StudioDriverState.publishActivityExpanded,
      );
    }

    // This observes an existing display lease, without admitting another reader.
    ref.watch(timelineViewModelProvider(threadId));
    final timeline = ref.read(timelineSessionOwnerProvider);
    final lease = timeline.lease(threadId);
    return ConversationCurrentConnector(
      key: ValueKey((threadId, content)),
      current: current,
      content: content,
      view: state.view,
      onExpandedChanged: StudioDriverState.publishActivityExpanded,
      registerDisplay: lease?.registerCurrentDisplay,
      completedItemsBuilder: lease == null
          ? null
          : (parentId, retirement) => TimelineChildrenConnector(
              key: ValueKey((lease.generation, parentId, retirement)),
              repository: conversations,
              threadId: threadId,
              parentId: parentId,
              parentRetirement: retirement,
              registerDisplay: lease.registerChildrenDisplay,
              isParentActive: () =>
                  !lease.retirement.value &&
                  identical(timeline.lease(threadId), lease) &&
                  identical(lease.content, content),
              readAttachment: (id) => ref
                  .read(anyworkClientProvider)
                  .readAttachmentBytes(threadId, id),
            ),
      isDisplayActive: () =>
          lease != null &&
          !lease.retirement.value &&
          identical(timeline.lease(threadId), lease) &&
          identical(lease.content, content),
    );
  }
}
