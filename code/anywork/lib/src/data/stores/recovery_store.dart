import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'recovery_store.g.dart';

/// 恢复问题。时钟是 [RecoveryStateSnapshot.revision]。
@Riverpod(keepAlive: true)
class RecoveryStore extends _$RecoveryStore {
  @override
  CanonicalClockState<RecoveryStateSnapshot> build() =>
      CanonicalClockState<RecoveryStateSnapshot>();

  void apply(RecoveryStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
