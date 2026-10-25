import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/recovery_state.dart';

part 'recovery_frames.freezed.dart';

@freezed
abstract class RecoveryBaseline with _$RecoveryBaseline {
  const factory RecoveryBaseline({
    required RecoveryHeader header,
    required ProductCollectionRef? collection,
  }) = _RecoveryBaseline;
}

@Freezed(toStringOverride: false)
final class RecoveryChange with _$RecoveryChange {
  RecoveryChange({
    required this.header,
    required this.baseCollectionRevision,
    required this.collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) : upserted = List.unmodifiable(upserted),
       removedEntries = List.unmodifiable(removedEntries);
  final RecoveryHeader header;
  final int? baseCollectionRevision;
  final ProductCollectionRef? collection;
  final List<ProductEntityRef> upserted;
  final List<int> removedEntries;
}

@freezed
sealed class RecoveryEvent with _$RecoveryEvent {
  const factory RecoveryEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required RecoveryBaseline value,
  }) = RecoveryBaselineEvent;
  const factory RecoveryEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required RecoveryChange value,
  }) = RecoveryChangeEvent;
}

@Freezed(toStringOverride: false)
sealed class RecoveryFrame with _$RecoveryFrame {
  const factory RecoveryFrame.data({
    required int deliverySequence,
    required RecoveryEvent event,
  }) = RecoveryData;
  const factory RecoveryFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = RecoveryResyncRequired;
  const factory RecoveryFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = RecoveryFeedFailure;
  const factory RecoveryFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = RecoveryClosed;
}
