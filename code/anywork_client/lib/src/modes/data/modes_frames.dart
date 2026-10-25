import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/modes_state.dart';

part 'modes_frames.freezed.dart';

@Freezed(toStringOverride: false)
sealed class ModeCatalogFrame with _$ModeCatalogFrame {
  const factory ModeCatalogFrame.data({
    required int deliverySequence,
    required ModeCatalogEvent event,
  }) = ModeCatalogData;
  const factory ModeCatalogFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = ModeCatalogResyncRequired;
  const factory ModeCatalogFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = ModeCatalogFeedFailure;
  const factory ModeCatalogFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = ModeCatalogClosed;
}

@Freezed(toStringOverride: false)
sealed class ModeCatalogEvent with _$ModeCatalogEvent {
  const factory ModeCatalogEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required ModeCatalogBaseline value,
  }) = ModeCatalogBaselineEvent;
  const factory ModeCatalogEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required ModeCatalogChange value,
  }) = ModeCatalogChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class ModeCatalogBaseline with _$ModeCatalogBaseline {
  const factory ModeCatalogBaseline({
    required ModeCatalogHeader header,
    required ProductCollectionRef? collection,
  }) = _ModeCatalogBaseline;
}

@Freezed(toStringOverride: false)
abstract class ModeCatalogChange with _$ModeCatalogChange {
  const factory ModeCatalogChange({
    required ModeCatalogHeader header,
    required int? baseCollectionRevision,
    required ProductCollectionRef? collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) = _ModeCatalogChange;
}
