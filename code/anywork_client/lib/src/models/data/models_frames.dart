import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/models_state.dart';

part 'models_frames.freezed.dart';

@Freezed(toStringOverride: false)
sealed class ModelCatalogFrame with _$ModelCatalogFrame {
  const factory ModelCatalogFrame.data({
    required int deliverySequence,
    required ModelCatalogEvent event,
  }) = ModelCatalogData;
  const factory ModelCatalogFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = ModelCatalogResyncRequired;
  const factory ModelCatalogFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = ModelCatalogFeedFailure;
  const factory ModelCatalogFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = ModelCatalogClosed;
}

@Freezed(toStringOverride: false)
sealed class ModelCatalogEvent with _$ModelCatalogEvent {
  const factory ModelCatalogEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required ModelCatalogBaseline value,
  }) = ModelCatalogBaselineEvent;
  const factory ModelCatalogEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required ModelCatalogChange value,
  }) = ModelCatalogChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class ModelCatalogBaseline with _$ModelCatalogBaseline {
  const factory ModelCatalogBaseline({
    required ModelCatalogHeader header,
    required ProductCollectionRef? collection,
  }) = _ModelCatalogBaseline;
}

@Freezed(toStringOverride: false)
final class ModelCatalogChange with _$ModelCatalogChange {
  ModelCatalogChange({
    required this.header,
    required this.baseCollectionRevision,
    required this.collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) : upserted = List.unmodifiable(upserted),
       removedEntries = List.unmodifiable(removedEntries);
  final ModelCatalogHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@Freezed(toStringOverride: false)
sealed class AccountTemplatesFrame with _$AccountTemplatesFrame {
  const factory AccountTemplatesFrame.data({
    required int deliverySequence,
    required AccountTemplatesEvent event,
  }) = AccountTemplatesData;
  const factory AccountTemplatesFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = AccountTemplatesResyncRequired;
  const factory AccountTemplatesFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = AccountTemplatesFeedFailure;
  const factory AccountTemplatesFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = AccountTemplatesClosed;
}

@Freezed(toStringOverride: false)
sealed class AccountTemplatesEvent with _$AccountTemplatesEvent {
  const factory AccountTemplatesEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required AccountTemplatesBaseline value,
  }) = AccountTemplatesBaselineEvent;
  const factory AccountTemplatesEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required AccountTemplatesChange value,
  }) = AccountTemplatesChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class AccountTemplatesBaseline with _$AccountTemplatesBaseline {
  const factory AccountTemplatesBaseline({
    required AccountTemplatesHeader header,
    required ProductCollectionRef? collection,
  }) = _AccountTemplatesBaseline;
}

@Freezed(toStringOverride: false)
final class AccountTemplatesChange with _$AccountTemplatesChange {
  AccountTemplatesChange({
    required this.header,
    required this.baseCollectionRevision,
    required this.collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) : upserted = List.unmodifiable(upserted),
       removedEntries = List.unmodifiable(removedEntries);
  final AccountTemplatesHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}
