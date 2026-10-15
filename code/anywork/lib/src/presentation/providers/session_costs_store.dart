import 'package:anywork_client/studio_client.dart'
    show
        CanonicalClockState,
        DomainSyncPhase,
        DomainSyncStatus,
        SessionCostsStateView;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show CanonicalClockState;

part 'session_costs_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
CanonicalClockState<SessionCostsStateView> sessionCostsStore(
  Ref ref,
  String rootThreadId,
) {
  final owner = ref
      .read(anyworkClientProvider)
      .existingSessionCosts(rootThreadId);
  if (owner != null) {
    return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
  }
  final failure = observeClientDemand(
    ref,
    ownsFailure: (owner) =>
        owner == 'costs:$rootThreadId' ||
        owner.startsWith('selection-topics:') &&
            owner.endsWith('/$rootThreadId'),
  );
  return CanonicalClockState<SessionCostsStateView>(
    sync: DomainSyncStatus(
      phase: failure == null ? DomainSyncPhase.idle : DomainSyncPhase.failed,
      errorMessage: failure?.reason.toString(),
    ),
  );
}
