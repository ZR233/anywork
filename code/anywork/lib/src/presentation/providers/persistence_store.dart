import 'package:anywork_client/studio_client.dart' show PersistenceStoreState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show PersistenceStoreState;

part 'persistence_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
PersistenceStoreState persistenceStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).persistence.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
