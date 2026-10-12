import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'model_performance_store.g.dart';

/// 模型统计。时钟是 [ModelPerformanceSnapshotView.revision]。
@Riverpod(keepAlive: true)
class ModelPerformanceStore extends _$ModelPerformanceStore {
  @override
  CanonicalClockState<ModelPerformanceSnapshotView> build() =>
      CanonicalClockState<ModelPerformanceSnapshotView>();

  void apply(ModelPerformanceSnapshotView next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
