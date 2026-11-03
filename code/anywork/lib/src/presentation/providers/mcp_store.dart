import 'package:anywork_client/studio_client.dart'
    show
        CanonicalClockState,
        DomainSyncPhase,
        DomainSyncStatus,
        McpCatalogSnapshot,
        McpScope,
        ThreadMcpStateSnapshot;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show CanonicalClockState;

part 'mcp_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
CanonicalClockState<McpCatalogSnapshot> mcpStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).mcp.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}

@riverpod
CanonicalClockState<McpCatalogSnapshot> mcpCatalogByScope(
  Ref ref,
  McpScope scope,
) {
  final source = ref.read(anyworkClientProvider).mcpCatalog(scope).source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}

@riverpod
CanonicalClockState<ThreadMcpStateSnapshot> threadMcp(
  Ref ref,
  String threadId,
) {
  final client = ref.read(anyworkClientProvider);
  final owner = client.existingThreadMcp(threadId);
  final failure = observeClientDemand(
    ref,
    ownsFailure: (owner) => owner == 'thread-mcp-page:$threadId',
  );
  if (owner != null) {
    final state = observeClient(ref, owner.source, (_) => ref.invalidateSelf());
    return failure == null
        ? state
        : state.withSync(
            DomainSyncStatus(
              phase: DomainSyncPhase.failed,
              errorMessage: failure.reason.toString(),
            ),
          );
  }
  observeClient(
    ref,
    client.conversations.visibleThreadId,
    (_) => ref.invalidateSelf(),
  );
  return CanonicalClockState<ThreadMcpStateSnapshot>(
    sync: DomainSyncStatus(
      phase: failure == null ? DomainSyncPhase.idle : DomainSyncPhase.failed,
      errorMessage: failure?.reason.toString(),
    ),
  );
}
