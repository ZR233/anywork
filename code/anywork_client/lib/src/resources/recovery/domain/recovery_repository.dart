import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'recovery_state.dart';
import 'recovery_values.dart';

abstract interface class RecoveryRepository {
  ReadonlyLatestValue<RecoveryState> get state;
  Future<void> loadIssuesPage({int limit = 32});
  Future<void> loadSourceStatus();
  OperationTicket<RecoveryReadTarget> retry();
  OperationTicket<Unit> cleanupWorktree(
    WorktreeOwner ownerKind,
    String ownerThreadId,
    int expectedLeaseRevision,
  );
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
