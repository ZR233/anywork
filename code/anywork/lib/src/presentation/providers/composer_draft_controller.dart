import 'package:anywork_client/models.dart' show ComposerThreadState;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';
import 'thread_session_store.dart';

part 'composer_draft_controller.g.dart';

/// This observer borrows the Client's logical draft across routes.
@riverpod
ComposerThreadState composerDraftController(Ref ref, String threadId) {
  // The application admits a draft once this destination has canonical identity.
  // Re-read that registry after first load; this observer never creates an owner.
  ref.watch(
    threadSessionStoreProvider(threadId)
        .select((state) => state.workspace?.thread),
  );
  final owner = ref
      .read(anyworkClientProvider)
      .drafts
      .existingComposer(threadId);
  if (owner != null) {
    return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
  }
  final failure = observeClientDemand(
    ref,
    ownsFailure: (owner) => owner == 'composer:$threadId',
  );
  return ComposerThreadState.failure(
    error: failure?.reason.toString() ?? '此会话的草稿尚未加载',
  );
}
