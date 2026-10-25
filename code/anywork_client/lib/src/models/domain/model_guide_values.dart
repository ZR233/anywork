import 'package:freezed_annotation/freezed_annotation.dart';

import 'model_evaluation_values.dart';

part 'model_guide_values.freezed.dart';

@Freezed(toStringOverride: false)
final class ModelSelectionGuide with _$ModelSelectionGuide {
  ModelSelectionGuide({
    required this.summary,
    required List<AgentTaskCategory> taskSuitability,
    required List<String> limitations,
    required List<ModelSelectionSource> sources,
  }) : taskSuitability = List.unmodifiable(taskSuitability),
       limitations = List.unmodifiable(limitations),
       sources = List.unmodifiable(sources);
  final String summary;
  final List<AgentTaskCategory> taskSuitability;
  final List<String> limitations;
  final List<ModelSelectionSource> sources;
}

enum ModelSelectionSourceKind { official, benchmark, community }

@Freezed(toStringOverride: false)
abstract class ModelSelectionSource with _$ModelSelectionSource {
  const factory ModelSelectionSource({
    required ModelSelectionSourceKind kind,
    required String url,
    required int verifiedAt,
    required ModelSelectionMeasurement? measurement,
  }) = _ModelSelectionSource;
}

@Freezed(toStringOverride: false)
abstract class ModelSelectionMeasurement with _$ModelSelectionMeasurement {
  const factory ModelSelectionMeasurement({
    required String model,
    required String? effort,
    required String metric,
    required String? metricVersion,
    required double? score,
  }) = _ModelSelectionMeasurement;
}
