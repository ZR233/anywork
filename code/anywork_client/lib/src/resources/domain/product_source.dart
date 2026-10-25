import 'package:freezed_annotation/freezed_annotation.dart';

import 'observed_resource.dart';
import 'product_identity.dart';
import 'read_primitives.dart';

part 'product_source.freezed.dart';

@freezed
sealed class ObservedBrief with _$ObservedBrief {
  const factory ObservedBrief.uninitialized({
    required int revision,
    required int updatedAt,
  }) = UninitializedObservedBrief;
  const factory ObservedBrief.loading({
    required int revision,
    required int startedAt,
  }) = LoadingObservedBrief;
  const factory ObservedBrief.ready({
    required int revision,
    required int updatedAt,
    required int? lastCheckedAt,
  }) = ReadyObservedBrief;
  const factory ObservedBrief.refreshing({
    required int revision,
    required int startedAt,
    required int? lastCheckedAt,
  }) = RefreshingObservedBrief;
  const factory ObservedBrief.stale({
    required int revision,
    required int staleAt,
    required int? lastCheckedAt,
  }) = StaleObservedBrief;
  const factory ObservedBrief.degraded({
    required int revision,
    required int failedAt,
    required int? lastCheckedAt,
    required bool retryable,
  }) = DegradedObservedBrief;
  const factory ObservedBrief.failed({
    required int revision,
    required int failedAt,
    required bool retryable,
  }) = FailedObservedBrief;
  const factory ObservedBrief.stopped({
    required int revision,
    required int stoppedAt,
  }) = StoppedObservedBrief;
}

@freezed
abstract class ObservedHeader with _$ObservedHeader {
  const factory ObservedHeader({
    required ObservedBrief brief,
    required ProductSourceStatusRef status,
  }) = _ObservedHeader;
}

@Freezed(toStringOverride: false)
abstract class SourceStateErrorRead with _$SourceStateErrorRead {
  const factory SourceStateErrorRead({
    required ReadText code,
    required ReadText message,
    required bool retryable,
  }) = _SourceStateErrorRead;
}

@Freezed(toStringOverride: false)
sealed class ProductSourceStatusReadHeader
    with _$ProductSourceStatusReadHeader {
  const factory ProductSourceStatusReadHeader.uninitialized({
    required int revision,
    required int updatedAt,
  }) = UninitializedProductSourceStatusReadHeader;
  const factory ProductSourceStatusReadHeader.loading({
    required int revision,
    required StateOperation operation,
    required ReadText operationId,
    required int startedAt,
  }) = LoadingProductSourceStatusReadHeader;
  const factory ProductSourceStatusReadHeader.ready({
    required int revision,
    required int updatedAt,
    required int? lastCheckedAt,
  }) = ReadyProductSourceStatusReadHeader;
  const factory ProductSourceStatusReadHeader.refreshing({
    required int revision,
    required StateOperation operation,
    required ReadText operationId,
    required int startedAt,
    required int? lastCheckedAt,
  }) = RefreshingProductSourceStatusReadHeader;
  const factory ProductSourceStatusReadHeader.stale({
    required int revision,
    required int staleAt,
    required int? lastCheckedAt,
  }) = StaleProductSourceStatusReadHeader;
  const factory ProductSourceStatusReadHeader.degraded({
    required int revision,
    required int failedAt,
    required int? lastCheckedAt,
    required StateOperation operation,
    required SourceStateErrorRead error,
  }) = DegradedProductSourceStatusReadHeader;
  const factory ProductSourceStatusReadHeader.failed({
    required int revision,
    required int failedAt,
    required StateOperation operation,
    required SourceStateErrorRead error,
  }) = FailedProductSourceStatusReadHeader;
  const factory ProductSourceStatusReadHeader.stopped({
    required int revision,
    required int stoppedAt,
  }) = StoppedProductSourceStatusReadHeader;
}

/// Materialized source metadata; this never embeds a domain business value.
@Freezed(toStringOverride: false)
sealed class ProductSourceStatus with _$ProductSourceStatus {
  const factory ProductSourceStatus.uninitialized({
    required int revision,
    required int updatedAt,
  }) = UninitializedProductSourceStatus;
  const factory ProductSourceStatus.loading({
    required int revision,
    required StateOperation operation,
    required String operationId,
    required int startedAt,
  }) = LoadingProductSourceStatus;
  const factory ProductSourceStatus.ready({
    required int revision,
    required int updatedAt,
    required int? lastCheckedAt,
  }) = ReadyProductSourceStatus;
  const factory ProductSourceStatus.refreshing({
    required int revision,
    required StateOperation operation,
    required String operationId,
    required int startedAt,
    required int? lastCheckedAt,
  }) = RefreshingProductSourceStatus;
  const factory ProductSourceStatus.stale({
    required int revision,
    required int staleAt,
    required int? lastCheckedAt,
  }) = StaleProductSourceStatus;
  const factory ProductSourceStatus.degraded({
    required int revision,
    required int failedAt,
    required int? lastCheckedAt,
    required StateOperation operation,
    required SourceStateError error,
  }) = DegradedProductSourceStatus;
  const factory ProductSourceStatus.failed({
    required int revision,
    required int failedAt,
    required StateOperation operation,
    required SourceStateError error,
  }) = FailedProductSourceStatus;
  const factory ProductSourceStatus.stopped({
    required int revision,
    required int stoppedAt,
  }) = StoppedProductSourceStatus;
}
