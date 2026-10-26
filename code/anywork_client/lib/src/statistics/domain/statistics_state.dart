import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'statistics_values.dart';

part 'statistics_state.freezed.dart';

/// One side's published projection header. Its `revision` is the billing
/// owner's shared business water level, its `reference` is that side's own
/// material identity, and the status flags describe the same publication.
@freezed
abstract class PerformanceSummariesHeader with _$PerformanceSummariesHeader {
  const factory PerformanceSummariesHeader({
    required int revision,
    required int updatedAt,
    required bool statisticsPending,
    required bool statisticsGap,
    required bool readFailed,
    required PerformanceSummariesReadRef reference,
  }) = _PerformanceSummariesHeader;
}

@freezed
abstract class PerformanceHistoryHeader with _$PerformanceHistoryHeader {
  const factory PerformanceHistoryHeader({
    required int revision,
    required int updatedAt,
    required bool statisticsPending,
    required bool statisticsGap,
    required bool readFailed,
    required PerformanceHistoryReadRef reference,
  }) = _PerformanceHistoryHeader;
}

/// The most recent complete statistics publication.
///
/// Both sides come from one authority origin and one business revision, and
/// their materials were read to completion before this value existed. The two
/// read references stay independent: an unchanged side keeps its own
/// reference while the other side advances. The summary and history delivery
/// sequences and projection stamps are not part of this value.
@Freezed(toStringOverride: false)
abstract class StatisticsSnapshot with _$StatisticsSnapshot {
  const factory StatisticsSnapshot({
    required ProductReadOrigin origin,
    required int revision,
    required int updatedAt,
    required bool statisticsPending,
    required bool statisticsGap,
    required bool readFailed,
    required PerformanceSummariesReadRef summariesReference,
    required PerformanceHistoryReadRef historyReference,
    required List<PerformanceSummary> summaries,
    required List<PerformanceSample> history,
  }) = _StatisticsSnapshot;
}

/// Canonical statistics mirror: the last complete snapshot plus the current
/// visible-attempt state. The snapshot stays published while a newer
/// publication is still being materialized, and it is `null` only before the
/// first complete publication.
@Freezed(toStringOverride: false)
abstract class StatisticsState with _$StatisticsState {
  const factory StatisticsState({
    required StatisticsSnapshot? snapshot,
    required ResourceSyncState sync,
  }) = _StatisticsState;
}
