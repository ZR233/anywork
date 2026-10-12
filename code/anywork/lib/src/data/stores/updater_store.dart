import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'updater_store.g.dart';

/// 更新状态。时钟是 [UpdaterStateSnapshot.revision]。
@Riverpod(keepAlive: true)
class UpdaterStore extends _$UpdaterStore {
  @override
  CanonicalClockState<UpdaterStateSnapshot> build() =>
      CanonicalClockState<UpdaterStateSnapshot>();

  void apply(UpdaterStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
