import 'package:anywork_client/studio_client.dart'
    show
        CanonicalClockState,
        DomainSyncPhase,
        DomainSyncStatus,
        SkillsStateSnapshot;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show CanonicalClockState;

part 'skills_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
CanonicalClockState<SkillsStateSnapshot> skillsStore(
  Ref ref,
  String projectId,
) {
  final owner = ref.read(anyworkClientProvider).existingSkills(projectId);
  if (owner != null) {
    return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
  }
  final failure = observeClientDemand(
    ref,
    ownsFailure: (owner) =>
        owner == 'skills:$projectId' ||
        owner.startsWith('selection-topics:$projectId/'),
  );
  return CanonicalClockState<SkillsStateSnapshot>(
    sync: DomainSyncStatus(
      phase: failure == null ? DomainSyncPhase.idle : DomainSyncPhase.failed,
      errorMessage: failure?.reason.toString(),
    ),
  );
}
