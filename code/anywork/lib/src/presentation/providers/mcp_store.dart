import 'package:anywork_client/studio_client.dart'
    show CanonicalClockState, McpStateSnapshot;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show CanonicalClockState;

part 'mcp_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
CanonicalClockState<McpStateSnapshot> mcpStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).mcp.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
