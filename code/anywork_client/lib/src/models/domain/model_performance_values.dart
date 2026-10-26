import 'package:freezed_annotation/freezed_annotation.dart';

part 'model_performance_values.freezed.dart';

/// The Rust-calculated performance projection of a model reference query.
///
/// This belongs to the original model-reference read, not to the current
/// statistics feed. A later statistics publication cannot update its source.
@freezed
abstract class LocalModelPerformanceSummary
    with _$LocalModelPerformanceSummary {
  const factory LocalModelPerformanceSummary({
    required int sampleCount,
    required double? tokensPerSecond,
    required double? averageTtftMillis,
    required int ttftSampleCount,
    required int? updatedAt,
  }) = _LocalModelPerformanceSummary;
}
