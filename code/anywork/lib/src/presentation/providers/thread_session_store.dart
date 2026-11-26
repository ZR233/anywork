import 'package:anywork_client/conversation.dart' show ThreadSessionState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

part 'thread_session_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
ThreadSessionState threadSessionStore(Ref ref, String threadId) {
  final client = ref.read(anyworkClientProvider);
  if (client.isClosed) return ThreadSessionState(threadId: threadId);
  final conversations = client.conversations;
  observeClient(
    ref,
    conversations.visibleThreadId,
    (_) => ref.invalidateSelf(),
  );
  final session = conversations.existingSession(threadId);
  if (session == null || session.isClosed) {
    return ThreadSessionState(threadId: threadId);
  }
  return observeClient(ref, session.source, (_) => ref.invalidateSelf());
}
