import 'package:freezed_annotation/freezed_annotation.dart';

part 'observed_resource.freezed.dart';

enum StateOperation {
  initialize,
  activate,
  reload,
  reconcile,
  discover,
  check,
  probe,
  repair,
  reset,
  shutdown,
}

@Freezed(toStringOverride: false)
abstract class SourceStateError with _$SourceStateError {
  const factory SourceStateError({
    required String code,
    required String message,
    required bool retryable,
  }) = _SourceStateError;
}

/// Source state is independent of transport health and operation evidence.
@Freezed(toStringOverride: false)
sealed class ObservedResource<T> with _$ObservedResource<T> {
  const ObservedResource._();

  const factory ObservedResource.uninitialized({
    required int revision,
    required int updatedAt,
  }) = UninitializedObservedResource<T>;
  const factory ObservedResource.loading({
    required int revision,
    required StateOperation operation,
    required String operationId,
    required int startedAt,
  }) = LoadingObservedResource<T>;
  const factory ObservedResource.ready({
    required int revision,
    required int updatedAt,
    required int? lastCheckedAt,
    required T value,
  }) = ReadyObservedResource<T>;
  const factory ObservedResource.refreshing({
    required int revision,
    required StateOperation operation,
    required String operationId,
    required int startedAt,
    required int? lastCheckedAt,
    required T value,
  }) = RefreshingObservedResource<T>;
  const factory ObservedResource.stale({
    required int revision,
    required int staleAt,
    required int? lastCheckedAt,
    required T value,
  }) = StaleObservedResource<T>;
  const factory ObservedResource.degraded({
    required int revision,
    required int failedAt,
    required int? lastCheckedAt,
    required StateOperation operation,
    required SourceStateError error,
    required T value,
  }) = DegradedObservedResource<T>;
  const factory ObservedResource.failed({
    required int revision,
    required int failedAt,
    required StateOperation operation,
    required SourceStateError error,
  }) = FailedObservedResource<T>;
  const factory ObservedResource.stopped({
    required int revision,
    required int stoppedAt,
  }) = StoppedObservedResource<T>;

  T? get value => switch (this) {
    ReadyObservedResource<T>(:final value) ||
    RefreshingObservedResource<T>(:final value) ||
    StaleObservedResource<T>(:final value) ||
    DegradedObservedResource<T>(:final value) => value,
    UninitializedObservedResource<T>() ||
    LoadingObservedResource<T>() ||
    FailedObservedResource<T>() ||
    StoppedObservedResource<T>() => null,
  };
}
