import 'package:freezed_annotation/freezed_annotation.dart';

part 'statistics_values.freezed.dart';

/// Existing Rust-calculated performance projection used by model reference
/// queries. No samples is unknown, not a synthesized zero/median/quality score.
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

/// Statistics are Rust-calculated facts. Nullable measurements stay unknown.
@freezed
abstract class PerformanceCounters with _$PerformanceCounters {
  const factory PerformanceCounters({
    required int sampleCount,
    required int completionTokens,
    required int totalTtftMillis,
    required int ttftSampleCount,
    required int totalResponseMillis,
    required double tokensPerSecond,
    required double? averageTtftMillis,
    required double averageResponseMillis,
  }) = _PerformanceCounters;
}

@freezed
abstract class PerformanceSummaryIdentity with _$PerformanceSummaryIdentity {
  const factory PerformanceSummaryIdentity({
    required String accountId,
    required String accountDisplayName,
    required String modelId,
  }) = _PerformanceSummaryIdentity;
}

@freezed
abstract class PerformanceEffortIdentity with _$PerformanceEffortIdentity {
  const factory PerformanceEffortIdentity({required String? effort}) =
      _PerformanceEffortIdentity;
}

enum ModelMatchState { matched, mismatched, unreported, legacyUnknown }

@freezed
abstract class PerformanceSampleIdentity with _$PerformanceSampleIdentity {
  const factory PerformanceSampleIdentity({
    required String accountId,
    required String accountDisplayName,
    required String? modelId,
    required String? sentModel,
    required String? reportedModel,
    required ModelMatchState modelMatchState,
    required String? effort,
  }) = _PerformanceSampleIdentity;
}

@freezed
abstract class PerformanceSampleCounters with _$PerformanceSampleCounters {
  const factory PerformanceSampleCounters({
    required int completedAt,
    required int completionTokens,
    required int? ttftMillis,
    required int? decodeMillis,
    required int? totalResponseMillis,
    required double? tokensPerSecond,
  }) = _PerformanceSampleCounters;
}

@freezed
abstract class PerformanceSummary with _$PerformanceSummary {
  const factory PerformanceSummary({
    required PerformanceSummaryIdentity identity,
    required PerformanceCounters counters,
    required List<PerformanceEffort> effortBreakdowns,
  }) = _PerformanceSummary;
}

@freezed
abstract class PerformanceEffort with _$PerformanceEffort {
  const factory PerformanceEffort({
    required PerformanceEffortIdentity identity,
    required PerformanceCounters counters,
  }) = _PerformanceEffort;
}

@freezed
abstract class PerformanceSample with _$PerformanceSample {
  const factory PerformanceSample({
    required PerformanceSampleIdentity identity,
    required PerformanceSampleCounters counters,
  }) = _PerformanceSample;
}

@freezed
abstract class SessionCost with _$SessionCost {
  const factory SessionCost({
    required String rootThreadId,
    required List<PurposeCost> purposeCosts,
    required List<RuntimeCost> estimatedCosts,
    required bool hasUnpricedUsage,
  }) = _SessionCost;
}

@freezed
abstract class PurposeCost with _$PurposeCost {
  const factory PurposeCost({
    required String? purpose,
    required List<RuntimeCost> estimatedCosts,
    required bool hasUnpricedUsage,
  }) = _PurposeCost;
}

@freezed
abstract class RuntimeCost with _$RuntimeCost {
  const factory RuntimeCost({
    required String currency,
    required double amount,
  }) = _RuntimeCost;
}
