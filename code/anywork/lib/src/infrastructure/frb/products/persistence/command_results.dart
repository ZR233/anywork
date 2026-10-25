import 'package:anywork_client/persistence.dart';

import '../../../../rust/api/studio/products/read/persistence_queue.dart'
    as native;
import '../../conversation/scalar_converters.dart' show historyFaultFromBridge;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';

/// Command snapshots carry no publication revision. Nullable watermarks remain
/// Unknown; no zero, latest mirror or inferred durability is substituted.
ThreadPersistenceSnapshot threadPersistenceCommandFromBridge(
  native.BridgeThreadPersistenceCommandSnapshot value,
) => ThreadPersistenceSnapshot(
  threadId: value.threadId,
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
  lastError: value.lastError,
  pressurePaused: value.pressurePaused,
);

PersistenceQueueSnapshot persistenceQueueCommandFromBridge(
  native.BridgePersistenceQueueCommandSnapshot value,
) => PersistenceQueueSnapshot(
  statisticsGap: value.statisticsGap,
  pendingOperations: exactU64(value.pendingOperations, 'pending operations'),
  pendingBytes: exactU64(value.pendingBytes, 'pending bytes'),
  inFlightBytes: exactU64(value.inFlightBytes, 'in-flight bytes'),
  oldestPendingAgeMillis: nullableU64(
    value.oldestPendingAgeMillis,
    'oldest pending age milliseconds',
  ),
  lastError: value.lastError,
  pressurePaused: value.pressurePaused,
  threads: value.threads
      .map(threadPersistenceCommandFromBridge)
      .toList(growable: false),
);
