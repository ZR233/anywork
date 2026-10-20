import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class AccountUsageStore
    extends ReadModel<CanonicalClockState<AccountUsageStateSnapshot>> {
  AccountUsageStore() : super(CanonicalClockState<AccountUsageStateSnapshot>());

  void apply(AccountUsageStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
