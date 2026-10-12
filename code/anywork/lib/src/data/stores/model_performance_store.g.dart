// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_performance_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 模型统计。时钟是 [ModelPerformanceSnapshotView.revision]。

@ProviderFor(ModelPerformanceStore)
final modelPerformanceStoreProvider = ModelPerformanceStoreProvider._();

/// 模型统计。时钟是 [ModelPerformanceSnapshotView.revision]。
final class ModelPerformanceStoreProvider
    extends
        $NotifierProvider<
          ModelPerformanceStore,
          CanonicalClockState<ModelPerformanceSnapshotView>
        > {
  /// 模型统计。时钟是 [ModelPerformanceSnapshotView.revision]。
  ModelPerformanceStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modelPerformanceStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modelPerformanceStoreHash();

  @$internal
  @override
  ModelPerformanceStore create() => ModelPerformanceStore();

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
    r'953997a8272deac7b8311c49e39277edd5c58e9f';

/// 模型统计。时钟是 [ModelPerformanceSnapshotView.revision]。

abstract class _$ModelPerformanceStore
    extends $Notifier<CanonicalClockState<ModelPerformanceSnapshotView>> {
  CanonicalClockState<ModelPerformanceSnapshotView> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<ModelPerformanceSnapshotView>,
              CanonicalClockState<ModelPerformanceSnapshotView>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<ModelPerformanceSnapshotView>,
                CanonicalClockState<ModelPerformanceSnapshotView>
              >,
              CanonicalClockState<ModelPerformanceSnapshotView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
