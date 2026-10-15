import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class ProviderUsageStore
    extends ReadModel<CanonicalClockState<ProviderUsageStateSnapshot>> {
  ProviderUsageStore()
    : super(CanonicalClockState<ProviderUsageStateSnapshot>());

  void apply(ProviderUsageStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
