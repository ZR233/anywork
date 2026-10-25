import 'package:anywork_client/persistence_ports.dart';

import '../../../../rust/api/studio/products/read/persistence.dart' as native;
import '../../conversation/scalar_converters.dart' show historyFaultFromBridge;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../source_converters.dart';

PersistenceStatusRead persistenceStatusReadFromBridge(
  native.BridgePersistenceStatusRead value,
) => switch (value) {
  native.BridgePersistenceStatusRead_Ready(:final pendingCommits) =>
    PersistenceStatusRead.ready(
      pendingCommits: exactU64(pendingCommits, 'pending commits'),
    ),
  native.BridgePersistenceStatusRead_Flushing(
    :final pendingCommits,
    :final oldestPendingRevision,
  ) =>
    PersistenceStatusRead.flushing(
      pendingCommits: exactU64(pendingCommits, 'pending commits'),
      oldestPendingRevision: nullableU64(
        oldestPendingRevision,
        'oldest pending revision',
      ),
    ),
  native.BridgePersistenceStatusRead_Degraded(
    :final pendingCommits,
    :final oldestPendingRevision,
    :final firstFailedAt,
    :final error,
  ) =>
    PersistenceStatusRead.degraded(
      pendingCommits: exactU64(pendingCommits, 'pending commits'),
      oldestPendingRevision: nullableU64(
        oldestPendingRevision,
        'oldest pending revision',
      ),
      firstFailedAt: exactI64(
        BigInt.from(firstFailedAt),
        'persistence first failure Unix seconds',
      ),
      error: sourceErrorReadFromBridge(error),
    ),
  native.BridgePersistenceStatusRead_Recovering(
    :final pendingCommits,
    :final oldestPendingRevision,
    :final firstFailedAt,
  ) =>
    PersistenceStatusRead.recovering(
      pendingCommits: exactU64(pendingCommits, 'pending commits'),
      oldestPendingRevision: nullableU64(
        oldestPendingRevision,
        'oldest pending revision',
      ),
      firstFailedAt: exactI64(
        BigInt.from(firstFailedAt),
        'persistence first failure Unix seconds',
      ),
    ),
  native.BridgePersistenceStatusRead_Blocked(
    :final pendingCommits,
    :final oldestPendingRevision,
    :final firstFailedAt,
    :final error,
  ) =>
    PersistenceStatusRead.blocked(
      pendingCommits: exactU64(pendingCommits, 'pending commits'),
      oldestPendingRevision: nullableU64(
        oldestPendingRevision,
        'oldest pending revision',
      ),
      firstFailedAt: exactI64(
        BigInt.from(firstFailedAt),
        'persistence first failure Unix seconds',
      ),
      error: sourceErrorReadFromBridge(error),
    ),
};

PersistenceReadHeader persistenceReadHeaderFromBridge(
  native.BridgePersistenceReadHeader value,
) => PersistenceReadHeader(
  revision: exactU64(value.revision, 'persistence revision'),
  state: persistenceStatusReadFromBridge(value.state),
);

ThreadPersistenceRead threadPersistenceReadFromBridge(
  native.BridgeThreadPersistenceRead value,
) => ThreadPersistenceRead(
  threadId: readTextFromBridge(value.threadId),
  faultGeneration: exactU64(value.faultGeneration, 'history fault generation'),
  fault: value.fault == null ? null : historyFaultFromBridge(value.fault!),
  stateDirtyRevision: nullableU64(
    value.stateDirtyRevision,
    'state dirty revision',
  ),
  stateSavingRevision: nullableU64(
    value.stateSavingRevision,
    'state saving revision',
  ),
  stateDurableRevision: nullableU64(
    value.stateDurableRevision,
    'state durable revision',
  ),
  historyAdmittedSequence: nullableU64(
    value.historyAdmittedSequence,
    'history admitted sequence',
  ),
  historyDurableSequence: nullableU64(
    value.historyDurableSequence,
    'history durable sequence',
  ),
  callsAdmittedSequence: nullableU64(
    value.callsAdmittedSequence,
    'calls admitted sequence',
  ),
  callsDurableSequence: nullableU64(
    value.callsDurableSequence,
    'calls durable sequence',
  ),
  pendingOperations: exactU64(value.pendingOperations, 'pending operations'),
  pendingBytes: exactU64(value.pendingBytes, 'pending bytes'),
  oldestPendingAgeMillis: nullableU64(
    value.oldestPendingAgeMillis,
    'oldest pending age milliseconds',
  ),
  inFlightBytes: exactU64(value.inFlightBytes, 'in-flight bytes'),
  lastError: nullableReadText(value.lastError),
  pressurePaused: value.pressurePaused,
);

PersistenceQueueSnapshotRead persistenceQueueReadFromBridge(
  native.BridgePersistenceQueueSnapshotRead value,
) => PersistenceQueueSnapshotRead(
  statisticsGap: value.statisticsGap,
  pendingOperations: exactU64(value.pendingOperations, 'pending operations'),
  pendingBytes: exactU64(value.pendingBytes, 'pending bytes'),
  inFlightBytes: exactU64(value.inFlightBytes, 'in-flight bytes'),
  oldestPendingAgeMillis: nullableU64(
    value.oldestPendingAgeMillis,
    'oldest pending age milliseconds',
  ),
  lastError: nullableReadText(value.lastError),
  pressurePaused: value.pressurePaused,
  threads: typedListFromBridge(value.threads),
);

PersistenceQueueReadHeader persistenceQueueReadHeaderFromBridge(
  native.BridgePersistenceQueueReadHeader value,
) => PersistenceQueueReadHeader(
  revision: exactU64(value.revision, 'persistence queue revision'),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'persistence queue updated Unix seconds',
  ),
  queue: persistenceQueueReadFromBridge(value.queue),
);

PersistenceQueueEntityRead persistenceQueueEntityFromBridge(
  native.BridgePersistenceQueueEntityRead value,
) => PersistenceQueueEntityRead(
  reference: entityRefFromBridge(value.reference),
  value: threadPersistenceReadFromBridge(value.value),
);

PersistenceQueueEntryPage persistenceQueueEntriesFromBridge(
  native.BridgePersistenceQueueEntryPage value,
) => PersistenceQueueEntryPage(
  collection: collectionRefFromBridge(value.collection),
  offset: exactU64(value.offset, 'persistence queue entries offset'),
  items: value.items.map(entityRefFromBridge).toList(growable: false),
  nextOffset: nullableU64(
    value.nextOffset,
    'persistence queue next entries offset',
  ),
);

ThreadPersistenceReadPage persistenceThreadsFromBridge(
  native.BridgeThreadPersistenceReadPage value,
) => ThreadPersistenceReadPage(
  listId: exactU64(value.listId, 'persistence threads list'),
  offset: exactU64(value.offset, 'persistence threads offset'),
  total: exactU64(value.total, 'persistence threads total'),
  items: value.items
      .map(threadPersistenceReadFromBridge)
      .toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'persistence threads next offset'),
);
