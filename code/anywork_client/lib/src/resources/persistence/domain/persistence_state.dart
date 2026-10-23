import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import 'persistence_values.dart';

part 'persistence_state.freezed.dart';

@freezed
abstract class PersistenceReadRef with _$PersistenceReadRef {
  const factory PersistenceReadRef({required int entry, required int revision}) =
      _PersistenceReadRef;
}

@freezed
abstract class PersistenceReadTarget with _$PersistenceReadTarget {
  const factory PersistenceReadTarget({
    required ProductReadOrigin origin,
    required PersistenceReadRef reference,
  }) = _PersistenceReadTarget;
}

@freezed
abstract class PersistenceQueueReadRef with _$PersistenceQueueReadRef {
  const factory PersistenceQueueReadRef({required int entry, required int revision}) =
      _PersistenceQueueReadRef;
}

@Freezed(toStringOverride: false)
sealed class PersistenceBrief with _$PersistenceBrief {
  const factory PersistenceBrief.ready({required int pendingCommits}) =
      ReadyPersistenceBrief;
  const factory PersistenceBrief.flushing({
    required int pendingCommits,
    required int? oldestPendingRevision,
  }) = FlushingPersistenceBrief;
  const factory PersistenceBrief.degraded({
    required int pendingCommits,
    required int? oldestPendingRevision,
    required int firstFailedAt,
  }) = DegradedPersistenceBrief;
  const factory PersistenceBrief.recovering({
    required int pendingCommits,
    required int? oldestPendingRevision,
    required int firstFailedAt,
  }) = RecoveringPersistenceBrief;
  const factory PersistenceBrief.blocked({
    required int pendingCommits,
    required int? oldestPendingRevision,
    required int firstFailedAt,
  }) = BlockedPersistenceBrief;
}

@freezed
abstract class PersistenceHeader with _$PersistenceHeader {
  const factory PersistenceHeader({
    required PersistenceReadRef reference,
    required int revision,
    required PersistenceBrief state,
  }) = _PersistenceHeader;
}

@freezed
abstract class PersistenceQueueHeader with _$PersistenceQueueHeader {
  const factory PersistenceQueueHeader({
    required PersistenceQueueReadRef reference,
    required int revision,
    required int updatedAt,
    required bool statisticsGap,
    required int pendingOperations,
    required int pendingBytes,
    required int inFlightBytes,
    required int? oldestPendingAgeMillis,
    required bool pressurePaused,
    required bool hasLastError,
  }) = _PersistenceQueueHeader;
}

@Freezed(toStringOverride: false)
abstract class PersistenceState with _$PersistenceState {
  const factory PersistenceState({
    required ProductProjection<PersistenceHeader> projection,
    required ReadValue<PersistenceValue, PersistenceReadRef>? value,
  }) = _PersistenceState;
}

@Freezed(toStringOverride: false)
abstract class PersistenceQueueState with _$PersistenceQueueState {
  const factory PersistenceQueueState({
    required ProductProjection<PersistenceQueueHeader> projection,
    required CollectionMirror<ThreadPersistenceSnapshot> threads,
    required ReadValue<String?, PersistenceQueueReadRef>? lastError,
  }) = _PersistenceQueueState;
}
