import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/session_costs_state.dart';

part 'session_costs_frames.freezed.dart';

@Freezed(toStringOverride: false)
sealed class SessionCostsFrame with _$SessionCostsFrame {
  const factory SessionCostsFrame.data({
    required int deliverySequence,
    required SessionCostsEvent event,
  }) = SessionCostsData;
  const factory SessionCostsFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = SessionCostsResyncRequired;
  const factory SessionCostsFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = SessionCostsFeedFailure;
  const factory SessionCostsFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = SessionCostsClosed;
}

/// A scalar replacement has no fabricated empty collection.
@Freezed(toStringOverride: false)
sealed class SessionCostsEvent with _$SessionCostsEvent {
  const factory SessionCostsEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required SessionCostsHeader value,
  }) = SessionCostsBaselineEvent;
  const factory SessionCostsEvent.replace({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required SessionCostsHeader value,
  }) = SessionCostsReplaceEvent;
}
