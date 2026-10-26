import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'session_costs_values.dart';

part 'session_costs_state.freezed.dart';

@freezed
abstract class SessionCostsReadTarget with _$SessionCostsReadTarget {
  const factory SessionCostsReadTarget({
    required ProductReadOrigin origin,
    required SessionCostsReadRef reference,
  }) = _SessionCostsReadTarget;
}

@freezed
abstract class SessionCostsReadRef with _$SessionCostsReadRef {
  const factory SessionCostsReadRef({
    required int entry,
    required int revision,
  }) = _SessionCostsReadRef;
}

@freezed
abstract class SessionCostsHeader with _$SessionCostsHeader {
  const factory SessionCostsHeader({
    required int revision,
    required int updatedAt,
    required bool statisticsPending,
    required bool statisticsGap,
    required bool readFailed,
    required bool hasCost,
    required bool? hasUnpricedUsage,
    required SessionCostsReadRef reference,
  }) = _SessionCostsHeader;
}

@Freezed(toStringOverride: false)
abstract class SessionCostsState with _$SessionCostsState {
  const factory SessionCostsState({
    required ProductProjection<SessionCostsHeader> projection,
    required String rootThreadId,
    required ReadValue<SessionCost?, SessionCostsReadRef>? cost,
  }) = _SessionCostsState;
}
