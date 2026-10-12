import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'session_costs_store.g.dart';

/// 根会话费用。`cost == null` 是显式清除，仍按 revision 保留条目。
@Riverpod(keepAlive: true)
class SessionCostsStore extends _$SessionCostsStore {
  @override
  CanonicalClockState<SessionCostsStateView> build(String rootThreadId) =>
      CanonicalClockState<SessionCostsStateView>();

  void apply(SessionCostsStateView next) {
    if (next.rootThreadId != rootThreadId) return;
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
