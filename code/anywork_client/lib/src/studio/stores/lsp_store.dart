import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class ThreadLspStore
    extends ReadModel<CanonicalClockState<ThreadLspStateSnapshot>> {
  ThreadLspStore(this.threadId)
    : super(CanonicalClockState<ThreadLspStateSnapshot>());

  final String threadId;

  void apply(ThreadLspStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}

class LspStore extends ReadModel<CanonicalClockState<LspStateSnapshot>> {
  LspStore() : super(CanonicalClockState<LspStateSnapshot>());

  void apply(LspStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
