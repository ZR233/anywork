import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../interactions/state/interaction_payload.dart';
import '../state/conversation_activity_state.dart';
import 'timeline_view_model.dart';

part 'conversation_activity_view_model.g.dart';

ConversationActivityState? projectConversationActivityState({
  required ThreadStorageStateView? storage,
  required List<PendingInteraction> interactions,
  LiveDisplayWindow? live,
  ThreadActivityView? status,
  ThreadBusinessRefs? businessRefs,
}) {
  final interaction = activePendingInteraction(interactions);
  final region = projectConversationRealtime(
    storage: storage, interaction: interaction, live: live, status: status,
  );
  final view = region is ContentRealtimeRegion
    ? region.notices.whereType<ExecutionRealtimeNotice>().firstOrNull?.view
    : null;
  return ConversationActivityState(
    view: view,
    region: region,
  );
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
  ref.watch(timelineViewModelProvider(threadId));
  final lease = ref.read(timelineSessionOwnerProvider).lease(threadId);
  if (lease != null) {
    void liveChanged() {
      if (ref.mounted) ref.invalidateSelf();
    }
    lease.live.addListener(liveChanged);
    ref.onDispose(() => lease.live.removeListener(liveChanged));
  }
  // The page owner publishes only after controller and live have both committed.
  final live = lease?.live.value;
  if (session.workspace == null && !session.hasSnapshot && live == null) {
    return null;
  }
  return projectConversationActivityState(
    storage: session.storage,
    interactions: session.interactions,
    live: live,
    status: session.activity,
    businessRefs: session.businessRefs,
  );
}
