import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../interactions/state/interaction_payload.dart';
import '../state/conversation_activity_state.dart';

part 'conversation_activity_view_model.g.dart';

ConversationActivityState? projectConversationActivityState({
  required ThreadStorageStateView? storage,
  required List<PendingInteraction> interactions,
  ActivitySnapshot? activity,
  ThreadActivityView? status,
  ThreadBusinessRefs? businessRefs,
}) {
  final interaction = activePendingInteraction(interactions);
  final view = interaction?.kind == InteractionKind.userInput
      ? null
      : projectConversationActivity(
          activity: status,
          snapshot: activity,
          businessRefs: businessRefs,
          storage: storage,
          interaction: interaction,
        );
  return view == null && activity == null
      ? null
      : ConversationActivityState(view: view, activity: activity);
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
  final activity = owner == null
      ? null
      : observeClient(ref, owner.activity, (_) => ref.invalidateSelf());
  if (session.workspace == null && !session.hasSnapshot && activity == null) {
    return null;
  }
  return projectConversationActivityState(
    storage: session.storage,
    interactions: session.interactions,
    activity: activity,
    status: session.activity,
    businessRefs: session.businessRefs,
  );
}
