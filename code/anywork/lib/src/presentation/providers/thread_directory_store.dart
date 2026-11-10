import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

part 'thread_directory_store.g.dart';

// Keep the demand alive across display-only rebuilds. A new ID gets a new owner.
@riverpod
DirectoryObservation<ThreadMetadataFrame> threadMetadataDemand(
  Ref ref,
  String threadId,
) {
  final demand = ref
      .watch(anyworkClientProvider)
      .threadDirectory
      .observeThread(threadId);
  ref.onDispose(() {
    unawaited(
      demand.release().catchError((Object error, StackTrace stack) {
        // The SDK retains this exact unresolved owner for cleanup retry.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'thread metadata observation',
            context: ErrorDescription(
              'while releasing the metadata demand for $threadId',
            ),
          ),
        );
      }),
    );
  });
  return demand;
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
