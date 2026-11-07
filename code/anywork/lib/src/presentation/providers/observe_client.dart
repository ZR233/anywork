import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';

/// An observation failed to attach; no observation remains owned by Ref.
final class ClientObservationFailure implements Exception {
  const ClientObservationFailure(this.cause);

  final Object cause;

  @override
  String toString() => 'Client observation could not attach: $cause';
}

/// Registers a read-only observer and reads its current snapshot synchronously.
/// Ref owns only this observer, never the Client resource.
T observeClient<T>(
  Ref ref,
  ValueObservation<T> source,
  void Function(T) onUpdate,
) {
  LatestWatch<T>? watched;
  try {
    watched = source.watchLatest(onUpdate);
    final observation = watched.observation;
    ref.onDispose(() {
      observation.cancel();
    });
    return watched.value;
  } catch (error, stack) {
    watched?.observation.cancel();
    Error.throwWithStackTrace(ClientObservationFailure(error), stack);
  }
}

/// Missing owners can appear only after a Client action changes logical demand.
/// Watching those signals never admits a resource from a account build.
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
