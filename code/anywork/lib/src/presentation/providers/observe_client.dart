import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';

/// An observation failed to attach; no observer permit remains owned by Ref.
final class ClientObservationFailure implements Exception {
  const ClientObservationFailure(this.cause);

  final Object cause;

  @override
  String toString() => 'Client observation could not attach: $cause';
}

/// Registers a read-only observer and reads its current snapshot synchronously.
/// Ref owns only this observer and its budget permit, never the Client resource.
T observeClient<T>(Ref ref, LatestValue<T> source, void Function(T) onUpdate) {
  final permit = ref
      .read(anyworkClientProvider)
      .budget
      .acquire(
        ResourceKind.observer,
        owner: 'presentation:${source.runtimeType}',
      );
  LatestWatch<T>? watched;
  try {
    watched = source.watchLatest(onUpdate);
    final observation = watched.observation;
    ref.onDispose(() {
      observation.cancel();
      permit.release();
    });
    return watched.value;
  } catch (error, stack) {
    watched?.observation.cancel();
    permit.release();
    Error.throwWithStackTrace(ClientObservationFailure(error), stack);
  }
}

/// Missing owners can appear only after a Client action changes logical demand.
/// Watching those signals never admits a resource from a provider build.
UnresolvedResource? observeClientDemand(
  Ref ref, {
  required bool Function(String owner) ownsFailure,
}) {
  final client = ref.read(anyworkClientProvider);
  observeClient(ref, client.selection.source, (_) => ref.invalidateSelf());
  final failure = observeClient(
    ref,
    client.resourceFailure,
    (_) => ref.invalidateSelf(),
  );
  return failure != null && ownsFailure(failure.owner) ? failure : null;
}
