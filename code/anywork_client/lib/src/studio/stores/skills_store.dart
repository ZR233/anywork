import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';
import 'canonical_clock.dart';

class SkillsStore extends ReadModel<CanonicalClockState<SkillsStateSnapshot>> {
  SkillsStore(this.projectId)
    : super(CanonicalClockState<SkillsStateSnapshot>());
  final String projectId;

  void apply(SkillsStateSnapshot next) {
    if (next.projectId != projectId) return;
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
