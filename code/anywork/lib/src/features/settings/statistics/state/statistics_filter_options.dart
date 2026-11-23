import 'package:anywork_client/statistics.dart';

/// Locale-independent options derived once from one pair of immutable materials.
final class StatisticsFilterOptions {
  factory StatisticsFilterOptions.fromMaterials(
    List<StatisticsSample> history,
    List<StatisticsSummary> summaries,
  ) {
    final models = <String, StatisticsModelFilterOption>{};
    final efforts = <String, StatisticsEffortFilterOption>{};
    final serviceTiers = <String, StatisticsServiceTierFilterOption>{};
    for (final sample in history) {
      models.putIfAbsent(
        sample.filterKey,
        () => StatisticsModelFilterOption(
          key: sample.filterKey,
          accountId: sample.accountId,
          accountDisplayName: sample.accountDisplayName,
          modelId: sample.displayModel,
        ),
      );
      efforts.putIfAbsent(
        sample.effortKey,
        () => StatisticsEffortFilterOption(
          key: sample.effortKey,
          effort: sample.effort,
        ),
      );
      serviceTiers.putIfAbsent(
        sample.serviceTierKey,
        () => StatisticsServiceTierFilterOption(
          key: sample.serviceTierKey,
          requestedServiceTier: sample.requestedServiceTier,
        ),
      );
    }
    for (final summary in summaries) {
      models.putIfAbsent(
        summary.filterKey,
        () => StatisticsModelFilterOption(
          key: summary.filterKey,
          accountId: summary.accountId,
          accountDisplayName: summary.accountDisplayName,
          modelId: summary.modelId,
        ),
      );
    }
    return StatisticsFilterOptions._(
      List.unmodifiable(models.values),
      List.unmodifiable(efforts.values),
      List.unmodifiable(serviceTiers.values),
    );
  }

  const StatisticsFilterOptions._(this.models, this.efforts, this.serviceTiers);

  final List<StatisticsModelFilterOption> models;
  final List<StatisticsEffortFilterOption> efforts;
  final List<StatisticsServiceTierFilterOption> serviceTiers;
}

final class StatisticsModelFilterOption {
  const StatisticsModelFilterOption({
    required this.key,
    required this.accountId,
    required this.accountDisplayName,
    required this.modelId,
  });

  final String key;
  final String accountId;
  final String accountDisplayName;
  final String modelId;
}

final class StatisticsEffortFilterOption {
  const StatisticsEffortFilterOption({required this.key, required this.effort});

  final String key;
  final String? effort;
}

final class StatisticsServiceTierFilterOption {
  const StatisticsServiceTierFilterOption({
    required this.key,
    required this.requestedServiceTier,
  });

  final String key;
  final String? requestedServiceTier;
}
