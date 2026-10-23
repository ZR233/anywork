import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'persistence_values.freezed.dart';

enum HistoryFault {
  queueFull,
  writeFailed,
  writerUnavailable,
  noProgress,
  checkpointFailed,
  blobFailed,
}

enum ThreadStorageExecution { running, pausing, paused }

@Freezed(toStringOverride: false)
sealed class PersistenceStatus with _$PersistenceStatus {
  const factory PersistenceStatus.ready({required int pendingCommits}) =
      ReadyPersistenceStatus;
  const factory PersistenceStatus.flushing({
    required int pendingCommits,
    required int? oldestPendingRevision,
  }) = FlushingPersistenceStatus;
  const factory PersistenceStatus.degraded({
    required int pendingCommits,
    required int? oldestPendingRevision,
    required int firstFailedAt,
    required SourceStateError error,
  }) = DegradedPersistenceStatus;
  const factory PersistenceStatus.recovering({
    required int pendingCommits,
    required int? oldestPendingRevision,
    required int firstFailedAt,
  }) = RecoveringPersistenceStatus;
  const factory PersistenceStatus.blocked({
    required int pendingCommits,
    required int? oldestPendingRevision,
    required int firstFailedAt,
    required SourceStateError error,
  }) = BlockedPersistenceStatus;
}

@Freezed(toStringOverride: false)
abstract class PersistenceValue with _$PersistenceValue {
  const factory PersistenceValue({
    required int revision,
    required PersistenceStatus state,
  }) = _PersistenceValue;
}

@Freezed(toStringOverride: false)
abstract class ThreadPersistenceSnapshot with _$ThreadPersistenceSnapshot {
  const factory ThreadPersistenceSnapshot({
    required String threadId,
    required int faultGeneration,
    required HistoryFault? fault,
    required int? stateDirtyRevision,
    required int? stateSavingRevision,
    required int? stateDurableRevision,
    required int? historyAdmittedSequence,
    required int? historyDurableSequence,
    required int? callsAdmittedSequence,
    required int? callsDurableSequence,
    required int pendingOperations,
    required int pendingBytes,
    required int? oldestPendingAgeMillis,
    required int inFlightBytes,
    required String? lastError,
    required bool pressurePaused,
  }) = _ThreadPersistenceSnapshot;
}

/// Raw retry/resume replies deliberately have no publication revision.
@Freezed(toStringOverride: false)
final class PersistenceQueueSnapshot with _$PersistenceQueueSnapshot {
  PersistenceQueueSnapshot({
    required this.statisticsGap,
    required this.pendingOperations,
    required this.pendingBytes,
    required this.inFlightBytes,
    required this.oldestPendingAgeMillis,
    required this.lastError,
    required this.pressurePaused,
    required List<ThreadPersistenceSnapshot> threads,
  }) : threads = List.unmodifiable(threads);
  final bool statisticsGap;
  final int pendingOperations;
  final int pendingBytes;
  final int inFlightBytes;
  final int? oldestPendingAgeMillis;
  final String? lastError;
  final bool pressurePaused;
  final List<ThreadPersistenceSnapshot> threads;
}

@Freezed(toStringOverride: false)
abstract class PersistenceQueueValue with _$PersistenceQueueValue {
  const factory PersistenceQueueValue({
    required int revision,
    required int updatedAt,
    required PersistenceQueueSnapshot queue,
  }) = _PersistenceQueueValue;
}
