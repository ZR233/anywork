import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'lsp_store.g.dart';

/// LSP 服务状态。时钟是 [LspStateSnapshot.revision]。
@Riverpod(keepAlive: true)
class LspStore extends _$LspStore {
  @override
  CanonicalClockState<LspStateSnapshot> build() =>
      CanonicalClockState<LspStateSnapshot>();

  void apply(LspStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
