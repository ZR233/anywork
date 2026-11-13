import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

/// Read-only projection. The visible connector owns topic demand, so a
/// canonical update cannot release and reacquire the underlying subscription.
final threadLspStoreProvider = Provider.autoDispose
    .family<CanonicalClockState<ThreadLspStateSnapshot>, String>((
      ref,
      threadId,
    ) {
      final owner = ref.read(anyworkClientProvider).existingThreadLsp(threadId);
      if (owner == null) {
        return const CanonicalClockState<ThreadLspStateSnapshot>();
      }
      return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
    });
