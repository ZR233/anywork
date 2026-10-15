import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

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
