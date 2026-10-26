import 'package:freezed_annotation/freezed_annotation.dart';

import 'thread_identity.dart';

part 'metrics_values.freezed.dart';

enum TurnObservationState { live, authoritative }

@freezed
abstract class ThreadMetricsValue with _$ThreadMetricsValue {
  const factory ThreadMetricsValue({
    required LiveTurnMetrics? live,
    required AuthoritativeTurnMetrics? authoritative,
  }) = _ThreadMetricsValue;
}

@freezed
abstract class LiveTurnMetrics with _$LiveTurnMetrics {
  const factory LiveTurnMetrics({
    required MetricsIdentityRef identity,
    required int? completionTokens,
    required int? responseMillis,
    required TurnObservationState state,
    required int observationSequence,
  }) = _LiveTurnMetrics;
}

@freezed
abstract class AuthoritativeTurnMetrics with _$AuthoritativeTurnMetrics {
  const factory AuthoritativeTurnMetrics({
    required MetricsIdentityRef identity,
    required int completionTokens,
    required int responseMillis,
  }) = _AuthoritativeTurnMetrics;
}
