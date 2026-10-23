import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/persistence_values.dart';

part 'persistence_reads.freezed.dart';

@Freezed(toStringOverride: false)
sealed class PersistenceStatusRead with _$PersistenceStatusRead {
  const factory PersistenceStatusRead.ready({required int pendingCommits}) = ReadyPersistenceStatusRead;
  const factory PersistenceStatusRead.flushing({required int pendingCommits,
    required int? oldestPendingRevision}) = FlushingPersistenceStatusRead;
  const factory PersistenceStatusRead.degraded({required int pendingCommits,
    required int? oldestPendingRevision, required int firstFailedAt,
    required SourceStateErrorRead error}) = DegradedPersistenceStatusRead;
  const factory PersistenceStatusRead.recovering({required int pendingCommits,
    required int? oldestPendingRevision, required int firstFailedAt}) = RecoveringPersistenceStatusRead;
  const factory PersistenceStatusRead.blocked({required int pendingCommits,
    required int? oldestPendingRevision, required int firstFailedAt,
    required SourceStateErrorRead error}) = BlockedPersistenceStatusRead;
}

@Freezed(toStringOverride: false)
abstract class PersistenceReadHeader with _$PersistenceReadHeader {
  const factory PersistenceReadHeader({required int revision,
    required PersistenceStatusRead state}) = _PersistenceReadHeader;
}

@Freezed(toStringOverride: false)
abstract class ThreadPersistenceRead with _$ThreadPersistenceRead {
  const factory ThreadPersistenceRead({required ReadText threadId, required int faultGeneration,
    required HistoryFault? fault, required int? stateDirtyRevision, required int? stateSavingRevision,
    required int? stateDurableRevision, required int? historyAdmittedSequence,
    required int? historyDurableSequence, required int? callsAdmittedSequence,
    required int? callsDurableSequence, required int pendingOperations, required int pendingBytes,
    required int? oldestPendingAgeMillis, required int inFlightBytes, required ReadText? lastError,
    required bool pressurePaused}) = _ThreadPersistenceRead;
}

@Freezed(toStringOverride: false)
abstract class PersistenceQueueSnapshotRead with _$PersistenceQueueSnapshotRead {
  const factory PersistenceQueueSnapshotRead({required bool statisticsGap,
    required int pendingOperations, required int pendingBytes, required int inFlightBytes,
    required int? oldestPendingAgeMillis, required ReadText? lastError,
    required bool pressurePaused, required TypedListRef threads}) = _PersistenceQueueSnapshotRead;
}

@Freezed(toStringOverride: false)
abstract class PersistenceQueueReadHeader with _$PersistenceQueueReadHeader {
  const factory PersistenceQueueReadHeader({required int revision, required int updatedAt,
    required PersistenceQueueSnapshotRead queue}) = _PersistenceQueueReadHeader;
}

@Freezed(toStringOverride: false)
abstract class PersistenceQueueEntityRead with _$PersistenceQueueEntityRead {
  const factory PersistenceQueueEntityRead({required ProductEntityRef reference,
    required ThreadPersistenceRead value}) = _PersistenceQueueEntityRead;
}

@freezed
final class PersistenceQueueEntryPage with _$PersistenceQueueEntryPage {
  PersistenceQueueEntryPage({required this.collection, required this.offset,
    required List<ProductEntityRef> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ThreadPersistenceReadPage with _$ThreadPersistenceReadPage {
  ThreadPersistenceReadPage({required this.listId, required this.offset, required this.total,
    required List<ThreadPersistenceRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ThreadPersistenceRead> items;
  final int? nextOffset;
}
