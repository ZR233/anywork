import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'authoring_values.dart';
import 'configuration_values.dart';
import 'context_values.dart';
import 'execution_values.dart';
import 'metrics_values.dart';
import 'thread_identity.dart';

part 'facet_state.freezed.dart';

enum FacetSyncPhase { idle, connecting, ready, reconnecting, failed, closed }

@Freezed(toStringOverride: false)
abstract class FacetSyncState with _$FacetSyncState {
  const factory FacetSyncState({
    required FacetSyncPhase phase,
    StudioFailure? error,
    @Default(false) bool retryExhausted,
  }) = _FacetSyncState;
}

@Freezed(toStringOverride: false)
abstract class ThreadExecutionState with _$ThreadExecutionState {
  const factory ThreadExecutionState({
    ThreadFacetStamp? stamp,
    required FacetSyncState sync,
    ThreadExecutionBaseline? value,
  }) = _ThreadExecutionState;
}

@Freezed(toStringOverride: false)
abstract class ThreadMetricsState with _$ThreadMetricsState {
  const factory ThreadMetricsState({
    ThreadFacetStamp? stamp,
    required FacetSyncState sync,
    ThreadMetricsValue? value,
  }) = _ThreadMetricsState;
}

@Freezed(toStringOverride: false)
abstract class ThreadContextState with _$ThreadContextState {
  const factory ThreadContextState({
    ThreadFacetStamp? stamp,
    required FacetSyncState sync,
    ThreadContextValue? value,
  }) = _ThreadContextState;
}

@Freezed(toStringOverride: false)
abstract class ThreadConfigurationState with _$ThreadConfigurationState {
  const factory ThreadConfigurationState({
    ThreadFacetStamp? stamp,
    required FacetSyncState sync,
    ThreadConfigurationValue? value,
  }) = _ThreadConfigurationState;
}

@Freezed(toStringOverride: false)
abstract class ThreadAuthoringState with _$ThreadAuthoringState {
  const factory ThreadAuthoringState({
    ThreadFacetStamp? stamp,
    required FacetSyncState sync,
    ThreadAuthoringBaseline? value,
  }) = _ThreadAuthoringState;
}
