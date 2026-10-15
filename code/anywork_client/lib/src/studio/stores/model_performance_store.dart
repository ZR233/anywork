import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class ModelPerformanceStore
    extends ReadModel<CanonicalClockState<ModelPerformanceSnapshotView>> {
  ModelPerformanceStore()
    : super(CanonicalClockState<ModelPerformanceSnapshotView>());

  void apply(ModelPerformanceSnapshotView next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
