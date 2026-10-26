import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_state.dart';
import '../domain/persistence_values.dart';
import 'persistence_port.dart';
import 'persistence_reads.dart';

PersistenceBrief persistenceReadBrief(PersistenceStatusRead value) =>
    switch (value) {
      ReadyPersistenceStatusRead(:final pendingCommits) =>
        PersistenceBrief.ready(pendingCommits: pendingCommits),
      FlushingPersistenceStatusRead(
        :final pendingCommits,
        :final oldestPendingRevision,
      ) =>
        PersistenceBrief.flushing(
          pendingCommits: pendingCommits,
          oldestPendingRevision: oldestPendingRevision,
        ),
      DegradedPersistenceStatusRead(
        :final pendingCommits,
        :final oldestPendingRevision,
        :final firstFailedAt,
      ) =>
        PersistenceBrief.degraded(
          pendingCommits: pendingCommits,
          oldestPendingRevision: oldestPendingRevision,
          firstFailedAt: firstFailedAt,
        ),
      RecoveringPersistenceStatusRead(
        :final pendingCommits,
        :final oldestPendingRevision,
        :final firstFailedAt,
      ) =>
        PersistenceBrief.recovering(
          pendingCommits: pendingCommits,
          oldestPendingRevision: oldestPendingRevision,
          firstFailedAt: firstFailedAt,
        ),
      BlockedPersistenceStatusRead(
        :final pendingCommits,
        :final oldestPendingRevision,
        :final firstFailedAt,
      ) =>
        PersistenceBrief.blocked(
          pendingCommits: pendingCommits,
          oldestPendingRevision: oldestPendingRevision,
          firstFailedAt: firstFailedAt,
        ),
    };

Future<PersistenceValue> readPersistenceValue(
  PersistenceReadConnection scope,
  PersistenceHeader expected,
) async {
  final value = await scope.header();
  if (value.revision != expected.revision ||
      persistenceReadBrief(value.state) != expected.state) {
    throw resourceProtocol(
      'Persistence value disagrees with its original header.',
    );
  }
  final read = (int field, int offset) =>
      scope.text(field, offset: offset, maxBytes: 65536);
  Future<SourceStateError> error(SourceStateErrorRead value) async =>
      SourceStateError(
        code: await materializeReadText(value.code, read: read),
        message: await materializeReadText(value.message, read: read),
        retryable: value.retryable,
      );
  final state = switch (value.state) {
    ReadyPersistenceStatusRead(:final pendingCommits) =>
      PersistenceStatus.ready(pendingCommits: pendingCommits),
    FlushingPersistenceStatusRead(
      :final pendingCommits,
      :final oldestPendingRevision,
    ) =>
      PersistenceStatus.flushing(
        pendingCommits: pendingCommits,
        oldestPendingRevision: oldestPendingRevision,
      ),
    DegradedPersistenceStatusRead(
      :final pendingCommits,
      :final oldestPendingRevision,
      :final firstFailedAt,
      error: final failure,
    ) =>
      PersistenceStatus.degraded(
        pendingCommits: pendingCommits,
        oldestPendingRevision: oldestPendingRevision,
        firstFailedAt: firstFailedAt,
        error: await error(failure),
      ),
    RecoveringPersistenceStatusRead(
      :final pendingCommits,
      :final oldestPendingRevision,
      :final firstFailedAt,
    ) =>
      PersistenceStatus.recovering(
        pendingCommits: pendingCommits,
        oldestPendingRevision: oldestPendingRevision,
        firstFailedAt: firstFailedAt,
      ),
    BlockedPersistenceStatusRead(
      :final pendingCommits,
      :final oldestPendingRevision,
      :final firstFailedAt,
      error: final failure,
    ) =>
      PersistenceStatus.blocked(
        pendingCommits: pendingCommits,
        oldestPendingRevision: oldestPendingRevision,
        firstFailedAt: firstFailedAt,
        error: await error(failure),
      ),
  };
  return PersistenceValue(revision: value.revision, state: state);
}

Future<PersistenceQueueReadHeader> readPersistenceQueueHeader(
  PersistenceQueueReadConnection scope,
  PersistenceQueueHeader expected,
  ProductCollectionRef collection,
) async {
  final value = await scope.header();
  final queue = value.queue;
  if (value.revision != expected.revision ||
      value.updatedAt != expected.updatedAt ||
      queue.statisticsGap != expected.statisticsGap ||
      queue.pendingOperations != expected.pendingOperations ||
      queue.pendingBytes != expected.pendingBytes ||
      queue.inFlightBytes != expected.inFlightBytes ||
      queue.oldestPendingAgeMillis != expected.oldestPendingAgeMillis ||
      queue.pressurePaused != expected.pressurePaused ||
      (queue.lastError != null) != expected.hasLastError ||
      queue.threads.listId < 0 ||
      queue.threads.total != collection.total) {
    throw resourceProtocol(
      'Persistence queue details changed their original header.',
    );
  }
  return value;
}

Future<ThreadPersistenceSnapshot> readThreadPersistence(
  PersistenceQueueReadConnection scope,
  ThreadPersistenceRead value,
) async {
  final read = (int field, int offset) =>
      scope.text(field, offset: offset, maxBytes: 65536);
  return ThreadPersistenceSnapshot(
    threadId: await materializeReadText(value.threadId, read: read),
    faultGeneration: value.faultGeneration,
    fault: value.fault,
    stateDirtyRevision: value.stateDirtyRevision,
    stateSavingRevision: value.stateSavingRevision,
    stateDurableRevision: value.stateDurableRevision,
    historyAdmittedSequence: value.historyAdmittedSequence,
    historyDurableSequence: value.historyDurableSequence,
    callsAdmittedSequence: value.callsAdmittedSequence,
    callsDurableSequence: value.callsDurableSequence,
    pendingOperations: value.pendingOperations,
    pendingBytes: value.pendingBytes,
    oldestPendingAgeMillis: value.oldestPendingAgeMillis,
    inFlightBytes: value.inFlightBytes,
    lastError: value.lastError == null
        ? null
        : await materializeReadText(value.lastError!, read: read),
    pressurePaused: value.pressurePaused,
  );
}
