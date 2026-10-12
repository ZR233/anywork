import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'mode_catalog_store.g.dart';

/// Mode 目录。时钟是 [ThreadModeCatalogView.revision]。
@Riverpod(keepAlive: true)
class ModeCatalogStore extends _$ModeCatalogStore {
  @override
  CanonicalClockState<ThreadModeCatalogView> build() =>
      CanonicalClockState<ThreadModeCatalogView>();

  void apply(ThreadModeCatalogView next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
