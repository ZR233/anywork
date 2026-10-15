import 'package:anywork_client/studio_client.dart'
    show ThreadDirectoryStoreState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart'
    show ThreadDirectoryStoreState;

part 'thread_directory_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
ThreadDirectoryStoreState threadDirectoryStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).threadDirectory.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
