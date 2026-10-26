import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'lsp_state.dart';

abstract interface class LspRepository {
  ReadonlyLatestValue<LspState> get state;
  Future<void> loadServersPage({int limit = 32});
  Future<void> loadActiveServerIds();
  Future<void> loadSourceStatus();
  OperationTicket<LspReadTarget> probe(String projectId);
  OperationTicket<LspReadTarget> repair(String projectId, String serverId);
  OperationTicket<LspReadTarget> resetServer(String projectId, String serverId);
  OperationTicket<LspReadTarget> resetWorkspace(String projectId);
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
