import 'package:anywork_client/studio_client.dart' show SelectionStoreState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show SelectionStoreState;

part 'selection_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
SelectionStoreState selectionStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).selection.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
