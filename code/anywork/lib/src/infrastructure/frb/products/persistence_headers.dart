import 'package:anywork_client/persistence.dart';

import '../../../rust/api/studio/products/feed/persistence.dart' as native;
import '../../../rust/api/studio/products/feed/persistence_queue.dart' as queue;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'resource_references.dart';

PersistenceBrief persistenceBriefFromBridge(native.BridgePersistenceBrief value) => switch (value) {
  native.BridgePersistenceBrief_Ready(:final pendingCommits) => PersistenceBrief.ready(
    pendingCommits: exactU64(pendingCommits, 'pending commits'),
  ),
  native.BridgePersistenceBrief_Flushing(:final pendingCommits, :final oldestPendingRevision) => PersistenceBrief.flushing(
    pendingCommits: exactU64(pendingCommits, 'pending commits'),
    oldestPendingRevision: nullableU64(oldestPendingRevision, 'oldest pending revision'),
  ),
  native.BridgePersistenceBrief_Degraded(:final pendingCommits, :final oldestPendingRevision, :final firstFailedAt) => PersistenceBrief.degraded(
    pendingCommits: exactU64(pendingCommits, 'pending commits'),
    oldestPendingRevision: nullableU64(oldestPendingRevision, 'oldest pending revision'),
    firstFailedAt: exactI64(firstFailedAt, 'persistence first failure Unix seconds'),
  ),
  native.BridgePersistenceBrief_Recovering(:final pendingCommits, :final oldestPendingRevision, :final firstFailedAt) => PersistenceBrief.recovering(
    pendingCommits: exactU64(pendingCommits, 'pending commits'),
    oldestPendingRevision: nullableU64(oldestPendingRevision, 'oldest pending revision'),
    firstFailedAt: exactI64(firstFailedAt, 'persistence first failure Unix seconds'),
  ),
  native.BridgePersistenceBrief_Blocked(:final pendingCommits, :final oldestPendingRevision, :final firstFailedAt) => PersistenceBrief.blocked(
    pendingCommits: exactU64(pendingCommits, 'pending commits'),
    oldestPendingRevision: nullableU64(oldestPendingRevision, 'oldest pending revision'),
    firstFailedAt: exactI64(firstFailedAt, 'persistence first failure Unix seconds'),
  ),
};

PersistenceHeader persistenceHeaderFromBridge(native.BridgePersistenceHeader value) => PersistenceHeader(
  reference: persistenceReadRefFromBridge(value.reference),
  revision: exactU64(value.revision, 'persistence revision'),
  state: persistenceBriefFromBridge(value.state),
);

PersistenceQueueHeader persistenceQueueHeaderFromBridge(queue.BridgePersistenceQueueHeader value) => PersistenceQueueHeader(
  reference: persistenceQueueReadRefFromBridge(value.reference),
  revision: exactU64(value.revision, 'persistence queue revision'),
  updatedAt: exactI64(value.updatedAt, 'persistence queue updated Unix seconds'),
  statisticsGap: value.statisticsGap,
  pendingOperations: exactU64(value.pendingOperations, 'pending persistence operations'),
  pendingBytes: exactU64(value.pendingBytes, 'pending persistence bytes'),
  inFlightBytes: exactU64(value.inFlightBytes, 'in-flight persistence bytes'),
  oldestPendingAgeMillis: nullableU64(value.oldestPendingAgeMillis, 'oldest pending age milliseconds'),
  pressurePaused: value.pressurePaused,
  hasLastError: value.hasLastError,
);
