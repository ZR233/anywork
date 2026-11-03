import 'package:anywork_client/studio_client.dart'
    show
        CanonicalClockState,
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
  final source = ref.read(anyworkClientProvider).threadMcp(threadId).source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
