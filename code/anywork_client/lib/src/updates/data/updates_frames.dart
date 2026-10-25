import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/updates_state.dart';

part 'updates_frames.freezed.dart';

@freezed
sealed class UpdatesEvent with _$UpdatesEvent {
  const factory UpdatesEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required UpdatesHeader value,
  }) = UpdatesBaselineEvent;
  const factory UpdatesEvent.replace({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required UpdatesHeader value,
  }) = UpdatesReplaceEvent;
}

@Freezed(toStringOverride: false)
sealed class UpdatesFrame with _$UpdatesFrame {
  const factory UpdatesFrame.data({
    required int deliverySequence,
    required UpdatesEvent event,
  }) = UpdatesData;
  const factory UpdatesFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = UpdatesResyncRequired;
  const factory UpdatesFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = UpdatesFeedFailure;
  const factory UpdatesFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = UpdatesClosed;
}
