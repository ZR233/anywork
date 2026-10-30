import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class SkillsStore extends ReadModel<CanonicalClockState<SkillsStateSnapshot>> {
  SkillsStore(this.workspaceId)
    : super(CanonicalClockState<SkillsStateSnapshot>());
  final String workspaceId;

  void apply(SkillsStateSnapshot next) {
    if (next.workspaceId != workspaceId) return;
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
