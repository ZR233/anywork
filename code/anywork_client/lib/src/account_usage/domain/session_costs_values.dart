import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_costs_values.freezed.dart';

/// Root-scoped costs published by the same billing owner as the statistics
/// projections. They are read by the root session owner only; the global
/// history never carries them.
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
