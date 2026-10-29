import '../../../anywork_client.dart' show ReadModel;
import '../../studio/stores/canonical_clock.dart';
import '../../studio/stores/domain_sync.dart';
import 'mode_catalog_models.dart';

class ModeCatalogStore
    extends ReadModel<CanonicalClockState<ThreadModeCatalogView>> {
  ModeCatalogStore() : super(CanonicalClockState<ThreadModeCatalogView>());

  void apply(ThreadModeCatalogView next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
