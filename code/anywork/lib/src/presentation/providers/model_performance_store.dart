import 'package:anywork_client/studio_client.dart'
    show CanonicalClockState, ModelPerformanceSnapshotView;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show CanonicalClockState;

part 'model_performance_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
CanonicalClockState<ModelPerformanceSnapshotView> modelPerformanceStore(
  Ref ref,
) {
  final source = ref.read(anyworkClientProvider).modelPerformance.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
