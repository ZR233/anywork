import 'package:anywork_client/studio_client.dart' show ProjectStoreState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show ProjectStoreState;

part 'project_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
ProjectStoreState projectStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).project.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
