import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class McpStore extends ReadModel<CanonicalClockState<McpCatalogSnapshot>> {
  McpStore([this.scope = const McpScope.host()])
    : super(CanonicalClockState<McpCatalogSnapshot>());

  final McpScope scope;

  void apply(McpCatalogSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}

class ThreadMcpStore
    extends ReadModel<CanonicalClockState<ThreadMcpStateSnapshot>> {
  ThreadMcpStore(this.threadId)
    : super(CanonicalClockState<ThreadMcpStateSnapshot>());

  final String threadId;

  void apply(ThreadMcpStateSnapshot next) {
    state = state.applyRevision(next, next.generation);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
