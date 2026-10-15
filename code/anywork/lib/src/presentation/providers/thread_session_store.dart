import 'package:anywork_client/studio_client.dart'
    show DomainSyncPhase, DomainSyncStatus, ThreadSessionState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

part 'thread_session_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
ThreadSessionState threadSessionStore(Ref ref, String threadId) {
  final owner = ref.read(anyworkClientProvider).existingSession(threadId);
  if (owner != null) {
    return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
  }
  final failure = observeClientDemand(
    ref,
    ownsFailure: (owner) => owner == 'session:$threadId',
  );
  return ThreadSessionState(
    threadId: threadId,
    sync: DomainSyncStatus(
      phase: failure == null ? DomainSyncPhase.idle : DomainSyncPhase.failed,
      errorMessage: failure?.reason.toString(),
    ),
  );
}
