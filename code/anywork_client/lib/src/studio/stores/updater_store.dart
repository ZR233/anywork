import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class UpdaterStore
    extends ReadModel<CanonicalClockState<UpdaterStateSnapshot>> {
  UpdaterStore() : super(CanonicalClockState<UpdaterStateSnapshot>());

  void apply(UpdaterStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
