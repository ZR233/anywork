import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../interactions/state/interaction_payload.dart';
import '../state/conversation_activity_state.dart';

part 'conversation_activity_view_model.g.dart';

ConversationActivityState? projectConversationActivityState({
  required CurrentProjection? current,
  required ThreadStorageStateView? storage,
  required List<PendingInteraction> interactions,
}) {
  final interaction = activePendingInteraction(interactions);
  if (interaction?.kind == InteractionKind.userInput) return null;
  final view = projectConversationActivity(
    current: current,
    storage: storage,
    interaction: interaction,
  );
  return view == null && current == null
      ? null
      : ConversationActivityState(view: view, current: current);
}

/// Observes only the activity component's current owner. Visibility and the
/// conversation reader remain owned by the committed page selection.
@riverpod
ConversationActivityState? conversationActivityViewModel(
  Ref ref,
  String threadId,
) {
  final session = ref.watch(threadSessionStoreProvider(threadId));
  final conversations = ref.read(anyworkClientProvider).conversations;
  if (conversations.visibleThreadId.value != threadId) return null;
  final owner = conversations.existingSession(threadId);
  final current = owner == null
      ? null
      : observeClient(ref, owner.current, (_) => ref.invalidateSelf());
  if (session.workspace == null && !session.hasSnapshot && current == null) {
    return null;
  }
  return projectConversationActivityState(
    current: current,
    storage: session.storage,
    interactions: session.interactions,
  );
}
