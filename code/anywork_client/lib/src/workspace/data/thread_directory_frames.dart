import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:anywork_client/resources.dart';

import '../domain/directory_state.dart';

part 'thread_directory_frames.freezed.dart';

@freezed
abstract class ThreadDirectoryBaseline with _$ThreadDirectoryBaseline {
  const factory ThreadDirectoryBaseline({
    required ThreadDirectoryHeader header,
    required ProductCollectionRef? collection,
  }) = _ThreadDirectoryBaseline;
}

@Freezed(toStringOverride: false)
final class ThreadDirectoryChange with _$ThreadDirectoryChange {
  ThreadDirectoryChange({
    required this.header,
    required this.baseCollectionRevision,
    required this.collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) : upserted = List.unmodifiable(upserted),
       removedEntries = List.unmodifiable(removedEntries);
  final ThreadDirectoryHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class ThreadDirectoryEvent with _$ThreadDirectoryEvent {
  const factory ThreadDirectoryEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required ThreadDirectoryBaseline value,
  }) = ThreadDirectoryBaselineEvent;
  const factory ThreadDirectoryEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required ThreadDirectoryChange value,
  }) = ThreadDirectoryChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class ThreadDirectoryFrame with _$ThreadDirectoryFrame {
  const factory ThreadDirectoryFrame.data({
    required int deliverySequence,
    required ThreadDirectoryEvent event,
  }) = ThreadDirectoryData;
  const factory ThreadDirectoryFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = ThreadDirectoryResyncRequired;
  const factory ThreadDirectoryFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = ThreadDirectoryFeedFailure;
  const factory ThreadDirectoryFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = ThreadDirectoryClosed;
}
