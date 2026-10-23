import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/persistence_state.dart';

part 'persistence_frames.freezed.dart';

@freezed
sealed class PersistenceEvent with _$PersistenceEvent {
  const factory PersistenceEvent.baseline({required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp, required PersistenceHeader value}) = PersistenceBaselineEvent;
  const factory PersistenceEvent.replace({required ProductProjectionStamp stamp,
    required int baseRevision, required PersistenceHeader value}) = PersistenceReplaceEvent;
}

@Freezed(toStringOverride: false)
sealed class PersistenceFrame with _$PersistenceFrame {
  const factory PersistenceFrame.data({required int deliverySequence,
    required PersistenceEvent event}) = PersistenceData;
  const factory PersistenceFrame.resyncRequired({required ProductFeedIdentity identity,
    required ProductResyncReason reason}) = PersistenceResyncRequired;
  const factory PersistenceFrame.failure({required ProductFeedIdentity identity,
    required StudioFailure error}) = PersistenceFeedFailure;
  const factory PersistenceFrame.closed({required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason}) = PersistenceClosed;
}

@freezed
abstract class PersistenceQueueBaseline with _$PersistenceQueueBaseline {
  const factory PersistenceQueueBaseline({required PersistenceQueueHeader header,
    required ProductCollectionRef? collection}) = _PersistenceQueueBaseline;
}

@Freezed(toStringOverride: false)
final class PersistenceQueueChange with _$PersistenceQueueChange {
  PersistenceQueueChange({required this.header, required this.baseCollectionRevision,
    required this.collection, required List<ProductEntityRef> upserted,
    required List<int> removedEntries})
      : upserted = List.unmodifiable(upserted), removedEntries = List.unmodifiable(removedEntries);
  final PersistenceQueueHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class PersistenceQueueEvent with _$PersistenceQueueEvent {
  const factory PersistenceQueueEvent.baseline({required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp, required PersistenceQueueBaseline value}) = PersistenceQueueBaselineEvent;
  const factory PersistenceQueueEvent.change({required ProductProjectionStamp stamp,
    required int baseRevision, required PersistenceQueueChange value}) = PersistenceQueueChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class PersistenceQueueFrame with _$PersistenceQueueFrame {
  const factory PersistenceQueueFrame.data({required int deliverySequence,
    required PersistenceQueueEvent event}) = PersistenceQueueData;
  const factory PersistenceQueueFrame.resyncRequired({required ProductFeedIdentity identity,
    required ProductResyncReason reason}) = PersistenceQueueResyncRequired;
  const factory PersistenceQueueFrame.failure({required ProductFeedIdentity identity,
    required StudioFailure error}) = PersistenceQueueFeedFailure;
  const factory PersistenceQueueFrame.closed({required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason}) = PersistenceQueueClosed;
}
