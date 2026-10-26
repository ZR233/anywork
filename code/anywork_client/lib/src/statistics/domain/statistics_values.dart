import 'package:freezed_annotation/freezed_annotation.dart';

part 'statistics_values.freezed.dart';

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

/// A summary's identity is the account plus the frozen configured model.
@freezed
abstract class PerformanceSummaryIdentity with _$PerformanceSummaryIdentity {
  const factory PerformanceSummaryIdentity({
    required String accountId,
    required String accountDisplayName,
    required String modelId,
  }) = _PerformanceSummaryIdentity;
}

/// A null effort is a real subgroup identity, not the string `none`.
@freezed
abstract class PerformanceEffortIdentity with _$PerformanceEffortIdentity {
  const factory PerformanceEffortIdentity({required String? effort}) =
      _PerformanceEffortIdentity;
}

enum ModelMatchState { matched, mismatched, unreported, legacyUnknown }

/// Frozen history diagnostics; unknown identities are never repaired from the
/// current catalog or from sent/reported aliases.
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

/// One top-level account/config-model aggregate with its effort subgroups.
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

/// Fixed native read references. Entry/revision identity a frozen material; it
/// is not a publication revision or a delivery sequence.
@freezed
abstract class PerformanceSummariesReadRef with _$PerformanceSummariesReadRef {
  const factory PerformanceSummariesReadRef({
    required int entry,
    required int revision,
  }) = _PerformanceSummariesReadRef;
}

@freezed
abstract class PerformanceHistoryReadRef with _$PerformanceHistoryReadRef {
  const factory PerformanceHistoryReadRef({
    required int entry,
    required int revision,
  }) = _PerformanceHistoryReadRef;
}

@freezed
abstract class PerformanceSummaryIdentityRef
    with _$PerformanceSummaryIdentityRef {
  const factory PerformanceSummaryIdentityRef({
    required int entry,
    required int revision,
  }) = _PerformanceSummaryIdentityRef;
}

@freezed
abstract class PerformanceEffortIdentityRef
    with _$PerformanceEffortIdentityRef {
  const factory PerformanceEffortIdentityRef({
    required int entry,
    required int revision,
  }) = _PerformanceEffortIdentityRef;
}

@freezed
abstract class PerformanceSampleIdentityRef
    with _$PerformanceSampleIdentityRef {
  const factory PerformanceSampleIdentityRef({
    required int entry,
    required int revision,
  }) = _PerformanceSampleIdentityRef;
}
