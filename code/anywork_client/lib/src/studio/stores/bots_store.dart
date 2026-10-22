import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'canonical_clock.dart';
import 'domain_sync.dart';

/// Bots topic 的唯一 canonical writer。
class BotsStore extends ReadModel<CanonicalClockState<BotsStateSnapshot>> {
  BotsStore() : super(CanonicalClockState<BotsStateSnapshot>());

  void apply(BotsStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
