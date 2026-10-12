import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'skills_store.g.dart';

/// 项目 Skills。family 参数是稳定 projectId；时钟是该快照的 revision。
@Riverpod(keepAlive: true)
class SkillsStore extends _$SkillsStore {
  @override
  CanonicalClockState<SkillsStateSnapshot> build(String projectId) =>
      CanonicalClockState<SkillsStateSnapshot>();

  void apply(SkillsStateSnapshot next) {
    if (next.projectId != projectId) return;
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
