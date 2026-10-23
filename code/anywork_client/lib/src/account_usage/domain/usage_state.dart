import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'usage_values.dart';

part 'usage_state.freezed.dart';

@freezed
abstract class AccountUsageReadRef with _$AccountUsageReadRef {
  const factory AccountUsageReadRef({required int entry, required int revision}) = _AccountUsageReadRef;
}

@freezed
abstract class AccountUsageReadTarget with _$AccountUsageReadTarget {
  const factory AccountUsageReadTarget({required ProductReadOrigin origin, required AccountUsageReadRef reference}) = _AccountUsageReadTarget;
}

@freezed
abstract class AccountUsageHeader with _$AccountUsageHeader {
  const factory AccountUsageHeader({required ObservedHeader source, required AccountUsageReadRef? reference}) = _AccountUsageHeader;
}

@Freezed(toStringOverride: false)
abstract class AccountUsageState with _$AccountUsageState {
  const factory AccountUsageState({required ProductProjection<AccountUsageHeader> projection, required ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, required CollectionMirror<AccountUsageRecord> usages, required ReadValue<String, AccountUsageReadRef>? configFingerprint}) = _AccountUsageState;
}
