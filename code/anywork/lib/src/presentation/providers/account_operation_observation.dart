import 'package:anywork_client/studio_client.dart'
    show OperationId, OperationState, ValueObservation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';

/// Looks up only the operation returned by a domain action. No target-string
/// lookup, writable handle, new owner or duplicate mutation board is exposed.
typedef AccountOperationLookup = ValueObservation<OperationState>? Function(
  OperationId id,
);

final accountOperationObservationProvider = Provider<AccountOperationLookup>((
  ref,
) {
  final mutations = ref.read(anyworkClientProvider).mutations;
  return (id) => mutations.lookup(id)?.state;
});
