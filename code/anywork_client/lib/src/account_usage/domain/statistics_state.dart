import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'statistics_values.dart';

part 'statistics_state.freezed.dart';

@freezed
abstract class PerformanceSummariesReadTarget with _$PerformanceSummariesReadTarget {
  const factory PerformanceSummariesReadTarget({required ProductReadOrigin origin, required PerformanceSummariesReadRef reference}) = _PerformanceSummariesReadTarget;
}

@freezed
abstract class PerformanceHistoryReadTarget with _$PerformanceHistoryReadTarget {
  const factory PerformanceHistoryReadTarget({required ProductReadOrigin origin, required PerformanceHistoryReadRef reference}) = _PerformanceHistoryReadTarget;
}

@freezed
abstract class SessionCostsReadTarget with _$SessionCostsReadTarget {
  const factory SessionCostsReadTarget({required ProductReadOrigin origin, required SessionCostsReadRef reference}) = _SessionCostsReadTarget;
}

@freezed
abstract class PerformanceSummariesReadRef with _$PerformanceSummariesReadRef {
  const factory PerformanceSummariesReadRef({required int entry, required int revision}) = _PerformanceSummariesReadRef;
}

@freezed
abstract class PerformanceHistoryReadRef with _$PerformanceHistoryReadRef {
  const factory PerformanceHistoryReadRef({required int entry, required int revision}) = _PerformanceHistoryReadRef;
}

@freezed
abstract class SessionCostsReadRef with _$SessionCostsReadRef {
  const factory SessionCostsReadRef({required int entry, required int revision}) = _SessionCostsReadRef;
}

@freezed
abstract class PerformanceSummaryIdentityRef with _$PerformanceSummaryIdentityRef {
  const factory PerformanceSummaryIdentityRef({required int entry, required int revision}) = _PerformanceSummaryIdentityRef;
}

@freezed
abstract class PerformanceEffortIdentityRef with _$PerformanceEffortIdentityRef {
  const factory PerformanceEffortIdentityRef({required int entry, required int revision}) = _PerformanceEffortIdentityRef;
}

@freezed
abstract class PerformanceSampleIdentityRef with _$PerformanceSampleIdentityRef {
  const factory PerformanceSampleIdentityRef({required int entry, required int revision}) = _PerformanceSampleIdentityRef;
}

@freezed
abstract class PerformanceSummariesHeader with _$PerformanceSummariesHeader {
  const factory PerformanceSummariesHeader({required int revision, required int updatedAt, required bool statisticsPending, required bool statisticsGap, required bool readFailed, required PerformanceSummariesReadRef reference}) = _PerformanceSummariesHeader;
}

@freezed
abstract class PerformanceHistoryHeader with _$PerformanceHistoryHeader {
  const factory PerformanceHistoryHeader({required int revision, required int updatedAt, required bool statisticsPending, required bool statisticsGap, required bool readFailed, required PerformanceHistoryReadRef reference}) = _PerformanceHistoryHeader;
}

@freezed
abstract class SessionCostsHeader with _$SessionCostsHeader {
  const factory SessionCostsHeader({required int revision, required int updatedAt, required bool statisticsPending, required bool statisticsGap, required bool readFailed, required bool hasCost, required bool? hasUnpricedUsage, required SessionCostsReadRef reference}) = _SessionCostsHeader;
}

@Freezed(toStringOverride: false)
abstract class StatisticsSummaryState with _$StatisticsSummaryState {
  const factory StatisticsSummaryState({required ProductProjection<PerformanceSummariesHeader> projection, required CollectionMirror<PerformanceSummary> summaries}) = _StatisticsSummaryState;
}

@Freezed(toStringOverride: false)
abstract class StatisticsHistoryState with _$StatisticsHistoryState {
  const factory StatisticsHistoryState({required ProductProjection<PerformanceHistoryHeader> projection, required CollectionMirror<PerformanceSample> samples}) = _StatisticsHistoryState;
}

@Freezed(toStringOverride: false)
abstract class SessionCostsState with _$SessionCostsState {
  const factory SessionCostsState({required ProductProjection<SessionCostsHeader> projection, required String rootThreadId, required ReadValue<SessionCost?, SessionCostsReadRef>? cost}) = _SessionCostsState;
}
