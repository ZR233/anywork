import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';

part 'session_costs_reads.freezed.dart';

@Freezed(toStringOverride: false)
abstract class SessionCostsReadHeader with _$SessionCostsReadHeader {
  const factory SessionCostsReadHeader({required SessionCostRead? cost}) =
      _SessionCostsReadHeader;
}

@Freezed(toStringOverride: false)
abstract class SessionCostRead with _$SessionCostRead {
  const factory SessionCostRead({
    required ReadText rootThreadId,
    required TypedListRef purposeCosts,
    required TypedListRef estimatedCosts,
    required bool hasUnpricedUsage,
  }) = _SessionCostRead;
}

@Freezed(toStringOverride: false)
abstract class PurposeCostRead with _$PurposeCostRead {
  const factory PurposeCostRead({
    required ReadText? purpose,
    required TypedListRef estimatedCosts,
    required bool hasUnpricedUsage,
  }) = _PurposeCostRead;
}

@Freezed(toStringOverride: false)
abstract class RuntimeCostRead with _$RuntimeCostRead {
  const factory RuntimeCostRead({
    required ReadText currency,
    required double amount,
  }) = _RuntimeCostRead;
}

@Freezed(toStringOverride: false)
abstract class PurposeCostReadPage with _$PurposeCostReadPage {
  const factory PurposeCostReadPage({
    required int listId,
    required int offset,
    required int total,
    required List<PurposeCostRead> items,
    required int? nextOffset,
  }) = _PurposeCostReadPage;
}

@Freezed(toStringOverride: false)
abstract class RuntimeCostReadPage with _$RuntimeCostReadPage {
  const factory RuntimeCostReadPage({
    required int listId,
    required int offset,
    required int total,
    required List<RuntimeCostRead> items,
    required int? nextOffset,
  }) = _RuntimeCostReadPage;
}
