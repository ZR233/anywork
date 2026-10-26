import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'mcp_values.freezed.dart';

@Freezed(toStringOverride: false)
sealed class McpServerState with _$McpServerState {
  const factory McpServerState.disabled({required String message}) =
      DisabledMcpServerState;
  const factory McpServerState.missingCredential({required String message}) =
      MissingCredentialMcpServerState;
  const factory McpServerState.checking({required String message}) =
      CheckingMcpServerState;
  const factory McpServerState.available({
    required int checkedAt,
    required int toolCount,
  }) = AvailableMcpServerState;
  const factory McpServerState.unavailable({
    required int checkedAt,
    required SourceStateError error,
  }) = UnavailableMcpServerState;
}

@Freezed(toStringOverride: false)
abstract class McpServer with _$McpServer {
  const factory McpServer({
    required String id,
    required String transport,
    required String endpoint,
    required String sourceKind,
    required String mutationPolicy,
    required McpServerState state,
  }) = _McpServer;
}

@freezed
abstract class McpHealth with _$McpHealth {
  const factory McpHealth({
    required List<McpServer> mcpServers,
    required List<String> activeMcpServers,
  }) = _McpHealth;
}

@freezed
abstract class McpValue with _$McpValue {
  const factory McpValue({
    required String desiredConfigFingerprint,
    required String appliedConfigFingerprint,
    required McpHealth health,
  }) = _McpValue;
}
