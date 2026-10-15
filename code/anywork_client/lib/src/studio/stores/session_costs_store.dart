import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class SessionCostsStore
    extends ReadModel<CanonicalClockState<SessionCostsStateView>> {
  SessionCostsStore(this.rootThreadId)
    : super(CanonicalClockState<SessionCostsStateView>());
  final String rootThreadId;

  void apply(SessionCostsStateView next) {
    if (next.rootThreadId != rootThreadId) return;
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
