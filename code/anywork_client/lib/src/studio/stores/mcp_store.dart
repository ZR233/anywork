import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class McpStore extends ReadModel<CanonicalClockState<McpStateSnapshot>> {
  McpStore() : super(CanonicalClockState<McpStateSnapshot>());

  void apply(McpStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
