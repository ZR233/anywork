// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_performance_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(modelPerformanceStore)
final modelPerformanceStoreProvider = ModelPerformanceStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class ModelPerformanceStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<ModelPerformanceSnapshotView>,
          CanonicalClockState<ModelPerformanceSnapshotView>,
          CanonicalClockState<ModelPerformanceSnapshotView>
        >
    with $Provider<CanonicalClockState<ModelPerformanceSnapshotView>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  ModelPerformanceStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modelPerformanceStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modelPerformanceStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<ModelPerformanceSnapshotView>>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  CanonicalClockState<ModelPerformanceSnapshotView> create(Ref ref) {
    return modelPerformanceStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    CanonicalClockState<ModelPerformanceSnapshotView> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<ModelPerformanceSnapshotView>>(
            value,
          ),
    );
  }
}

String _$modelPerformanceStoreHash() =>
    r'f0ad70d7b5616af481a32fd768b1a6f379e5443d';
