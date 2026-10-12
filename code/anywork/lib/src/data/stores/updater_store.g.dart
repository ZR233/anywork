// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'updater_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 更新状态。时钟是 [UpdaterStateSnapshot.revision]。

@ProviderFor(UpdaterStore)
final updaterStoreProvider = UpdaterStoreProvider._();

/// 更新状态。时钟是 [UpdaterStateSnapshot.revision]。
final class UpdaterStoreProvider
    extends
        $NotifierProvider<
          UpdaterStore,
          CanonicalClockState<UpdaterStateSnapshot>
        > {
  /// 更新状态。时钟是 [UpdaterStateSnapshot.revision]。
  UpdaterStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updaterStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updaterStoreHash();

  @$internal
  @override
  UpdaterStore create() => UpdaterStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<UpdaterStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<UpdaterStateSnapshot>>(value),
    );
  }
}

String _$updaterStoreHash() => r'cf1e78939c07f71077e8a389bbb9cb988806283c';

/// 更新状态。时钟是 [UpdaterStateSnapshot.revision]。

abstract class _$UpdaterStore
    extends $Notifier<CanonicalClockState<UpdaterStateSnapshot>> {
  CanonicalClockState<UpdaterStateSnapshot> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<UpdaterStateSnapshot>,
              CanonicalClockState<UpdaterStateSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<UpdaterStateSnapshot>,
                CanonicalClockState<UpdaterStateSnapshot>
              >,
              CanonicalClockState<UpdaterStateSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
