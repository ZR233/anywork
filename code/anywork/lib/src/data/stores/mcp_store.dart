import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import 'canonical_clock.dart';
import 'domain_sync.dart';

part 'mcp_store.g.dart';

/// MCP 服务状态。时钟是 [McpStateSnapshot.revision]。
@Riverpod(keepAlive: true)
class McpStore extends _$McpStore {
  @override
  CanonicalClockState<McpStateSnapshot> build() =>
      CanonicalClockState<McpStateSnapshot>();

  void apply(McpStateSnapshot next) {
    state = state.applyRevision(next, next.revision);
  }

  void applyTransport(DomainSyncStatus sync) {
    state = state.withSync(sync);
  }
}
