import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/statistics_state.dart';
import '../domain/statistics_values.dart';

part 'statistics_reads.freezed.dart';

@freezed
abstract class PerformanceSummariesReadHeader
    with _$PerformanceSummariesReadHeader {
  const factory PerformanceSummariesReadHeader({
    required TypedListRef summaries,
  }) = _PerformanceSummariesReadHeader;
}

@freezed
abstract class PerformanceHistoryReadHeader
    with _$PerformanceHistoryReadHeader {
  const factory PerformanceHistoryReadHeader({required TypedListRef samples}) =
      _PerformanceHistoryReadHeader;
}

@freezed
abstract class PerformanceSummaryRead with _$PerformanceSummaryRead {
  const factory PerformanceSummaryRead({
    required PerformanceSummaryIdentityRef identity,
    required PerformanceCounters counters,
    required TypedListRef effortBreakdowns,
  }) = _PerformanceSummaryRead;
}

@freezed
abstract class PerformanceEffortRead with _$PerformanceEffortRead {
  const factory PerformanceEffortRead({
    required PerformanceEffortIdentityRef identity,
    required PerformanceCounters counters,
  }) = _PerformanceEffortRead;
}

@freezed
abstract class PerformanceSampleRead with _$PerformanceSampleRead {
  const factory PerformanceSampleRead({
    required PerformanceSampleIdentityRef identity,
    required PerformanceSampleCounters counters,
  }) = _PerformanceSampleRead;
}

@Freezed(toStringOverride: false)
abstract class PerformanceSummaryIdentityRead
    with _$PerformanceSummaryIdentityRead {
  const factory PerformanceSummaryIdentityRead({
    required ReadText accountId,
    required ReadText accountDisplayName,
    required ReadText modelId,
  }) = _PerformanceSummaryIdentityRead;
}

@Freezed(toStringOverride: false)
abstract class PerformanceEffortIdentityRead
    with _$PerformanceEffortIdentityRead {
  const factory PerformanceEffortIdentityRead({required ReadText? effort}) =
      _PerformanceEffortIdentityRead;
}

@Freezed(toStringOverride: false)
abstract class PerformanceSampleIdentityRead
    with _$PerformanceSampleIdentityRead {
  const factory PerformanceSampleIdentityRead({
    required ReadText accountId,
    required ReadText accountDisplayName,
    required ReadText? modelId,
    required ReadText? sentModel,
    required ReadText? reportedModel,
    required ModelMatchState modelMatchState,
    required ReadText? effort,
  }) = _PerformanceSampleIdentityRead;
}

@Freezed(toStringOverride: false)
abstract class SessionCostsReadHeader with _$SessionCostsReadHeader {
  const factory SessionCostsReadHeader({required SessionCostRead? cost}) =
      _SessionCostsReadHeader;
}

@Freezed(toStringOverride: false)
abstract class SessionCostRead with _$SessionCostRead {
  const factory SessionCostRead({
    required ReadText rootThreadId,
    required TypedListRef purposeCosts,
    required TypedListRef estimatedCosts,
    required bool hasUnpricedUsage,
  }) = _SessionCostRead;
}

@Freezed(toStringOverride: false)
abstract class PurposeCostRead with _$PurposeCostRead {
  const factory PurposeCostRead({
    required ReadText? purpose,
    required TypedListRef estimatedCosts,
    required bool hasUnpricedUsage,
  }) = _PurposeCostRead;
}

@Freezed(toStringOverride: false)
abstract class RuntimeCostRead with _$RuntimeCostRead {
  const factory RuntimeCostRead({
    required ReadText currency,
    required double amount,
  }) = _RuntimeCostRead;
}

@freezed
abstract class PerformanceSummariesEntryPage
    with _$PerformanceSummariesEntryPage {
  const factory PerformanceSummariesEntryPage({
    required ProductCollectionRef collection,
    required int offset,
    required List<ProductEntityRef> items,
    required int? nextOffset,
  }) = _PerformanceSummariesEntryPage;
}

@freezed
abstract class PerformanceSummariesEntityRead
    with _$PerformanceSummariesEntityRead {
  const factory PerformanceSummariesEntityRead({
    required ProductEntityRef reference,
    required PerformanceSummaryRead value,
  }) = _PerformanceSummariesEntityRead;
}

@freezed
abstract class PerformanceHistoryEntryPage with _$PerformanceHistoryEntryPage {
  const factory PerformanceHistoryEntryPage({
    required ProductCollectionRef collection,
    required int offset,
    required List<ProductEntityRef> items,
    required int? nextOffset,
  }) = _PerformanceHistoryEntryPage;
}

@freezed
abstract class PerformanceHistoryEntityRead
    with _$PerformanceHistoryEntityRead {
  const factory PerformanceHistoryEntityRead({
    required ProductEntityRef reference,
    required PerformanceSampleRead value,
  }) = _PerformanceHistoryEntityRead;
}

@freezed
abstract class PerformanceSummaryReadPage with _$PerformanceSummaryReadPage {
  const factory PerformanceSummaryReadPage({
    required int listId,
    required int offset,
    required int total,
    required List<PerformanceSummaryRead> items,
    required int? nextOffset,
  }) = _PerformanceSummaryReadPage;
}

@freezed
abstract class PerformanceEffortReadPage with _$PerformanceEffortReadPage {
  const factory PerformanceEffortReadPage({
    required int listId,
    required int offset,
    required int total,
    required List<PerformanceEffortRead> items,
    required int? nextOffset,
  }) = _PerformanceEffortReadPage;
}

@freezed
abstract class PerformanceSampleReadPage with _$PerformanceSampleReadPage {
  const factory PerformanceSampleReadPage({
    required int listId,
    required int offset,
    required int total,
    required List<PerformanceSampleRead> items,
    required int? nextOffset,
  }) = _PerformanceSampleReadPage;
}

@Freezed(toStringOverride: false)
abstract class PurposeCostReadPage with _$PurposeCostReadPage {
  const factory PurposeCostReadPage({
    required int listId,
    required int offset,
    required int total,
    required List<PurposeCostRead> items,
    required int? nextOffset,
  }) = _PurposeCostReadPage;
}

@Freezed(toStringOverride: false)
abstract class RuntimeCostReadPage with _$RuntimeCostReadPage {
  const factory RuntimeCostReadPage({
    required int listId,
    required int offset,
    required int total,
    required List<RuntimeCostRead> items,
    required int? nextOffset,
  }) = _RuntimeCostReadPage;
}
