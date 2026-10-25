import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

/// Observation only: never opens a Session, changes display demand or clears a
/// composer on dispose. Status and composer borrow the same canonical source.
final threadAudienceProvider = Provider.autoDispose
    .family<ThreadAudience, String>((ref, threadId) {
      final client = ref.read(anyworkClientProvider);
      final owner = client.existingSession(threadId);
      if (client.isClosed) {
        return owner?.state.audience ??
            const ThreadAudienceUnavailable(
              reason: ThreadAudienceUnavailableReason.runtimeClosed,
            );
      }
      if (owner == null) {
        observeClientDemand(
          ref,
          ownsFailure: (key) => key == 'session:$threadId',
        );
        return const ThreadAudienceUnavailable(
          reason: ThreadAudienceUnavailableReason.ownershipUnproven,
        );
      }
      late final ThreadAudience current;
      current = observeClient(ref, owner.source, (next) {
        if (next.audience != current) ref.invalidateSelf();
      }).audience;
      return current;
    });

final threadSyncProgressProvider = Provider.autoDispose
    .family<BotThreadSyncProgress?, String>((ref, threadId) {
      final client = ref.read(anyworkClientProvider);
      final commands = client.botThreadSync;
      if (client.isClosed) return commands.forThread(threadId);
      late final BotThreadSyncProgress? current;
      current = observeClient(ref, commands.source, (next) {
        if (next[threadId] != current) ref.invalidateSelf();
      })[threadId];
      return current;
    });

final threadAudienceItemsProvider = Provider.autoDispose
    .family<ThreadAudienceItemsState, ThreadAudienceScope>((ref, scope) {
      // A retire notification can schedule this rebuild after the owner has
      // joined its reads and closed the source while the old view is mounted.
      // Read its retired snapshot; observation must never reopen that scope.
      if (!scope.isActive) return scope.state;
      return observeClient(ref, scope.source, (_) => ref.invalidateSelf());
    });
