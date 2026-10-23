import 'package:freezed_annotation/freezed_annotation.dart';

import 'failures.dart';
import 'product_identity.dart';

part 'product_projection.freezed.dart';

enum ResourceSyncPhase { idle, connecting, ready, reconnecting, failed, closed }

@Freezed(toStringOverride: false)
abstract class ResourceSyncState with _$ResourceSyncState {
  const factory ResourceSyncState({
    required ResourceSyncPhase phase,
    required StudioFailure? error,
    required bool retryExhausted,
  }) = _ResourceSyncState;
}

@Freezed(toStringOverride: false)
abstract class ProductProjection<H> with _$ProductProjection<H> {
  const factory ProductProjection({
    required ProductProjectionStamp? stamp,
    required H? header,
    required ResourceSyncState sync,
  }) = _ProductProjection<H>;
}

@Freezed(toStringOverride: false)
abstract class Materialized<T, R> with _$Materialized<T, R> {
  // T and R are immutable domain values. A domain using a typed collection as
  // its payload snapshots that collection at its own materialization boundary;
  // this container does not inspect generic payloads or introduce a JSON copier.
  const factory Materialized({
    required ProductReadOrigin origin,
    required R reference,
    required T value,
  }) = _Materialized<T, R>;
}

/// Previous values retain their own origin; they are not new-current evidence.
@Freezed(toStringOverride: false)
sealed class ReadValue<T, R> with _$ReadValue<T, R> {
  const factory ReadValue.unloaded({
    required ProductReadOrigin origin,
    required R reference,
  }) = UnloadedReadValue<T, R>;
  const factory ReadValue.loading({
    required ProductReadOrigin origin,
    required R reference,
    required Materialized<T, R>? previous,
  }) = LoadingReadValue<T, R>;
  const factory ReadValue.ready({
    required Materialized<T, R> current,
  }) = ReadyReadValue<T, R>;
  const factory ReadValue.failed({
    required ProductReadOrigin origin,
    required R reference,
    required StudioFailure error,
    required Materialized<T, R>? previous,
  }) = FailedReadValue<T, R>;
}

@Freezed(toStringOverride: false)
sealed class CollectionContinuation with _$CollectionContinuation {
  const factory CollectionContinuation.unknown() = UnknownCollectionContinuation;
  const factory CollectionContinuation.offset({required int value}) =
      OffsetCollectionContinuation;
  const factory CollectionContinuation.cursor({required String value}) =
      CursorCollectionContinuation;
  const factory CollectionContinuation.end() = EndCollectionContinuation;
}

@Freezed(toStringOverride: false)
final class CollectionWindow<T> with _$CollectionWindow<T> {
  CollectionWindow({
    required this.origin,
    required this.reference,
    required List<ProductEntityRef> entries,
    required Map<int, ReadValue<T, ProductEntityRef>> rows,
    required this.continuation,
    required this.complete,
    required this.loading,
    required this.error,
  }) : entries = List.unmodifiable(entries), rows = Map.unmodifiable(rows);

  final ProductReadOrigin origin;
  final ProductCollectionRef reference;
  final List<ProductEntityRef> entries;
  final Map<int, ReadValue<T, ProductEntityRef>> rows;
  final CollectionContinuation continuation;
  final bool complete;
  final bool loading;
  final StudioFailure? error;
}

@Freezed(toStringOverride: false)
sealed class CollectionMirror<T> with _$CollectionMirror<T> {
  const factory CollectionMirror.unavailable({
    required CollectionWindow<T>? lastKnown,
  }) = UnavailableCollectionMirror<T>;
  const factory CollectionMirror.current({
    required CollectionWindow<T> window,
  }) = CurrentCollectionMirror<T>;
}
