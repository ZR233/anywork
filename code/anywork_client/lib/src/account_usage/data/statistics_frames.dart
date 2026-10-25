import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/statistics_state.dart';

part 'statistics_frames.freezed.dart';

@Freezed(toStringOverride: false)
sealed class PerformanceSummariesFrame with _$PerformanceSummariesFrame {
  const factory PerformanceSummariesFrame.data({
    required int deliverySequence,
    required PerformanceSummariesEvent event,
  }) = PerformanceSummariesData;
  const factory PerformanceSummariesFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = PerformanceSummariesResyncRequired;
  const factory PerformanceSummariesFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = PerformanceSummariesFeedFailure;
  const factory PerformanceSummariesFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = PerformanceSummariesClosed;
}

@Freezed(toStringOverride: false)
sealed class PerformanceSummariesEvent with _$PerformanceSummariesEvent {
  const factory PerformanceSummariesEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required PerformanceSummariesBaseline value,
  }) = PerformanceSummariesBaselineEvent;
  const factory PerformanceSummariesEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required PerformanceSummariesChange value,
  }) = PerformanceSummariesChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class PerformanceSummariesBaseline
    with _$PerformanceSummariesBaseline {
  const factory PerformanceSummariesBaseline({
    required PerformanceSummariesHeader header,
    required ProductCollectionRef? collection,
  }) = _PerformanceSummariesBaseline;
}

@Freezed(toStringOverride: false)
abstract class PerformanceSummariesChange with _$PerformanceSummariesChange {
  const factory PerformanceSummariesChange({
    required PerformanceSummariesHeader header,
    required int? baseCollectionRevision,
    required ProductCollectionRef? collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) = _PerformanceSummariesChange;
}

@Freezed(toStringOverride: false)
sealed class PerformanceHistoryFrame with _$PerformanceHistoryFrame {
  const factory PerformanceHistoryFrame.data({
    required int deliverySequence,
    required PerformanceHistoryEvent event,
  }) = PerformanceHistoryData;
  const factory PerformanceHistoryFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = PerformanceHistoryResyncRequired;
  const factory PerformanceHistoryFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = PerformanceHistoryFeedFailure;
  const factory PerformanceHistoryFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = PerformanceHistoryClosed;
}

@Freezed(toStringOverride: false)
sealed class PerformanceHistoryEvent with _$PerformanceHistoryEvent {
  const factory PerformanceHistoryEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required PerformanceHistoryBaseline value,
  }) = PerformanceHistoryBaselineEvent;
  const factory PerformanceHistoryEvent.change({
    required ProductProjectionStamp stamp,
    required int baseRevision,
    required PerformanceHistoryChange value,
  }) = PerformanceHistoryChangeEvent;
}

@Freezed(toStringOverride: false)
abstract class PerformanceHistoryBaseline with _$PerformanceHistoryBaseline {
  const factory PerformanceHistoryBaseline({
    required PerformanceHistoryHeader header,
    required ProductCollectionRef? collection,
  }) = _PerformanceHistoryBaseline;
}

@Freezed(toStringOverride: false)
abstract class PerformanceHistoryChange with _$PerformanceHistoryChange {
  const factory PerformanceHistoryChange({
    required PerformanceHistoryHeader header,
    required int? baseCollectionRevision,
    required ProductCollectionRef? collection,
    required List<ProductEntityRef> upserted,
    required List<int> removedEntries,
  }) = _PerformanceHistoryChange;
}

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
