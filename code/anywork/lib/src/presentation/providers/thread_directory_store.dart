import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';
import 'use_client_resource.dart';

part 'thread_directory_store.g.dart';

// Keep the demand alive across display-only rebuilds. A new ID gets a new owner.
@riverpod
DirectoryObservation<ThreadMetadataFrame> threadMetadataDemand(
  Ref ref,
  String threadId,
) {
  return useClientResource(
    ref,
    () =>
        ref.read(anyworkClientProvider).threadDirectory.observeThread(threadId),
    owner: 'thread-metadata-demand',
  );
}

/// Metadata is independent of list membership, filtering and pagination.
@riverpod
DirectoryObservationState<ThreadMetadataFrame> threadMetadataStore(
  Ref ref,
  String threadId,
) {
  final demand = ref.watch(threadMetadataDemandProvider(threadId));
  return observeClient(ref, demand.state, (_) => ref.invalidateSelf());
}
