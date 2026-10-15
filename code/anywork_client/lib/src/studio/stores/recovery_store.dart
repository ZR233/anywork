import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class RecoveryStore
    extends ReadModel<CanonicalClockState<RecoveryStateSnapshot>> {
  RecoveryStore() : super(CanonicalClockState<RecoveryStateSnapshot>());

  void apply(RecoveryStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
