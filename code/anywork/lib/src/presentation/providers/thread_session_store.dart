import 'package:anywork_client/conversation.dart' show ThreadSessionState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

part 'thread_session_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
ThreadSessionState threadSessionStore(Ref ref, String threadId) {
  final conversations = ref.read(anyworkClientProvider).conversations;
  observeClient(
    ref,
    conversations.visibleThreadId,
    (_) => ref.invalidateSelf(),
  );
  final session = conversations.existingSession(threadId);
  if (session == null) return ThreadSessionState(threadId: threadId);
  return observeClient(ref, session.source, (_) => ref.invalidateSelf());
}
