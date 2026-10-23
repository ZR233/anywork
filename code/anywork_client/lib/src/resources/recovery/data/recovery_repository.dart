import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/recovery_repository.dart';
import '../domain/recovery_state.dart';
import '../domain/recovery_values.dart';
import 'recovery_actions.dart';
import 'recovery_mirror.dart';
import 'recovery_pages.dart';
import 'recovery_port.dart';
import 'recovery_source_reads.dart';

RecoveryRepository createRecoveryRepository({
  required RecoveryPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _RecoveryRepository(port, budget, operations);

final class _RecoveryRepository implements RecoveryRepository {
  _RecoveryRepository(RecoveryPort port, ResourceBudget budget,
      OperationRecorder operations) : lifetime = ResourceLifetime(budget) {
    mirror = RecoveryMirror(port, lifetime);
    pages = RecoveryPages(port, mirror, lifetime);
    sourceReads = RecoverySourceReads(port, mirror, lifetime);
    actions = RecoveryActions(port, pages, lifetime, operations);
    mirror.adopted = (binding) {
      pages.adopted(binding);
      sourceReads.adopted(binding);
    };
  }
  final ResourceLifetime lifetime;
  late final RecoveryMirror mirror;
  late final RecoveryPages pages;
  late final RecoverySourceReads sourceReads;
  late final RecoveryActions actions;
  bool _sourceClosed = false;

  @override
  ReadonlyLatestValue<RecoveryState> get state => mirror.source.readonly;
  @override
  Future<void> loadIssuesPage({int limit = 32}) => pages.load(limit: limit);
  @override
  Future<void> loadSourceStatus() => sourceReads.load();
  @override
  OperationTicket<RecoveryReadTarget> retry() => actions.retry();
  @override
  OperationTicket<Unit> cleanupWorktree(WorktreeOwner ownerKind,
      String ownerThreadId, int expectedLeaseRevision) =>
      actions.cleanupWorktree(ownerKind, ownerThreadId, expectedLeaseRevision);
  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final resources = await lifetime.close(deadline: deadline, retry: retry);
    final report = CloseReport(unresolved: [
      ...resources.unresolved, ...actions.unresolved,
    ]);
    if (report.complete && !_sourceClosed) {
      _sourceClosed = true;
      mirror.source.publish(mirror.source.value.copyWith(
        projection: mirror.source.value.projection.copyWith(sync: const ResourceSyncState(
          phase: ResourceSyncPhase.closed, error: null, retryExhausted: false))));
      mirror.source.close();
    }
    return report;
  }
}
