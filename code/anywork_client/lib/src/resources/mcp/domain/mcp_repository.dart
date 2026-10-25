import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'mcp_state.dart';

abstract interface class McpRepository {
  ReadonlyLatestValue<McpState> get state;
  Future<void> loadServersPage({int limit = 32});
  Future<void> loadActiveServerIds();
  Future<void> loadDesiredConfigFingerprint();
  Future<void> loadAppliedConfigFingerprint();
  Future<void> loadSourceStatus();
  OperationTicket<McpReadTarget> resetServer(String serverId);
  OperationTicket<McpReadTarget> resetAll();
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
