import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'provider_usage_store.g.dart';

/// 服务商用量。协议水位 [ProviderUsageStateSnapshot.revision] 就是查询代次，
/// 不另造 generation 计数器。
@Riverpod(keepAlive: true)
class ProviderUsageStore extends _$ProviderUsageStore {
  @override
  CanonicalClockState<ProviderUsageStateSnapshot> build() =>
      CanonicalClockState<ProviderUsageStateSnapshot>();

  void apply(ProviderUsageStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
