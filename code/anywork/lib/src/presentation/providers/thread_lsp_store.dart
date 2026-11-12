import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

/// The popover borrows a thread-scoped Client topic while it is observed.
/// Client remains the owner of the canonical state and subscription.
final threadLspStoreProvider = Provider.autoDispose
    .family<CanonicalClockState<ThreadLspStateSnapshot>, String>((
      ref,
      threadId,
    ) {
      final client = ref.read(anyworkClientProvider);
      final lease = client.channels.acquireThreadLsp(threadId);
      ref.onDispose(() {
        unawaited(
          lease.release().catchError((Object error) {
            client.resourceFailure.publish(
              UnresolvedResource(
                owner: 'thread-lsp-popover:$threadId',
                attemptId: const AttemptId(0),
                reason: error,
              ),
            );
          }),
        );
      });
      final owner = client.existingThreadLsp(threadId)!;
      return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
    });
