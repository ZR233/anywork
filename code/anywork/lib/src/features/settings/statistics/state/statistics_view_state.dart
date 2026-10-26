import 'package:anywork_client/statistics.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'statistics_view_state.freezed.dart';

/// One top-level account/config-model identity: the only composite filter key.
/// It is never repaired from the current catalog or from sent/reported aliases.
@freezed
abstract class StatisticsModelKey with _$StatisticsModelKey {
  const factory StatisticsModelKey({
    required String accountId,
    required String? modelId,
  }) = _StatisticsModelKey;
}

/// Null wrapper = all efforts; wrapper(value:null) = the actual unspecified
/// reasoning-effort subgroup, which is a real identity and not "all".
@freezed
abstract class StatisticsEffortFilter with _$StatisticsEffortFilter {
  const factory StatisticsEffortFilter({required String? value}) =
      _StatisticsEffortFilter;
}

@Freezed(toStringOverride: false)
abstract class StatisticsModelOption with _$StatisticsModelOption {
  const factory StatisticsModelOption({
    required StatisticsModelKey key,
    required String accountDisplayName,
    required String displayModel,
  }) = _StatisticsModelOption;
}

/// Immutable presentation of the one canonical statistics mirror: the latest
/// complete snapshot, the page's own visibility and its local filters.
///
/// It carries no feed, read scope, paging cursor or second materialization:
/// the Repository publishes only complete snapshots, so an empty collection
/// here always means "known empty", never "not read yet".
@Freezed(toStringOverride: false)
abstract class StatisticsViewState with _$StatisticsViewState {
  const StatisticsViewState._();

  const factory StatisticsViewState({
    required StatisticsState source,
    required bool visible,
    StatisticsModelKey? modelFilter,
    StatisticsEffortFilter? effortFilter,
    @Default(false) bool mismatchesOnly,
    @Default(<PerformanceSample>[]) List<PerformanceSample> filteredHistory,
    @Default(<StatisticsModelOption>[])
    List<StatisticsModelOption> modelOptions,
    @Default(<StatisticsEffortFilter>[])
    List<StatisticsEffortFilter> effortOptions,
  }) = _StatisticsViewState;

  /// Null until the first complete publication of this application instance.
  StatisticsSnapshot? get snapshot => source.snapshot;
}
