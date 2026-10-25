import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import 'recovery_values.dart';

part 'recovery_state.freezed.dart';

@freezed
abstract class RecoveryReadRef with _$RecoveryReadRef {
  const factory RecoveryReadRef({required int entry, required int revision}) =
      _RecoveryReadRef;
}

@freezed
abstract class RecoveryReadTarget with _$RecoveryReadTarget {
  const factory RecoveryReadTarget({
    required ProductReadOrigin origin,
    required RecoveryReadRef reference,
  }) = _RecoveryReadTarget;
}

@freezed
abstract class RecoveryHeader with _$RecoveryHeader {
  const factory RecoveryHeader({
    required ObservedHeader source,
    required RecoveryReadRef? reference,
  }) = _RecoveryHeader;
}

@Freezed(toStringOverride: false)
abstract class RecoveryState with _$RecoveryState {
  const factory RecoveryState({
    required ProductProjection<RecoveryHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>?
    sourceStatus,
    required CollectionMirror<RecoveryIssue> issues,
  }) = _RecoveryState;
}
