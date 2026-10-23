import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'statistics_view_state.freezed.dart';

enum StatisticsReadField { summaries, history }

@freezed
abstract class StatisticsModelKey with _$StatisticsModelKey {
  const factory StatisticsModelKey({required String accountId, required String? modelId}) = _StatisticsModelKey;
}

/// Null wrapper = all efforts; wrapper(value:null) = the actual unspecified group.
@freezed
abstract class StatisticsEffortFilter with _$StatisticsEffortFilter {
  const factory StatisticsEffortFilter({required String? value}) = _StatisticsEffortFilter;
}

@Freezed(toStringOverride: false)
abstract class StatisticsModelOption with _$StatisticsModelOption {
  const factory StatisticsModelOption({required StatisticsModelKey key,
    required String accountDisplayName, required String displayModel}) = _StatisticsModelOption;
}

@Freezed(toStringOverride: false)
abstract class StatisticsViewState with _$StatisticsViewState {
  const factory StatisticsViewState({
    required StatisticsSummaryState summaries,
    required StatisticsHistoryState history,
    StatisticsModelKey? modelFilter,
    StatisticsEffortFilter? effortFilter,
    @Default(false) bool mismatchesOnly,
    @Default({}) Set<StatisticsReadField> reading,
    @Default({}) Map<StatisticsReadField, StudioFailure> readIssues,
    @Default({}) Map<StatisticsReadField, StudioFailure> observationIssues,
    @Default(false) bool visible,
  }) = _StatisticsViewState;
}
